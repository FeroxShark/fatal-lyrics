#!/usr/bin/env python3
"""fatal-lyrics — banco del golpe del bajo y los agudos, fuera de pantalla.

    ./render.py          # docs/tanda8-estado/golpe-motif.png + out/metrics.json

Nunca abre nada en pantalla (plataforma `offscreen`). El `Motif` es el de `shell/`; los
números del golpe salen de la fila `normal` de `crtPaceTable` y de la MISMA cuenta que
hace `shell.qml` (`kickAmp`, `kickMs`) para un tema lento (carácter 0.1) y uno agitado (0.9).
"""
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402
from PyQt6.QtCore import QUrl  # noqa: E402
from PyQt6.QtGui import QGuiApplication, QImage  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

OUT = os.path.join(HERE, "out")
DOCS = os.path.join(ROOT, "docs", "tanda8-estado")


def pace_row(name):
    with open(os.path.join(ROOT, "shell", "shell.qml"), encoding="utf-8") as f:
        qml = f.read()
    table = re.search(r"crtPaceTable:\s*\(\{(.*?)\n    \}\)", qml, re.S).group(1)
    table = re.sub(r"//[^\n]*", "", table)
    for row, body in re.findall(r"^\s{8}(\w+):\s*\{(.*?)\n\s{8}\},", table, re.S | re.M):
        if row == name:
            return {k: float(v) for k, v in re.findall(r"(\w+):\s*([\d.]+)\b", body)}
    raise SystemExit(f"no hay fila {name}")


def kick_for(p, ch, knob=0.75):
    """La cuenta de `shell.qml`: (amplitud del dibujo, caída en ms)."""
    amp = (p["kickAmpMin"] + (1 - p["kickAmpMin"]) * ch) * knob
    ms = p["kickSlowMs"] + (p["kickFastMs"] - p["kickSlowMs"]) * ch
    return p["kickMotif"] * amp, round(ms)


def main():
    app = QGuiApplication(sys.argv[:1])
    view = QQuickView()
    view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
    view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Bench.qml")))
    if view.status() != QQuickView.Status.Ready:
        for e in view.errors():
            print(e.toString(), file=sys.stderr)
        sys.exit(1)
    view.resize(1280, 720)
    view.show()
    root = view.rootObject()

    def wait(sec):
        end = time.time() + sec
        while time.time() < end:
            app.processEvents()
            time.sleep(0.004)

    def grab():
        app.processEvents()
        img = view.grabWindow().convertToFormat(QImage.Format.Format_RGBA8888)
        a = np.frombuffer(img.constBits().asstring(img.sizeInBytes()), np.uint8)
        return a.reshape(img.height(), img.width(), 4)[:, :, :3].copy()

    p = pace_row("normal")
    metrics = {}
    shots = []
    wait(0.5)
    for name, ch in (("lento", 0.1), ("agitado", 0.9)):
        amt, ms = kick_for(p, ch)
        root.setProperty("bassAmt", amt)
        root.setProperty("bassMs", ms)
        wait(0.3)
        rest = grab()
        root.setProperty("bass", root.property("bass") + 1)
        peak_scale = root.property("scaleNow")
        peak = grab()
        wait(ms / 1000 * 1.5 + 0.1)
        after = root.property("scaleNow")
        metrics[name] = {"caracter": ch, "amp": round(amt, 4), "caida_ms": ms,
                         "escala_pico": round(peak_scale, 4), "escala_despues": round(after, 4)}
        shots += [(f"{name}: reposo", rest), (f"{name}: pico (x{peak_scale:.3f}, {ms} ms)", peak)]
    assert metrics["agitado"]["escala_pico"] > metrics["lento"]["escala_pico"] > 1.0
    assert metrics["agitado"]["caida_ms"] < metrics["lento"]["caida_ms"]
    assert abs(metrics["lento"]["escala_despues"] - 1.0) < 1e-3, "el golpe no volvió a 1"

    # agudos: subida marcada -> un destello blanco chico; sin subida, nada
    # fuera del disco del radar (x < 370 o x > 910) no se mueve nada: ahí sólo puede estar el
    # destello. Cae en un lugar al azar, así que se prueba hasta 12 veces
    outside = lambda a: np.concatenate([a[:, :370], a[:, 910:]], axis=1)
    base = grab().astype(np.int32)
    changed, glint = 0, None
    for _ in range(12):
        root.setProperty("hat", 0.0)
        wait(0.15)
        root.setProperty("hat", 0.9)
        glint = grab().astype(np.int32)
        changed = int((np.abs(outside(glint) - outside(base)).sum(axis=2) > 60).sum())
        if changed > 30:
            break
        wait(0.3)
    wait(0.4)
    quiet = int((np.abs(outside(grab().astype(np.int32)) - outside(base)).sum(axis=2) > 60).sum())
    metrics["agudos"] = {"pixeles_del_destello": changed, "pixeles_despues_de_apagarse": quiet}
    assert changed > 30 and quiet == 0, metrics["agudos"]
    shots.append(("agudos: destello", glint.astype(np.uint8)))

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "metrics.json"), "w") as f:
        json.dump(metrics, f, indent=2)
    print(json.dumps(metrics, indent=2))
    w = 640
    tiles = []
    for label, rgb in shots:
        im = Image.fromarray(rgb).resize((w, 360), Image.LANCZOS)
        ImageDraw.Draw(im).text((8, 6), label, fill=(255, 255, 255))
        tiles.append(im)
    cols = 2
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (w * cols, 360 * rows), (0, 0, 0))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * w, (i // cols) * 360))
    os.makedirs(DOCS, exist_ok=True)
    sheet.save(os.path.join(DOCS, "golpe-motif.png"))
    print("hoja:", os.path.join(DOCS, "golpe-motif.png"))


if __name__ == "__main__":
    main()
