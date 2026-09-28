#!/usr/bin/env python3
"""Hoja de muestra de las fuentes de la letra, offscreen (tanda 8).

    ./fontsheet.py [salida.png]      # default: docs/tanda8-estado/fuentes-muestra.png
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# ASIGNADO, no setdefault (misma trampa que render.py: la sesión exporta wayland)
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

from PyQt6.QtCore import QUrl, qInstallMessageHandler  # noqa: E402
from PyQt6.QtGui import QGuiApplication  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402


# sin esto los errores de QML (un FontLoader que no carga) no salen por ningún lado
qInstallMessageHandler(lambda mode, ctx, msg: print(f"qml: {msg}", file=sys.stderr))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        HERE, "..", "..", "docs", "tanda8-estado", "fuentes-muestra.png")
    app = QGuiApplication(sys.argv[:1])
    view = QQuickView()
    view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "FontSheet.qml")))
    if view.status() != QQuickView.Status.Ready:
        for e in view.errors():
            print(e.toString(), file=sys.stderr)
        sys.exit(1)
    view.show()
    for _ in range(20):   # que carguen los FontLoader
        app.processEvents()
    img = view.grabWindow()
    img.save(os.path.abspath(out))
    print(os.path.abspath(out))


if __name__ == "__main__":
    main()
