#!/usr/bin/env python3
"""cartelitos / fatal-lyrics — synced Spotify lyrics as Windows error dialogs.

Follows playback via MPRIS (playerctl), fetches synced lyrics from
lrclib.net, and sends each line to the Quickshell overlay over a Unix
socket. Config at ~/.config/cartelitos/config.toml (auto-created with
defaults).
"""
import hashlib
import json
import math
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request

UA = "fatal-lyrics/3.0 (https://github.com/FeroxShark/fatal-lyrics)"
FIELD_SEP = "\x1f"
POLL = 0.3
POLL_IDLE = 1.0     # en pausa: un playerctl por segundo alcanza
SOCK_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos.sock")
# interruptor del modo CRT: un archivo, no el socket (ver set_crt)
CRT_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos-crt")
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

[crt]
# CRT mode: every screen becomes one big cathode ray tube showing the lyric.
# It covers the whole desktop, so it is opt-in and toggled by hand:
#   fatal crt on | off | toggle     (works even if the daemon is dead)
enabled = false        # true = start with the tube on
screens = "all"        # which screens the tube takes: "all" | "DP-1" | ["DP-1","DP-2"]
                       # | "same" (the same ones the dialogs use)
order = "auto"         # screen order, left to right — this is what decides where each
                       # piece of a split line lands. "auto" = the layout the compositor
                       # already knows; or name them: ["DP-1", "HDMI-A-1", "DP-2"]
palette = "album"      # where the two colours come from:
                       #   "album" = from the cover of what's playing (needs
                       #             ImageMagick; falls back to the presets)
                       #   "auto"  = a preset picked by the register of the song
                       #   or a preset by name: dragons | ado | poison | bloodline
                       #             | vapor | bone
                       # Each palette is TWO faces that go together — one lit screen
                       # (burnt background, dark letters) and one dark tube (deep
                       # background, glowing letters). Your screens alternate between
                       # them, so there are never three colours fighting each other.
split = "mixed"        # how the line is spread over several screens:
                       # mixed = whole phrase, and short lines cut in pieces
                       # whole = never cut | fragment = always cut short lines
director = true        # the lyric travels across the screens instead of showing the
                       # same thing on all of them at once: one screen is in focus,
                       # the phrase continues on the next one, the rest go quiet
focus = "roam"         # "roam" = the focus moves around | "all" = every screen shows
                       # the whole line at the same time (the old behaviour)
audio = true           # react to what's actually playing (captures the sound card's
                       # monitor with pw-record/parec — no extra packages). Only while
                       # the tube is up. false = everything follows the lyric clock
color_from_pitch = true  # the phosphor leans on the register of what's playing:
                       # high voices go cyan/blue, low ones amber/red
color_hold = 10        # seconds a colour has to stay before it may change again
motifs = true          # animations on the quiet screens (an eye, bars, rings, a tunnel)
camera = 1.0           # how much the framing moves (letterbox, zoom); 0 = still
quality = 1.0          # resolution the tube is drawn at, before the CRT pass (1.0 =
                       # native). Lower it on a weaker GPU: the glass, the bloom and
                       # the phosphor grid hide most of the difference
exit_on = "mouse"      # how you get out of the tube:
                       #   "mouse"    = cursor hidden, moving it (or a click, or the
                       #                wheel) returns
                       #   "keyboard" = any key returns, but the cursor stays visible
                       # (a layer surface can't hold the keyboard and the pointer at
                       # once; `fatal crt off` and a compositor keybind always work)
font = ""              # font family for the lyric; "" = system default
chrome = false         # console readouts (REC, track, timecode, progress bar). Off by
                       # default: full screen, nothing else on it
intensity = 0.45       # how restless the tube is: signal breaks, how hard beats
                       # shake it, static. 0 = dead still, 1 = the old behaviour
word_flash = 0.3       # how much each word flashes as it lands: 0 = it arrives
                       # straight in its own colour, 1 = it lands white. This one is
                       # not the tube beating — it happens on EVERY word, which is
                       # what reads as "the letters keep flickering"
flicker = 0.25         # how hard AND how often the picture beats with the music
                       # (the curve is gentle at the bottom, which is where you
                       # actually want to live: 0.25 is a light beat, not a quarter
                       # of the way to a strobe):
                       # 0 = the light never moves, 1 = it thumps every couple of
                       # seconds. Above ~0.6 the loudest part of a song also gets the
                       # odd blackout of a frame or two. Whenever it beats, the
                       # animations on the other screens surge along with it
curvature = 1.0        # how fat the tube glass is (0 = flat panel)
scanlines = 0.5        # depth of the horizontal comb
chroma = 0.6           # steady RGB misalignment
bloom = 1.0            # phosphor glow around the letters
noise = 0.22           # static
roll = 0.5             # brightness bar rolling down the tube
vignette = 0.9         # darkening towards the corners
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
    "crt": {
        "enabled": False, "screens": "all", "order": "auto", "palette": "album",
        "split": "mixed", "director": True, "focus": "roam", "audio": True,
        "color_from_pitch": True, "color_hold": 10, "motifs": True, "camera": 1.0,
        "quality": 1.0,
        "exit_on": "mouse", "font": "",
        "chrome": False, "intensity": 0.45, "flicker": 0.25, "word_flash": 0.3, "curvature": 1.0, "scanlines": 0.5,
        "chroma": 0.6, "bloom": 1.0, "noise": 0.22, "roll": 0.5, "vignette": 0.9,
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


def crt_on():
    """True si el tubo está prendido ahora mismo."""
    try:
        with open(CRT_PATH) as f:
            return f.read().strip() == "1"
    except OSError:
        return False


def set_crt(on):
    """Prende/apaga el modo CRT escribiendo el interruptor.

    El estado va en un archivo de XDG_RUNTIME_DIR y no por el socket a propósito:
    el overlay lo vigila él mismo, así que `fatal crt off` apaga el tubo aunque el
    daemon esté colgado o muerto. Con las tres pantallas tapadas por el tubo, esa
    es la única salida que no depende de nada que pueda romperse."""
    try:
        tmp = CRT_PATH + ".tmp"
        with open(tmp, "w") as f:
            f.write("1" if on else "0")
        os.replace(tmp, CRT_PATH)   # atómico: el overlay nunca lee un archivo a medias
        return True
    except OSError as e:
        log(f"couldn't switch CRT mode ({e})")
        return False


def apply_config():
    """Relee el archivo y aplica: overlay + etiquetas de la bandeja. Único camino,
    lo llaman tanto el watcher como la bandeja (que además no quiere esperar el poll)."""
    was_crt = CFG["crt"]["enabled"]
    if not reload_config():
        return False
    log("config reloaded")
    # sólo si cambió en el archivo: un `fatal crt off` en vivo no se pisa con
    # cualquier otro cambio de config que pase después
    if CFG["crt"]["enabled"] != was_crt:
        set_crt(CFG["crt"]["enabled"])
    send(_config_event())
    if _tray_refresh is not None:
        _tray_refresh()
    return True


TUNE_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos-tune")


def parse_tune(text):
    """Líneas `clave=valor` que manda el panel de sliders. Devuelve sólo las
    claves que existen en [crt] y con el número bien formado: es un archivo que
    escribe otro proceso, no se le cree nada."""
    out = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, _, raw = line.partition("=")
        key = key.strip()
        if key not in DEFAULTS["crt"]:
            continue
        try:
            value = float(raw.strip())
        except ValueError:
            continue
        out[key] = value
    return out


def watch_tune():
    """Aplica lo que mueve el panel de sliders (`fatal tune`).

    Va por archivo y no por el socket porque el socket lo sirve el overlay: el
    panel es otro proceso y sólo tiene que dejar el valor escrito. El daemon lo
    pasa a la config, así el cambio queda para la próxima vez."""
    # Se anota lo que YA estaba al arrancar: así lo que quedó de una sesión
    # anterior no se aplica, pero el primer movimiento del slider sí (antes se
    # perdía el primer arrastre, que es justo el que uno prueba).
    try:
        last = os.stat(TUNE_PATH).st_mtime_ns
    except OSError:
        last = None
    while True:
        time.sleep(0.35)
        try:
            stamp = os.stat(TUNE_PATH).st_mtime_ns
        except OSError:
            continue
        if stamp == last:
            continue
        last = stamp
        try:
            with open(TUNE_PATH) as f:
                changes = parse_tune(f.read())
        except OSError:
            continue
        for key, value in changes.items():
            log(f"tune: crt.{key} = {value}")
            set_option(key, "crt", value)


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


# Ventanas que se ponen en pantalla completa TODO el tiempo y no son un juego:
# un video a pantalla completa es justo cuando uno quiere que esto siga andando.
NOT_A_GAME = ("chrome", "chromium", "firefox", "zen", "brave", "vivaldi",
              "librewolf", "waterfox", "epiphany", "mpv", "vlc", "celluloid",
              "haruna", "totem", "spotify", "netflix", "youtube")


def is_game_window(win):
    """¿Esa ventana a pantalla completa es un juego, o alguien mirando un video?

    La heurística de "fullscreen = juego" sola es demasiado ancha: un YouTube a
    pantalla completa apagaba la letra entera, que es exactamente cuando uno la
    quiere. Se mira la clase de la ventana antes de cortar."""
    if not win:
        return False
    if win.get("fullscreen", 0) == 0 and win.get("fullscreenClient", 0) == 0:
        return False
    name = (str(win.get("class", "")) + " " + str(win.get("initialClass", ""))).lower()
    return not any(tag in name for tag in NOT_A_GAME)


def gaming():
    """True si hay un JUEGO en pantalla completa (no molestar). Vía Hyprland, sin
    depender de una lista de juegos: cualquiera que pida fullscreen cuenta, menos
    los navegadores y reproductores (ver is_game_window). No detecta borderless
    windowed, que para Hyprland es una ventana normal."""
    if not CFG["behavior"]["game_pause"]:
        return False
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"],
                             capture_output=True, text=True, timeout=2)
        if out.returncode != 0 or not out.stdout.strip():
            return False
        return is_game_window(json.loads(out.stdout))
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
    d, e, b, c = CFG["display"], CFG["effects"], CFG["behavior"], CFG["crt"]
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


# ---------------------------------------------------------------- portada
# Los colores del tubo salen de la tapa del disco: así cada tema trae los suyos
# y no hay que elegir a mano una paleta que combine. Se saca con ImageMagick, que
# es opcional — sin él, el modo usa las paletas de fábrica.
_art_cache = {}


def parse_histogram(text, keep=4):
    """Colores dominantes de la salida `histogram:` de ImageMagick.

    Ordena por presencia PESADA POR SATURACIÓN: la tapa más común del mundo es
    mayormente gris o negra, y si se ordena por cantidad pelada el tubo termina
    pintado del color de una sombra."""
    out = []
    for line in text.splitlines():
        line = line.strip()
        if ":" not in line or "#" not in line:
            continue
        try:
            count = int(line.split(":", 1)[0])
            hexa = line.split("#", 1)[1].split()[0][:6]
            r, g, b = (int(hexa[i:i + 2], 16) for i in (0, 2, 4))
        except (ValueError, IndexError):
            continue
        hi, lo = max(r, g, b), min(r, g, b)
        sat = (hi - lo) / hi if hi else 0.0
        light = hi / 255.0
        # ni el negro ni el blanco puro sirven de color de pantalla
        weight = count * (0.15 + sat) * (0.25 + min(light, 0.85))
        out.append((weight, sat, "#" + hexa.lower()))
    out.sort(reverse=True)
    # los que tienen tono de verdad primero; los grises quedan al final, sólo por
    # si la tapa entera es gris y no hay nada mejor
    tinted = [c for _, sat, c in out if sat >= 0.15]
    greys = [c for _, sat, c in out if sat < 0.15]
    return (tinted + greys)[:keep]


def album_colors(url):
    """Hasta cuatro colores de la portada. None si no se puede (sin red, sin
    ImageMagick, sin portada): el tubo sigue andando con sus paletas."""
    if not url:
        return None
    if url in _art_cache:
        return _art_cache[url]
    tool = shutil.which("magick") or shutil.which("convert")
    if not tool:
        return None
    path = None
    try:
        if url.startswith("file://"):
            path = urllib.parse.unquote(url[7:])
            tmp = None
        else:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = resp.read(4_000_000)
            tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False)
            tmp.write(data)
            tmp.close()
            path = tmp.name
        out = subprocess.run(
            [tool, path, "-resize", "64x64!", "-colors", "6", "-format", "%c",
             "histogram:info:"], capture_output=True, text=True, timeout=10)
        colors = parse_histogram(out.stdout) if out.returncode == 0 else None
    except Exception as e:
        log(f"couldn't read the cover's colours ({e})")
        colors = None
    finally:
        if tmp is not None and path:
            try:
                os.unlink(path)
            except OSError:
                pass
    _art_cache[url] = colors
    return colors


def send_album_colors(url):
    """Los saca en un hilo: descarga + ImageMagick no pueden trabar la letra."""
    def work():
        colors = album_colors(url)
        if colors:
            send({"cmd": "art", "colors": colors})
    threading.Thread(target=work, daemon=True, name="art").start()



# ------------------------------------------------------- cortes de la línea
# Una línea de letra no siempre es una frase: muchas veces son golpes repetidos
# ("take-take-take me to the beach", "down, down, down, down", "take me, take me,
# take me"). Cada golpe se merece su propia pantalla, así que la línea se corta
# acá — en el daemon, donde se puede probar de verdad — y viaja ya cortada.
SEG_PUNCT = re.compile(r"[\s.,;:!¡?¿\"'“”‘’()\[\]{}…·•\-–—*~`+/|\\]+")
SEG_SPLIT = re.compile(r"\s*[/|]\s*")
SEG_MAX = 6                 # más pedazos que esto y cada uno dura un suspiro
SEG_MAX_SHORT = 9           # salvo que sean cortitos: deletrear pide más lugar


def seg_key(word):
    """Palabra normalizada para comparar: sin puntuación y sin mayúsculas.

    NO se filtra por alfabeto: sacando todo lo que no fuera a–z, una letra en
    japonés o en cirílico quedaba en blanco y dos palabras distintas parecían la
    misma repetición."""
    return SEG_PUNCT.sub("", word.lower())


def expand_repeats(word):
    """Abre las repeticiones pegadas con guiones: "Take-take-take" son tres.

    Sólo si los pedazos se repiten de verdad — "T-A-K-E" es una palabra
    deletreada y "people-pleasing" es una compuesta, y ésas no se tocan."""
    if "-" not in word:
        return [word]
    parts = [p for p in word.split("-") if p]
    if len(parts) < 2:
        return [word]
    keys = [seg_key(p) for p in parts]
    # antes se exigía que el pedazo tuviera más de una letra, para no romper
    # "T-A-K-E"; de eso ahora se ocupa expand_spelled, así que "D-D-D-DJ" también
    # se abre
    repeated = any(keys[i] and keys[i] == keys[i - 1] for i in range(1, len(keys)))
    return parts if repeated else [word]


SPELL_SEP = re.compile(r"[-.·•]")


def expand_spelled(word):
    """Abre una palabra DELETREADA: "T-A-K-E" se canta letra por letra, o sea son
    cuatro golpes, no una palabra.

    Se pide que TODOS los pedazos sean de un solo carácter y que haya al menos
    tres: así entran "R-E-S-P-E-C-T" y "9-1-1", y quedan afuera "e-mail",
    "T-shirt", "K-pop" o "U-turn", que tienen una letra suelta pero no se
    deletrean."""
    parts = [p for p in SPELL_SEP.split(word) if p]
    if len(parts) < 3:
        return [word]
    if not all(len(seg_key(p)) == 1 for p in parts):
        return [word]
    return parts


def spelled_run(keys, i):
    """Largo de la tirada de letras sueltas que arranca en i ("T A K E" separado
    por espacios es lo mismo que deletreado con guiones)."""
    n = 0
    while i + n < len(keys) and len(keys[i + n]) == 1:
        n += 1
    return n


def split_repeats(text):
    """Corta una línea en golpes. Devuelve la lista de pedazos, en orden.

    Busca grupos de hasta tres palabras que se repitan pegados: cubre desde
    "na na na" hasta "take me, take me, take me". Si no hay repeticiones queda
    un solo pedazo y la línea sigue entera."""
    out = []
    for part in SEG_SPLIT.split(text):
        words = []
        for raw in part.split():
            for piece in expand_repeats(raw):
                words.extend(expand_spelled(piece))
        keys = [seg_key(w) for w in words]
        cur = []
        i = 0
        while i < len(words):
            # una palabra deletreada: cada letra es un golpe propio
            run = spelled_run(keys, i)
            if run >= 3:
                if cur:
                    out.append(" ".join(cur))
                    cur = []
                for k in range(run):
                    out.append(words[i + k])
                i += run
                continue

            group = 0
            # De MENOR a mayor: "take take take take" son cuatro golpes, no dos
            # pares. El grupo grande sólo gana cuando el chico no repite, que es
            # justo el caso de "take me, take me".
            for n in range(1, min(3, (len(words) - i) // 2) + 1):
                if keys[i:i + n] == keys[i + n:i + 2 * n] and any(keys[i:i + n]):
                    group = n
                    break
            if group == 0:
                cur.append(words[i])
                i += 1
                continue
            if cur:
                out.append(" ".join(cur))
                cur = []
            base = keys[i:i + group]
            while i + group <= len(words) and keys[i:i + group] == base:
                out.append(" ".join(words[i:i + group]))
                i += group
        if cur:
            out.append(" ".join(cur))
    out = [sg for sg in (s.strip() for s in out) if sg]
    # demasiados pedazos no se leen: los últimos se juntan. Una palabra
    # deletreada entra con más, porque cada golpe es una letra sola.
    cap = SEG_MAX_SHORT if all(len(sg) <= 2 for sg in out) else SEG_MAX
    if len(out) > cap:
        out = out[:cap - 1] + [" ".join(out[cap - 1:])]
    return out


# --------------------------------------------------------- perfil del tema
# El tubo no reacciona sólo al instante: mide la canción entera y ubica cada
# momento DENTRO de ella. "Fuerte" no es un número de volumen, es estar arriba
# de lo que viene siendo este tema — un lofi entero no puede ser todo "bajo" ni
# un tema de metal todo "drop".
#
# El perfil se guarda: la segunda vez que suena el tema, el modo ya sabe dónde
# están los silencios y los golpes ANTES de que pasen, y puede prepararse.
PROFILE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                           "cartelitos", "audio")
PROFILE_STEP = 0.5          # un punto cada medio segundo
SECTION_HOLD = 4.0          # segundos antes de aceptar que cambió de parte
SECTION_SMOOTH = 0.12       # cuánto pesa cada muestra en la curva suavizada
SECTIONS = ("quiet", "verse", "build", "drop")


def classify_level(rms, samples):
    """En qué parte de SU PROPIA canción está este momento.

    Devuelve (parte, percentil 0..1). Con menos de un puñado de muestras todavía
    no hay canción con qué comparar, así que se contesta "verse" y se espera."""
    # los ceros son tramos que todavía no se escucharon, no silencio del tema:
    # contarlos como parte de la canción hace que TODO parezca fuerte
    heard = [v for v in samples if v > 0.0]
    if len(heard) < 8:
        return "verse", 0.5
    ordered = sorted(heard)
    below = equal = 0
    for v in ordered:
        if v < rms:
            below += 1
        elif v == rms:
            equal += 1
        else:
            break
    # los empates cuentan a la mitad: si no, un tema parejo (un lofi, un drone)
    # da percentil 1.0 en todo momento y queda marcado como un drop eterno
    pct = (below + equal / 2) / len(ordered)
    if pct < 0.25:
        return "quiet", pct
    if pct < 0.62:
        return "verse", pct
    if pct < 0.86:
        return "build", pct
    return "drop", pct


class TrackProfile:
    """Curva de energía y de tono del tema, con memoria entre reproducciones."""

    def __init__(self, key, length=0.0):
        self.key = key
        self.length = length
        self.rms = []        # una muestra cada PROFILE_STEP, en orden
        self.cen = []
        self.known = False   # True si vino del cache: entonces se puede anticipar
        self.section = "verse"
        self.since = 0.0
        # Curva suavizada aparte para decidir la PARTE. Con el rms crudo, un tema
        # cambiaba de "parte" cada dos segundos: eso no es una sección, es el
        # bombo. Una sección dura estrofas, no compases.
        self.smooth = 0.0

    # ---- persistencia
    def path(self):
        return os.path.join(PROFILE_DIR, hashlib.sha1(self.key.encode()).hexdigest() + ".json")

    def load(self):
        try:
            with open(self.path()) as f:
                data = json.load(f)
        except Exception:
            return False
        if not data.get("rms"):
            return False
        self.rms = data["rms"]
        self.cen = data.get("cen", [])
        self.known = True
        return True

    def save(self):
        if len(self.rms) < 20:
            return False       # medio tema no sirve de mapa
        try:
            os.makedirs(PROFILE_DIR, exist_ok=True)
            tmp = self.path() + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"step": PROFILE_STEP, "len": self.length,
                           "rms": [round(v, 4) for v in self.rms],
                           "cen": [round(v, 3) for v in self.cen]}, f)
            os.replace(tmp, self.path())
            return True
        except OSError as e:
            log(f"couldn't save the track profile ({e})")
            return False

    # ---- en vivo
    def at(self, pos):
        """Índice de muestra para un momento de la canción."""
        return max(0, int(pos / PROFILE_STEP))

    def record(self, pos, rms, cen):
        """Guarda la muestra de este momento (la del tema que está sonando)."""
        i = self.at(pos)
        while len(self.rms) <= i:
            self.rms.append(0.0)
            self.cen.append(0.5)
        # promedio con lo que ya había: si el tema se escuchó otras veces, el
        # mapa se afina en vez de pisarse
        self.rms[i] = rms if self.rms[i] == 0.0 else (self.rms[i] * 0.6 + rms * 0.4)
        self.cen[i] = cen if self.cen[i] == 0.5 else (self.cen[i] * 0.6 + cen * 0.4)

    def update(self, pos, rms, now):
        """Parte actual, con histéresis. Devuelve (parte, percentil, cambió)."""
        self.smooth = (self.smooth * (1 - SECTION_SMOOTH) + rms * SECTION_SMOOTH
                       if self.smooth > 0 else rms)
        kind, pct = classify_level(self.smooth, self.rms)
        if kind == self.section:
            self.since = now
            return kind, pct, False
        if now - self.since < SECTION_HOLD:
            return self.section, pct, False
        self.section = kind
        self.since = now
        return kind, pct, True

    def coming(self, pos, ahead=2.0):
        """Qué se viene en los próximos segundos, si el tema ya se conoce.

        Sin esto la reacción siempre llega tarde: el golpe se ve DESPUÉS de que
        sonó. Con el mapa cargado, el tubo puede empezar a apretar antes."""
        if not self.known or not self.rms:
            return None
        here = self.at(pos)
        there = self.at(pos + ahead)
        if there >= len(self.rms) or here >= len(self.rms):
            return None
        if self.rms[here] <= 0.0 or self.rms[there] <= 0.0:
            return None      # ese pedazo del tema todavía no se escuchó nunca
        now_kind, _ = classify_level(self.rms[here], self.rms)
        then_kind, _ = classify_level(self.rms[there], self.rms)
        if then_kind == now_kind:
            return None
        return then_kind


_profile = None
_profile_lock = threading.Lock()


def profile_for(track):
    """Perfil del tema que suena; lo carga del cache si ya se escuchó."""
    key = FIELD_SEP.join([track.get("artist", ""), track.get("title", ""),
                          str(int(round(track.get("length", 0))))])
    prof = TrackProfile(key, track.get("length", 0.0))
    if prof.load():
        log("track profile: known, the tube can see what's coming")
    return prof


def set_profile(prof):
    global _profile
    with _profile_lock:
        old = _profile
        _profile = prof
    if old is not None:
        old.save()


# ------------------------------------------------------------------ audio
# El tubo late con la música de verdad. Se graba el monitor de la placa con
# pw-record (o parec) y se analiza acá, en Python pelado: sin numpy, sin cava,
# sin dependencias nuevas — pipewire ya está o no hay sonido en la máquina.
AUDIO_RATE = 16000
AUDIO_HOP = 512                                   # 32 ms por análisis
AUDIO_BANDS = (60.0, 150.0, 400.0, 1000.0, 2500.0, 5000.0)
AUDIO_MIN_SEND = 0.04                             # ~25 eventos por segundo


_BAND_TABLES = {}


def _band_table(n, rate, freq):
    """Seno/coseno de la banda, ya multiplicados por una ventana de Hann.

    Se calcula una vez por (largo, frecuencia) y se reusa: sin esto el análisis
    haría 500 senos por banda y por bloque, 30 veces por segundo."""
    key = (n, rate, freq)
    table = _BAND_TABLES.get(key)
    if table is None:
        w = 2.0 * math.pi * freq / rate
        cos_t, sin_t = [], []
        for i in range(n):
            # Hann: sin la ventana, un tono agudo se derrama sobre las bandas
            # graves y el centroide miente feo
            win = 0.5 - 0.5 * math.cos(2.0 * math.pi * i / max(n - 1, 1))
            cos_t.append(math.cos(w * i) * win)
            sin_t.append(math.sin(w * i) * win)
        table = (cos_t, sin_t)
        _BAND_TABLES[key] = table
    return table


def band_energy(samples, rate, freq):
    """Energía de UNA frecuencia, con la DFT de ese bin nomás.

    Se probó Goertzel (más barato) y hay que dejar dicho por qué no quedó: en las
    bandas graves, con bloques de 512, el término `s1² + s2² - coeff·s1·s2` pierde
    toda la precisión (coeff ≈ 2) y un tono de 4 kHz aparecía con la mitad de su
    energía en la banda de 60 Hz. Acá se suman seno y coseno y listo — el costo
    real está en las tablas, y ésas se precalculan."""
    n = len(samples)
    if n == 0:
        return 0.0
    cos_t, sin_t = _band_table(n, rate, freq)
    re = im = 0.0
    for i, x in enumerate(samples):
        re += x * cos_t[i]
        im += x * sin_t[i]
    return (re * re + im * im) / (n * n)


class AudioAnalyzer:
    """PCM crudo → nivel, bandas, centroide (proxy del tono) y golpes.

    El nivel va normalizado contra un pico que decae solo: la música no viene con
    un volumen fijo y sin eso el tubo late fuerte o no late según el master del
    sistema. El golpe se mide aparte, contra el rms crudo, con refractario para no
    disparar tres veces el mismo bombo."""

    def __init__(self, rate=AUDIO_RATE):
        self.rate = rate
        self.peak = 1e-4
        self.slow = 0.0
        self.last_beat = 0.0

    def feed(self, pcm, now):
        """pcm: bytes s16 mono. Devuelve el dict del evento, o None si vino vacío."""
        n = len(pcm) // 2
        if n == 0:
            return None
        samples = [int.from_bytes(pcm[i * 2:i * 2 + 2], "little", signed=True) / 32768.0
                   for i in range(n)]
        rms = math.sqrt(sum(x * x for x in samples) / n)

        # pico con decaimiento: se adapta al volumen del sistema sin saltos
        self.peak = max(rms, self.peak * 0.995, 1e-4)
        level = min(rms / self.peak, 1.0)

        energies = [band_energy(samples, self.rate, f) for f in AUDIO_BANDS]
        total = sum(energies)
        if total > 0:
            # Centroide en escala logarítmica (el oído oye octavas, no hertz) y
            # pesado por amplitud, no por energía: la música tiene espectro ~1/f
            # y con energía cruda TODO da grave, no se distingue una voz de otra.
            amps = [math.sqrt(e) for e in energies]
            atot = sum(amps)
            logf = sum(math.log(f) * a for f, a in zip(AUDIO_BANDS, amps)) / atot
            lo, hi = math.log(AUDIO_BANDS[0]), math.log(AUDIO_BANDS[-1])
            centroid = min(max((logf - lo) / (hi - lo), 0.0), 1.0)
            bands = [e / total for e in energies]
        else:
            centroid = 0.5
            bands = [0.0] * len(AUDIO_BANDS)

        # El golpe se mide contra el rms CRUDO, no contra el nivel normalizado:
        # el nivel se adapta al volumen, así que un tema bajito y parejo también
        # marca 1.0 y contra eso ningún golpe sobresale.
        # Un golpe es algo que SOBRESALE, no cada bombo: con el umbral bajo, en un
        # tema con batería marcada se dispara tres veces por segundo y la pantalla
        # queda vibrando todo el tiempo.
        beat = False
        if (rms > max(self.slow * 1.6, 0.012)
                and now - self.last_beat > 0.25):
            beat = True
            self.last_beat = now
        self.slow = self.slow * 0.9 + rms * 0.1

        return {
            "cmd": "aud",
            "l": round(level, 3),
            "lo": round(bands[0] + bands[1], 3),
            "mid": round(bands[2] + bands[3], 3),
            "hi": round(bands[4] + bands[5], 3),
            "c": round(centroid, 3),
            "b": 1 if beat else 0,
        }


def _default_sink():
    """Nombre de la salida por default. Se pregunta en cada captura: si Ferox se
    cambia de auriculares a parlantes, el nombre viejo ya no existe."""
    try:
        out = subprocess.run(["pactl", "get-default-sink"],
                             capture_output=True, text=True, timeout=3)
        name = out.stdout.strip()
        if out.returncode == 0 and name:
            return name
    except Exception:
        pass
    return None


def sink_node_id(listing, name):
    """Id de nodo de un sink dentro de la salida de `pactl list sinks short`."""
    for line in listing.splitlines():
        cols = line.split("\t")
        if len(cols) >= 2 and cols[1] == name and cols[0].strip().isdigit():
            return cols[0].strip()
    return None


def _sink_node_id(name):
    try:
        out = subprocess.run(["pactl", "list", "sinks", "short"],
                             capture_output=True, text=True, timeout=3)
        if out.returncode == 0:
            return sink_node_id(out.stdout, name)
    except Exception:
        pass
    return None


def _audio_command():
    """Con qué grabar lo que suena.

    OJO con pw-record: `--target=<nombre>.monitor` conecta sin quejarse y graba
    SILENCIO — hay que pasarle el id del nodo. Medido acá: 0.0012 de rms con el
    nombre contra 0.0757 con el id, con la misma música sonando. Por eso primero
    se resuelve el id, y parec (que sí acepta el nombre del monitor) queda de
    respaldo."""
    name = _default_sink()
    if not name:
        return None
    if shutil.which("pw-record"):
        node = _sink_node_id(name)
        if node:
            return ["pw-record", "--format=s16", f"--rate={AUDIO_RATE}",
                    "--channels=1", "--latency=20ms", f"--target={node}", "-"]
    if shutil.which("parec"):
        return ["parec", "--format=s16le", f"--rate={AUDIO_RATE}",
                "--channels=1", "-d", name + ".monitor"]
    return None


def audio_loop():
    """Graba y manda eventos mientras el tubo esté prendido. Fuera del modo CRT
    no se abre ni el proceso: cero consumo cuando no se ve."""
    while True:
        if not (CFG["crt"]["audio"] and crt_on()):
            time.sleep(0.5)
            continue
        cmd = _audio_command()
        if not cmd:
            log("no way to capture audio (pw-record/parec), the tube won't react")
            time.sleep(10)
            continue
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL)
        except Exception as e:
            log(f"couldn't capture audio ({e})")
            time.sleep(5)
            continue
        log("audio: reacting to what's playing")
        an = AudioAnalyzer()
        last = 0.0
        last_sec = 0.0
        last_cue = 0.0
        last_save = time.monotonic()
        quiet_since = time.monotonic()
        warned = False
        try:
            while CFG["crt"]["audio"] and crt_on():
                chunk = proc.stdout.read(AUDIO_HOP * 2)
                if not chunk or len(chunk) < AUDIO_HOP * 2:
                    break     # se cayó la captura (cambio de salida, sink muerto)
                now = time.monotonic()
                ev = an.feed(chunk, now)
                if not ev:
                    continue
                # captura muda un rato largo: casi siempre es que la salida por
                # default no es la que suena. Se avisa una vez y se sigue.
                if ev["l"] > 0.02:
                    quiet_since = now
                elif not warned and now - quiet_since > 20:
                    warned = True
                    log("audio: only silence on the default output, "
                        "the tube won't react to the music")
                if ev["b"] or now - last >= AUDIO_MIN_SEND:
                    last = now
                    send_soft(ev)

                # dónde estamos DENTRO de la canción (no cuánto suena ahora)
                with _profile_lock:
                    prof = _profile
                if prof is None or now - last_sec < PROFILE_STEP:
                    continue
                last_sec = now
                # se guarda cada tanto, no sólo al cambiar de tema: si el daemon
                # se cae en la mitad, el mapa de lo escuchado no se pierde
                if now - last_save > 30:
                    last_save = now
                    prof.save()
                pos = _song_pos()
                if pos is None:
                    continue
                rms = ev["l"] * an.peak      # el rms crudo, sin la normalización
                prof.record(pos, rms, ev["c"])
                kind, pct, changed = prof.update(pos, rms, now)
                if changed:
                    log(f"section: {kind} ({pct:.0%})")
                    send_soft({"cmd": "sec", "kind": kind, "p": round(pct, 2)})
                # y lo que se viene, si el tema ya se escuchó antes
                if now - last_cue > 2.0:
                    nxt = prof.coming(pos)
                    if nxt and nxt != kind:
                        last_cue = now
                        log(f"coming: {nxt}")
                        send_soft({"cmd": "cue", "kind": nxt, "in": 2.0})
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except Exception:
                proc.kill()
        log("audio: capture stopped")


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
    segs = split_repeats(text)
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
                mons.append((m["name"], f"{m['width']}x{m['height']} {shape}",
                             m.get("x", 0), m.get("y", 0)))
            return [(n, info) for n, info, _, _ in mons]
    except Exception:
        pass
    return []


def _monitors_lr():
    """Monitores ordenados como están puestos: de izquierda a derecha."""
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"],
                             capture_output=True, text=True, timeout=3)
        if out.returncode != 0:
            return []
        mons = []
        for m in json.loads(out.stdout):
            shape = "vertical" if m.get("transform", 0) % 2 else "horizontal"
            mons.append((m["name"], f"{m['width']}x{m['height']} {shape}, "
                                    f"at x={m.get('x', 0)}",
                         m.get("x", 0), m.get("y", 0)))
        mons.sort(key=lambda t: (t[2], t[3]))
        return [(n, info) for n, info, _, _ in mons]
    except Exception:
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


def _ask_crt_order(current):
    """Orden de las pantallas del tubo, de izquierda a derecha.

    Es lo que decide dónde cae cada pedazo de una línea partida: la primera de
    la lista se queda con el principio. Anda con la cantidad de monitores que
    haya — con uno solo no cambia nada."""
    mons = _monitors_lr()
    if len(mons) < 2:
        print("\n  only one screen detected, the order changes nothing")
        input("  enter to go back ")
        return None
    print(f"\nScreen order, left to right   (now: {_fmt(current)})")
    print("  it decides where each piece of a split line lands\n")
    for i, (name, info) in enumerate(mons, 1):
        print(f"  {i}) {name}  ({info})")
    print("\n  type the numbers left to right (e.g. 2,1,3),")
    print("  'a' to follow how they are physically placed, enter to keep it")
    raw = input("> ").strip().lower()
    if not raw:
        return None
    if raw in ("a", "auto"):
        return "auto"
    picked = [t.strip() for t in raw.replace(" ", ",").split(",") if t.strip()]
    if not all(t.isdigit() and 1 <= int(t) <= len(mons) for t in picked):
        print("  numbers from the list, separated by commas")
        input("  enter to go back ")
        return None
    names = [mons[int(t) - 1][0] for t in picked]
    if len(set(names)) != len(names):
        print("  a screen twice in the same order")
        input("  enter to go back ")
        return None
    # las que no nombró van al final solas: nadie se queda sin tubo
    return names


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

    ("— CRT mode (fatal crt on/off) —", None, None, None),
    ("enabled", "crt", "Start with the tube on",
     lambda c: _pick("Start with CRT mode on (it covers every screen)", YESNO, c)),
    ("screens", "crt", "Screens the tube takes", _ask_screens),
    ("order", "crt", "Screen order, left to right", _ask_crt_order),
    ("palette", "crt", "Phosphor colour", lambda c: _pick("Phosphor colour", [
        ("auto (one per screen, rotates per track)", "auto"), ("amber", "amber"),
        ("cyan", "cyan"), ("green", "green"), ("violet", "violet"),
        ("red (always critical)", "red")], c)),
    ("split", "crt", "Line across screens", lambda c: _pick(
        "How the line is spread over several screens", [
            ("mixed (whole phrase, short lines cut in pieces)", "mixed"),
            ("whole (never cut)", "whole"),
            ("fragment (always cut short lines)", "fragment")], c)),
    ("director", "crt", "Lyric travels across screens",
     lambda c: _pick("The lyric travels across the screens (director)", YESNO, c)),
    ("focus", "crt", "Focus", lambda c: _pick("Where the lyric goes", [
        ("roam: one screen at a time, the focus moves", "roam"),
        ("all: every screen shows the whole line", "all")], c)),
    ("audio", "crt", "React to the music",
     lambda c: _pick("React to what's actually playing", YESNO, c)),
    ("color_from_pitch", "crt", "Colour follows the register",
     lambda c: _pick("The phosphor leans on the register of what's playing", YESNO, c)),
    ("color_hold", "crt", "Seconds before the colour may change",
     lambda c: _ask_int("Seconds a colour has to stay before it may change", c, 0, 600)),
    ("motifs", "crt", "Animations on the quiet screens",
     lambda c: _pick("Animations on the screens without lyric", YESNO, c)),
    ("quality", "crt", "Render resolution (less = cheaper)",
     lambda c: _ask_num("Resolution the tube is drawn at (1.0 = native)", c, 0.4, 1.0)),
    ("camera", "crt", "Framing movement",
     lambda c: _ask_num("How much the framing moves (0 = still)", c, 0.0, 2.0)),
    ("exit_on", "crt", "How you get out", lambda c: _pick(
        "How you get out of the tube", [
            ("mouse: cursor hidden, click or wheel returns", "mouse"),
            ("keyboard: any key returns, cursor stays visible", "keyboard")], c)),
    ("chrome", "crt", "Console readouts (REC, timecode)",
     lambda c: _pick("Console readouts on the tube", YESNO, c)),
    ("word_flash", "crt", "Flash as each word lands (0 = none)",
     lambda c: _ask_num("How much each word flashes as it lands "
                        "(0 = straight in its colour, 1 = lands white)", c, 0.0, 1.0)),
    ("flicker", "crt", "Beating with the music (0 = none)",
     lambda c: _ask_num("How hard the picture beats with the music "
                        "(0 = the light never moves, 1 = it thumps)", c, 0.0, 1.0)),
    ("intensity", "crt", "How restless it is (0 = still)",
     lambda c: _ask_num("How restless the tube is: breaks, static, channel split, "
                        "beat shakes (0 = dead still, 1 = wild)", c, 0.0, 2.0)),
    ("curvature", "crt", "Tube glass curvature",
     lambda c: _ask_num("Tube glass curvature (0 = flat panel)", c, 0.0, 3.0)),
    ("scanlines", "crt", "Scanline depth",
     lambda c: _ask_num("Scanline depth", c, 0.0, 1.0)),
    ("bloom", "crt", "Phosphor glow",
     lambda c: _ask_num("Phosphor glow around the letters", c, 0.0, 3.0)),

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
    ("palette", "crt", "CRT colours", [
        ("Album cover", "album"), ("Auto (by register)", "auto"),
        ("Dragons", "dragons"), ("Ado", "ado"), ("Poison", "poison"),
        ("Bloodline", "bloodline"), ("Vapor", "vapor"), ("Bone", "bone")]),
    ("split", "crt", "CRT split", [
        ("Mixed", "mixed"), ("Never cut", "whole"), ("Always cut", "fragment")]),
    ("exit_on", "crt", "CRT exit", [
        ("Mouse (cursor hidden)", "mouse"), ("Keyboard (any key)", "keyboard")]),
    ("flicker", "crt", "CRT beating", [
        ("Off", 0.0), ("Gentle", 0.15), ("Normal", 0.25), ("Hard", 0.7)]),
    ("word_flash", "crt", "CRT word flash", [
        ("Off", 0.0), ("Gentle", 0.15), ("Normal", 0.3), ("Hard", 0.8)]),
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

        # el tubo se prende/apaga en vivo (no toca el archivo: `enabled` es sólo
        # con qué estado arranca), así que la etiqueta lee el interruptor real
        def toggle_crt():
            set_crt(not crt_on())
            GLib.idle_add(refresh)

        item(menu, "CRT mode", on_click=toggle_crt,
             dynamic=lambda: f"CRT mode: {'on' if crt_on() else 'off'}")

        menu.append(Gtk.SeparatorMenuItem())
        item(menu, "Sliders…", on_click=lambda: subprocess.Popen([fatal_bin, "tune"]))
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
    crt_paused_by_game = False
    last_game_check = 0.0
    pause_started = None
    pause_cleared = False
    resend_np = False
    last_pos_sent = 0.0
    log("fatal-lyrics daemon started")
    # el modo CRT arranca como diga la config: un `fatal crt on` de la sesión
    # anterior no se hereda (tapa las tres pantallas, mejor que sea deliberado)
    set_crt(CFG["crt"]["enabled"])
    start_tray()
    send(_config_event())
    threading.Thread(target=watch_config, daemon=True, name="config").start()
    threading.Thread(target=audio_loop, daemon=True, name="audio").start()
    threading.Thread(target=watch_tune, daemon=True, name="tune").start()
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
                    # un tubo full-bleed encima de un juego es lo peor que puede
                    # pasar: se apaga y se devuelve como estaba al salir
                    crt_paused_by_game = crt_on()
                    if crt_paused_by_game:
                        set_crt(False)
                    log("game detected: pausing")
            elif paused_by_game:
                paused_by_game = False
                if crt_paused_by_game:
                    crt_paused_by_game = False
                    set_crt(True)
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

        _song_where["pos"] = t["pos"]
        _song_where["at"] = now
        _song_where["playing"] = t["status"] == "Playing"

        if t["id"] != track_id:
            track_id = t["id"]
            set_profile(profile_for(t))
            idx = -1
            clear()
            log(f"track: {t['artist']} — {t['title']}")
            if CFG["behavior"]["now_playing"]:
                send({"cmd": "np", "title": t["title"], "artist": t["artist"],
                      "album": t["album"], "art": t["art"]})
            send_album_colors(t["art"])
            lyrics = None
            if t["title"]:
                fetch_lyrics_async(t)
            else:
                _fetch.update(id=None, lyrics=None, done=False)

        # la búsqueda corre en un hilo: se recoge cuando llega
        if lyrics is None and _fetch["done"] and _fetch["id"] == track_id:
            lyrics = _fetch["lyrics"]

        # progreso de la canción: barra de la funda + karaoke (1 evento por segundo)
        # el modo CRT los necesita SIEMPRE: el director reparte los pedazos en
        # tiempo de canción, y sin estos eventos el reloj se queda clavado
        if ((CFG["behavior"]["now_playing"] or CFG["display"]["karaoke"] or crt_on())
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
