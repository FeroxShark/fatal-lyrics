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


def main():
    track_id = None
    lyrics = None
    idx = -1
    paused_by_game = False
    crt_paused_by_game = False
    last_game_check = 0.0
    pause_started = None
    pause_cleared = False
    resend_np = False
    last_pos_sent = 0.0
    log("fatal-lyrics daemon started")
    # el modo CRT arranca como diga la config: un `fatal crt on` de la sesión
    # anterior no se hereda (tapa las tres pantallas, mejor que sea deliberado)
    config.set_crt(config.CFG["crt"]["enabled"])
    tray.start_tray()
    ipc.send(ipc._config_event())
    threading.Thread(target=config.watch_config, daemon=True, name="config").start()
    threading.Thread(target=audio.audio_loop, daemon=True, name="audio").start()
    threading.Thread(target=config.watch_tune, daemon=True, name="tune").start()
    signal.signal(signal.SIGUSR1, ipc.demo)
    while True:
        # pausa automática si hay un juego corriendo
        now = time.monotonic()
        if now - last_game_check > 5:
            last_game_check = now
            if system.gaming():
                if not paused_by_game:
                    paused_by_game = True
                    track_id = None
                    lyrics = None
                    idx = -1
                    ipc.clear()
                    # un tubo full-bleed encima de un juego es lo peor que puede
                    # pasar: se apaga y se devuelve como estaba al salir
                    crt_paused_by_game = config.crt_on()
                    if crt_paused_by_game:
                        config.set_crt(False)
                    log("game detected: pausing")
            elif paused_by_game:
                paused_by_game = False
                if crt_paused_by_game:
                    crt_paused_by_game = False
                    config.set_crt(True)
                log("game closed: resuming")
        if paused_by_game:
            time.sleep(2)
            continue

        t = system.playerctl_state()
        if not t or t["status"] not in ("Playing", "Paused"):
            if track_id is not None:
                ipc.clear()
                track_id = None
                lyrics = None
                idx = -1
            time.sleep(1.5)
            continue

        # música en pausa mucho tiempo → limpiar carteles colgados
        if t["status"] == "Paused":
            if pause_started is None:
                pause_started = now
            elif (config.CFG["behavior"]["pause_clear"] > 0 and not pause_cleared
                    and now - pause_started > config.CFG["behavior"]["pause_clear"]):
                ipc.clear()
                pause_cleared = True
                resend_np = True
                idx = -1
                log("long pause: dialogs cleared")
        else:
            pause_started = None
            pause_cleared = False
            # la pausa larga escondió la funda: al retomar, mostrarla de nuevo
            if resend_np:
                resend_np = False
                if config.CFG["behavior"]["now_playing"] and t["title"]:
                    ipc.send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                          "album": t["album"], "art": t["art"]})

        ipc._song_where["pos"] = t["pos"]
        ipc._song_where["at"] = now
        ipc._song_where["playing"] = t["status"] == "Playing"

        if t["id"] != track_id:
            track_id = t["id"]
            audio.set_profile(audio.profile_for(t))
            idx = -1
            ipc.clear()
            log(f"track: {t['artist']} — {t['title']}")
            if config.CFG["behavior"]["now_playing"]:
                ipc.send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                      "album": t["album"], "art": t["art"]})
            art.send_album_colors(t["art"])
            lyrics = None
            if t["title"]:
                lyr.fetch_lyrics_async(t)
            else:
                lyr._fetch.update(id=None, lyrics=None, done=False)

        # la búsqueda corre en un hilo: se recoge cuando llega
        if lyrics is None and lyr._fetch["done"] and lyr._fetch["id"] == track_id:
            lyrics = lyr._fetch["lyrics"]

        # progreso de la canción: barra de la funda + karaoke (1 evento por segundo)
        # el modo CRT los necesita SIEMPRE: el director reparte los pedazos en
        # tiempo de canción, y sin estos eventos el reloj se queda clavado
        if ((config.CFG["behavior"]["now_playing"] or config.CFG["display"]["karaoke"]
                or config.crt_on())
                and t["status"] == "Playing"
                and t["length"] > 0 and now - last_pos_sent >= 1.0):
            last_pos_sent = now
            ipc.send({"cmd": "pos", "p": round(t["pos"], 2), "l": round(t["length"], 2)})

        if lyrics and t["status"] == "Playing":
            i = lyr.current_line_index(lyrics, t["pos"] + config.CFG["behavior"]["offset"])
            if i != idx:
                idx = i
                if i >= 0 and lyrics[i][1]:
                    t1 = lyrics[i + 1][0] if i + 1 < len(lyrics) else lyrics[i][0] + 5
                    ipc.show(lyrics[i][1], t["title"], lyrics[i][0], t1)

        # Cada vuelta spawnea un playerctl (~4 ms de CPU). El poll fino sólo hace
        # falta para pegarle al momento de cada verso: en pausa, o en un tema sin
        # letra sincronizada, con una vuelta por segundo alcanza — y ésa es la
        # frecuencia de los eventos de progreso, así que no se pierde nada.
        fast = t["status"] == "Playing" and lyrics
        time.sleep(POLL if fast else POLL_IDLE)
