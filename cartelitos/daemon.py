"""El loop principal: sigue al player y manda cada linea al overlay."""
import signal
import threading
import time

from . import audio
from . import art
from . import config
from . import ipc
from . import lyrics as lyr
from . import system
from . import tray
from .util import log

POLL = 0.3
POLL_IDLE = 1.0     # en pausa: un playerctl por segundo alcanza


class DaemonLoop:
    """Máquina de estados del loop principal, con las dependencias inyectadas.

    Se separó de main() para poder instanciarla en los tests con mocks (system,
    ipc, config, etc.) sin tocar sockets/subprocess/threads reales. La lógica es
    exactamente la que tenía el `while True` de antes, sólo movida a métodos."""

    def __init__(self, *, gaming=None, playerctl_state=None, ipc=ipc, config=config,
                 audio=audio, art=art, lyr=lyr, tray=tray, log=log,
                 sleep=time.sleep, monotonic=time.monotonic):
        self._gaming = gaming or system.gaming
        self._playerctl_state = playerctl_state or system.playerctl_state
        self._ipc = ipc
        self._config = config
        self._audio = audio
        self._art = art
        self._lyr = lyr
        self._tray = tray
        self._log = log
        self._sleep = sleep
        self._monotonic = monotonic

        self.track_id = None
        self.lyrics = None
        self.idx = -1
        self.paused_by_game = False
        self.crt_paused_by_game = False
        self.last_game_check = 0.0
        self.pause_started = None
        self.pause_cleared = False
        self.resend_np = False
        self.last_pos_sent = 0.0

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

    def handle_track(self, t, now):
        """Procesa un tick con el estado del player (t puede ser None/parado).

        Devuelve True si conviene el poll rápido (canción sonando con letra
        sincronizada) — mismo cálculo que `fast` en el loop original."""
        # música en pausa mucho tiempo → limpiar carteles colgados
        if t["status"] == "Paused":
            if self.pause_started is None:
                self.pause_started = now
            elif (self._config.CFG["behavior"]["pause_clear"] > 0 and not self.pause_cleared
                    and now - self.pause_started > self._config.CFG["behavior"]["pause_clear"]):
                self._ipc.clear()
                self.pause_cleared = True
                self.resend_np = True
                self.idx = -1
                self._log("long pause: dialogs cleared")
        else:
            self.pause_started = None
            self.pause_cleared = False
            # la pausa larga escondió la funda: al retomar, mostrarla de nuevo
            if self.resend_np:
                self.resend_np = False
                if self._config.CFG["behavior"]["now_playing"] and t["title"]:
                    self._ipc.send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                          "album": t["album"], "art": t["art"]})

        self._ipc._song_where["pos"] = t["pos"]
        self._ipc._song_where["at"] = now
        self._ipc._song_where["playing"] = t["status"] == "Playing"

        if t["id"] != self.track_id:
            self.track_id = t["id"]
            self._audio.set_profile(self._audio.profile_for(t))
            self.idx = -1
            self._ipc.clear()
            self._log(f"track: {t['artist']} — {t['title']}")
            if self._config.CFG["behavior"]["now_playing"]:
                self._ipc.send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                      "album": t["album"], "art": t["art"]})
            self._art.send_album_colors(t["art"])
            self.lyrics = None
            if t["title"]:
                self._lyr.fetch_lyrics_async(t)
            else:
                self._lyr._fetch.update(id=None, lyrics=None, done=False)

        # la búsqueda corre en un hilo: se recoge cuando llega
        if self.lyrics is None and self._lyr._fetch["done"] and self._lyr._fetch["id"] == self.track_id:
            self.lyrics = self._lyr._fetch["lyrics"]

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
            i = self._lyr.current_line_index(self.lyrics, t["pos"] + self._config.CFG["behavior"]["offset"])
            if i != self.idx:
                self.idx = i
                if i >= 0 and self.lyrics[i][1]:
                    t1 = self.lyrics[i + 1][0] if i + 1 < len(self.lyrics) else self.lyrics[i][0] + 5
                    self._ipc.show(self.lyrics[i][1], t["title"], self.lyrics[i][0], t1)

        # Cada vuelta spawnea un playerctl (~4 ms de CPU). El poll fino sólo hace
        # falta para pegarle al momento de cada verso: en pausa, o en un tema sin
        # letra sincronizada, con una vuelta por segundo alcanza — y ésa es la
        # frecuencia de los eventos de progreso, así que no se pierde nada.
        return t["status"] == "Playing" and bool(self.lyrics)

    def clear_track_state(self):
        """Limpia el estado de track/letra en curso y avisa al overlay."""
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
        # el modo CRT arranca como diga la config: un `fatal crt on` de la sesión
        # anterior no se hereda (tapa las tres pantallas, mejor que sea deliberado)
        self._config.set_crt(self._config.CFG["crt"]["enabled"])
        self._tray.start_tray()
        self._ipc.send(self._ipc._config_event())
        threading.Thread(target=self._config.watch_config, daemon=True, name="config").start()
        threading.Thread(target=self._audio.audio_loop, daemon=True, name="audio").start()
        threading.Thread(target=self._config.watch_tune, daemon=True, name="tune").start()
        signal.signal(signal.SIGUSR1, self._ipc.demo)
        while True:
            self.tick()


def main():
    DaemonLoop().run()
