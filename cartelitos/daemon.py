"""El loop principal: sigue al player y manda cada linea al overlay."""
import collections
import os
import signal
import threading
import time

from . import audio
from . import art
from . import config
from . import ipc
from . import lyrics as lyr
from . import offsets
from . import system
from . import tray
from .util import log

POLL = 0.3
POLL_IDLE = 1.0     # en pausa: un playerctl por segundo alcanza
# T4.5: silencio con la letra cargada y el tema sonando. Un instrumental largo
# (una intro, un solo, el puente) deja la pantalla vacía y parece que el
# programa se murió. Que se cuelgue A PROPÓSITO, como un programa de Windows,
# es mejor que quedarse sin decir nada. Una vez por tema.
HANG_AFTER = 30.0

# T5.2: ¿está cantando? El umbral NO puede ser un número fijo: depende del
# micrófono, de cuánto se le escapa la música al mic y de cuánto grita Ferox.
# Sale del propio cuarto — el percentil 60 de los últimos 20 segundos.
SING_WINDOW = 1.5      # segundos de mic que se promedian para decidir
SING_HISTORY = 20.0    # de cuánto cuarto CALLADO sale el umbral
SING_PCT = 0.6         # percentil que hace de piso del cuarto
# Los dos multiplicadores son > 1 a propósito: el umbral ES el nivel del cuarto,
# así que volver al nivel del cuarto tiene que apagar. Con un multiplicador de
# apagado por debajo de 1, un ruido de fondo parejo (un ventilador) queda para
# siempre por encima de su propio umbral y el modo no se apaga nunca más.
SING_ON = 1.6          # cuánto hay que superar el cuarto para que cuente como cantar
SING_OFF = 1.15        # ...y por debajo de cuánto se apaga (histéresis)
SING_FLOOR = 0.01      # rms mínimo: en un cuarto mudo, el percentil 60 es ruido
SING_MIN_SAMPLES = 20  # dos segundos de mic antes de decidir nada


class SingGate:
    """Decide si hay alguien cantando, con un umbral que sale de la sala.

    La ventana de 20 s se llena SÓLO mientras NO se está cantando. Con la voz
    adentro, el percentil 60 sube hasta la voz misma y el promedio de 1.5 s deja
    de superarlo: cantando el estribillo entero, el modo se apagaba solo a los
    veinte segundos. Con la voz afuera, el umbral es el cuarto (el ventilador,
    lo que se le escapa de la música al micrófono) y la voz siempre sobresale.

    Por eso son 20 segundos DE CUARTO y no "los últimos 20 segundos de reloj":
    son las últimas N muestras calladas, sin filtro por tiempo. Con el filtro por
    reloj, un estribillo de más de veinte segundos dejaba toda la memoria vencida
    y al primer respiro se borraba entera — el umbral se rearmaba con la voz que
    venía enseguida y el modo no volvía a prender hasta el próximo silencio largo.

    La histéresis (SING_ON para prender, SING_OFF para apagar) es lo que evita
    que en el borde el estado parpadee entre verso y verso."""

    def __init__(self, window=SING_WINDOW, history=SING_HISTORY, pct=SING_PCT,
                 floor=SING_FLOOR):
        self.window = window
        self.history = history
        self.pct = pct
        self.floor = floor
        self.singing = False
        # el cuarto se mide en MUESTRAS (llegan a 10 Hz), no en reloj: ver arriba
        self.room = collections.deque(maxlen=max(int(history * 10), 1))
        self.recent = []    # (t, rms) de la ventana corta: con voz y todo

    def threshold(self):
        """El piso del cuarto ahora, o None si todavía no hay con qué medir."""
        if len(self.room) < SING_MIN_SAMPLES:
            return None
        vals = sorted(self.room)
        i = min(int(len(vals) * self.pct), len(vals) - 1)
        return max(vals[i], self.floor)

    def feed(self, rms, now, active=True):
        """Un bloque de micrófono. Devuelve True si el estado CAMBIÓ.

        `active` es "hay letra sonando ahora": sin canción no se está cantando,
        se está hablando, y eso no tiene que prender nada."""
        self.recent = [(t, r) for t, r in self.recent if t > now - self.window]
        self.recent.append((now, rms))
        if not self.singing:
            # el umbral se mide con el cuarto callado, no con la voz adentro
            self.room.append(rms)
        thr = self.threshold()
        level = sum(r for _, r in self.recent) / len(self.recent)
        if thr is None:
            want = False
        elif self.singing:
            want = level > thr * SING_OFF
        else:
            want = level > thr * SING_ON
        want = bool(want and active)
        if want == self.singing:
            return False
        self.singing = want
        return True

    def reset(self):
        """El modo se apagó (o cambió el tema): que no quede el estado viejo."""
        was = self.singing
        self.singing = False
        self.recent = []
        return was


class DaemonLoop:
    """Máquina de estados del loop principal, con las dependencias inyectadas.

    Se separó de main() para poder instanciarla en los tests con mocks (system,
    ipc, config, etc.) sin tocar sockets/subprocess/threads reales. La lógica es
    exactamente la que tenía el `while True` de antes, sólo movida a métodos."""

    def __init__(self, *, gaming=None, playerctl_state=None, ipc=ipc, config=config,
                 audio=audio, art=art, lyr=lyr, offsets=offsets, tray=tray, log=log,
                 sleep=time.sleep, monotonic=time.monotonic, system=system):
        self._gaming = gaming or system.gaming
        self._playerctl_state = playerctl_state or system.playerctl_state
        self._system = system
        self._ipc = ipc
        self._config = config
        self._audio = audio
        self._art = art
        self._lyr = lyr
        self._offsets = offsets
        self._tray = tray
        self._log = log
        self._sleep = sleep
        self._monotonic = monotonic

        self.track_id = None
        self.current_artist = None
        self.session_offset = 0.0
        self.lyrics = None
        self.lyrics_kind = None
        self.plain_shown = False
        self.idx = -1
        self.paused_by_game = False
        self.crt_paused_by_game = False
        self.last_game_check = 0.0
        self.pause_started = None
        self.pause_cleared = False
        self.resend_np = False
        self.crt_was_on = False
        self.last_pos_sent = 0.0
        self.last_pos = 0.0
        self.last_show_at = 0.0
        self.hang_sent = False
        # T5.2: el modo karaoke. `voice_active` es "hay letra sonando ahora":
        # sin canción no se está cantando, se está hablando.
        self.sing = SingGate()
        self.voice_active = False

    def check_game(self, now):
        """Actualiza paused_by_game según gaming(); devuelve el estado resultante.

        Sólo consulta gaming() cada 5s, como hacía el loop original. Al entrar
        en pausa por juego limpia el estado de track/letra en curso; al salir,
        restaura el modo CRT si lo había apagado."""
        if now - self.last_game_check > 5:
            self.last_game_check = now
            if self._gaming():
                if not self.paused_by_game:
                    self.paused_by_game = True
                    self.voice_active = False
                    self.track_id = None
                    self.lyrics = None
                    self.idx = -1
                    self._ipc.clear()
                    # un tubo full-bleed encima de un juego es lo peor que puede
                    # pasar: se apaga y se devuelve como estaba al salir
                    self.crt_paused_by_game = self._config.crt_on()
                    if self.crt_paused_by_game:
                        self._config.set_crt(False)
                    self._log("game detected: pausing")
            elif self.paused_by_game:
                self.paused_by_game = False
                if self.crt_paused_by_game:
                    self.crt_paused_by_game = False
                    self._config.set_crt(True)
                self._log("game closed: resuming")
        return self.paused_by_game

    def _np_wanted(self):
        """Si hay que mandar el evento `np` (qué suena).

        `now_playing` es la perilla de la FUNDA, pero el tubo usa el mismo
        evento para otra cosa: con música y sin letra, la pantalla enfocada dice
        qué está sonando en vez de quedarse en "NO SIGNAL". Sin esto, con la
        funda apagada el modo instrumental no tiene nada que decir. Mismo
        criterio que los eventos de posición, que el CRT también necesita
        siempre. (La funda no aparece por esto: el overlay no la prende si el
        tubo está puesto.)"""
        return self._config.CFG["behavior"]["now_playing"] or self._config.crt_on()

    def handle_track(self, t, now):
        """Procesa un tick con el estado del player (t puede ser None/parado).

        Devuelve True si conviene el poll rápido (canción sonando con letra
        sincronizada) — mismo cálculo que `fast` en el loop original."""
        # El tubo prendido a mitad de un tema: el overlay nunca vio el `np` de
        # lo que suena (con la funda apagada no se manda ninguno), y el modo
        # instrumental se queda sin nada que decir hasta el tema siguiente. Se
        # reenvía UNA vez, cuando el interruptor pasa de apagado a prendido.
        crt_now = self._config.crt_on()
        if crt_now and not self.crt_was_on:
            self.resend_np = True
        self.crt_was_on = crt_now

        # música en pausa mucho tiempo → limpiar carteles colgados
        if t["status"] == "Paused":
            if self.pause_started is None:
                self.pause_started = now
            # el tema termina en pausa (usuario paró justo al final): no tiene
            # sentido esperar el pause_clear si ya no queda nada por mostrar
            near_end = t["length"] - t["pos"] < 2.0
            if not self.pause_cleared and (near_end or (
                    self._config.CFG["behavior"]["pause_clear"] > 0
                    and now - self.pause_started > self._config.CFG["behavior"]["pause_clear"])):
                self._ipc.clear()
                self.pause_cleared = True
                self.resend_np = True
                self.idx = -1
                self._log("track ending: dialogs cleared" if near_end
                           else "long pause: dialogs cleared")
        else:
            self.pause_started = None
            self.pause_cleared = False
            # la pausa larga escondió la funda: al retomar, mostrarla de nuevo
            if self.resend_np:
                self.resend_np = False
                if self._np_wanted() and t["title"]:
                    self._ipc.send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                          "album": t["album"], "art": t["art"]})

        self._ipc._song_where["pos"] = t["pos"]
        self._ipc._song_where["at"] = now
        self._ipc._song_where["playing"] = t["status"] == "Playing"

        # el usuario saltó para atrás en el mismo tema (rebobinó, repitió un
        # verso): la línea vieja quedaba pegada porque `idx` sólo avanza
        if t["id"] == self.track_id and t["pos"] < self.last_pos - 2.0:
            self.idx = -1
            self._ipc.clear()
            self._log("seek back: reset")
        self.last_pos = t["pos"]

        if t["id"] != self.track_id:
            self.track_id = t["id"]
            self.current_artist = t["artist"]
            # arranca en lo que ya se sabe de este artista (T0.13) más lo que
            # ESTE tema pidió en esta sesión y todavía no se ganó el derecho a
            # guardarse (tanda 3, C: hacen falta dos temas del mismo artista
            # pidiendo lo mismo). Volver a un tema ya corregido lo recupera.
            self.session_offset = self._offsets.effective(t["artist"], t["id"])
            self._audio.set_profile(self._audio.profile_for(t))
            self.idx = -1
            self._ipc.clear()
            self._log(f"track: {t['artist']} — {t['title']}")
            if self._np_wanted():
                self._ipc.send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                      "album": t["album"], "art": t["art"]})
            self._art.send_album_colors(t["art"])
            self.lyrics = None
            self.lyrics_kind = None
            self.plain_shown = False
            self.hang_sent = False
            self.last_show_at = now
            if t["title"]:
                self._lyr.fetch_lyrics_async(t)
            else:
                self._lyr._fetch.update(id=None, lyrics=None, status=None, done=False)

        # la búsqueda corre en un hilo: se recoge cuando llega
        if self.lyrics is None and self._lyr._fetch["done"] and self._lyr._fetch["id"] == self.track_id:
            self.lyrics = self._lyr._fetch["lyrics"]
            self.lyrics_kind = self._lyr._fetch.get("status")
            # la letra entera, una sola vez: el `show` manda una línea por vez y
            # el overlay no ve el resto. Sin sincronizar no hay tiempos que
            # mandar (el "plain" es un bloque de texto suelto), pero el texto
            # igual viaja: la marea de texto del tubo lo hace correr, sin
            # resaltar nada.
            if self.lyrics and self.lyrics_kind == "plain":
                self._ipc.lyrics_plain(self.lyrics[0][1])
            elif self.lyrics:
                self._ipc.lyrics_list(self.lyrics)
            # el reloj del "no responde" arranca cuando HAY letra: la búsqueda
            # va en otro hilo y puede tardar, y esa espera no es un silencio
            self.last_show_at = now

        # progreso de la canción: barra de la funda + karaoke (1 evento por segundo)
        # el modo CRT los necesita SIEMPRE: el director reparte los pedazos en
        # tiempo de canción, y sin estos eventos el reloj se queda clavado
        if ((self._config.CFG["behavior"]["now_playing"] or self._config.CFG["display"]["karaoke"]
                or self._config.crt_on())
                and t["status"] == "Playing"
                and t["length"] > 0 and now - self.last_pos_sent >= 1.0):
            self.last_pos_sent = now
            self._ipc.send({"cmd": "pos", "p": round(t["pos"], 2), "l": round(t["length"], 2)})

        if self.lyrics and t["status"] == "Playing":
            if self.lyrics_kind == "plain":
                # lrclib no tiene la letra sincronizada para este tema, sólo el
                # texto entero: un cartel único con el arranque, no una línea
                # por vez (no hay tiempos con los que seguirla)
                if not self.plain_shown:
                    self.plain_shown = True
                    self.last_show_at = now
                    preview = "\n".join(self.lyrics[0][1].splitlines()[:6])
                    self._ipc.show(preview, "unsynced lyrics")
            else:
                # offset global (config) + el de este artista (T0.13: la
                # persistida de sesiones pasadas más lo que se ajustó ahora)
                pos_offset = self._config.CFG["behavior"]["offset"] + self.session_offset
                i = self._lyr.current_line_index(self.lyrics, t["pos"] + pos_offset)
                if i != self.idx:
                    self.idx = i
                    line = self.lyrics[i] if i >= 0 else None
                    if line and line[1]:
                        t1 = self.lyrics[i + 1][0] if i + 1 < len(self.lyrics) else line[0] + 5
                        # el tercer campo (tiempos por palabra) es de T1.1: una
                        # letra que venga de dos campos sigue andando igual
                        self.last_show_at = now
                        words = line[2] if len(line) > 2 else None
                        # el offset viaja con la línea: el aro del tubo cuenta
                        # contra el instante en que ESTE daemon va a mandar el
                        # próximo `show`, no contra el `t0` pelado de la letra
                        nxt_t0 = self.lyrics[i + 1][0] if i + 1 < len(self.lyrics) else None
                        v_end = self._lyr.voice_end(line[0], line[1], words,
                                                    nxt_t0) - pos_offset
                        self._ipc.show(line[1], t["title"], line[0], t1, words,
                                       nxt=self._ipc.next_line(self.lyrics, i,
                                                               pos_offset),
                                       v_end=v_end)

            # silencio largo con la letra cargada: el programa se cuelga solo.
            # Con la letra sin sincronizar no aplica: ahí no viene ninguna línea
            # más por diseño, no porque el tema se haya quedado callado.
            if (self.lyrics_kind != "plain" and not self.hang_sent
                    and now - self.last_show_at > HANG_AFTER):
                self.hang_sent = True
                self._log("long silence: fatal-lyrics is not responding")
                self._ipc.hang()

        # Cada vuelta spawnea un playerctl (~4 ms de CPU). El poll fino sólo hace
        # falta para pegarle al momento de cada verso: en pausa, o en un tema sin
        # letra sincronizada, con una vuelta por segundo alcanza — y ésa es la
        # frecuencia de los eventos de progreso, así que no se pierde nada.
        # el karaoke sólo cuenta como "cantar" con una canción y su letra
        # encima: lo demás es hablar al lado del micrófono
        self.voice_active = t["status"] == "Playing" and bool(self.lyrics)
        return self.voice_active

    def sync(self, delta):
        """Gesto de ajuste fino (T0.13): keybind, menú de bandeja o el
        watcher del archivo de sync (otro proceso) llaman acá.

        La cuenta la lleva offsets.record(), no este método: se aplica al tema
        que suena de una, y se guarda para el artista recién cuando DOS temas
        distintos suyos pidieron lo mismo (tanda 3, C). Lo que devuelve YA es
        el offset efectivo del tema, con el rebase de lo que se persistió
        adentro — sumarle el delta encima lo contaría dos veces.

        El aviso sale por un evento propio (`sync`) y no por un cartel: con el
        tubo prendido un `show` se vuelve LA LÍNEA de la letra, así que el
        ajuste tapaba justo el verso que se estaba tratando de sincronizar. El
        overlay decide qué dibujar — el cartel de Windows o el rótulo chico en
        la pantalla enfocada —, porque es el que sabe si el tubo está arriba."""
        if self.current_artist and self.track_id:
            self.session_offset = self._offsets.record(
                self.current_artist, delta, self.track_id)
        else:
            self.session_offset = round(self.session_offset + delta, 3)
        sign = "+" if delta >= 0 else "-"
        self._log(f"sync {sign}{abs(delta):.1f}s (session offset now {self.session_offset:+.2f}s)")
        self._ipc.sync_hint(delta, self.session_offset, self.current_artist)
        self.idx = -1   # re-muestra la línea actual, ya con el offset nuevo

    def _watch_sync(self):
        """Vigila SYNC_PATH (lo escribe `fatal sync +/-`, otro proceso) y
        aplica el ajuste acá — mismo mecanismo de archivo que crt/tune,
        porque el daemon vivo no es alcanzable de otra forma desde afuera."""
        last = None
        try:
            last = os.stat(self._ipc.SYNC_PATH).st_mtime_ns
        except OSError:
            pass
        while True:
            self._sleep(0.35)
            try:
                stamp = os.stat(self._ipc.SYNC_PATH).st_mtime_ns
            except OSError:
                continue
            if stamp == last:
                continue
            last = stamp
            try:
                with open(self._ipc.SYNC_PATH) as f:
                    raw = f.read()
            except OSError:
                continue
            delta = self._ipc.parse_sync(raw)
            if delta is not None:
                self.sync(delta)

    def voice(self, rms, now):
        """Un bloque de micrófono (T5.2). Lo llama el hilo de la captura.

        El cambio de estado va por `send` y no por `send_soft`: son dos o tres
        eventos por tema, y perder justo el que prende la pantalla es perder el
        modo entero."""
        if not self._config.CFG["behavior"]["sing"]:
            if self.sing.reset():
                self._ipc.send({"cmd": "sing", "on": False})
            return
        if self.sing.feed(rms, now, self.voice_active):
            self._log("voice: singing" if self.sing.singing else "voice: quiet")
            self._ipc.send({"cmd": "sing", "on": self.sing.singing})

    def clear_track_state(self):
        """Limpia el estado de track/letra en curso y avisa al overlay."""
        self.voice_active = False
        if self.track_id is not None:
            self._ipc.clear()
            self.track_id = None
            self.lyrics = None
            self.idx = -1

    def tick(self):
        """Una vuelta del loop: chequeo de juego + estado del player + sleep.

        Misma estructura de tres ramas que el `while True` original, cada una
        con su propio sleep: 2s en pausa por juego, 1.5s sin player activo, y
        POLL/POLL_IDLE cuando hay música."""
        now = self._monotonic()
        if self.check_game(now):
            self._sleep(2)
            return

        t = self._playerctl_state()
        if not t or t["status"] not in ("Playing", "Paused"):
            self.clear_track_state()
            self._sleep(1.5)
            return

        fast = self.handle_track(t, now)
        self._sleep(POLL if fast else POLL_IDLE)

    def run(self):
        """El while True de siempre, delegando cada vuelta a tick()."""
        self._log("fatal-lyrics daemon started")
        self._lyr.purge_cache(time.time())
        # el modo CRT arranca como diga la config: un `fatal crt on` de la sesión
        # anterior no se hereda (tapa las tres pantallas, mejor que sea deliberado)
        self._config.set_crt(self._config.CFG["crt"]["enabled"])
        # las teclas del sync (tanda 3, C). `None` = arranque: lo que valga el
        # default no se toca, porque ese bind ya vive en la config de Hyprland
        # y escribirlo de nuevo sería tener el mismo atajo dos veces.
        self._system.apply_key_binds(None, self._config.CFG["keys"])
        self._tray.start_tray(sync=self.sync)
        self._ipc.send(self._ipc._config_event())
        threading.Thread(target=self._config.watch_config, daemon=True, name="config").start()
        threading.Thread(target=self._audio.audio_loop, daemon=True, name="audio").start()
        threading.Thread(target=self._config.watch_tune, daemon=True, name="tune").start()
        threading.Thread(target=self._watch_sync, daemon=True, name="sync").start()
        # T5.1: el hilo del micrófono existe siempre, pero no abre nada mientras
        # `sing` esté apagada (que es el default): dormita mirando la perilla
        threading.Thread(target=self._config.watch_sing, daemon=True, name="sing").start()
        self._audio.set_voice_sink(self.voice)
        threading.Thread(target=self._audio.voice_loop, daemon=True, name="voice").start()
        signal.signal(signal.SIGUSR1, self._ipc.demo)
        while True:
            self.tick()


def main():
    DaemonLoop().run()
