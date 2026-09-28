#!/usr/bin/env python3
"""fatal-lyrics — rinde el vidrio (crt.frag) y el túnel fuera de pantalla y los mide.

    ./render.py --dir ../../shell --tag despues     # out/<tag>/*.png + métricas
    ./render.py --dir /tmp/antes --tag antes

Nunca abre nada en pantalla (plataforma `offscreen` ASIGNADA). Rinde a las
resoluciones de los monitores de Ferox: 1920×1080 y la vertical 1080×1920.

Métricas:
  moire   — energía de baja frecuencia (período > 8 px) del campo parejo pasado
            por el vidrio, después de sacarle la viñeta/curvatura con un pasabajos
            muy ancho. Un vidrio sin figuras da ~0: la máscara y las scanlines
            viven en frecuencias altas y el moiré es justo lo que las baja.
  costura — túnel sin vidrio: salto medio entre la fila de arriba y la de abajo
            del eje horizontal en la mitad izquierda, dividido por el salto
            típico entre filas vecinas en el resto de la imagen.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

import numpy as np  # noqa: E402
from PyQt6.QtCore import QUrl  # noqa: E402
from PyQt6.QtGui import QGuiApplication, QImage  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

TUBES = ["custom", "trinitron", "pvm", "arcade", "green", "amber"]
SIZES = [(1920, 1080), (1080, 1920)]


def grab(view, app):
    for _ in range(3):
        app.processEvents()
        img = view.grabWindow()
    img = img.convertToFormat(QImage.Format.Format_RGBA8888)
    a = np.frombuffer(img.constBits().asstring(img.sizeInBytes()), np.uint8)
    return img, a.reshape(img.height(), img.width(), 4)[:, :, :3].astype(np.float64)


def lowpass(x, k):
    # caja separable por suma acumulada (sin scipy). Borde en ESPEJO: con
    # "edge" la fila repetida rompe el peine de scanlines y el borde se lee
    # como moiré que no existe.
    def box(a, axis):
        c = np.cumsum(np.pad(a, [(k, k) if i == axis else (0, 0) for i in range(a.ndim)], mode="reflect"), axis=axis)
        n = a.shape[axis]
        hi = np.take(c, np.arange(2 * k, 2 * k + n), axis=axis)
        lo = np.take(c, np.arange(0, n), axis=axis)
        return (hi - lo) / (2 * k)
    return box(box(x, 0), 1)


def smooth(x, k):
    """Tres cajas seguidas: casi una gaussiana, que es como filtra el ojo. Una
    caja sola deja pasar la textura de período 3 (no cancela en 8 muestras) y la
    medida la confunde con moiré."""
    for _ in range(3):
        x = lowpass(x, k)
    return x


def moire(rgb):
    """Energía entre períodos de ~8 y ~200 px del campo parejo, en % del nivel medio."""
    y = rgb @ np.array([0.299, 0.587, 0.114])
    h, w = y.shape
    y = y[int(h * 0.12):int(h * 0.88), int(w * 0.12):int(w * 0.88)]   # lejos del bisel
    band = smooth(y, 2) - smooth(y, 40)     # períodos ~8..200 px
    return float(np.sqrt(np.mean(band ** 2)) / max(y.mean(), 1e-6) * 100)


def spectrum_peak(rgb):
    """El pico más alto del espectro 2D a baja frecuencia (sin DC), relativo al total."""
    y = rgb @ np.array([0.299, 0.587, 0.114])
    h, w = y.shape
    y = y[int(h * 0.12):int(h * 0.88), int(w * 0.12):int(w * 0.88)]
    y = smooth(y, 2) - smooth(y, 40)
    f = np.abs(np.fft.fftshift(np.fft.fft2(y * np.outer(np.hanning(y.shape[0]), np.hanning(y.shape[1])))))
    cy, cx = np.array(f.shape) // 2
    ry, rx = f.shape[0] // 8, f.shape[1] // 8          # períodos > 8 px
    low = f[cy - ry:cy + ry, cx - rx:cx + rx].copy()
    low[ry - 2:ry + 3, rx - 2:rx + 3] = 0
    return float(low.max() / (f.sum() / f.size))


def texture(rgb):
    """Lo que queda de textura fina (períodos de 2 a ~6 px), en % del nivel medio:
    que el moiré baje sin que esto se vaya a cero es la prueba de que no se
    borró la máscara."""
    y = rgb @ np.array([0.299, 0.587, 0.114])
    h, w = y.shape
    y = y[int(h * 0.12):int(h * 0.88), int(w * 0.12):int(w * 0.88)]
    band = y - smooth(y, 2)
    return float(np.sqrt(np.mean(band ** 2)) / max(y.mean(), 1e-6) * 100)


def envelope(rgb):
    """El moiré de un peine casi en Nyquist no es brillo: es CONTRASTE. El
    peine de 2 px, estirado por la curvatura, sigue siendo un peine, pero con
    zonas donde se ve fuerte y zonas donde se apaga (la estrella, los círculos).
    Esto mide cuánto varía, a gran escala, la amplitud local de la textura fina,
    en % de su promedio."""
    y = rgb @ np.array([0.299, 0.587, 0.114])
    h, w = y.shape
    y = y[int(h * 0.12):int(h * 0.88), int(w * 0.12):int(w * 0.88)]
    env = smooth(np.abs(y - smooth(y, 2)), 4)
    band = env - smooth(env, 40)
    return float(np.sqrt(np.mean(band ** 2)) / max(env.mean(), 1e-6) * 100)


def seam(rgb):
    y = rgb @ np.array([0.299, 0.587, 0.114])
    h, w = y.shape
    m = h // 2
    left = slice(int(w * 0.02), int(w * 0.45))
    jump = np.abs(y[m, left] - y[m - 1, left]).mean()
    rows = np.abs(np.diff(y[:, left], axis=0))
    rows = np.delete(rows, [m - 2, m - 1, m], axis=0)
    return float(jump / max(rows.mean(), 1e-6))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--tag", required=True)
    args = ap.parse_args()
    shader_dir = os.path.abspath(args.dir)
    out = os.path.join(HERE, "out", args.tag)
    os.makedirs(out, exist_ok=True)

    app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
    view = QQuickView()
    view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
    view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Check.qml")))
    if view.status() != QQuickView.Status.Ready:
        for e in view.errors():
            print(e.toString(), file=sys.stderr)
        sys.exit(1)
    root = view.rootObject()
    root.setProperty("dir", QUrl.fromLocalFile(shader_dir).toString())
    view.show()

    res = {}
    for w, h in SIZES:
        view.resize(w, h)
        root.setProperty("width", w)
        root.setProperty("height", h)
        for tube in TUBES:
            root.setProperty("tube", tube)
            root.setProperty("source", "flat")
            root.setProperty("glassOn", True)
            img, rgb = grab(view, app)
            name = f"glass-{tube}-{w}x{h}"
            img.save(os.path.join(out, name + ".png"))
            res[name] = {"moire": round(moire(rgb), 3), "peak": round(spectrum_peak(rgb), 1),
                         "textura": round(texture(rgb), 2), "envolvente": round(envelope(rgb), 2)}
            root.setProperty("source", "tunnel")
            img, _ = grab(view, app)
            img.save(os.path.join(out, f"tunnel-glass-{tube}-{w}x{h}.png"))
        # plano: el vidrio sin curvatura tiene que dar lo mismo que antes
        root.setProperty("source", "flat")
        root.setProperty("curvOverride", 0.0)
        for tube in ("custom", "green"):
            root.setProperty("tube", tube)
            img, _ = grab(view, app)
            img.save(os.path.join(out, f"glass-{tube}-plano-{w}x{h}.png"))
        root.setProperty("curvOverride", -1.0)
        # la costura, con el túnel derecho: el corte de atan cae justo entre
        # las filas h/2-1 y h/2 (con curva se corre y la medida no lo encuentra)
        root.setProperty("source", "tunnel")
        root.setProperty("glassOn", False)
        root.setProperty("bend", 0.0)
        worst = 0.0
        for i, rl in enumerate(np.linspace(0, 1, 7)):
            root.setProperty("roll", float(rl))
            img, rgb = grab(view, app)
            if i == 0:
                img.save(os.path.join(out, f"tunnel-flat-{w}x{h}.png"))
            worst = max(worst, seam(rgb))
        root.setProperty("roll", 0.0)
        root.setProperty("bend", 0.45)
        root.setProperty("glassOn", True)
        res[f"tunnel-seam-{w}x{h}"] = round(worst, 2)
    with open(os.path.join(out, "metrics.json"), "w") as f:
        json.dump(res, f, indent=1)
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
