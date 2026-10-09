"""Todo lo que le pregunta al sistema: playerctl, hyprctl."""
import json
import os
import shutil
import subprocess

from . import config
from . import util
from .util import FIELD_SEP, log

_hypr_warned = False


def _hyprland():
    """¿Estamos abajo de Hyprland, con hyprctl a mano?

    `hyprctl` es exclusivo de Hyprland: no existe en Sway, river ni el resto de
    los wlroots. Las dos features que dependen de él —la pausa por juego de
    gaming() y la enumeración de monitores de _monitors()/_monitors_lr()— chequean
    esto antes de shellear, así en otro compositor degradan limpio y avisan UNA
    sola vez, en vez de comerse un FileNotFoundError por tick escondido adentro de
    un except ancho.

    TODO: un fallback genérico es viable a futuro — `wlr-randr` o
    `swaymsg -t get_outputs` para los monitores, y el protocolo
    wlr-foreign-toplevel (o `swaymsg -t get_tree`) para la ventana activa.
    Fuera de scope por ahora: acá solo se avisa qué queda apagado.
    """
    # La firma sola no alcanza: arrancado como unit de systemd / app2unit / uwsm
    # el entorno viene lavado y HYPRLAND_INSTANCE_SIGNATURE puede no estar aunque
    # Hyprland esté andando. Por eso hay tres señales, todas baratas (nada de
    # subprocess): si alguna da, hyprctl encuentra el socket solo.
    global _hypr_warned
    signals = (
        bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")),
        "hyprland" in os.environ.get("XDG_CURRENT_DESKTOP", "").lower(),
        os.path.isdir(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/nonexistent"), "hypr")),
    )
    if any(signals) and shutil.which("hyprctl"):
        return True
    if not _hypr_warned:
        _hypr_warned = True
        log("no parece Hyprland (ni HYPRLAND_INSTANCE_SIGNATURE, ni "
            "XDG_CURRENT_DESKTOP, ni socket en XDG_RUNTIME_DIR/hypr) o falta hyprctl: "
            "quedan apagadas la pausa por juego y la lista de monitores. "
            "El resto de cartelitos anda igual.")
    return False


def playerctl_state():
    """Devuelve dict con track+posición del player, o None si no hay."""
    fmt = FIELD_SEP.join([
        "{{mpris:trackid}}", "{{title}}", "{{artist}}", "{{album}}",
        "{{mpris:length}}", "{{status}}", "{{position}}", "{{mpris:artUrl}}",
    ])
    try:
        out = subprocess.run(
            ["playerctl", "-p", config.CFG["behavior"]["player"], "metadata", "--format", fmt],
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


def is_game_window(win):
    """¿Esa ventana a pantalla completa es un juego, o alguien mirando un video?

    La heurística de "fullscreen = juego" sola es demasiado ancha: un YouTube a
    pantalla completa apagaba la letra entera, que es exactamente cuando uno la
    quiere. Se mira la clase de la ventana antes de cortar contra la lista
    configurable config.CFG["system"]["not_a_game"] (default en
    config.DEFAULTS, ver config.toml).

    `win` es el JSON de `hyprctl activewindow -j` (claves fullscreen,
    fullscreenClient, class, initialClass): la forma es de Hyprland. La
    función no shellea nada — sí lee la config viva, así que no es pura."""
    if not win:
        return False
    if win.get("fullscreen", 0) == 0 and win.get("fullscreenClient", 0) == 0:
        return False
    name = (str(win.get("class", "")) + " " + str(win.get("initialClass", ""))).lower()
    return not any(tag in name for tag in config.CFG["system"]["not_a_game"])


def gaming():
    """True si hay un JUEGO en pantalla completa (no molestar).

    REQUIERE HYPRLAND: se apoya en `hyprctl activewindow`, que no tiene equivalente
    en otros compositores. Fuera de Hyprland siempre devuelve False (o sea: la
    pausa por juego queda apagada) y _hyprland() avisa una vez por qué.

    No depende de una lista de juegos: cualquiera que pida fullscreen cuenta, menos
    los navegadores y reproductores (ver is_game_window). No detecta borderless
    windowed, que para Hyprland es una ventana normal."""
    if not config.CFG["behavior"]["game_pause"]:
        return False
    if not _hyprland():
        return False
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"],
                             capture_output=True, text=True, timeout=2)
        if out.returncode != 0 or not out.stdout.strip():
            return False
        return is_game_window(json.loads(out.stdout))
    except Exception:
        return False

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
    """Monitores conectados.

    REQUIERE HYPRLAND: sale de `hyprctl monitors -j`. Fuera de Hyprland devuelve
    lista vacía (en Ajustes no aparecen monitores para marcar) y _hyprland() avisa una vez."""
    if not _hyprland():
        return []
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
    """Monitores ordenados como están puestos: de izquierda a derecha.

    REQUIERE HYPRLAND, igual que _monitors(): las coordenadas x/y salen de
    `hyprctl monitors -j`. Fuera de Hyprland, lista vacía."""
    if not _hyprland():
        return []
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

def _daemon_pid():
    """PID del daemon, o None. Confirma el cmdline: un PID reciclado con
    SIGUSR1 encima mata un proceso ajeno."""
    try:
        with open(util.DAEMON_PID_PATH) as f:
            pid = int(f.read().strip())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            if b"cartelitos" not in f.read():
                return None
        return pid
    except (OSError, ValueError):
        return None

# Nada de esto es obligatorio: cada cosa que falta apaga UNA función y el resto
# sigue andando. El problema era enterarse — sin bandeja, sin colores de tapa o
# con el tubo quieto parecía un bug, no un paquete que no estaba instalado.
OPTIONAL_TOOLS = [
    (("magick", "convert"),
     "no album-cover colours (the tube falls back to its own palettes)"),
    (("pw-record", "parec"),
     "audio-reactive CRT mode off (the tube won't move with the music)"),
    (("pactl",),
     "the default sink can't be found, so audio capture never starts"),
    (("hyprctl",),
     "no auto-pause on games and no monitor list in the config menu"),
]


def _tray_available():
    """Si el ícono de la bandeja puede levantarse: gi + el typelib de Ayatana."""
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        gi.require_version("AyatanaAppIndicator3", "0.1")
        return True
    except Exception:
        return False


def missing_tools():
    """[(qué falta, qué queda degradado)] de las herramientas OPCIONALES."""
    out = []
    for names, consequence in OPTIONAL_TOOLS:
        if not any(shutil.which(n) for n in names):
            out.append(("/".join(names), consequence))
    if not _tray_available():
        out.append(("python-gobject + AyatanaAppIndicator3",
                    "no tray icon (fatal-lyrics still runs, just without it)"))
    return out


def health_lines():
    """Las mismas líneas que muestra `fatal status`, listas para imprimir."""
    return [f"{what} not found → {consequence}"
            for what, consequence in missing_tools()]


# ------------------------------------------------------ los binds del sync
# `fatal sync +/-` corregido a ojo, con teclas propias (tanda 3, C). Los binds
# viven en la config de Hyprland del usuario, así que fatal-lyrics NO los
# escribe por default: mientras la perilla valga lo mismo que DEFAULTS, el bind
# que ya está ahí es el correcto y tocarlo sería tener el mismo atajo dos veces.
# Recién cuando alguien la cambia hay que intervenir, y ahí siempre igual:
# UNBIND del anterior, BIND del nuevo. Volver al valor de fábrica también pasa
# por acá — si sólo se actuara "cuando difiere del default", volver dejaría la
# tecla muerta hasta el próximo reload de Hyprland, porque el unbind ya se hizo.
# perilla de [keys] -> lo que corre el bind. El del CRT entró después (con el
# rótulo de las teclas en la letra): para que el rótulo salga de la config, la
# tecla del tubo tenía que estar en la config, y entonces se bindea igual.
BIND_KEYS = (("sync_forward", "sync +"), ("sync_back", "sync -"),
             ("crt_toggle", "crt toggle"))
# de fábrica; se lee de config para que haya UN solo lugar con el valor
DEFAULTS_KEYS = config.DEFAULTS["keys"]


def _fatal_bin():
    """Ruta ABSOLUTA a bin/fatal. El `exec` de Hyprland no tiene ~/.local/bin en
    el PATH: un `fatal sync +` pelado no corre nunca y el bind queda mudo."""
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "bin", "fatal")


_hypr_lua_cache = None


def _hypr_lua():
    """¿El Hyprland que corre lee su config en Lua (0.56+)?

    Con el parser de Lua `hyprctl keyword` ya no hace nada: contesta "keyword
    can't work with non-legacy parsers. Use eval." con código de salida 0, así
    que un bind por `keyword` fallaba MUDO. Se pregunta una vez con un `eval`
    inofensivo: el Lua contesta "ok", el hyprlang de antes no conoce `eval`."""
    global _hypr_lua_cache
    if _hypr_lua_cache is None:
        try:
            out = subprocess.run(["hyprctl", "eval", "return 0"],
                                 capture_output=True, text=True, timeout=2)
            _hypr_lua_cache = out.returncode == 0 and out.stdout.strip() == "ok"
        except (OSError, subprocess.SubprocessError):
            _hypr_lua_cache = False
    return _hypr_lua_cache


def _lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _lua_keys(hypr):
    """"Super+Alt, Right" (sintaxis hyprlang, la de la perilla) a
    "SUPER + ALT + Right", la del Lua: ahí los modificadores van en mayúsculas
    — "Super" lo toma por una tecla y falla con `Unknown keysym`."""
    mods, _, key = hypr.partition(",")
    parts = [m.upper() for m in mods.replace("+", " ").split()]
    return " + ".join(parts + [key.strip()])


def key_bind_commands(old, new, lua=False):
    """Los `hyprctl` que hay que correr para pasar de `old` a `new`.

    Devolver la lista en vez de correrla es lo que hace testeable el orden
    (unbind antes que bind, siempre) sin shellear en los tests. `old`/`new` son
    los dicts de la sección [keys]; `old` en None es el arranque, donde lo que
    ya vale el default no se toca. `lua` elige el dialecto: `hyprctl eval` con
    `hl.unbind`/`hl.bind` (Hyprland 0.56+) o el `hyprctl keyword` de antes."""
    out = []
    first = old is None
    for key, arg in BIND_KEYS:
        # una perilla que falta es la de fábrica (un dict de [keys] de antes
        # del CRT): leerla como "" sería desbindear la tecla del tubo
        want = (new.get(key, DEFAULTS_KEYS.get(key)) or "").strip()
        was = None if first else (old.get(key, DEFAULTS_KEYS.get(key)) or "").strip()
        if first:
            if want == DEFAULTS_KEYS.get(key):
                continue        # el bind del usuario ya hace esto
        elif want == was:
            continue            # no cambió: nada que rebindear
        # el anterior sale SIEMPRE, incluso el del default: si no, el atajo
        # viejo sigue vivo y dos binds mandan el mismo gesto dos veces
        gone = DEFAULTS_KEYS.get(key) if first else was
        cmd = f"{_fatal_bin()} {arg}"
        if lua:
            if gone:
                out.append(["hyprctl", "eval", f"hl.unbind({_lua_str(_lua_keys(gone))})"])
            if want:
                out.append(["hyprctl", "eval",
                            f"hl.bind({_lua_str(_lua_keys(want))}, "
                            f"hl.dsp.exec_cmd({_lua_str(cmd)}))"])
            continue
        if gone:
            out.append(["hyprctl", "keyword", "unbind", gone])
        if want:
            out.append(["hyprctl", "keyword", "bind", f"{want}, exec, {cmd}"])
    return out


_ARROWS = {"right": "→", "left": "←", "up": "↑", "down": "↓"}


def _pretty_keys(hypr):
    """"Super+Alt, Right" a ("Super+Alt+", "→"): los modificadores con la
    mayúscula de siempre y las flechas como flechas. Separados para poder
    escribir "Super+Alt+→ / ←" cuando los dos sync comparten modificadores."""
    mods, _, key = (hypr or "").partition(",")
    if not key.strip():          # sin coma: un bind pelado, sin modificadores
        mods, key = "", mods
    parts = [m.capitalize() for m in mods.replace("+", " ").split()]
    key = key.strip()
    key = _ARROWS.get(key.lower(), key.upper() if len(key) == 1 else key)
    return ("+".join(parts) + "+" if parts else ""), key


def keys_hint(keys):
    """El rótulo de las teclas que la letra muestra unos segundos al empezar
    un tema: "Super+Alt+→ / ←  sync ±0.1 s   ·   Super+Shift+Y  CRT".

    Sale de [keys] y no de un texto fijo: si alguien cambia el bind, el rótulo
    cambia con él (la config es la que manda los binds, ver arriba). Una tecla
    vacía no aparece; sin ninguna, "" y el overlay no dibuja nada. Fuera de
    Hyprland igual se manda: las perillas dicen qué teclas habría."""
    get = lambda k: (keys.get(k, DEFAULTS_KEYS.get(k)) or "").strip()
    fwd, back, crt = get("sync_forward"), get("sync_back"), get("crt_toggle")
    out = []
    if fwd and back:
        (fm, fk), (bm, bk) = _pretty_keys(fwd), _pretty_keys(back)
        both = fm + fk + " / " + (bk if fm == bm else bm + bk)
        out.append(both + "  sync ±0.1 s")
    elif fwd or back:
        m, k = _pretty_keys(fwd or back)
        out.append(m + k + "  sync " + ("+" if fwd else "-") + "0.1 s")
    if crt:
        m, k = _pretty_keys(crt)
        out.append(m + k + "  CRT")
    return "   ·   ".join(out)


def apply_key_binds(old, new, run=None, lua=None):
    """Aplica los binds de [keys]. Devuelve los comandos que corrió."""
    if not key_bind_commands(old, new) or not _hyprland():
        return []
    cmds = key_bind_commands(old, new, _hypr_lua() if lua is None else lua)
    runner = run or (lambda argv: subprocess.run(
        argv, capture_output=True, timeout=2, check=False))
    for argv in cmds:
        try:
            runner(argv)
        except (OSError, subprocess.SubprocessError) as e:
            log(f"couldn't apply the sync keybind ({e})")
            continue
        log("keys: " + " ".join(argv[2:]))
    return cmds
