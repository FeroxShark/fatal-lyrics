#!/usr/bin/env python3
"""Mapa del moiré: el campo parejo pasado por el vidrio, con la textura fina
(máscara, scanlines) sacada por un pasabajos de 8 px y el resto estirado de
contraste. Lo que queda dibujado es lo que el ojo ve como figura.

    ./moire_map.py out/antes/glass-custom-1920x1080.png [salida.png]
"""
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from render import smooth  # noqa: E402

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else src.replace(".png", "-moire.png")
y = np.asarray(Image.open(src).convert("L"), np.float64)
band = smooth(y, 2) - smooth(y, 40)
m = y.mean()
v = np.clip(128 + band / m * 128 / 0.03, 0, 255)   # ±3 % del nivel medio = negro..blanco
Image.fromarray(v.astype(np.uint8)).save(dst)
print(dst)
