"""La ventana de Ajustes (`fatal ajustes`): qué muestra y cómo le llega lo que se cambia.

La ventana es Quickshell (shell/settings.qml), otro proceso. Lo que dibuja sale
de acá: `--settings-json` le da los grupos, las filas y el valor de cada una, así
que una opción nueva se agrega en GROUPS y la ventana la muestra sola.

Lo que se toca vuelve por un archivo de XDG_RUNTIME_DIR (mismo mecanismo que
`fatal sing` o el sync): el socket lo sirve el overlay, y la ventana sólo tiene
que dejar el pedido escrito. El daemon lo valida contra GROUPS y lo pasa a la
config con set_option, así que queda en el TOML igual que desde la bandeja."""
import json
import os
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


# Las tres columnas de la ventana, de izquierda a derecha. `crt` y `sync` no son
# perillas del TOML: el tubo se prende en vivo (el interruptor de config.set_crt)
# y el sync es `fatal sync +|-`. La ventana los dibuja como botones.
GROUPS = [
    {"title": "Dialogs", "column": 0, "rows": [
        _toggle("display", "karaoke", "Karaoke", "the current line paints word by word"),
        _toggle("behavior", "now_playing", "Album art",
                "the sleeve with the cover shows up on every new track"),
        _toggle("effects", "tearing", "Tearing", "old dialogs split their window"),
        _slider("display", "scale", "Size", "how big the dialogs are", 0.5, 3.0, 0.1),
        _choice("display", "spawn_area", "Spawn zone", "where on the screen they appear", [
            ("Full screen", "full"), ("Top", "top"), ("Bottom", "bottom"),
            ("Left", "left"), ("Right", "right"), ("Edges", "edges")]),
        _choice("effects", "glitch", "Glitch", "how broken the dialogs look", [
            ("Off", "off"), ("Soft", "soft"), ("Normal", "normal"),
            ("Aggressive", "aggressive")]),
    ]},
    {"title": "Lyrics sync", "column": 0, "rows": [
        {"kind": "sync", "id": "sync", "label": "Nudge the lyric",
         "hint": "0.1 s per click, learned for this artist"},
    ]},
    {"title": "CRT mode", "column": 1, "rows": [
        {"kind": "crt", "id": "crt", "label": "Tube on",
         "hint": "every screen becomes a CRT with the lyric inside"},
        _choice("crt", "palette", "Colours", "the phosphor of the tube", [
            ("Album cover", "album"), ("Auto", "auto"), ("Dragons", "dragons"),
            ("Ado", "ado"), ("Poison", "poison"), ("Bloodline", "bloodline"),
            ("Vapor", "vapor"), ("Bone", "bone")]),
        _choice("crt", "pace", "Pace", "how much may happen per minute (nothing moves slower)", [
            ("Calm", "calm"), ("Normal", "normal"), ("Wild", "wild")]),
        _choice("crt", "split", "Line across screens", "whether a short line is cut in pieces", [
            ("Mixed", "mixed"), ("Never cut", "whole"), ("Always cut", "fragment")]),
        _choice("crt", "exit_on", "Exit with", "how you get back to the desktop", [
            ("Mouse (cursor hidden)", "mouse"), ("Keyboard (any key)", "keyboard")]),
    ]},
    {"title": "CRT fine-tuning", "column": 2, "rows": [
        _slider("crt", "word_flash", "Word flash", "how much each word jolts", 0.0, 1.0),
        _slider("crt", "flicker", "Beating", "how hard it beats on peaks", 0.0, 1.0),
        _slider("crt", "intensity", "Restlessness", "signal breaks, static", 0.0, 1.5),
        _slider("crt", "camera", "Framing", "how much the shot moves", 0.0, 2.0),
        _slider("crt", "bloom", "Phosphor glow", "light around the letters", 0.0, 2.0),
        _slider("crt", "scanlines", "Scanlines", "depth of the comb", 0.0, 1.0),
        _slider("crt", "noise", "Static", "grain on the glass", 0.0, 1.0),
        _slider("crt", "water_amp", "Water", "sea swell and pond shiver", 0.0, 1.0),
        _slider("crt", "infect_lead", "Colour lead", "how early the colour jumps", 0.0, 0.5),
        _slider("crt", "alarm_threshold", "Alarm rarity", "how rare the red screen is", 0.0, 1.0),
    ]},
]

# las filas que son perillas del TOML, por id ("seccion.clave")
ROWS = {row["id"]: row for group in GROUPS for row in group["rows"]
        if row["kind"] in ("toggle", "choice", "slider")}


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
    # slider: número de verdad (True también es un int en Python) y dentro del rango
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = min(max(float(value), row["min"]), row["max"])
    return round(round(value / row["step"]) * row["step"], 2)


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
    """Lo que la ventana necesita para dibujarse: grupos, valores actuales, si el
    tubo está prendido, los atajos y si hay daemon que aplique los cambios."""
    from . import system   # tarde: system importa config (mismo círculo que apply_config)
    cfg = config.load_config()
    values = {}
    for row_id in ROWS:
        section, key = _split(row_id)
        values[row_id] = cfg[section][key]
    return {
        "groups": GROUPS,
        "values": values,
        "crt": config.crt_on(),
        "keys": dict(cfg["keys"]),
        "terminal": system._terminal() or "",
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
