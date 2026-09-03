"""Corrección de sync por artista (T0.13): ~/.config/cartelitos/offsets.toml.

Separado de config.py porque lo escribe el propio daemon (un gesto del
usuario, "fatal sync +/-" o el menú de bandeja), no Ferox editando el TOML a
mano. Una sola corrección no alcanza — el dedo se resbala, o el offset
global ya andaba bien y esto es ruido — así que sólo se persiste cuando el
mismo artista se corrige DOS veces seguidas en el mismo sentido."""
import os
import tomllib

from .util import log

OFFSETS_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "cartelitos")
OFFSETS_PATH = os.path.join(OFFSETS_DIR, "offsets.toml")

# streak de correcciones en curso por artista, sólo en memoria: (signo, suma
# acumulada, cantidad de correcciones seguidas en ese signo). Un cambio de
# signo reinicia la cuenta.
_pending = {}


def _read():
    try:
        with open(OFFSETS_PATH, "rb") as f:
            data = tomllib.load(f)
    except (OSError, ValueError):
        return {}
    artists = data.get("artists")
    return artists if isinstance(artists, dict) else {}


def get(artist):
    """Offset persistido para este artista, o 0.0 si nunca se corrigió."""
    try:
        return float(_read().get(artist, 0.0))
    except (TypeError, ValueError):
        return 0.0


def _toml_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _write(artists):
    lines = ["[artists]"]
    for name, value in artists.items():
        lines.append(f"{_toml_str(name)} = {value}")
    try:
        os.makedirs(OFFSETS_DIR, exist_ok=True)
        tmp = OFFSETS_PATH + ".tmp"
        with open(tmp, "w") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(tmp, OFFSETS_PATH)   # atómico, como el resto de los TOML acá
    except OSError as e:
        log(f"couldn't save the artist offset ({e})")


def record(artist, delta):
    """Anota una corrección de `delta` segundos para `artist`.

    Devuelve el offset persistido para ese artista (sin cambios si esta
    corrección todavía no alcanzó el umbral). Dos correcciones seguidas en
    el mismo sentido se suman y se guardan juntas; un cambio de sentido
    reinicia la cuenta sin guardar nada."""
    if not artist:
        return 0.0
    sign = 1 if delta >= 0 else -1
    psign, psum, pcount = _pending.get(artist, (0, 0.0, 0))
    if sign == psign:
        psum += delta
        pcount += 1
    else:
        psign, psum, pcount = sign, delta, 1
    if pcount >= 2:
        artists = _read()
        new_val = round(float(artists.get(artist, 0.0)) + psum, 3)
        artists[artist] = new_val
        _write(artists)
        _pending.pop(artist, None)
        return new_val
    _pending[artist] = (psign, psum, pcount)
    return get(artist)
