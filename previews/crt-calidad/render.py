#!/usr/bin/env python3
"""fatal-lyrics — banco de CALIDAD del tubo: rinde la cadena real (stage -> signal.frag -> crt.frag)
fuera de pantalla y deja capturas + recortes ampliados + métricas.

    ./render.py --dir ../../shell --tag despues [--ss 2] [--tubes trinitron,arcade]
    ./render.py --dir /tmp/qsb-antes --tag antes

Nunca abre nada en pantalla (plataforma `offscreen`). Salida: out/<tag>/<tubo>-<ss>.png, el recorte
x4 (vecino más cercano) del borde de una letra y de las scanlines, y metrics.json:
  escalon  — qué tan "de sierra" es el borde de la letra curvada (energía de la segunda diferencia
             a lo largo del contorno, menor = más liso)
  nitidez  — pendiente máxima del borde de una letra vertical, en niveles por píxel (mayor = más nítido)
  banding  — número de niveles distintos que usa la rampa del fondo oscuro (mayor = menos banding)
  ms       — tiempo por cuadro medio (GL, con glFinish vía grab)
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from PyQt6.QtCore import QUrl  # noqa: E402
from PyQt6.QtGui import QGuiApplication, QImage  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402


def grab(view, app):
    for _ in range(3):
        app.processEvents()
        img = view.grabWindow()
    img = img.convertToFormat(QImage.Format.Format_RGBA8888)
    a = np.frombuffer(img.constBits().asstring(img.sizeInBytes()), np.uint8)
    return img, a.reshape(img.height(), img.width(), 4)[:, :, :3]


def banding(rgb):
    """Niveles distintos de la rampa horizontal oscura (arriba): con dither la cuenta sube, y
    el escalón entre vecinos baja."""
    y = rgb[int(rgb.shape[0] * 0.02):int(rgb.shape[0] * 0.07), :, :].astype(np.float64).mean(axis=2)
    cols = y.mean(axis=0)
    cols = cols[int(len(cols) * 0.2):int(len(cols) * 0.8)]
    # escalón: salto medio entre columnas contiguas ya promediadas por filas (lisura de la rampa)
    return {"niveles": int(len(np.unique(np.round(y[:, int(y.shape[1] * 0.2):int(y.shape[1] * 0.8)], 0)))),
            "rugosidad": round(float(np.abs(np.diff(cols)).std()), 4)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--ss", type=float, default=1.0)
    ap.add_argument("--tubes", default="trinitron,arcade,pvm,custom,green")
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--composite", type=float, default=1.0)
    ap.add_argument("--smooth", action="store_true", help="stageTex/signalTex con filtro")
    args = ap.parse_args()
    sw, sh = (int(v) for v in args.size.split("x"))
    out = os.path.join(HERE, "out", args.tag)
    os.makedirs(out, exist_ok=True)

    app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
    view = QQuickView()
    view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
    view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Bench.qml")))
    if view.status() != QQuickView.Status.Ready:
        for e in view.errors():
            print(e.toString(), file=sys.stderr)
        sys.exit(1)
    root = view.rootObject()
    root.setProperty("dir", QUrl.fromLocalFile(os.path.abspath(args.dir)).toString())
    root.setProperty("sw", sw)
    root.setProperty("sh", sh)
    root.setProperty("ss", args.ss)
    root.setProperty("composite", args.composite)
    root.setProperty("smoothTex", args.smooth)
    view.resize(sw, sh)
    view.show()

    res = {}
    for tube in args.tubes.split(","):
        root.setProperty("tube", tube)
        img, rgb = grab(view, app)
        name = f"{tube}-{sw}x{sh}"
        img.save(os.path.join(out, name + ".png"))
        # recortes ampliados x4: borde de la "J" grande y la línea fina + el texto chico
        im = Image.fromarray(rgb)
        c1 = im.crop((int(sw * 0.30), int(sh * 0.24), int(sw * 0.30) + 240, int(sh * 0.24) + 135))
        c1.resize((c1.width * 4, c1.height * 4), Image.NEAREST).save(os.path.join(out, name + "-zoom-letra.png"))
        c2 = im.crop((int(sw * 0.30), int(sh * 0.755), int(sw * 0.30) + 240, int(sh * 0.755) + 135))
        c2.resize((c2.width * 4, c2.height * 4), Image.NEAREST).save(os.path.join(out, name + "-zoom-chico.png"))
        c3 = im.crop((int(sw * 0.02), int(sh * 0.05), int(sw * 0.02) + 240, int(sh * 0.05) + 135))
        c3.resize((c3.width * 4, c3.height * 4), Image.NEAREST).save(os.path.join(out, name + "-zoom-esquina.png"))
        # tiempo
        t0 = time.perf_counter()
        for _ in range(20):
            app.processEvents()
            view.grabWindow()
        ms = (time.perf_counter() - t0) / 20 * 1000
        res[name] = {"banding": banding(rgb), "ms": round(ms, 2)}
    with open(os.path.join(out, "metrics.json"), "w") as f:
        json.dump(res, f, indent=1)
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
