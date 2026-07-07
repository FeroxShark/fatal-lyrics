#!/usr/bin/env python3
"""cartelitos / fatal-lyrics — letras de Spotify sincronizadas como diálogos
de error de Windows.

Sigue la reproducción por MPRIS (playerctl), baja letras sincronizadas de
lrclib.net y le manda cada línea al overlay Quickshell vía socket Unix.
Config en ~/.config/cartelitos/config.toml (se crea sola con defaults).
"""
import json
import os
import re
import socket
import subprocess
import sys
import time
import tomllib
import urllib.parse
import urllib.request

UA = "fatal-lyrics/1.0 (https://github.com/FeroxShark/fatal-lyrics)"
FIELD_SEP = "\x1f"
POLL = 0.3
SOCK_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos.sock")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "cartelitos")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.toml")

DEFAULT_CONFIG = """\
# fatal-lyrics — configuración
# Aplicar cambios con: cartelitos restart

[display]
screen = "auto"        # "auto" (primer monitor) o nombre exacto ("DP-1", hyprctl monitors)
max_dialogs = 12       # máximo de carteles vivos a la vez
scale = 1.0            # tamaño base de todos los carteles
current_scale = 1.3    # factor extra del cartel de la línea actual
spawn_area = "full"    # full | top | bottom | left | right | edges (bordes, no tapa el centro)

[effects]
glitch = "normal"      # off | soft | normal | aggressive
effects_on_current = false  # true = el cartel actual también vibra/glitchea
tearing = true         # los carteles viejos quedan con la ventana partida
death_age_min = 3      # un cartel muere entre N…
death_age_max = 7      # …y M carteles después de aparecer
max_lifetime = 60      # vida máxima en segundos por cartel; 0 = sin límite
burn_in = true         # los carteles muertos dejan una sombra quemada que se desvanece

[behavior]
now_playing = true     # funda de vinilo con la portada al cambiar de canción
np_corner = "top-right"  # esquina donde se estaciona la funda: top-left | top-right | bottom-left | bottom-right
np_margin = 14         # píxeles libres contra los bordes (por si hay una barra/panel)
troll_no = true        # el botón "No" duplica el cartel; false = solo cierra
click_through = false  # true = los carteles no capturan el mouse (clicks pasan de largo)
pause_clear = 15       # segundos en pausa antes de limpiar todo; 0 = nunca
player = "spotify"     # nombre del player MPRIS (ver: playerctl -l)
offset = 0.15          # adelanto de sincronización en segundos
game_procs = ["cs2"]   # si alguno de estos procesos corre, pausa automática
"""

DEFAULTS = {
    "display": {
        "screen": "auto", "max_dialogs": 12, "scale": 1.0,
        "current_scale": 1.3, "spawn_area": "full",
    },
    "effects": {
        "glitch": "normal", "effects_on_current": False, "tearing": True,
        "death_age_min": 3, "death_age_max": 7, "max_lifetime": 60,
        "burn_in": True,
    },
    "behavior": {
        "now_playing": True, "np_corner": "top-right", "np_margin": 14,
        "troll_no": True, "click_through": False,
        "pause_clear": 15, "player": "spotify", "offset": 0.15,
        "game_procs": ["cs2"],
    },
}

TS_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def log(*args):
    print(time.strftime("%H:%M:%S"), *args, flush=True)


def load_config():
    if not os.path.exists(CONFIG_PATH):
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_PATH, "w") as f:
            f.write(DEFAULT_CONFIG)
        log(f"config default creada en {CONFIG_PATH}")
    cfg = {k: dict(v) for k, v in DEFAULTS.items()}
    try:
        with open(CONFIG_PATH, "rb") as f:
            user = tomllib.load(f)
        for section, values in user.items():
            if section in cfg and isinstance(values, dict):
                cfg[section].update(values)
    except Exception as e:
        log(f"config inválida ({e}), usando defaults")
    return cfg


CFG = load_config()


def playerctl_state():
    """Devuelve dict con track+posición del player, o None si no hay."""
    fmt = FIELD_SEP.join([
        "{{mpris:trackid}}", "{{title}}", "{{artist}}", "{{album}}",
        "{{mpris:length}}", "{{status}}", "{{position}}", "{{mpris:artUrl}}",
    ])
    try:
        out = subprocess.run(
            ["playerctl", "-p", CFG["behavior"]["player"], "metadata", "--format", fmt],
            capture_output=True, text=True, timeout=3,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    fields = out.stdout.strip("\n").split(FIELD_SEP)
    if len(fields) != 8:
        return None
    tid, title, artist, album, length, status, pos, art = fields
    try:
        return {
            "id": tid,
            "title": title,
            "artist": artist,
            "album": album,
            "length": int(length or 0) / 1e6,
            "status": status,
            "pos": int(pos or 0) / 1e6,
            "art": art,
        }
    except ValueError:
        return None


def gaming():
    """True si hay un juego corriendo (no molestar)."""
    for proc in CFG["behavior"]["game_procs"]:
        if subprocess.run(["pgrep", "-x", proc], capture_output=True).returncode == 0:
            return True
    return False


def parse_lrc(text):
    lines = []
    for raw in text.splitlines():
        stamps = TS_RE.findall(raw)
        if not stamps:
            continue
        content = TS_RE.sub("", raw).strip()
        for mins, secs in stamps:
            lines.append((int(mins) * 60 + float(secs), content))
    lines.sort(key=lambda x: x[0])
    return lines or None


def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.load(resp)


def fetch_lyrics(track):
    """Letra sincronizada de lrclib: match exacto y si no, búsqueda."""
    params = urllib.parse.urlencode({
        "artist_name": track["artist"],
        "track_name": track["title"],
        "album_name": track["album"],
        "duration": str(int(round(track["length"]))),
    })
    try:
        data = http_json("https://lrclib.net/api/get?" + params)
        if data.get("syncedLyrics"):
            return parse_lrc(data["syncedLyrics"])
    except Exception:
        pass
    try:
        params = urllib.parse.urlencode({
            "track_name": track["title"],
            "artist_name": track["artist"],
        })
        for data in http_json("https://lrclib.net/api/search?" + params):
            if data.get("syncedLyrics"):
                return parse_lrc(data["syncedLyrics"])
    except Exception:
        pass
    return None


_sock = None
_last_np = None


def _config_event():
    d, e, b = CFG["display"], CFG["effects"], CFG["behavior"]
    return {
        "cmd": "config",
        "screen": d["screen"], "max_dialogs": d["max_dialogs"],
        "scale": d["scale"], "current_scale": d["current_scale"],
        "spawn_area": d["spawn_area"],
        "glitch": e["glitch"], "effects_on_current": e["effects_on_current"],
        "tearing": e["tearing"], "death_age_min": e["death_age_min"],
        "death_age_max": e["death_age_max"], "max_lifetime": e["max_lifetime"],
        "burn_in": e["burn_in"],
        "click_through": b["click_through"], "troll_no": b["troll_no"],
        "np_corner": b["np_corner"], "np_margin": b["np_margin"],
    }


def send(event):
    """Manda un evento JSON al overlay; en cada reconexión manda la config primero
    y reenvía el último Now Playing (el overlay nuevo arranca sin estado)."""
    global _sock, _last_np
    if event.get("cmd") == "np":
        _last_np = event
    data = (json.dumps(event, ensure_ascii=False) + "\n").encode()
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


def show(text, title):
    send({"cmd": "show", "text": text, "title": title})


def clear():
    send({"cmd": "clear"})


def current_line_index(lyrics, pos):
    idx = -1
    for i, (ts, _) in enumerate(lyrics):
        if ts <= pos:
            idx = i
        else:
            break
    return idx


def main():
    track_id = None
    lyrics = None
    idx = -1
    paused_by_game = False
    last_game_check = 0.0
    pause_started = None
    pause_cleared = False
    resend_np = False
    last_pos_sent = 0.0
    pause_clear_s = CFG["behavior"]["pause_clear"]
    offset = CFG["behavior"]["offset"]
    log("cartelitos daemon arrancó")
    send(_config_event())
    while True:
        # pausa automática si hay un juego corriendo
        now = time.monotonic()
        if now - last_game_check > 5:
            last_game_check = now
            if gaming():
                if not paused_by_game:
                    paused_by_game = True
                    track_id = None
                    lyrics = None
                    idx = -1
                    clear()
                    log("juego detectado: cartelitos en pausa")
            elif paused_by_game:
                paused_by_game = False
                log("juego cerrado: cartelitos vuelve")
        if paused_by_game:
            time.sleep(2)
            continue

        t = playerctl_state()
        if not t or t["status"] not in ("Playing", "Paused"):
            if track_id is not None:
                clear()
                track_id = None
                lyrics = None
                idx = -1
            time.sleep(1.5)
            continue

        # música en pausa mucho tiempo → limpiar carteles colgados
        if t["status"] == "Paused":
            if pause_started is None:
                pause_started = now
            elif pause_clear_s > 0 and not pause_cleared and now - pause_started > pause_clear_s:
                clear()
                pause_cleared = True
                resend_np = True
                idx = -1
                log("pausa larga: carteles limpiados")
        else:
            pause_started = None
            pause_cleared = False
            # la pausa larga escondió la funda: al retomar, mostrarla de nuevo
            if resend_np:
                resend_np = False
                if CFG["behavior"]["now_playing"] and t["title"]:
                    send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                          "album": t["album"], "art": t["art"]})

        if t["id"] != track_id:
            track_id = t["id"]
            idx = -1
            clear()
            log(f"track: {t['artist']} — {t['title']}")
            if CFG["behavior"]["now_playing"]:
                send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                      "album": t["album"], "art": t["art"]})
            lyrics = fetch_lyrics(t) if t["title"] else None
            if lyrics:
                log(f"letra sincronizada: {len(lyrics)} líneas")
            else:
                log("sin letra sincronizada (sin carteles)")

        # progreso de la canción para la barra de la funda (1 evento por segundo)
        if (CFG["behavior"]["now_playing"] and t["status"] == "Playing"
                and t["length"] > 0 and now - last_pos_sent >= 1.0):
            last_pos_sent = now
            send({"cmd": "pos", "p": round(t["pos"], 2), "l": round(t["length"], 2)})

        if lyrics and t["status"] == "Playing":
            i = current_line_index(lyrics, t["pos"] + offset)
            if i != idx:
                idx = i
                if i >= 0 and lyrics[i][1]:
                    show(lyrics[i][1], t["title"])

        time.sleep(POLL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
