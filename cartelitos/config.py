"""Config: defaults, lectura/escritura del TOML, interruptor del CRT."""
import os
import re
import tomllib
import time

from .util import log

# interruptor del modo CRT: un archivo, no el socket (ver set_crt)
CRT_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos-crt")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "cartelitos")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.toml")

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
                       # high voices go cyan/blue, low ones amber/red. Only used when
                       # the cover gives no colours — with art, the palette is the
                       # album's and doesn't move for the whole track
color_hold = 10        # seconds a colour has to stay before it may change again. It
                       # is a floor, not a licence: a colour change also has to land
                       # on a peak of the song, so it happens two or three times a
                       # track and not every ten seconds
motifs = true          # animations on the quiet screens (an eye, a scope, a radar,
                       # falling data, hyperspace, a test card, the sea)
water = true           # the two water animations: a sea of loose points seen in
                       # perspective, and a dish of water that stands still and
                       # SHIVERS at the frequency of what is playing. They take their
                       # turn like every other animation; false = leave them out
water_amp = 0.55       # how much the water moves (0 = a flat field of points)
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
word_flash = 0.3       # how much each word jolts as it lands — the white flash, the
                       # misaligned colour ghosts and the size kick, all on this one
                       # knob: 0 = the word simply appears, 1 = it lands white and
                       # shaking. This is not the tube beating — it happens on EVERY
                       # word, which is what reads as "the letters keep flickering"
flicker = 0.25         # how hard the picture beats with the music. How OFTEN is not
                       # a knob: the tube only beats on the peaks of the song — the
                       # highest few moments measured against the whole track, at
                       # least 15 s apart and a handful per song. A beat is not every
                       # kick drum; if it were, it would beat all the time.
                       # 0 = nothing moves with the volume (not the light, not the
                       # camera, not the animations on the other screens). Above ~0.6
                       # a peak can also drop a frame or two to black
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
        "quality": 1.0, "water": True, "water_amp": 0.55,
        "exit_on": "mouse", "font": "",
        "chrome": False, "intensity": 0.45, "flicker": 0.25, "word_flash": 0.3, "curvature": 1.0, "scanlines": 0.5,
        "chroma": 0.6, "bloom": 1.0, "noise": 0.22, "roll": 0.5, "vignette": 0.9,
    },
}

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
    # tarde a propósito: ipc lee la config, así que importarlo arriba sería un
    # círculo. Acá ya está todo cargado y sale gratis.
    from . import ipc
    ipc.send(ipc._config_event())
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

# ------------------------------------------------- escritura del TOML

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


def set_option(key, section, value):
    """Escribe una clave y la aplica ya. Mismo camino que el menú y que editar el
    TOML a mano: se escribe el archivo y se relee."""
    _save_config({key: (section, value)})
    apply_config()
