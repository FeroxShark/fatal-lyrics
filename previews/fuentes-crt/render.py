#!/usr/bin/env python3
"""Banco de FUENTES de la letra del CRT: cada fuente de `shell/shell.qml` (y las `--extra`) pasa por
el vidrio real (stage -> signal.frag -> crt.frag), 5 por página, offscreen (nunca abre ventana).

    ./render.py [--tube trinitron] [--only vt323,plex] [--extra ruta.ttf[:bold]] [--tag nombre]

Salida: out/<tag>/<tubo>-p<N>.png (+ un recorte x3 del chico por fuente: out/<tag>/zoom-<clave>.png).
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

from PIL import Image  # noqa: E402
from PyQt6.QtCore import QUrl, qInstallMessageHandler  # noqa: E402
from PyQt6.QtGui import QGuiApplication  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

qInstallMessageHandler(lambda mode, ctx, msg: print(f"qml: {msg}", file=sys.stderr))
PER_PAGE = 5


def manifest():
    """[(clave, ruta, bold)] de lo que carga shell.qml (la fuente de verdad)."""
    qml = open(os.path.join(ROOT, "shell", "shell.qml"), encoding="utf-8").read()
    files = dict(re.findall(r'FontLoader \{ id: font(\w+); source: Qt\.resolvedUrl\("fonts/([^"]+)"\)', qml))
    keys = re.findall(r"(\w+): font(\w+)\.name", re.search(r"crtFontFamilies: \(\{(.*?)\}\)", qml, re.S).group(1))
    bold = dict(re.findall(r"(\w+):\s*(true|false)", re.search(r"crtFontBold: \(\{(.*?)\}\)", qml, re.S).group(1)))
    return [(k, os.path.join(ROOT, "shell", "fonts", files[i]), bold.get(k) == "true") for k, i in keys]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tube", default="trinitron")
    ap.add_argument("--only", default="")
    ap.add_argument("--extra", action="append", default=[], help="ruta.ttf[:bold] fuera de shell/fonts")
    ap.add_argument("--tag", default="fuentes")
    ap.add_argument("--no-bundled", action="store_true")
    ap.add_argument("--size", default="1920x1080")
    args = ap.parse_args()
    sw, sh = (int(v) for v in args.size.split("x"))
    fonts = [] if args.no_bundled else manifest()
    for e in args.extra:
        path, _, b = e.partition(":")
        fonts.append((os.path.splitext(os.path.basename(path))[0].split("-")[0].lower(), os.path.abspath(path), b == "bold"))
    if args.only:
        fonts = [f for f in fonts if f[0] in args.only.split(",")]
    out = os.path.join(HERE, "out", args.tag)
    os.makedirs(out, exist_ok=True)

    app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
    view = QQuickView()
    view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
    view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Glass.qml")))
    if view.status() != QQuickView.Status.Ready:
        for e in view.errors():
            print(e.toString(), file=sys.stderr)
        sys.exit(1)
    root = view.rootObject()
    root.setProperty("dir", QUrl.fromLocalFile(os.path.join(ROOT, "shell")).toString())
    root.setProperty("sw", sw)
    root.setProperty("sh", sh)
    root.setProperty("tube", args.tube)
    view.resize(sw, sh)
    view.show()
    for n, i in enumerate(range(0, len(fonts), PER_PAGE), 1):
        page = fonts[i:i + PER_PAGE]
        root.setProperty("rows", [[k, QUrl.fromLocalFile(p).toString(), os.path.basename(p), b] for k, p, b in page])
        for _ in range(12):   # que carguen los FontLoader y se asiente el vidrio
            app.processEvents()
        img = view.grabWindow()
        name = os.path.join(out, f"{args.tube}-p{n}.png")
        img.save(name)
        print(name)
        pil = Image.open(name)
        rowh = sh * 0.164
        for j, (k, _p, _b) in enumerate(page):
            y0 = int(sh * 0.045 + j * rowh + sh * 0.105)
            c = pil.crop((int(sw * 0.07), y0, int(sw * 0.07) + 640, y0 + 70))
            c.resize((c.width * 3, c.height * 3), Image.NEAREST).save(os.path.join(out, f"zoom-{k}.png"))


if __name__ == "__main__":
    main()
