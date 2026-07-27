#!/usr/bin/env python3
"""cartelitos / fatal-lyrics — synced Spotify lyrics as Windows error dialogs.

Follows playback via MPRIS (playerctl), fetches synced lyrics from
lrclib.net, and sends each line to the Quickshell overlay over a Unix
socket. Config at ~/.config/cartelitos/config.toml (auto-created with
defaults).
"""
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request

UA = "fatal-lyrics/2.4 (https://github.com/FeroxShark/fatal-lyrics)"
FIELD_SEP = "\x1f"
POLL = 0.3
POLL_IDLE = 1.0     # en pausa: un playerctl por segundo alcanza
SOCK_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos.sock")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "cartelitos")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.toml")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "cartelitos", "lyrics")
NONE_TTL = 7 * 86400   # cuánto vale un "este tema no tiene letra" cacheado

DEFAULT_CONFIG = """\
# fatal-lyrics — configuration
# Saving this file applies the changes right away. Menu: fatal config

[display]
screen = "auto"        # "auto" (first monitor) | "all" (every one) | "DP-1" | ["DP-1", "DP-2"]
max_dialogs = 0        # max live dialogs at once; 0 = unlimited
scale = 1.0            # base size for all dialogs
current_scale = 1.3    # extra size factor for the current-line dialog
spawn_area = "full"    # full | top | bottom | left | right | edges (leaves the center clear)
karaoke = false        # current line paints word by word (estimated timing)

[effects]
glitch = "normal"      # off | soft | normal | aggressive
effects_on_current = false  # true = the current dialog also vibrates/glitches
tearing = true         # old dialogs get a split window
death_age_min = 3      # a dialog dies between N…
death_age_max = 7      # …and M dialogs after it appears
max_lifetime = 60      # max lifetime per dialog in seconds; 0 = unlimited
burn_in = true         # dead dialogs leave a fading burnt shadow
cascade = true         # on track change, dialogs die in a chain (CRT domino)

[behavior]
now_playing = true     # vinyl sleeve with album art on track change
np_corner = "top-right"  # where the sleeve docks: top-left | top-right | bottom-left | bottom-right | center
np_margin = 14         # free pixels against the edges (in case of a bar/panel)
np_vinyl = true        # spinning vinyl record peeking out of the sleeve
troll_no = true        # the "No" button duplicates the dialog; false = just closes it
click_through = false  # true = dialogs don't capture the mouse (clicks pass through)
pause_clear = 15       # seconds paused before clearing everything; 0 = never
player = "spotify"     # MPRIS player name (see: playerctl -l)
offset = 0.15          # sync lead time in seconds
game_pause = true      # auto-pause when a window goes fullscreen (generic "game" heuristic
                        # via Hyprland, doesn't depend on a specific process);
                        # false = never pause for games
"""

DEFAULTS = {
    "display": {
        "screen": "auto", "max_dialogs": 0, "scale": 1.0,
        "current_scale": 1.3, "spawn_area": "full", "karaoke": False,
    },
    "effects": {
        "glitch": "normal", "effects_on_current": False, "tearing": True,
        "death_age_min": 3, "death_age_max": 7, "max_lifetime": 60,
        "burn_in": True, "cascade": True,
    },
    "behavior": {
        "now_playing": True, "np_corner": "top-right", "np_margin": 14,
        "np_vinyl": True, "troll_no": True, "click_through": False,
        "pause_clear": 15, "player": "spotify", "offset": 0.15,
        "game_pause": True,
    },
}

TS_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def log(*args):
    print(time.strftime("%H:%M:%S"), *args, flush=True)


def read_config():
    """Lee el TOML mezclado sobre los defaults. Propaga la excepción si está roto."""
    if not os.path.exists(CONFIG_PATH):
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_PATH, "w") as f:
            f.write(DEFAULT_CONFIG)
        log(f"default config created at {CONFIG_PATH}")
    cfg = {k: dict(v) for k, v in DEFAULTS.items()}
    with open(CONFIG_PATH, "rb") as f:
        user = tomllib.load(f)
    for section, values in user.items():
        if section in cfg and isinstance(values, dict):
            cfg[section].update(values)
    return cfg


def load_config():
    try:
        return read_config()
    except Exception as e:
        log(f"invalid config ({e}), using defaults")
        return {k: dict(v) for k, v in DEFAULTS.items()}


CFG = load_config()
# lo setea start_tray(); None = corriendo sin bandeja
_tray_refresh = None


def reload_config():
    """Relee la config sobre el CFG vivo. Si el archivo está roto deja la anterior
    intacta: un typo o un editor a medio guardar no puede resetear nada."""
    try:
        fresh = read_config()
    except Exception as e:
        log(f"config not applied ({e}), keeping the previous one")
        return False
    if fresh == CFG:
        return False
    for section, values in fresh.items():
        CFG[section].update(values)   # in place: todo el proceso lee el mismo dict
    return True


def apply_config():
    """Relee el archivo y aplica: overlay + etiquetas de la bandeja. Único camino,
    lo llaman tanto el watcher como la bandeja (que además no quiere esperar el poll)."""
    if not reload_config():
        return False
    log("config reloaded")
    send(_config_event())
    if _tray_refresh is not None:
        _tray_refresh()
    return True


def watch_config():
    """Aplica la config sola cuando cambia el archivo — sin reiniciar nada."""
    last = None
    while True:
        time.sleep(1.0)
        try:
            stamp = os.stat(CONFIG_PATH).st_mtime_ns
        except OSError:
            continue
        if stamp == last:
            continue
        # el editor trunca y escribe: esperar a que el tamaño se quede quieto
        time.sleep(0.4)
        try:
            stamp = os.stat(CONFIG_PATH).st_mtime_ns
        except OSError:
            continue
        first, last = last is None, stamp
        if first:
            continue
        apply_config()


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
    """True si hay una ventana en pantalla completa (no molestar). Heurística
    genérica vía Hyprland: no depende de una lista de procesos puntuales, así
    que funciona con cualquier juego que pida fullscreen (no detecta borderless
    windowed, que para Hyprland es una ventana normal)."""
    if not CFG["behavior"]["game_pause"]:
        return False
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"],
                             capture_output=True, text=True, timeout=2)
        if out.returncode != 0 or not out.stdout.strip():
            return False
        w = json.loads(out.stdout)
        return bool(w) and (w.get("fullscreen", 0) != 0 or w.get("fullscreenClient", 0) != 0)
    except Exception:
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
    """Letra sincronizada de lrclib: match exacto y si no, búsqueda.

    Devuelve (estado, líneas) con TRES resultados, no dos: "ok", "none" (lrclib
    contestó y este tema no tiene letra sincronizada) y "error" (no se pudo
    llegar a lrclib). Mezclarlos rompe el cache y el reintento, que necesitan
    lo contrario uno del otro: el "no hay" se cachea y no se reintenta, la
    caída de red se reintenta y no se cachea nunca."""
    reached = False

    def try_url(url):
        nonlocal reached
        try:
            data = http_json(url)
        except urllib.error.HTTPError:
            reached = True      # contestó "no lo tengo": es una respuesta, no una caída
            return None
        except Exception:
            return None
        reached = True
        return data

    params = urllib.parse.urlencode({
        "artist_name": track["artist"],
        "track_name": track["title"],
        "album_name": track["album"],
        "duration": str(int(round(track["length"]))),
    })
    data = try_url("https://lrclib.net/api/get?" + params)
    if data and data.get("syncedLyrics"):
        lines = parse_lrc(data["syncedLyrics"])
        if lines:
            return "ok", lines

    params = urllib.parse.urlencode({
        "track_name": track["title"],
        "artist_name": track["artist"],
    })
    for data in try_url("https://lrclib.net/api/search?" + params) or []:
        if data.get("syncedLyrics"):
            lines = parse_lrc(data["syncedLyrics"])
            if lines:
                return "ok", lines

    return ("none", None) if reached else ("error", None)


def _cache_path(track):
    key = FIELD_SEP.join([track["artist"], track["title"], track["album"],
                          str(int(round(track["length"])))])
    return os.path.join(CACHE_DIR, hashlib.sha1(key.encode()).hexdigest() + ".json")


def cache_get(track):
    """Resultado guardado, o None si no hay / caducó."""
    try:
        with open(_cache_path(track)) as f:
            data = json.load(f)
    except Exception:
        return None
    if not data.get("lines"):
        # el "no hay letra" caduca: lrclib suma letras con el tiempo y un tema
        # instrumental hoy puede tenerla el mes que viene
        if time.time() - data.get("at", 0) > NONE_TTL:
            return None
        return "none", None
    return "ok", [(ts, text) for ts, text in data["lines"]]


def cache_put(track, status, lines):
    """Guarda "ok" y "none". Una caída de red NO se guarda: si no, cada tema que
    sonó sin internet queda marcado como sin letra."""
    if status == "error":
        return
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        path = _cache_path(track)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"lines": lines, "at": int(time.time())}, f)
        os.replace(tmp, path)   # atómico: nadie lee un archivo a medio escribir
    except Exception as e:
        log(f"couldn't cache the lyrics ({e})")


# resultado de la búsqueda en curso. `gen` sube en cada cambio de tema: el hilo
# sólo publica si sigue siendo el suyo, y lo chequea con el lock tomado — sin eso,
# un hilo que pasó el chequeo justo antes del cambio pisa el tema nuevo.
_fetch_lock = threading.Lock()
_fetch = {"gen": 0, "id": None, "lyrics": None, "done": False}
RETRY_DELAY = 10
RETRIES = 2


def fetch_lyrics_async(track):
    """Busca la letra en un hilo. Son dos requests con timeout de 10s cada uno:
    hechos en el loop principal, un lrclib lento o caído congelaba todo —
    detección de juego, eventos de progreso y limpieza incluidos."""
    with _fetch_lock:
        _fetch["gen"] += 1
        gen = _fetch["gen"]
        _fetch.update(id=track["id"], lyrics=None, done=False)

    def mine():
        return _fetch["gen"] == gen

    def publish(lines):
        with _fetch_lock:
            if not mine():
                return False
            _fetch.update(lyrics=lines, done=True)
        return True

    def work():
        hit = cache_get(track)
        if hit:
            if publish(hit[1]):
                log(f"cached lyrics: {len(hit[1])} lines" if hit[1]
                    else "no synced lyrics (cached)")
            return
        for attempt in range(RETRIES + 1):
            status, lines = fetch_lyrics(track)
            if status != "error":
                break
            if attempt == RETRIES:
                log("lrclib unreachable, giving up on this track")
                return
            # red caída: esperar y reintentar, salvo que ya haya cambiado de tema
            log(f"lrclib unreachable, retrying in {RETRY_DELAY}s")
            for _ in range(RETRY_DELAY * 2):
                time.sleep(0.5)
                if not mine():
                    return
        cache_put(track, status, lines)
        if publish(lines):
            log(f"synced lyrics: {len(lines)} lines" if lines
                else "no synced lyrics (no dialogs)")

    threading.Thread(target=work, daemon=True, name="lyrics").start()


_sock = None
_last_np = None
# el watcher de config escribe desde otro hilo: sin esto dos eventos se pisan
_send_lock = threading.Lock()


def _config_event():
    d, e, b = CFG["display"], CFG["effects"], CFG["behavior"]
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


def show(text, title, t0=0.0, t1=0.0):
    # t0/t1: comienzo y fin estimado de la línea, para el karaoke del overlay
    send({"cmd": "show", "text": text, "title": title,
          "t0": round(t0, 2), "t1": round(t1, 2)})


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


# --------------------------------------------------------------- setup TUI

def _toml_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return f'"{v}"'
    if isinstance(v, list):
        return "[" + ", ".join(_toml_val(x) for x in v) + "]"
    return str(v)


def _save_config(changes):
    """Pisa claves puntuales del TOML preservando comentarios y el resto.
    changes: {clave: (sección, valor)}. Sólo pisa la clave dentro de SU sección:
    un `scale` suelto en otra sección no se toca. Si no estaba, la agrega al
    final de la suya (o crea la sección)."""
    with open(CONFIG_PATH) as f:
        lines = f.read().split("\n")
    section = None
    pending = dict(changes)
    key_re = re.compile(r"^(\s*)([a-z_]+)(\s*=\s*)([^#]*?)(\s*#.*)?$")
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            section = s[1:-1]
            continue
        m = key_re.match(line)
        if m and m.group(2) in pending and pending[m.group(2)][0] == section:
            _, val = pending.pop(m.group(2))
            lines[i] = f"{m.group(1)}{m.group(2)}{m.group(3)}{_toml_val(val)}{m.group(5) or ''}"
    for key, (sec, val) in pending.items():
        # clave que no estaba: al final de su sección (o en una nueva)
        starts = [i for i, l in enumerate(lines) if l.strip() == f"[{sec}]"]
        if starts:
            end = next((j for j in range(starts[0] + 1, len(lines))
                        if lines[j].strip().startswith("[")), len(lines))
            while end > starts[0] + 1 and not lines[end - 1].strip():
                end -= 1
            lines.insert(end, f"{key} = {_toml_val(val)}")
        else:
            lines += [f"[{sec}]", f"{key} = {_toml_val(val)}", ""]
    with open(CONFIG_PATH, "w") as f:
        f.write("\n".join(lines))


def _players():
    """Players MPRIS detectados vía playerctl; lista vacía si no hay o falta el binario."""
    try:
        out = subprocess.run(["playerctl", "-l"], capture_output=True, text=True, timeout=2)
        if out.returncode == 0:
            return [p.strip() for p in out.stdout.splitlines() if p.strip()]
    except Exception:
        pass
    return []


def _monitors():
    """Monitores conectados vía hyprctl; lista vacía si no es Hyprland."""
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"],
                             capture_output=True, text=True, timeout=3)
        if out.returncode == 0:
            mons = []
            for m in json.loads(out.stdout):
                shape = "vertical" if m.get("transform", 0) % 2 else "horizontal"
                mons.append((m["name"], f"{m['width']}x{m['height']} {shape}"))
            return mons
    except Exception:
        pass
    return []


def _pick(title, options, current):
    """Numbered menu; enter = keep the current value. options: [(label, value)]."""
    print(f"\n{title}   (now: {_fmt(current)})")
    for i, (label, _) in enumerate(options, 1):
        print(f"  {i}) {label}")
    while True:
        raw = input("> ").strip()
        if not raw:
            return None
        if raw.isdigit() and 1 <= int(raw) <= len(options):
            return options[int(raw) - 1][1]
        print("  pick a number from the list, or enter to keep it")


def _ask_num(title, current, lo, hi):
    print(f"\n{title}   (now: {current}, enter = keep)")
    while True:
        raw = input("> ").strip().replace(",", ".")
        if not raw:
            return None
        try:
            v = float(raw)
            if lo <= v <= hi:
                return v
        except ValueError:
            pass
        print(f"  a number between {lo} and {hi}")


def _ask_int(title, current, lo, hi):
    print(f"\n{title}   (now: {current}, enter = keep)")
    while True:
        raw = input("> ").strip()
        if not raw:
            return None
        try:
            v = int(raw)
            if lo <= v <= hi:
                return v
        except ValueError:
            pass
        print(f"  an integer between {lo} and {hi}")


def _ask_text(title, current):
    print(f"\n{title}   (now: \"{current}\", enter = keep)")
    raw = input("> ").strip()
    return raw or None


def _ask_screens(current):
    """Pantallas: auto / todas / una / varias. Devuelve str o lista."""
    mons = _monitors()
    opts = [("auto (first monitor)", "auto"), ("all screens", "all")]
    opts += [(f"only {n}  ({info})", n) for n, info in mons]
    if len(mons) > 1:
        opts.append(("several (pick which)", "__multi__"))
    v = _pick("Which screen(s) should dialogs appear on?", opts, _fmt(current))
    if v != "__multi__":
        return v
    for i, (n, info) in enumerate(mons, 1):
        print(f"  {i}) {n}  ({info})")
    raw = input("comma-separated numbers (e.g. 1,3) > ").strip()
    picked = [mons[int(t) - 1][0] for t in (t.strip() for t in raw.split(","))
              if t.isdigit() and 1 <= int(t) <= len(mons)]
    return picked or None


def _ask_player(current):
    players = _players()
    if not players:
        return _ask_text("MPRIS player to follow (see: playerctl -l)", current)
    v = _pick("MPRIS player to follow",
              [(p, p) for p in players] + [("other (type it in)", "__manual__")], current)
    if v == "__manual__":
        return _ask_text("Player name (see: playerctl -l)", current)
    return v


YESNO = [("yes", True), ("no", False)]

# (clave, sección, etiqueta, editor). El editor recibe el valor actual y
# devuelve el nuevo, o None para dejarlo como está.
SETTINGS = [
    ("— screen —", None, None, None),
    ("screen", "display", "Screens", _ask_screens),
    ("spawn_area", "display", "Spawn zone", lambda c: _pick("Spawn zone", [
        ("full screen", "full"), ("top", "top"), ("bottom", "bottom"),
        ("left", "left"), ("right", "right"),
        ("edges (leaves the center clear)", "edges")], c)),
    ("scale", "display", "Dialog scale", lambda c: _ask_num("Dialog scale", c, 0.5, 3.0)),
    ("current_scale", "display", "Extra scale, current line",
     lambda c: _ask_num("Extra scale for the current-line dialog", c, 0.5, 3.0)),
    ("max_dialogs", "display", "Max live dialogs (0 = unlimited)",
     lambda c: _ask_int("Max live dialogs at once (0 = unlimited)", c, 0, 50)),
    ("karaoke", "display", "Karaoke (paints word by word)",
     lambda c: _pick("Karaoke (current line paints word by word)", YESNO, c)),

    ("— effects —", None, None, None),
    ("glitch", "effects", "Glitch intensity", lambda c: _pick("Glitch intensity", [
        ("off (clean dialogs)", "off"), ("soft", "soft"),
        ("normal", "normal"), ("aggressive (dying GPU)", "aggressive")], c)),
    ("effects_on_current", "effects", "Current dialog also glitches",
     lambda c: _pick("The current dialog also vibrates/glitches", YESNO, c)),
    ("tearing", "effects", "Split window on old dialogs",
     lambda c: _pick("Split window on old dialogs", YESNO, c)),
    ("burn_in", "effects", "Burn-in shadow when one dies",
     lambda c: _pick("Fading burnt shadow when a dialog dies (burn-in)", YESNO, c)),
    ("cascade", "effects", "Chain death on track change",
     lambda c: _pick("Dialogs die in a chain on track change", YESNO, c)),
    ("death_age_min", "effects", "A dialog dies after at least",
     lambda c: _ask_int("A dialog dies between... (new dialogs after it appears)", c, 1, 50)),
    ("death_age_max", "effects", "...and at most",
     lambda c: _ask_int("...and at most (new dialogs)", c, 1, 50)),
    ("max_lifetime", "effects", "Max lifetime, seconds (0 = unlimited)",
     lambda c: _ask_int("Max lifetime per dialog in seconds (0 = unlimited)", c, 0, 600)),

    ("— vinyl sleeve —", None, None, None),
    ("now_playing", "behavior", "Sleeve with album art",
     lambda c: _pick("Vinyl sleeve (album art on track change)", YESNO, c)),
    ("np_corner", "behavior", "Where it docks", lambda c: _pick("Where should the sleeve dock?", [
        ("top-left", "top-left"), ("top-right", "top-right"),
        ("bottom-left", "bottom-left"), ("bottom-right", "bottom-right"),
        ("always centered (shrinks in place)", "center")], c)),
    ("np_margin", "behavior", "Margin against the edges (px)",
     lambda c: _ask_int("Sleeve margin against the edges (px)", c, 0, 200)),
    ("np_vinyl", "behavior", "Spinning vinyl record",
     lambda c: _pick("Spinning vinyl record peeking out of the sleeve", YESNO, c)),

    ("— behavior —", None, None, None),
    ("player", "behavior", "Player to follow", _ask_player),
    ("offset", "behavior", "Sync lead time (s)",
     lambda c: _ask_num("Lyric sync lead time in seconds (can be negative)", c, -2.0, 2.0)),
    ("troll_no", "behavior", '"No" button duplicates the dialog',
     lambda c: _pick('The "No" button duplicates the dialog', YESNO, c)),
    ("click_through", "behavior", "Ghost dialogs (clicks pass through)",
     lambda c: _pick("Ghost dialogs (clicks pass through)", YESNO, c)),
    ("pause_clear", "behavior", "Clear after N s paused (0 = never)",
     lambda c: _ask_int("Seconds paused before clearing everything (0 = never)", c, 0, 300)),
    ("game_pause", "behavior", "Auto-pause on fullscreen games",
     lambda c: _pick("Auto-pause when a game is in fullscreen", YESNO, c)),
]

DIM, BOLD, YEL, OFF = "\033[2m", "\033[1m", "\033[33m", "\033[0m"


def _fmt(v):
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, list):
        return ", ".join(str(x) for x in v)
    return str(v)


def _daemon_pid():
    """PID del daemon, o None. Confirma el cmdline: un PID reciclado con
    SIGUSR1 encima mata un proceso ajeno."""
    try:
        with open("/tmp/cartelitos-daemon.pid") as f:
            pid = int(f.read().strip())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            if b"cartelitos" not in f.read():
                return None
        return pid
    except (OSError, ValueError):
        return None


def _demo():
    """Le pide al daemon un par de carteles de mentira, para ver los cambios
    sin depender de que haya música sonando."""
    pid = _daemon_pid()
    if not pid or not os.path.exists(SOCK_PATH):
        print("  fatal-lyrics isn't running — start it with: fatal on")
        return
    os.kill(pid, signal.SIGUSR1)
    print("  demo dialogs sent")


def _menu(cfg, opening):
    print("\033[H\033[J", end="")
    print(f"{BOLD}fatal-lyrics — config{OFF}   "
          f"{DIM}every change applies live, no restart{OFF}\n")
    rows = {}
    n = 0
    for key, section, label, editor in SETTINGS:
        if section is None:
            print(f"\n {DIM}{key}{OFF}")
            continue
        n += 1
        rows[n] = (key, section, label, editor)
        cur, was = cfg[section][key], opening[section][key]
        dots = "." * max(1, 34 - len(label))
        mark = f" {YEL}*{OFF} {DIM}(was {_fmt(was)}){OFF}" if cur != was else ""
        print(f"  {n:>2}  {label} {DIM}{dots}{OFF} {_fmt(cur)}{mark}")
    print(f"\n {DIM}number{OFF} edit   {DIM}d{OFF} demo dialogs   "
          f"{DIM}u{OFF} undo everything   {DIM}q{OFF} done")
    return rows


def setup():
    """Menú: todo a la vista, se edita sólo lo que se quiere, se aplica al toque."""
    cfg = load_config()
    opening = {s: dict(v) for s, v in cfg.items()}
    msg = ""
    while True:
        rows = _menu(cfg, opening)
        if msg:
            print(f"\n{msg}")
            msg = ""
        raw = input("\n> ").strip().lower()

        if raw in ("q", "quit", "exit", "x", ""):
            changed = [(k, s) for s, vals in cfg.items() for k in vals
                       if vals[k] != opening[s][k]]
            print("\033[H\033[J", end="")
            if changed:
                print(f"Saved to {CONFIG_PATH}:")
                for key, sec in changed:
                    print(f"  {sec}.{key} = {_toml_val(cfg[sec][key])}")
            else:
                print("No changes.")
            return

        if raw in ("d", "demo"):
            _demo()
            input("  enter to go back ")
            continue

        if raw in ("u", "undo"):
            back = {k: (s, opening[s][k]) for s, vals in cfg.items() for k in vals
                    if vals[k] != opening[s][k]}
            if not back:
                msg = "  nothing to undo"
                continue
            _save_config(back)
            for key, (sec, val) in back.items():
                cfg[sec][key] = val
            msg = f"  {len(back)} setting(s) back to how you found them"
            continue

        if not (raw.isdigit() and int(raw) in rows):
            msg = "  pick a number from the list, or q to finish"
            continue

        key, section, _, editor = rows[int(raw)]
        print("\033[H\033[J", end="")
        try:
            new = editor(cfg[section][key])
        except (KeyboardInterrupt, EOFError):
            continue
        if new is None or new == cfg[section][key]:
            continue
        cfg[section][key] = new
        _save_config({key: (section, new)})
        msg = f"  {section}.{key} = {_toml_val(new)}"
        if key in ("death_age_min", "death_age_max") and \
                cfg["effects"]["death_age_min"] > cfg["effects"]["death_age_max"]:
            msg += f"\n  {YEL}heads up:{OFF} the minimum is above the maximum"


def current_line_index(lyrics, pos):
    idx = -1
    for i, (ts, _) in enumerate(lyrics):
        if ts <= pos:
            idx = i
        else:
            break
    return idx


def set_option(key, section, value):
    """Escribe una clave y la aplica ya. Mismo camino que el menú y que editar el
    TOML a mano: se escribe el archivo y se relee."""
    _save_config({key: (section, value)})
    apply_config()


def _terminal():
    """Terminal para abrir el menú completo. $TERMINAL primero: en un repo público
    no se puede asumir la de nadie."""
    names = [os.environ.get("TERMINAL"), "kitty", "alacritty", "foot", "wezterm",
             "ghostty", "konsole", "gnome-terminal", "xterm"]
    for name in names:
        if name:
            found = shutil.which(name)
            if found:
                return found
    return None


# submenús de la bandeja: (clave, sección, título, [(etiqueta, valor)])
TRAY_CHOICES = [
    ("glitch", "effects", "Glitch", [
        ("Off", "off"), ("Soft", "soft"), ("Normal", "normal"),
        ("Aggressive", "aggressive")]),
    ("spawn_area", "display", "Spawn zone", [
        ("Full screen", "full"), ("Top", "top"), ("Bottom", "bottom"),
        ("Left", "left"), ("Right", "right"), ("Edges", "edges")]),
]
# toggles que se cambian de un click, con el estado en el texto
TRAY_TOGGLES = [
    ("karaoke", "display", "Karaoke"),
    ("now_playing", "behavior", "Album art"),
    ("tearing", "effects", "Tearing"),
]
SCALE_STEP = 0.1


def start_tray():
    """Ícono en la bandeja del sistema mientras el daemon está vivo (StatusNotifierItem
    vía AyatanaAppIndicator3). Opcional: si gtk3/libayatana-appindicator no están
    instalados, el daemon sigue andando igual, sin bandeja.

    El estado va en el TEXTO de cada ítem ("Glitch: normal", "• Soft"), no en
    checkboxes: DBusMenu los expone, pero varios shells (caelestia, entre otros)
    dibujan sólo ícono + texto y el tilde no se ve. Los submenús sí se dibujan."""
    global _tray_refresh
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        gi.require_version("AyatanaAppIndicator3", "0.1")
        from gi.repository import Gtk, GLib, AyatanaAppIndicator3
    except Exception as e:
        log(f"tray not available ({e}), continuing without an icon")
        return

    fatal_bin = shutil.which("fatal") or os.path.expanduser("~/.local/bin/fatal")
    term = _terminal()
    labels = []   # [(item, función que devuelve el texto)] para refrescar

    def item(menu, label, on_click=None, dynamic=None):
        it = Gtk.MenuItem(label=label)
        if on_click:
            it.connect("activate", lambda *_: on_click())
        else:
            it.set_sensitive(False)
        if dynamic:
            labels.append((it, dynamic))
        menu.append(it)
        return it

    def run():
        indicator = AyatanaAppIndicator3.Indicator.new(
            "cartelitos", "dialog-warning",
            AyatanaAppIndicator3.IndicatorCategory.APPLICATION_STATUS)
        indicator.set_status(AyatanaAppIndicator3.IndicatorStatus.ACTIVE)
        indicator.set_title("Fatal Lyrics")

        menu = Gtk.Menu()
        item(menu, "Fatal Lyrics active")
        menu.append(Gtk.SeparatorMenuItem())

        for key, section, title, options in TRAY_CHOICES:
            sub = Gtk.Menu()
            for label, value in options:
                # el punto marca la opción activa: el tilde de DBusMenu no se dibuja
                item(sub, label,
                     on_click=lambda k=key, s=section, v=value: set_option(k, s, v),
                     dynamic=lambda l=label, k=key, s=section, v=value:
                         ("• " if CFG[s][k] == v else "   ") + l)
            root_item = item(menu, title,
                             dynamic=lambda t=title, k=key, s=section:
                                 f"{t}: {CFG[s][k]}")
            root_item.set_sensitive(True)
            root_item.set_submenu(sub)

        size = Gtk.Menu()
        item(size, "Bigger", on_click=lambda: set_option(
            "scale", "display", round(min(CFG["display"]["scale"] + SCALE_STEP, 3.0), 2)))
        item(size, "Smaller", on_click=lambda: set_option(
            "scale", "display", round(max(CFG["display"]["scale"] - SCALE_STEP, 0.5), 2)))
        item(size, "Reset", on_click=lambda: set_option("scale", "display", 1.0))
        size_root = item(menu, "Size",
                         dynamic=lambda: f"Size: {CFG['display']['scale']}")
        size_root.set_sensitive(True)
        size_root.set_submenu(size)

        for key, section, title in TRAY_TOGGLES:
            item(menu, title,
                 on_click=lambda k=key, s=section: set_option(k, s, not CFG[s][k]),
                 dynamic=lambda t=title, k=key, s=section:
                     f"{t}: {'on' if CFG[s][k] else 'off'}")

        menu.append(Gtk.SeparatorMenuItem())
        item(menu, "Demo dialogs", on_click=lambda: demo())
        if term:
            item(menu, "All settings…",
                 on_click=lambda: subprocess.Popen([term, "-e", fatal_bin, "config"]))
        menu.append(Gtk.SeparatorMenuItem())
        item(menu, "Quit", on_click=lambda: subprocess.Popen([fatal_bin, "off"]))

        def refresh():
            for it, text in labels:
                it.set_label(text())
            return False   # idle_add: una sola pasada

        refresh()
        menu.show_all()
        indicator.set_menu(menu)
        # el watcher corre en otro hilo; GTK sólo se toca desde el suyo
        global _tray_refresh
        _tray_refresh = lambda: GLib.idle_add(refresh)
        Gtk.main()

    threading.Thread(target=run, daemon=True, name="tray").start()


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
    log("fatal-lyrics daemon started")
    start_tray()
    send(_config_event())
    threading.Thread(target=watch_config, daemon=True, name="config").start()
    signal.signal(signal.SIGUSR1, demo)
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
                    log("game detected: pausing")
            elif paused_by_game:
                paused_by_game = False
                log("game closed: resuming")
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
            elif (CFG["behavior"]["pause_clear"] > 0 and not pause_cleared
                    and now - pause_started > CFG["behavior"]["pause_clear"]):
                clear()
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
            lyrics = None
            if t["title"]:
                fetch_lyrics_async(t)
            else:
                _fetch.update(id=None, lyrics=None, done=False)

        # la búsqueda corre en un hilo: se recoge cuando llega
        if lyrics is None and _fetch["done"] and _fetch["id"] == track_id:
            lyrics = _fetch["lyrics"]

        # progreso de la canción: barra de la funda + karaoke (1 evento por segundo)
        if ((CFG["behavior"]["now_playing"] or CFG["display"]["karaoke"])
                and t["status"] == "Playing"
                and t["length"] > 0 and now - last_pos_sent >= 1.0):
            last_pos_sent = now
            send({"cmd": "pos", "p": round(t["pos"], 2), "l": round(t["length"], 2)})

        if lyrics and t["status"] == "Playing":
            i = current_line_index(lyrics, t["pos"] + CFG["behavior"]["offset"])
            if i != idx:
                idx = i
                if i >= 0 and lyrics[i][1]:
                    t1 = lyrics[i + 1][0] if i + 1 < len(lyrics) else lyrics[i][0] + 5
                    show(lyrics[i][1], t["title"], lyrics[i][0], t1)

        # Cada vuelta spawnea un playerctl (~4 ms de CPU). El poll fino sólo hace
        # falta para pegarle al momento de cada verso: en pausa, o en un tema sin
        # letra sincronizada, con una vuelta por segundo alcanza — y ésa es la
        # frecuencia de los eventos de progreso, así que no se pierde nada.
        fast = t["status"] == "Playing" and lyrics
        time.sleep(POLL if fast else POLL_IDLE)


if __name__ == "__main__":
    if "--setup" in sys.argv[1:]:
        try:
            setup()
        except (KeyboardInterrupt, EOFError):
            print("\nok, bye")
        sys.exit(0)
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
