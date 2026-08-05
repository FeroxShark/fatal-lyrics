"""El socket con el overlay: los eventos salen todos por aca."""
import json
import os
import socket
import threading
import time

from . import config
from . import lyrics

SOCK_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos.sock")

_sock = None
_last_np = None
# posición de la canción, para que el hilo de audio sepa en qué minuto está
_song_where = {"pos": 0.0, "at": 0.0, "playing": False}


def _song_pos():
    """Segundo de la canción ahora mismo, extrapolado del último dato."""
    if not _song_where["playing"]:
        return None
    return _song_where["pos"] + min(time.monotonic() - _song_where["at"], 2.0)
# el watcher de config escribe desde otro hilo: sin esto dos eventos se pisan
_send_lock = threading.Lock()


def _config_event():
    cfg = config.CFG
    d, e, b, c = cfg["display"], cfg["effects"], cfg["behavior"], cfg["crt"]
    return {
        "cmd": "config",
        "screen": d["screen"], "max_dialogs": d["max_dialogs"],
        "scale": d["scale"], "current_scale": d["current_scale"],
        "spawn_area": d["spawn_area"], "karaoke": d["karaoke"],
        "glitch": e["glitch"], "effects_on_current": e["effects_on_current"],
        "tearing": e["tearing"], "death_age_min": e["death_age_min"],
        "death_age_max": e["death_age_max"], "max_lifetime": e["max_lifetime"],
        "burn_in": e["burn_in"], "cascade": e["cascade"],
        "click_through": b["click_through"], "troll_no": b["troll_no"],
        "np_corner": b["np_corner"], "np_margin": b["np_margin"],
        "np_vinyl": b["np_vinyl"],
        "crt_screens": c["screens"], "crt_order": c["order"],
        "crt_palette": c["palette"],
        "crt_split": c["split"], "crt_exit_on": c["exit_on"],
        "crt_director": c["director"], "crt_focus": c["focus"],
        "crt_color_from_pitch": c["color_from_pitch"],
        "crt_color_hold": c["color_hold"], "crt_motifs": c["motifs"],
        "crt_water": c["water"], "crt_water_amp": c["water_amp"],
        "crt_camera": c["camera"], "crt_quality": c["quality"],
        "crt_flicker": c["flicker"], "crt_word_flash": c["word_flash"],
        "crt_font": c["font"], "crt_chrome": c["chrome"],
        "crt_intensity": c["intensity"], "crt_curvature": c["curvature"],
        "crt_scanlines": c["scanlines"], "crt_chroma": c["chroma"],
        "crt_bloom": c["bloom"], "crt_noise": c["noise"],
        "crt_roll": c["roll"], "crt_vignette": c["vignette"],
    }


def send(event):
    """Manda un evento JSON al overlay; en cada reconexión manda la config primero
    y reenvía el último Now Playing (el overlay nuevo arranca sin estado)."""
    global _sock, _last_np
    if event.get("cmd") == "np":
        _last_np = event
    data = (json.dumps(event, ensure_ascii=False) + "\n").encode()
    with _send_lock:
        for _ in range(2):
            try:
                if _sock is None:
                    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    s.settimeout(2)
                    s.connect(SOCK_PATH)
                    s.sendall((json.dumps(_config_event(), ensure_ascii=False) + "\n").encode())
                    if _last_np is not None and _last_np is not event:
                        s.sendall((json.dumps(_last_np, ensure_ascii=False) + "\n").encode())
                    _sock = s
                _sock.sendall(data)
                return
            except Exception:
                try:
                    if _sock:
                        _sock.close()
                except Exception:
                    pass
                _sock = None


def send_soft(event):
    """Manda sin hacer cola. Si el socket está ocupado con un evento de letra,
    este se descarta: perder un frame de animación no se ve, atrasar un verso sí."""
    if not _send_lock.acquire(blocking=False):
        return False
    _send_lock.release()
    send(event)
    return True


def show(text, title, t0=0.0, t1=0.0):
    # t0/t1: comienzo y fin estimado de la línea, para el karaoke del overlay
    ev = {"cmd": "show", "text": text, "title": title,
          "t0": round(t0, 2), "t1": round(t1, 2)}
    segs = lyrics.split_repeats(text)
    if len(segs) > 1:
        ev["segs"] = segs      # golpes repetidos: cada uno a una pantalla
    send(ev)


def clear():
    send({"cmd": "clear"})


DEMO_LINES = [
    "this is what a dialog looks like",
    "no music needed to try it out",
    "tweak it until it feels right",
    "0x0000DEAD — everything is fine",
]


def _demo_burst():
    for i, line in enumerate(DEMO_LINES):
        show(line, "fatal-lyrics — demo")
        if i < len(DEMO_LINES) - 1:
            time.sleep(0.7)


def demo(*_):
    """SIGUSR1: tira unos carteles de mentira. Sirve para ver cómo quedó la
    config sin tener que poner música. Va en un hilo aparte: mandar desde el
    handler trabaría el daemon si la señal cae con el lock de send() tomado."""
    threading.Thread(target=_demo_burst, daemon=True, name="demo").start()
