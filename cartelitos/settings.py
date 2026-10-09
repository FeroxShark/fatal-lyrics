"""La ventana de Ajustes (`fatal ajustes`): qué muestra y cómo le llega lo que se cambia.

La ventana es Quickshell (shell/settings.qml), otro proceso. Lo que dibuja sale
de acá: `--settings-json` le da las pestañas, los grupos, las filas y el valor de
cada una, así que una opción nueva se agrega en GROUPS y la ventana la muestra
sola. Es la ÚNICA pantalla de opciones: no hay menú de terminal (`fatal config`
abre esta ventana), y un test exige que toda perilla de DEFAULTS tenga su fila.

Lo que se toca vuelve por un archivo de XDG_RUNTIME_DIR (mismo mecanismo que
`fatal sing` o el sync): el socket lo sirve el overlay, y la ventana sólo tiene
que dejar el pedido escrito. El daemon lo valida contra GROUPS y lo pasa a la
config con set_option, así que queda en el TOML igual que desde la bandeja."""
import json
import os
import re
import time

from . import config
from .util import log

SETTINGS_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos-settings")



def _toggle(section, key, label, hint):
    return {"kind": "toggle", "id": f"{section}.{key}", "label": label, "hint": hint}


def _choice(section, key, label, hint, options):
    return {"kind": "choice", "id": f"{section}.{key}", "label": label, "hint": hint,
            "options": [{"label": l, "value": v} for l, v in options]}


def _slider(section, key, label, hint, lo, hi, step=0.01):
    return {"kind": "slider", "id": f"{section}.{key}", "label": label, "hint": hint,
            "min": lo, "max": hi, "step": step}


def _count(section, key, label, hint, lo, hi, step=1):
    """Un slider de enteros: en el TOML queda `60`, no `60.0`."""
    return dict(_slider(section, key, label, hint, lo, hi, step), int=True)


def _screens(section, key, label, hint, specials):
    """Qué pantallas: una opción especial ("auto", "all"...) o nombres de
    monitor. La ventana dibuja las especiales como botones de opción y cada
    monitor (los del snapshot, `monitors`) como casilla."""
    return {"kind": "screens", "id": f"{section}.{key}", "label": label, "hint": hint,
            "specials": [{"label": l, "value": v} for l, v in specials]}


def _text(section, key, label, hint, check="name", suggest=None):
    """Texto en un campo. `check` es lo que se le exige (ver coerce): "name" no
    vacío, "key" un atajo de Hyprland con su coma o vacío, "font" cualquier
    cosa. `suggest`: una lista del snapshot que se ofrece como botones (los
    players que ve playerctl), para no tener que tipear."""
    row = {"kind": "text", "id": f"{section}.{key}", "label": label, "hint": hint,
           "check": check}
    if suggest:
        row["suggest"] = suggest
    return row


# Las pestañas de la ventana y, en cada una, tres columnas. Es TODO lo que se
# puede tocar: el menú de terminal de antes (`fatal config`) se fue y esto lo
# reemplaza entero. Fuera quedan sólo [system].not_a_game (una lista, se edita
# en el TOML) y los comandos para mirar un dibujo (`fatal crt motif` y familia).
# `crt` y `sync` no son perillas del TOML: el tubo se prende en vivo (el
# interruptor de config.set_crt) y el sync es `fatal sync +|-|reset`. La
# ventana los dibuja como botones.
TABS = ["Dialogs", "Behavior", "CRT", "CRT scenes", "CRT glass"]

GROUPS = [
    # ---------------------------------------------------------------- Dialogs
    {"title": "Dialogs", "tab": 0, "column": 0, "rows": [
        _toggle("display", "karaoke", "Karaoke", "the current line paints word by word"),
        _slider("display", "scale", "Size", "all dialogs", 0.5, 3.0, 0.1),
        _slider("display", "current_scale", "Current line", "extra size", 0.5, 3.0, 0.1),
        _count("display", "max_dialogs", "At once", "0 = no limit", 0, 50),
        _choice("display", "spawn_area", "Spawn zone", "where on the screen they appear", [
            ("Full screen", "full"), ("Top", "top"), ("Bottom", "bottom"),
            ("Left", "left"), ("Right", "right"), ("Edges", "edges")]),
        _screens("display", "screen", "Screens", "which monitors get dialogs", [
            ("Auto (the first)", "auto"), ("All", "all")]),
    ]},
    {"title": "Effects", "tab": 0, "column": 1, "rows": [
        _choice("effects", "glitch", "Glitch", "how broken the dialogs look", [
            ("Off", "off"), ("Soft", "soft"), ("Normal", "normal"),
            ("Aggressive", "aggressive")]),
        _toggle("effects", "effects_on_current", "Current one glitches too",
                "the dialog with the current line also shakes"),
        _toggle("effects", "tearing", "Tearing", "old dialogs split their window"),
        _toggle("effects", "burn_in", "Burn-in", "a dead dialog leaves a burnt shadow"),
        _toggle("effects", "mirror", "Reflection", "the current dialog stands on its reflection"),
        _toggle("effects", "cascade", "Chain death", "on a new track they die one after another"),
        _choice("effects", "cascade_style", "Chain order", "who dies first", [
            ("Random", "random"), ("Oldest", "age"), ("Top", "top"),
            ("From the centre", "center")]),
    ]},
    {"title": "Lifetime", "tab": 0, "column": 2, "rows": [
        _count("effects", "death_age_min", "Dies after", "new dialogs, at least", 1, 50),
        _count("effects", "death_age_max", "…at most", "new dialogs", 1, 50),
        _count("effects", "max_lifetime", "Max life", "s, 0 = none", 0, 600, 5),
    ]},
    {"title": "Album sleeve", "tab": 0, "column": 2, "rows": [
        _toggle("behavior", "now_playing", "Album art",
                "the sleeve with the cover shows up on every new track"),
        _toggle("behavior", "np_vinyl", "Spinning record", "the vinyl peeks out of the sleeve"),
        _choice("behavior", "np_corner", "Docks at", "where the sleeve rests", [
            ("Top left", "top-left"), ("Top right", "top-right"),
            ("Bottom left", "bottom-left"), ("Bottom right", "bottom-right"),
            ("Centre", "center")]),
        _count("behavior", "np_margin", "Margin", "px from the edges", 0, 200),
    ]},
    # --------------------------------------------------------------- Behavior
    {"title": "Player", "tab": 1, "column": 0, "rows": [
        _text("behavior", "player", "Player to follow", "MPRIS name, as in playerctl -l",
              suggest="players"),
        _slider("behavior", "offset", "Lead time", "s, + = earlier", -2.0, 2.0, 0.05),
    ]},
    {"title": "Lyrics sync", "tab": 1, "column": 0, "rows": [
        {"kind": "sync", "id": "sync", "label": "Nudge the lyric",
         "hint": "0.1 s per click, learned for this artist"},
    ]},
    {"title": "Behavior", "tab": 1, "column": 1, "rows": [
        _toggle("behavior", "troll_no", "“No” clones the dialog",
                "the No button duplicates it instead of closing it"),
        _toggle("behavior", "click_through", "Ghost dialogs", "clicks pass through them"),
        _toggle("behavior", "game_pause", "Pause for games", "a fullscreen game pauses everything"),
        _count("behavior", "pause_clear", "Clear on pause", "s, 0 = never", 0, 300, 5),
        _toggle("behavior", "sing", "Sing mode",
                "listens to the mic: everything lights up only while you sing"),
    ]},
    {"title": "Keys (Hyprland)", "tab": 1, "column": 2, "rows": [
        _text("keys", "sync_forward", "Lyric earlier", "MODS, KEY · empty = no key", check="key"),
        _text("keys", "sync_back", "Lyric later", "MODS, KEY · empty = no key", check="key"),
        _text("keys", "crt_toggle", "CRT on / off", "MODS, KEY · empty = no key", check="key"),
    ]},
    # -------------------------------------------------------------------- CRT
    {"title": "CRT mode", "tab": 2, "column": 0, "rows": [
        {"kind": "crt", "id": "crt", "label": "Tube on",
         "hint": "every screen becomes a CRT with the lyric inside"},
        _toggle("crt", "enabled", "Start with it on", "the tube is on when Fatal starts"),
        _screens("crt", "screens", "Screens", "which monitors the tube takes", [
            ("All", "all"), ("Same as the dialogs", "same")]),
        {"kind": "order", "id": "crt.order", "label": "Screen order",
         "hint": "left to right: where each piece of a line lands"},
        _choice("crt", "exit_on", "Exit with", "how you get back to the desktop", [
            ("Mouse (cursor hidden)", "mouse"), ("Keyboard (any key)", "keyboard")]),
        _toggle("crt", "chrome", "Console readouts", "REC, track, timecode, progress bar"),
    ]},
    {"title": "Colours", "tab": 2, "column": 1, "rows": [
        _choice("crt", "palette", "Colours", "the phosphor of the tube", [
            ("Album cover", "album"), ("Auto", "auto"), ("Dragons", "dragons"),
            ("Ado", "ado"), ("Poison", "poison"), ("Bloodline", "bloodline"),
            ("Vapor", "vapor"), ("Bone", "bone")]),
        _choice("crt", "face_mode", "Spread", "how the palette shares the screens", [
            ("Follows the song", "song"), ("Classic 2-1", "classic")]),
        _toggle("crt", "color_from_pitch", "Follows the register",
                "the phosphor leans on the pitch of the song"),
        _count("crt", "color_hold", "Colour hold", "s before it changes", 0, 600, 5),
    ]},
    {"title": "Pace", "tab": 2, "column": 1, "rows": [
        _choice("crt", "pace", "Pace", "how much may happen per minute (nothing moves slower)", [
            ("Calm", "calm"), ("Normal", "normal"), ("Wild", "wild")]),
        _slider("crt", "rare", "Odd screens", "fake crash, no signal", 0.0, 2.0, 0.05),
    ]},
    {"title": "The lyric", "tab": 2, "column": 2, "rows": [
        _choice("crt", "split", "Line across screens", "whether a short line is cut in pieces", [
            ("Mixed", "mixed"), ("Never cut", "whole"), ("Always cut", "fragment")]),
        _toggle("crt", "director", "Travels across screens",
                "one screen in focus, the phrase moves on"),
        _choice("crt", "focus", "Focus", "where the lyric goes", [
            ("Roams", "roam"), ("Every screen", "all")]),
        _choice("crt", "hop", "The jump", "how a jump to another screen shows", [
            ("Ray + glitch", "both"), ("Ray", "corridor"), ("Glitch", "interference"),
            ("Nothing", "off")]),
        _toggle("crt", "iown", "Giant word on a drop", "a one-word line crosses the whole wall"),
        _toggle("crt", "foreshadow", "Next screen gives it away",
                "it lights up before the line lands"),
        _count("crt", "ghost_ms", "Ghost line", "ms the old one burns", 0, 3000, 10),
        _text("crt", "font", "Font", "family name · empty = the default", check="font"),
    ]},
    # ------------------------------------------------------------- CRT scenes
    {"title": "The track", "tab": 3, "column": 0, "rows": [
        _choice("crt", "scene", "Lit screens", "which screens keep drawing", [
            ("Follow the sections", "sections"), ("All of them", "all")]),
        _choice("crt", "set", "Drawing set", "what each track gets", [
            ("One set per track", "track"), ("The whole pool", "off")]),
        _toggle("crt", "intro", "Track intro", "goes dark, static, then a title card"),
        _choice("crt", "intro_card", "Intro card", "what the title sits on", [
            ("Test card", "testcard"), ("Plain title", "plain")]),
        _toggle("crt", "ring", "Instrumental ring", "counts down to the voice coming back"),
        _count("crt", "ring_gap", "Ring after", "s of silence", 2, 120),
    ]},
    {"title": "Drawings", "tab": 3, "column": 1, "rows": [
        _toggle("crt", "motifs", "Drawings", "animations on the screens without lyric"),
        _toggle("crt", "water", "Water drawings", "a sea and a shivering pond"),
        _slider("crt", "water_amp", "Water", "sea swell and pond shiver", 0.0, 1.0),
        _toggle("crt", "screen_off", "Screens may go dark",
                "the intro and the sections switch some off"),
        _toggle("crt", "testcard", "Test card mid-track", "in the pool and as a rare event"),
        _toggle("crt", "maze_eggs", "Maze surprises", "rare easter eggs in the maze"),
    ]},
    {"title": "Music", "tab": 3, "column": 2, "rows": [
        _toggle("crt", "audio", "React to the music", "listens to what is actually playing"),
        _toggle("crt", "beat_lock", "Land on the beat", "loose glitches wait for the next beat"),
        _toggle("crt", "word_fx", "Key words", "fire, die, break, dark fire an effect"),
        _toggle("crt", "section_zoom", "Camera follows the song", "back in a verse, in on a drop"),
        _slider("crt", "camera", "Framing", "how much the shot moves", 0.0, 2.0),
        _slider("crt", "mov_speed", "Drawing speed", "follows the music", 0.0, 1.0),
        _slider("crt", "tension", "Tension", "breaks up toward the end", 0.0, 1.0),
        _slider("crt", "dirt", "Dirt", "static follows distortion", 0.0, 1.0),
    ]},
    # -------------------------------------------------------------- CRT glass
    {"title": "Glass", "tab": 4, "column": 0, "rows": [
        _choice("crt", "tube", "Tube", "a named tube ignores the knobs below", [
            ("Auto", "auto"), ("Custom", "custom"), ("Trinitron", "trinitron"),
            ("PVM", "pvm"), ("Arcade", "arcade"), ("Green", "green"), ("Amber", "amber")]),
        _slider("crt", "curvature", "Curvature", "0 = flat panel", 0.0, 3.0),
        _slider("crt", "scanlines", "Scanlines", "depth of the comb", 0.0, 1.0),
        _slider("crt", "bloom", "Phosphor glow", "around the letters", 0.0, 3.0),
        _slider("crt", "noise", "Static", "grain on the glass", 0.0, 1.0),
        _slider("crt", "chroma", "Colour shift", "RGB misalignment", 0.0, 1.0),
        _slider("crt", "roll", "Rolling bar", "a bright band", 0.0, 1.0),
        _slider("crt", "vignette", "Corners", "how dark", 0.0, 1.5),
        _slider("crt", "composite", "Analog signal", "0 RGB · 1 VHS", 0.0, 1.0),
        _slider("crt", "persistence", "Phosphor trail", "what moves lingers", 0.0, 1.0),
    ]},
    {"title": "Restlessness", "tab": 4, "column": 1, "rows": [
        _slider("crt", "intensity", "Restlessness", "signal breaks, static", 0.0, 2.0),
        _slider("crt", "flicker", "Beating", "how hard it beats on peaks", 0.0, 1.0),
        _slider("crt", "word_flash", "Word flash", "how much each word jolts", 0.0, 1.0),
        _slider("crt", "channel_switch", "Channel change", "lines landing so", 0.0, 1.0),
        _slider("crt", "burnin", "Chorus burn-in", "a faint silhouette", 0.0, 1.0),
        _slider("crt", "quality", "Resolution", "lower = cheaper", 0.4, 1.0, 0.05),
    ]},
    {"title": "Colour timing", "tab": 4, "column": 2, "rows": [
        _slider("crt", "infect_lead", "Colour lead", "how early it jumps", 0.0, 0.5),
        _slider("crt", "alarm_threshold", "Alarm rarity", "how rare the red screen is", 0.0, 1.0),
    ]},
]

# las filas que son perillas del TOML, por id ("seccion.clave")
KNOB_KINDS = ("toggle", "choice", "slider", "screens", "order", "text")
ROWS = {row["id"]: row for group in GROUPS for row in group["rows"]
        if row["kind"] in KNOB_KINDS}

# un nombre de monitor como lo da hyprctl (DP-1, HDMI-A-1, eDP-1)
_SCREEN_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,31}$")


def _screen_list(value):
    """Una lista de nombres de monitor válida y sin repetidos, o None."""
    if not isinstance(value, list) or not value:
        return None
    if not all(isinstance(n, str) and _SCREEN_NAME.match(n) for n in value):
        return None
    return value if len(set(value)) == len(value) else None


def _text_ok(row, value):
    """El texto tal cual, si se puede escribir en el TOML sin romperlo (sin
    comillas, barras ni controles: _toml_val no escapa) y cumple su `check`."""
    if not isinstance(value, str) or len(value) > 80:
        return None
    if any(ch in value for ch in '"\\') or any(ord(ch) < 32 for ch in value):
        return None
    value = value.strip()
    check = row["check"]
    if check == "name" and not value:
        return None
    # sin la coma Hyprland lo lee como un bind sin modificadores y el atajo
    # queda mudo sin avisar
    if check == "key" and value and "," not in value:
        return None
    return value


def _split(row_id):
    section, _, key = row_id.partition(".")
    return section, key


def coerce(row, value):
    """El valor tal como tiene que quedar en el TOML, o None si no vale. Lo
    escribe otro proceso: no se le cree nada."""
    kind = row["kind"]
    if kind == "toggle":
        return value if isinstance(value, bool) else None
    if kind == "choice":
        allowed = [o["value"] for o in row["options"]]
        return value if isinstance(value, str) and value in allowed else None
    if kind == "screens":
        specials = [o["value"] for o in row["specials"]]
        if isinstance(value, str):
            return value if value in specials or _SCREEN_NAME.match(value) else None
        return _screen_list(value)
    if kind == "order":
        return value if value == "auto" else _screen_list(value)
    if kind == "text":
        return _text_ok(row, value)
    # slider: número de verdad (True también es un int en Python) y dentro del rango
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = min(max(float(value), row["min"]), row["max"])
    value = round(round(value / row["step"]) * row["step"], 2)
    return int(value) if row.get("int") else value


def parse(text):
    """Las líneas `<serie> <seccion.clave>=<json>` que escribe la ventana, ya
    validadas: [(serie, seccion, clave, valor)]. La serie crece siempre (la
    ventana arranca de la hora en ms), y es lo que deja aplicar cada cambio una
    sola vez aunque el archivo traiga los últimos varios."""
    out = []
    for line in (text or "").splitlines():
        head, sep, raw = line.partition("=")
        serial, _, row_id = head.strip().partition(" ")
        row = ROWS.get(row_id.strip())
        if not sep or row is None:
            continue
        try:
            serial = int(serial)
            value = coerce(row, json.loads(raw))
        except ValueError:
            continue
        if value is None:
            continue
        out.append((serial, *_split(row["id"]), value))
    return out


def pending(text, last):
    """Lo que falta aplicar del archivo: {(seccion, clave): valor} con lo más
    nuevo de cada perilla, y la serie más alta vista. Un arrastre de slider deja
    varias líneas de la misma clave: se aplica la última, una sola escritura."""
    changes, top = {}, last
    for serial, section, key, value in sorted(parse(text)):
        if serial <= last:
            continue
        changes[(section, key)] = value
        top = max(top, serial)
    return changes, top


def _read():
    try:
        with open(SETTINGS_PATH) as f:
            return f.read()
    except OSError:
        return ""


def watch_settings():
    """Aplica lo que se toca en la ventana de Ajustes.

    Lo que ya estaba en el archivo al arrancar es de una sesión anterior y no se
    aplica: se anota su serie más alta y se sigue desde ahí."""
    _, last = pending(_read(), 0)
    stamp = None
    while True:
        time.sleep(0.25)
        try:
            now = os.stat(SETTINGS_PATH).st_mtime_ns
        except OSError:
            continue
        if now == stamp:
            continue
        stamp = now
        changes, last = pending(_read(), last)
        changes = {sk: v for sk, v in changes.items() if config.CFG[sk[0]][sk[1]] != v}
        if not changes:
            continue
        for (section, key), value in changes.items():
            log(f"settings: {section}.{key} = {value}")
        config._save_config({key: (section, value) for (section, key), value in changes.items()})
        config.apply_config()


def snapshot():
    """Lo que la ventana necesita para dibujarse: pestañas, grupos, valores
    actuales, si el tubo está prendido, los atajos, los monitores y players que
    hay para elegir, y si hay daemon que aplique los cambios."""
    from . import system   # tarde: system importa config (mismo círculo que apply_config)
    cfg = config.load_config()
    values = {}
    for row_id in ROWS:
        section, key = _split(row_id)
        values[row_id] = cfg[section][key]
    return {
        "tabs": TABS,
        "groups": GROUPS,
        "values": values,
        "crt": config.crt_on(),
        "keys": dict(cfg["keys"]),
        "monitors": [{"name": n, "info": info} for n, info in system._monitors_lr()],
        "players": system._players(),
        "daemon": bool(system._daemon_pid()),
    }


def set_cli(args):
    """`--settings-set <seccion.clave>=<json>`: la ventana escribe así el TOML
    directo cuando no hay daemon que lea el archivo. El cambio queda guardado y
    se ve al prender."""
    applied = 0
    for arg in args:
        for _, section, key, value in parse(f"0 {arg}"):
            config._save_config({key: (section, value)})
            applied += 1
    return 0 if applied else 1
