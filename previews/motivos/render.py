#!/usr/bin/env python3
"""fatal-lyrics — banco de los motivos de Motif.qml, fuera de pantalla.

    ./render.py antes  radar rain ekg textsea harmonograph vector   # hoja a docs/tanda8-estado/motivos/
    ./render.py despues radar ...

Nunca abre nada en pantalla (plataforma `offscreen`). El `Motif` es el de `shell/`, sin vidrio.
Corre en tiempo real (los motivos integran `frameTime`), con un tempo de 128 BPM sintético.
Salida: docs/tanda8-estado/motivos/<tag>-<kind>.png (tira de cuadros con rótulo).
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402
from PyQt6.QtCore import QUrl, qInstallMessageHandler  # noqa: E402
from PyQt6.QtGui import QGuiApplication, QImage  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

DOCS = os.path.join(ROOT, "docs", "tanda8-estado", "motivos")
BEAT = 60 / 128
LETRA = ["Cuando la noche cae sobre la ciudad", "las luces se prenden una por una",
         "y vos seguís mirando la pantalla", "como si el mundo no pudiera esperar"] * 12


def _qt_log(mode, ctx, msg):
    print(f"qml: {msg}", file=sys.stderr)


qInstallMessageHandler(_qt_log)


class Bench:
    def __init__(self, kind):
        self.app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
        self.view = QQuickView()
        self.view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
        self.view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Bench.qml")))
        if self.view.status() != QQuickView.Status.Ready:
            for e in self.view.errors():
                print(e.toString(), file=sys.stderr)
            sys.exit(1)
        self.view.resize(1280, 720)
        self.view.show()
        self.root = self.view.rootObject()
        self.root.setProperty("kind", kind)
        self.root.setProperty("beatMs", BEAT * 1000)
        self.root.setProperty("bpmLive", True)
        self.t0 = time.time()
        self.next_beat = self.t0 + BEAT
        self.n = 0
        self.level = 0.5

    def run(self, sec):
        """Tiempo real: reloj, un `tick` por tiempo, y deja pasar `sec` segundos."""
        end = time.time() + sec
        while time.time() < end:
            now = time.time()
            self.root.setProperty("clock", 3000 + now - self.t0)
            if now >= self.next_beat:
                self.next_beat += BEAT
                self.n += 1
                self.root.setProperty("tick", self.n)
                self.root.setProperty("beat", self.n)
                self.root.setProperty("kick", self.n)
                # el volumen llega vivo (14 Hz): el ekg se calla si no cambia en 2 s
                self.root.setProperty("level", self.level + 0.04 * (self.n % 2))
            self.app.processEvents()
            time.sleep(0.004)

    def run_to_beat(self, after=0.0):
        """Corre hasta que cae el próximo tiempo y `after` segundos más."""
        n = self.n
        while self.n == n:
            self.run(0.01)
        self.run(after)

    def grab(self):
        self.app.processEvents()
        img = self.view.grabWindow().convertToFormat(QImage.Format.Format_RGBA8888)
        a = np.frombuffer(img.constBits().asstring(img.sizeInBytes()), np.uint8)
        return a.reshape(img.height(), img.width(), 4)[:, :, :3].copy()


def scene(kind, tag):
    b = Bench(kind)
    shots = []
    if kind == "radar":
        b.level = 0.55
        b.run(1.0)
        for i in range(4):
            b.run(0.9)
            shots.append((f"radar +{i * 0.9 + 1.0:.1f}s", b.grab()))
    elif kind == "rain":
        b.level = 0.5
        b.run(3.0)
        shots.append(("lluvia", b.grab()))
        b.run(1.0)
        shots.append(("lluvia +1s", b.grab()))
    elif kind == "ekg":
        b.level = 0.6
        b.run(6.5)
        shots.append(("ekg", b.grab()))
        b.run(1.7)
        shots.append(("ekg +1.7s", b.grab()))
    elif kind == "textsea":
        b.level = 0.5
        b.root.setProperty("lines", [{"t0": i, "t1": i + 1, "text": s} for i, s in enumerate(LETRA)])
        b.root.setProperty("linesSynced", True)
        b.root.setProperty("lineNo", 20)
        b.run(3.0)
        shots.append(("textsea (verso 20)", b.grab()))
        b.root.setProperty("lineNo", 21)
        b.run(1.5)
        shots.append(("textsea (verso 21)", b.grab()))
    elif kind == "harmonograph":
        b.level = 0.5
        b.run(3.5)
        for i in range(3):
            b.run_to_beat(0.0)
            shots.append((f"harmonograph t={time.time() - b.t0:.1f}s", b.grab()))
            b.run(4.0)
    elif kind == "vector":
        b.level = 0.5
        b.run(2.0)
        for k in range(2):
            b.run_to_beat(0.03)
            shots.append((f"vector tiempo {b.n % 4 + 1} +30ms", b.grab()))
            b.run(0.30)
            shots.append((f"vector tiempo {b.n % 4 + 1} +330ms", b.grab()))
    else:
        raise SystemExit("kind sin escena: " + kind)
    return shots


def sheet(shots, path):
    w = 640
    tiles = []
    for label, rgb in shots:
        im = Image.fromarray(rgb).resize((w, 360), Image.LANCZOS)
        ImageDraw.Draw(im).text((8, 6), label, fill=(255, 255, 255))
        tiles.append(im)
    cols = 2
    rows = (len(tiles) + cols - 1) // cols
    out = Image.new("RGB", (w * cols, 360 * rows), (0, 0, 0))
    for i, t in enumerate(tiles):
        out.paste(t, ((i % cols) * w, (i // cols) * 360))
    out.save(path)
    print("hoja:", path)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    tag, kinds = sys.argv[1], sys.argv[2:]
    os.makedirs(DOCS, exist_ok=True)
    for kind in kinds:
        # una instancia por motivo: el proceso es nuevo para cada uno (ver abajo)
        sheet(scene(kind, tag), os.path.join(DOCS, f"{tag}-{kind}.png"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
