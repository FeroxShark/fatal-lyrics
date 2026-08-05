"""Colores de la portada (ImageMagick, opcional)."""
import os
import shutil
import subprocess
import tempfile
import threading
import urllib.parse
import urllib.request

from . import ipc
from .util import UA, log

# ---------------------------------------------------------------- portada
# Los colores del tubo salen de la tapa del disco: así cada tema trae los suyos
# y no hay que elegir a mano una paleta que combine. Se saca con ImageMagick, que
# es opcional — sin él, el modo usa las paletas de fábrica.
_art_cache = {}


def parse_histogram(text, keep=4):
    """Colores dominantes de la salida `histogram:` de ImageMagick.

    Ordena por presencia PESADA POR SATURACIÓN: la tapa más común del mundo es
    mayormente gris o negra, y si se ordena por cantidad pelada el tubo termina
    pintado del color de una sombra."""
    out = []
    for line in text.splitlines():
        line = line.strip()
        if ":" not in line or "#" not in line:
            continue
        try:
            count = int(line.split(":", 1)[0])
            hexa = line.split("#", 1)[1].split()[0][:6]
            r, g, b = (int(hexa[i:i + 2], 16) for i in (0, 2, 4))
        except (ValueError, IndexError):
            continue
        hi, lo = max(r, g, b), min(r, g, b)
        sat = (hi - lo) / hi if hi else 0.0
        light = hi / 255.0
        # ni el negro ni el blanco puro sirven de color de pantalla
        weight = count * (0.15 + sat) * (0.25 + min(light, 0.85))
        out.append((weight, sat, "#" + hexa.lower()))
    out.sort(reverse=True)
    # los que tienen tono de verdad primero; los grises quedan al final, sólo por
    # si la tapa entera es gris y no hay nada mejor
    tinted = [c for _, sat, c in out if sat >= 0.15]
    greys = [c for _, sat, c in out if sat < 0.15]
    return (tinted + greys)[:keep]


def album_colors(url):
    """Hasta cuatro colores de la portada. None si no se puede (sin red, sin
    ImageMagick, sin portada): el tubo sigue andando con sus paletas."""
    if not url:
        return None
    if url in _art_cache:
        return _art_cache[url]
    tool = shutil.which("magick") or shutil.which("convert")
    if not tool:
        return None
    path = None
    try:
        if url.startswith("file://"):
            path = urllib.parse.unquote(url[7:])
            tmp = None
        else:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=8) as resp:
                data = resp.read(4_000_000)
            tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False)
            tmp.write(data)
            tmp.close()
            path = tmp.name
        out = subprocess.run(
            [tool, path, "-resize", "64x64!", "-colors", "6", "-format", "%c",
             "histogram:info:"], capture_output=True, text=True, timeout=10)
        colors = parse_histogram(out.stdout) if out.returncode == 0 else None
    except Exception as e:
        log(f"couldn't read the cover's colours ({e})")
        colors = None
    finally:
        if tmp is not None and path:
            try:
                os.unlink(path)
            except OSError:
                pass
    _art_cache[url] = colors
    return colors


def send_album_colors(url):
    """Los saca en un hilo: descarga + ImageMagick no pueden trabar la letra."""
    def work():
        colors = album_colors(url)
        if colors:
            ipc.send({"cmd": "art", "colors": colors})
    threading.Thread(target=work, daemon=True, name="art").start()
