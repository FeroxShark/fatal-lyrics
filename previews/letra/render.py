#!/usr/bin/env python3
"""fatal-lyrics — banco de la letra en el tubo (renglones de `Rows.js`), fuera de pantalla.

    ./render.py          # docs/tanda8-estado/letra-renglones.png + out/metrics.json

Nunca abre nada en pantalla (plataforma `offscreen`). `Bench.qml` replica el `measure` y las
palabras de `shell/Crt.qml` con el `WordSlot` real: cada línea se dibuja como estaba (una palabra
por renglón, "antes") y con renglones centrados ("después"), en una pantalla ancha (1920x1080) y
en la vertical (1080x1920). Mide el tamaño de la letra y avisa si algún renglón se sale de la caja.
"""
import json
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

OUT = os.path.join(HERE, "out")
DOCS = os.path.join(ROOT, "docs", "tanda8-estado")
LINES = [
    "Hello world",
    "Come back in focus again",
    "Just as you take my hand",
    "I want to break free from your lies",
    "Just as you take my hand and write my number down tonight",
]
SCREENS = [("ancha", 1920, 1080), ("vertical", 1080, 1920)]
SCALE = 0.25


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

    metrics = {}
    tiles = []
    for sname, w, h in SCREENS:
        for line in LINES:
            row = []
            for mode in ("stack", "rows"):
                root.setProperty("sw", w)
                root.setProperty("sh", h)
                root.setProperty("line", line)
                root.setProperty("mode", mode)
                wait(0.25)
                px = root.property("px")
                img = view.grabWindow()
                metrics[f"{sname} | {line} | {mode}"] = round(px)
                row.append((mode, px, img))
            tiles.append((sname, line, row))
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "metrics.json"), "w") as f:
        json.dump(metrics, f, indent=1, ensure_ascii=False)
    print(json.dumps(metrics, indent=1, ensure_ascii=False))

    for sname, w, h in SCREENS:
        sub = [t for t in tiles if t[0] == sname]
        tw, th = int(w * SCALE), int(h * SCALE)
        sheet = Image.new("RGB", (tw * 2 + 12, (th + 18) * len(sub)), (20, 20, 20))
        for r, (_, line, row) in enumerate(sub):
            for c, (mode, px, img) in enumerate(row):
                path = os.path.join(OUT, "tmp.png")
                img.save(path)
                im = Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS)
                ImageDraw.Draw(im).text((4, 4), f"{'antes' if mode == 'stack' else 'despues'}  {round(px)} px", fill=(255, 255, 0))
                sheet.paste(im, (c * (tw + 12), r * (th + 18) + 16))
            ImageDraw.Draw(sheet).text((4, r * (th + 18) + 2), line, fill=(255, 255, 255))
        os.makedirs(DOCS, exist_ok=True)
        dest = os.path.join(DOCS, f"letra-renglones-{sname}.png")
        sheet.save(dest)
        print("hoja:", dest)
    os.remove(os.path.join(OUT, "tmp.png"))


if __name__ == "__main__":
    main()
