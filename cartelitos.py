#!/usr/bin/env python3
"""Arranque de fatal-lyrics. El código está en el paquete `cartelitos/`.

Este archivo queda porque es lo que ejecuta bin/fatal (`python3 cartelitos.py`)
y lo que quedó instalado en /usr/share/fatal-lyrics: se limita a poner el
directorio del repo en el path y a delegar en el paquete.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cartelitos.__main__ import run  # noqa: E402

if __name__ == "__main__":
    run()
