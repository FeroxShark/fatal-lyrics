#!/usr/bin/env python3
"""fatal-lyrics — karaoke de la letra del tubo: la palabra que suena toma `pal.hot`, fuera de pantalla.

    ./karaoke.py     # docs/tanda8-estado/letra/karaoke-hot.png

Cuatro paletas reales de `shell.qml` (las de menos y más contraste entre `ink` y `hot`), con la
palabra 3 sonando contra todas quietas. Plataforma `offscreen`, nunca abre nada en pantalla.
"""
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

from PIL import Image, ImageDraw  # noqa: E402
from PyQt6.QtCore import QUrl  # noqa: E402
from PyQt6.QtGui import QColor, QGuiApplication  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

DOCS = os.path.join(ROOT, "docs", "tanda8-estado", "letra")
LINE = "Just as you take my hand"
SCALE = 0.4


def palettes():
    with open(os.path.join(ROOT, "shell", "shell.qml"), encoding="utf-8") as f:
        t = re.findall(r'bg: "(#\w{6})", ink: "(#\w{6})", hot: "(#\w{6})"', f.read())

    def lum(h):
        c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

    def ratio(a, b):
        hi, lo = sorted([lum(a), lum(b)], reverse=True)
        return (hi + 0.05) / (lo + 0.05)

    t.sort(key=lambda p: ratio(p[1], p[2]))
    return [t[0], t[2], t[len(t) // 2], t[-1]], ratio


def main():
    pals, ratio = palettes()
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
    sheet = Image.new("RGB", (tw * 2 + 12, (th + 18) * len(pals)), (20, 20, 20))
    tmp = os.path.join(HERE, "out", "tmp.png")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    for r, (bg, ink, hot) in enumerate(pals):
        for c, sung in enumerate((-1, 3)):
            root.setProperty("sw", w)
            root.setProperty("sh", h)
            root.setProperty("line", LINE)
            root.setProperty("mode", "rows")
            root.setProperty("bgC", QColor(bg))
            root.setProperty("inkC", QColor(ink))
            root.setProperty("hotC", QColor(hot))
            root.setProperty("sungIdx", sung)
            wait(1.2)   # el Behavior de la tinta (900 ms) tiene que asentar
            view.grabWindow().save(tmp)
            im = Image.open(tmp).convert("RGB").resize((tw, th), Image.LANCZOS)
            label = "antes (todo en ink)" if sung < 0 else "ahora: 'take' suena (hot)"
            ImageDraw.Draw(im).text((4, 4), f"{label}   ink {ink}  hot {hot}  contraste {ratio(ink, hot):.2f}",
                                    fill=(255, 255, 0))
            sheet.paste(im, (c * (tw + 12), r * (th + 18) + 16))
    os.makedirs(DOCS, exist_ok=True)
    dest = os.path.join(DOCS, "karaoke-hot.png")
    sheet.save(dest)
    os.remove(tmp)
    print("hoja:", dest)


if __name__ == "__main__":
    main()
