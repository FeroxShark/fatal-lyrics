#!/usr/bin/env python3
"""fatal-lyrics — captura de la ventana de Ajustes, fuera de pantalla.

    ./render.py [qml] [salida.png]      # por defecto shell/settings.qml -> out/ajustes.png

Nunca abre nada en pantalla (plataforma `offscreen`). settings.qml es un ShellRoot de Quickshell
con una PanelWindow de layer-shell, que no corre en un QQuickView; acá se la copia con los tipos
de Quickshell cambiados por Items pelados (`stubs()`) y se le carga el snapshot REAL de
cartelitos/settings.py (con el sistema simulado). Sirve para mirar la jerarquía, no para medir.
"""
import json
import os
import re
import sys
import tempfile
import time
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"
sys.path.insert(0, ROOT)

from PyQt6.QtCore import QUrl  # noqa: E402
from PyQt6.QtGui import QGuiApplication  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

PRELUDE = """
import QtQuick
Item { }
"""


def stubs(src):
    src = re.sub(r"^import Quickshell[^\n]*\n", "", src, flags=re.M)
    src = re.sub(r"^\s*(WlrLayershell\.[^\n]*|exclusionMode:[^\n]*)\n", "", src, flags=re.M)
    src = src.replace("Quickshell.env(", "env(").replace("Quickshell.execDetached(", "execDetached(")
    src = src.replace("ShellRoot {", "Item {", 1)
    src = re.sub(r"\bPanelWindow \{", "Item { property color color", src)
    # lo que habla con el sistema pasa a no hacer nada
    helpers = """
    function env(n) { return ""; }
    function execDetached(a) { }
    property var screen: null
    component FileView: Item { property string path; property bool preload; property bool printErrors;
        property bool atomicWrites; property bool watchChanges; signal loaded(); signal loadFailed();
        function setText(t) { } function reload() { } function text() { return ""; } }
    component StdioCollector: Item { signal streamFinished() }
    component Process: Item { property var command; property var stdout; property bool running;
        signal exited() }
"""
    src = src.replace("    id: root\n", "    id: root\n" + helpers, 1)
    return src


def snapshot():
    from cartelitos import settings, system
    with mock.patch.object(system, "_monitors_lr",
                           lambda: [("DP-2", "1080x1920"), ("HDMI-A-1", "1920x1080"),
                                    ("DP-1", "1920x1080")]), \
            mock.patch.object(system, "_players", lambda: ["spotify"]), \
            mock.patch.object(system, "_daemon_pid", lambda: 1):
        snap = settings.snapshot()
    snap["values"].update({"display.karaoke": True, "display.dialogs": True,
                           "behavior.now_playing": True, "behavior.sing": False})
    snap["crt"] = False
    return snap


def main():
    qml = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "shell", "settings.qml")
    out = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.path.join(HERE, "out", "ajustes.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(qml, encoding="utf-8") as f:
        src = stubs(f.read())
    tmp = tempfile.mkdtemp(prefix="ajustes-")
    path = os.path.join(tmp, "settings.qml")
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    app = QGuiApplication(sys.argv[:1])
    view = QQuickView()
    view.setResizeMode(QQuickView.ResizeMode.SizeViewToRootObject)
    view.setSource(QUrl.fromLocalFile(path))
    if view.status() != QQuickView.Status.Ready:
        for e in view.errors():
            print(e.toString(), file=sys.stderr)
        sys.exit(1)
    root = view.rootObject()
    snap = snapshot()
    from PyQt6.QtCore import QMetaObject, Q_ARG, Qt  # noqa: E402
    QMetaObject.invokeMethod(root, "load", Qt.ConnectionType.DirectConnection,
                             Q_ARG("QVariant", json.dumps(snap)))
    # el frame (la ventana de adentro) es lo que se muestra; la raíz mide 0
    frame = root.findChild(type(root), "frame") if False else None
    view.setWidth(960)
    view.setHeight(860)
    view.show()
    end = time.time() + 1.0
    while time.time() < end:
        app.processEvents()
        time.sleep(0.01)
    view.grabWindow().save(out)
    print(out)


if __name__ == "__main__":
    main()
