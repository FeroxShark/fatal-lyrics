#!/usr/bin/env python3
"""Costo por cuadro de cada motivo en el banco offscreen (GPU real, nada en pantalla).

    ./bench.py                 # todos, con vidrio
    ./bench.py mystify --flat  # uno, sin vidrio
Mide, por motivo, sobre N cuadros de un loop: ms de pared por cuadro (incluye
grabWindow, que sincroniza con la GPU) y ms de CPU del proceso (process_time).
El costo del vidrio y del readback es el mismo para todos: la diferencia entre
motivos es lo que importa.
"""
import argparse
import sys
import time

import render as R


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kinds", nargs="*")
    ap.add_argument("--flat", action="store_true")
    ap.add_argument("--n", type=int, default=240)
    ap.add_argument("--rounds", type=int, default=1, help="rondas intercaladas")
    ap.add_argument("--portrait", action="store_true")
    a = ap.parse_args()
    kinds = a.kinds or list(R.MOTIFS)
    # `<kind>old` carga motifs/<Kind>old.qml: la versión vieja, para el A/B intercalado
    for k in kinds * a.rounds:
        tube, scheme = R.MOTIFS.get(k.replace('old', ''), R.MOTIFS['mystify'])
        st = R.Stage(k, tube, scheme, portrait=a.portrait, glass=not a.flat)
        for f in range(60):
            st.frame(f / R.FPS)
        w0, c0 = time.perf_counter(), time.process_time()
        for f in range(a.n):
            st.frame((60 + f * 3) / R.FPS)   # saltos de 3 cuadros: recorre el loop
        w1, c1 = time.perf_counter(), time.process_time()
        # sólo el lado QML (bindings + JS + sync a la cola de eventos, sin dibujar ni grab)
        q0 = time.process_time()
        for f in range(a.n):
            st.root.setProperty("t", (60 + f * 3) / R.FPS)
            st.app.processEvents()
        qml = 1000 * (time.process_time() - q0) / a.n
        # cada st.frame() hace 2 vueltas de eventos+grab
        print(f"{k:13s} pared {1000*(w1-w0)/a.n:6.1f} ms/cuadro   cpu {1000*(c1-c0)/a.n:6.1f} ms/cuadro   qml {qml:6.2f} ms/cuadro",
              flush=True)
        st.view.close()
        del st


if __name__ == "__main__":
    main()
