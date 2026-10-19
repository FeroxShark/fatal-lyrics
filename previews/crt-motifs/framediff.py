#!/usr/bin/env python3
"""Diff de cuadros con el reloj congelado (para cambios de shader que deben salir idénticos).

    ./framediff.py render dunes ocean pond --out /tmp/antes     # cuadros fijos, sin vidrio
    ./framediff.py render dunes ocean pond --out /tmp/despues
    ./framediff.py cmp /tmp/antes /tmp/despues                  # diff máximo y píxeles > 1/255

`render` usa `freeze` de Stage.qml: el motivo no corre solo y los pisotones/gotas quedan clavados,
así el mismo `t` da el mismo cuadro. Los .qsb salen de `motifs/` (correr `sync-shell.sh` antes).
Nunca abre nada en pantalla.
"""
import argparse
import os
import sys
import time

import render as R

TIMES = [1.7, 5.3, 9.1, 13.9]


def one(kind, portrait, out, times):
    tube, scheme = R.MOTIFS.get(kind) or R.TESTEO.get(kind) or R.MOTIFS["mystify"]
    st = R.Stage(kind, tube, scheme, portrait=portrait, glass=False, freeze=True)
    for t in times:
        st.root.setProperty("t", float(t))
        t0 = time.time()
        while time.time() - t0 < 0.7:      # deja que el `Behavior` del nivel (420 ms) termine
            st.app.processEvents()
        img = st.frame(t)
        img.save(os.path.join(out, f"{kind}-{'v' if portrait else 'h'}-{t:05.1f}.png"))


def do_render(a):
    # un proceso por (motivo, orientación): dos ventanas offscreen en el mismo proceso no dan
    # cuadros repetibles (el Stage anterior deja timers vivos)
    import subprocess
    os.makedirs(a.out, exist_ok=True)
    for kind in a.kinds:
        for portrait in (False, True):
            subprocess.run([sys.executable, __file__, "one", kind, "--out", a.out]
                           + (["--portrait"] if portrait else [])
                           + (["--times"] + [str(t) for t in a.times] if a.times else []),
                           check=True, stderr=subprocess.DEVNULL)


def do_cmp(a):
    import numpy as np
    from PyQt6.QtGui import QImage
    worst = 0
    for f in sorted(os.listdir(a.a)):
        pa, pb = os.path.join(a.a, f), os.path.join(a.b, f)
        if not os.path.exists(pb):
            print(f, "falta en B")
            continue
        ims = []
        for p in (pa, pb):
            im = QImage(p).convertToFormat(QImage.Format.Format_RGBA8888)
            ims.append(np.frombuffer(im.constBits().asstring(im.sizeInBytes()), np.uint8)
                       .reshape(im.height(), im.width(), 4)[:, :, :3].astype(int))
        d = np.abs(ims[0] - ims[1])
        worst = max(worst, int(d.max()))
        print(f"{f:28s} max {int(d.max()):3d}   >1: {int((d.max(axis=2) > 1).sum()):7d} px   media {d.mean():.4f}")
    print("PEOR:", worst, "/255")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("kinds", nargs="+")
    r.add_argument("--out", required=True)
    r.add_argument("--times", type=float, nargs="*")
    o = sub.add_parser("one")
    o.add_argument("kind")
    o.add_argument("--out", required=True)
    o.add_argument("--portrait", action="store_true")
    o.add_argument("--times", type=float, nargs="*")
    c = sub.add_parser("cmp")
    c.add_argument("a")
    c.add_argument("b")
    a = ap.parse_args()
    if a.cmd == "one":
        one(a.kind, a.portrait, a.out, a.times or TIMES)
    else:
        do_render(a) if a.cmd == "render" else do_cmp(a)
