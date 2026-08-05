"""Todo lo que le pregunta al sistema: playerctl, hyprctl, la terminal."""
import json
import os
import shutil
import subprocess

from . import config
from . import util
from .util import FIELD_SEP

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
    if not config.CFG["behavior"]["game_pause"]:
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
