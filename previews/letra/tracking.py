#!/usr/bin/env python3
"""fatal-lyrics — tracking de la letra: 3 px fijos ("antes") contra 0.03 em del cuerpo ("después"),
fuera de pantalla. Tres versos de distinto cuerpo, en la pantalla ancha, con el `WordSlot` real.

    ./tracking.py     # docs/tanda8-estado/letra/tracking-antes-despues.png + ancho medido de cada línea

Nunca abre nada en pantalla (plataforma `offscreen`).
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

from PIL import Image, ImageDraw  # noqa: E402
from PyQt6.QtCore import QUrl  # noqa: E402
from PyQt6.QtGui import QGuiApplication  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

DOCS = os.path.join(ROOT, "docs", "tanda8-estado", "letra")
LINES = ["Hello world", "Come back in focus again",
         "Just as you take my hand and write my number down tonight"]
SCALE = 0.4


def main():
    app = QGuiApplication(sys.argv[:1])
    view = QQuickView()
    view.setResizeMode(QQuickView.ResizeMode.SizeViewToRootObject)
    view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Bench.qml")))
    if view.status() != QQuickView.Status.Ready:
        for e in view.errors():
            print(e.toString(), file=sys.stderr)
        sys.exit(1)
    root = view.rootObject()
    view.show()

    def wait(sec):
        end = time.time() + sec
        while time.time() < end:
            app.processEvents()
            time.sleep(0.004)

    w, h = 1920, 1080
    tw, th = int(w * SCALE), int(h * SCALE)
    sheet = Image.new("RGB", (tw * 2 + 12, (th + 18) * len(LINES)), (20, 20, 20))
    for r, line in enumerate(LINES):
        for c, tracking in enumerate(("fixed", "em")):
            root.setProperty("sw", w)
            root.setProperty("sh", h)
            root.setProperty("line", line)
            root.setProperty("mode", "rows")
            root.setProperty("tracking", tracking)
            wait(0.3)
            px, ls = root.property("px"), root.property("ls")
            tmp = os.path.join(HERE, "out", "tmp.png")
            os.makedirs(os.path.dirname(tmp), exist_ok=True)
            view.grabWindow().save(tmp)
            im = Image.open(tmp).convert("RGB").resize((tw, th), Image.LANCZOS)
            label = "antes 3 px" if tracking == "fixed" else "despues 0.03 em"
            ImageDraw.Draw(im).text((4, 4), f"{label}  cuerpo {round(px)} px  tracking {ls:.1f} px = {ls / px:.3f} em",
                                    fill=(255, 255, 0))
            sheet.paste(im, (c * (tw + 12), r * (th + 18) + 16))
            print(f"{line[:20]:20s} {tracking:5s} cuerpo={px:.0f} tracking={ls:.1f}")
        ImageDraw.Draw(sheet).text((4, r * (th + 18) + 2), line, fill=(255, 255, 255))
    os.makedirs(DOCS, exist_ok=True)
    dest = os.path.join(DOCS, "tracking-antes-despues.png")
    sheet.save(dest)
    os.remove(tmp)
    print("hoja:", dest)


if __name__ == "__main__":
    main()
