"""`fatal crt motif <kind>`: forzar un dibujo en una pantalla del tubo.

Hasta acá, ver un motivo concreto era PESCARLO: mandarle al overlay una letra
con la palabra clave que lo elige y rerollear (`cue drop`) hasta que el sorteo
lo sacara — minutos de espera para mirar una animación. Esto es el camino
directo: un evento propio al socket del overlay y esa pantalla dibuja eso.

El evento va por un `cmd` propio (`motif`) y NO como una perilla de `config`:
el daemon reenvía el evento `config` entero en cada reconexión y el overlay
responde a ese evento tirando el reparto de la línea (`crtForget`), así que un
forzado metido ahí se borraría solo y de paso movería la letra.

La lista de kinds válidos NO se escribe acá: se lee de `motifKinds` en
`shell/shell.qml`, que es de donde sale el pool de verdad. Duplicarla es
garantizar que algún día digan cosas distintas.
"""
import json
import os
import re
import socket
import subprocess

SOCK_PATH = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos.sock")

# el `off` del CLI: cualquiera de estas tres apaga el forzado
OFF_WORDS = ("off", "none", "clear")

_KINDS_RE = re.compile(r"property\s+var\s+motifKinds\s*:\s*\[(.*?)\]", re.S)


def qml_path():
    """`shell/shell.qml`, al lado del paquete (el repo o /usr/share/fatal-lyrics)."""
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, "shell", "shell.qml")


def read_kinds(path=None):
    """Los motivos que conoce el overlay, leídos de `motifKinds` en shell.qml.

    Devuelve [] si el archivo no está o si la lista cambió de forma: sin lista
    no se puede validar nada, y es mejor decirlo que inventar una vieja."""
    try:
        with open(path or qml_path(), encoding="utf-8") as fh:
            src = fh.read()
    except OSError:
        return []
    m = _KINDS_RE.search(src)
    if not m:
        return []
    return re.findall(r'"([^"]+)"', m.group(1))


def screen_names():
    """Los monitores conectados, o None si no se pudo preguntar.

    Es sólo para dar un error útil ("esa pantalla no existe") antes de mandar
    el evento; None significa "no sé", y ahí se manda igual y el overlay
    decide. El orden del índice NO sale de acá — el índice es el de
    `fatal crt setup`, que lo ordena el overlay."""
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True,
                             text=True, timeout=2)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    try:
        return [m["name"] for m in json.loads(out.stdout)]
    except (ValueError, KeyError, TypeError):
        return None


def usage(kinds=None):
    kinds = read_kinds() if kinds is None else kinds
    return ("usage: fatal crt motif <kind> [--screen <name|idx|all>]\n"
            "       fatal crt motif off\n"
            "kinds: " + (", ".join(kinds) if kinds else "(no se pudo leer shell.qml)")
            + "\nel índice es el de `fatal crt setup` (0 = la primera de la fila);"
              " sin --screen va a todas")


def parse_force(argv, kinds=None, screens=None):
    """Los argumentos de `fatal crt motif` -> (evento, error).

    Función pura: los kinds y los monitores se le pasan, no se averiguan acá
    (así el test no depende ni de shell.qml ni de que haya un compositor).
    Exactamente uno de los dos valores devueltos es None."""
    kinds = read_kinds() if kinds is None else kinds
    argv = list(argv)
    if not argv or argv[0] in ("-h", "--help"):
        return None, usage(kinds)
    kind = argv[0]
    rest = argv[1:]
    screen = None
    while rest:
        arg = rest.pop(0)
        if arg.startswith("--screen="):
            screen = arg.split("=", 1)[1]
        elif arg in ("--screen", "-s"):
            if not rest:
                return None, "--screen needs a value (name, index or 'all')"
            screen = rest.pop(0)
        else:
            return None, f"unknown argument {arg!r}\n" + usage(kinds)
    if kind.lower() in OFF_WORDS:
        # apagar es global: no hay "apagalo en una y dejalo en la otra" porque
        # el forzado es uno solo (un kind, una pantalla o todas)
        return {"cmd": "motif", "kind": None}, None
    if kinds and kind not in kinds:
        return None, (f"unknown motif kind {kind!r}\nkinds: " + ", ".join(kinds))
    if screen is None or screen == "all":
        return {"cmd": "motif", "kind": kind, "screen": "all"}, None
    if re.fullmatch(r"-?\d+", screen):
        idx = int(screen)
        if idx < 0:
            return None, f"screen index {idx} is out of range"
        if screens is not None and idx >= len(screens):
            return None, (f"screen index {idx} is out of range "
                          f"(hay {len(screens)}: " + ", ".join(screens) + ")")
        return {"cmd": "motif", "kind": kind, "screen": idx}, None
    if screens is not None and screen not in screens:
        return None, (f"unknown screen {screen!r} — hay: " + ", ".join(screens))
    return {"cmd": "motif", "kind": kind, "screen": screen}, None


def send(event, path=SOCK_PATH):
    """El evento al socket DEL OVERLAY (el daemon es otro cliente más)."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect(path)
        s.sendall((json.dumps(event, ensure_ascii=False) + "\n").encode())
    finally:
        s.close()


def force_cli(argv, screens=None):
    """`fatal crt motif ...`. Devuelve el código de salida.

    `screens=None` es "averigualos vos" (hyprctl); se los pasa el test."""
    ev, err = parse_force(argv, screens=screens if screens is not None else screen_names())
    if ev is None:
        print(err)
        # `--help` (o el llamado pelado) no es un error: imprime y se va bien
        return 0 if (not argv or argv[0] in ("-h", "--help")) else 1
    try:
        # el path se lee ACÁ y no en el default de send(): un default se
        # congela al importar y el test no podría apuntar a otro lado
        send(ev, SOCK_PATH)
    except OSError as exc:
        print(f"can't talk to the overlay ({exc}) — is it running? fatal status")
        return 1
    if ev["kind"] is None:
        print("motif force off")
    else:
        print(f"motif {ev['kind']} forced on {ev['screen']}")
    return 0
