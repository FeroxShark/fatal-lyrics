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

def _toml_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return f'"{v}"'
    if isinstance(v, list):
        return "[" + ", ".join(_toml_val(x) for x in v) + "]"
    return str(v)


# Comentario de cada perilla del TOML de ejemplo. No vive en DEFAULTS porque
# DEFAULTS es sólo valores (lo que se aplica); esto es sólo prosa (lo que se
# lee en `fatal config`). Un string con "\n" es un comentario de varias
# líneas, alineado bajo la primera. Perder esta prosa por generar el TOML
# a mano sería peor que el problema que estamos resolviendo, así que separar
# valores (DEFAULTS) de texto (esto) es lo que permite generar el archivo
# sin perderla.
_CONFIG_COMMENTS = {
    "display": {
        "screen": '"auto" (first monitor) | "all" (every one) | "DP-1" | ["DP-1", "DP-2"]',
        "max_dialogs": "max live dialogs at once; 0 = unlimited",
        "scale": "base size for all dialogs",
        "current_scale": "extra size factor for the current-line dialog",
        "spawn_area": "full | top | bottom | left | right | edges (leaves the center clear)",
        "karaoke": "current line paints word by word (estimated timing)",
    },
    "effects": {
        "glitch": "off | soft | normal | aggressive",
        "effects_on_current": "true = the current dialog also vibrates/glitches",
        "tearing": "old dialogs get a split window",
        "death_age_min": "a dialog dies between N…",
        "death_age_max": "…and M dialogs after it appears",
        "max_lifetime": "max lifetime per dialog in seconds; 0 = unlimited",
        "burn_in": "dead dialogs leave a fading burnt shadow",
        "cascade": "on track change, dialogs die in a chain (CRT domino)",
    },
    "behavior": {
        "now_playing": "vinyl sleeve with album art on track change",
        "np_corner": "where the sleeve docks: top-left | top-right | bottom-left | bottom-right | center",
        "np_margin": "free pixels against the edges (in case of a bar/panel)",
        "np_vinyl": "spinning vinyl record peeking out of the sleeve",
        "troll_no": 'the "No" button duplicates the dialog; false = just closes it',
        "click_through": "true = dialogs don't capture the mouse (clicks pass through)",
        "pause_clear": "seconds paused before clearing everything; 0 = never",
        "player": "MPRIS player name (see: playerctl -l)",
        "offset": "sync lead time in seconds",
        "game_pause": 'auto-pause when a window goes fullscreen (generic "game" heuristic\n'
                       "via Hyprland, doesn't depend on a specific process);\n"
                       "false = never pause for games",
    },
    "crt": {
        "enabled": "true = start with the tube on",
        "screens": 'which screens the tube takes: "all" | "DP-1" | ["DP-1","DP-2"]\n'
                   '| "same" (the same ones the dialogs use)',
        "order": "screen order, left to right — this is what decides where each\n"
                 'piece of a split line lands. "auto" = the layout the compositor\n'
                 'already knows; or name them: ["DP-1", "HDMI-A-1", "DP-2"]',
        "palette": "where the two colours come from:\n"
                   '  "album" = from the cover of what\'s playing (needs\n'
                   "            ImageMagick; falls back to the presets)\n"
                   '  "auto"  = a preset picked by the register of the song\n'
                   "  or a preset by name: dragons | ado | poison | bloodline\n"
                   "            | vapor | bone\n"
                   "Each palette is TWO faces that go together — one lit screen\n"
                   "(burnt background, dark letters) and one dark tube (deep\n"
                   "background, glowing letters). Your screens alternate between\n"
                   "them, so there are never three colours fighting each other.",
        "split": "how the line is spread over several screens:\n"
                 "mixed = whole phrase, and short lines cut in pieces\n"
                 "whole = never cut | fragment = always cut short lines",
        "director": "the lyric travels across the screens instead of showing the\n"
                    "same thing on all of them at once: one screen is in focus,\n"
                    "the phrase continues on the next one, the rest go quiet",
        "focus": '"roam" = the focus moves around | "all" = every screen shows\n'
                 "the whole line at the same time (the old behaviour)",
        "audio": "react to what's actually playing (captures the sound card's\n"
                 "monitor with pw-record/parec — no extra packages). Only while\n"
                 "the tube is up. false = everything follows the lyric clock",
        "color_from_pitch": "the phosphor leans on the register of what's playing:\n"
                             "high voices go cyan/blue, low ones amber/red. Only used when\n"
                             "the cover gives no colours — with art, the palette is the\n"
                             "album's and doesn't move for the whole track",
        "color_hold": "seconds a colour has to stay before it may change again. It\n"
                      "is a floor, not a licence: a colour change also has to land\n"
                      "on a peak of the song, so it happens two or three times a\n"
                      "track and not every ten seconds",
        "motifs": "animations on the quiet screens (an eye, a scope, a radar,\n"
                  "falling data, hyperspace, a test card, the sea)",
        "water": "the two water animations: a sea of loose points seen in\n"
                 "perspective, and a dish of water that stands still and\n"
                 "SHIVERS at the frequency of what is playing. They take their\n"
                 "turn like every other animation; false = leave them out",
        "water_amp": "how much the water moves (0 = a flat field of points)",
        "camera": "how much the framing moves (letterbox, zoom); 0 = still",
        "quality": "resolution the tube is drawn at, before the CRT pass (1.0 =\n"
                   "native). Lower it on a weaker GPU: the glass, the bloom and\n"
                   "the phosphor grid hide most of the difference",
        "exit_on": "how you get out of the tube:\n"
                   '  "mouse"    = cursor hidden, moving it (or a click, or the\n'
                   "               wheel) returns\n"
                   '  "keyboard" = any key returns, but the cursor stays visible\n'
                   "(a layer surface can't hold the keyboard and the pointer at\n"
                   "once; `fatal crt off` and a compositor keybind always work)",
        "font": 'font family for the lyric; "" = system default',
        "chrome": "console readouts (REC, track, timecode, progress bar). Off by\n"
                  "default: full screen, nothing else on it",
        "intensity": "how restless the tube is: signal breaks, how hard beats\n"
                     "shake it, static. 0 = dead still, 1 = the old behaviour",
        "word_flash": "how much each word jolts as it lands — the white flash, the\n"
                      "misaligned colour ghosts and the size kick, all on this one\n"
                      "knob: 0 = the word simply appears, 1 = it lands white and\n"
                      "shaking. This is not the tube beating — it happens on EVERY\n"
                      'word, which is what reads as "the letters keep flickering"',
        "flicker": "how hard the picture beats with the music. How OFTEN is not\n"
                   "a knob: the tube only beats on the peaks of the song — the\n"
                   "highest few moments measured against the whole track, at\n"
                   "least 15 s apart and a handful per song. A beat is not every\n"
                   "kick drum; if it were, it would beat all the time.\n"
                   "0 = nothing moves with the volume (not the light, not the\n"
                   "camera, not the animations on the other screens). Above ~0.6\n"
                   "a peak can also drop a frame or two to black",
        "curvature": "how fat the tube glass is (0 = flat panel)",
        "scanlines": "depth of the horizontal comb",
        "chroma": "steady RGB misalignment",
        "bloom": "phosphor glow around the letters",
        "noise": "static",
        "roll": "brightness bar rolling down the tube",
        "vignette": "darkening towards the corners",
    },
}

# Encabezado de archivo y, para alguna sección, un bloque de comentario antes
# de la primera clave (hoy sólo [crt], que necesita explicar el modo entero).
_CONFIG_HEADER = ("# fatal-lyrics — configuration\n"
                   "# Saving this file applies the changes right away. Menu: fatal config")
_SECTION_INTRO = {
    "crt": "# CRT mode: every screen becomes one big cathode ray tube showing the lyric.\n"
           "# It covers the whole desktop, so it is opt-in and toggled by hand:\n"
           "#   fatal crt on | off | toggle     (works even if the daemon is dead)",
}
def _render_default_config(defaults):
    """Arma el TOML de ejemplo a partir de DEFAULTS (valores, y también el
    orden de despliegue: no hay una lista de orden aparte que se pueda
    desincronizar) y _CONFIG_COMMENTS (prosa): una única fuente para los
    valores, en vez de mantenerlos escritos dos veces (acá y en DEFAULTS)."""
    lines = [_CONFIG_HEADER, ""]
    for section, values in defaults.items():
        lines.append(f"[{section}]")
        intro = _SECTION_INTRO.get(section)
        if intro:
            lines.append(intro)
        comments = _CONFIG_COMMENTS.get(section, {})
        assigns = {k: f"{k} = {_toml_val(v)}" for k, v in values.items()}
        width = max(len(a) for a in assigns.values())
        for key, assign in assigns.items():
            comment = comments.get(key)
            if not comment:
                lines.append(assign)
                continue
            clines = comment.split("\n")
            pad = " " * (width - len(assign) + 1)
            lines.append(f"{assign}{pad}# {clines[0]}")
            for extra in clines[1:]:
                lines.append(" " * (width + 1) + "# " + extra)
        lines.append("")
    return "\n".join(lines).rstrip("\n") + "\n"


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
        "color_from_pitch": True, "color_hold": 10, "motifs": True,
        "water": True, "water_amp": 0.55, "camera": 1.0, "quality": 1.0,
        "exit_on": "mouse", "font": "", "chrome": False, "intensity": 0.45,
        "word_flash": 0.3, "flicker": 0.25, "curvature": 1.0, "scanlines": 0.5,
        "chroma": 0.6, "bloom": 1.0, "noise": 0.22, "roll": 0.5, "vignette": 0.9,
    },
}

DEFAULT_CONFIG = _render_default_config(DEFAULTS)


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
# (_toml_val vive arriba, junto al resto del renderer del TOML de ejemplo:
# ambos formatean el mismo tipo de valor)


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
