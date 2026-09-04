"""Corrección de sync por artista (T0.13): ~/.config/cartelitos/offsets.toml.

Separado de config.py porque lo escribe el propio daemon (un gesto del
usuario, "fatal sync +/-" o el menú de bandeja), no Ferox editando el TOML a
mano.

La regla de guardado (tanda 3, C) es POR TEMA, no por golpe: el offset se
persiste para el artista recién cuando Ferox lo corrigió en el mismo sentido
en DOS TEMAS DISTINTOS suyos. Un tema mal masterizado, o una letra de lrclib
que arranca corrida, no puede desfasar al artista entero — hasta que un
segundo tema diga lo mismo, la corrección vale sólo para ese tema (el
"TrackProfile": `_pending`, que vive en memoria y se pierde al reiniciar,
justamente porque es lo que todavía no se ganó el derecho a durar).

Lo que se guarda es el PROMEDIO de los temas que votaron, no la suma: dos
temas que necesitan +0.3 dicen que el artista necesita +0.3, no +0.6. Y los
temas que votaron se rebasan contra lo guardado (`neto -= promedio`), así el
tema que está sonando no pega un salto justo en el golpe que persistió."""
import os
import tomllib

from .util import log

OFFSETS_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "cartelitos")
OFFSETS_PATH = os.path.join(OFFSETS_DIR, "offsets.toml")

# Lo corregido y todavía NO persistido, por artista: {artista: {track_id: neto}}.
# Es a la vez el perfil por tema (lo que se le suma al artista mientras suena
# ESE tema) y la urna de la votación (dos temas con el neto del mismo signo).
_pending = {}

# un neto por debajo de esto es "este tema no dice nada": no vota, y no arrastra
# el signo de un tema que quedó en cero después de rebasarlo
_EPS = 1e-6


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


def all_offsets():
    """Lo guardado, ordenado por artista. Lo usa `fatal sync show`."""
    out = {}
    for name, value in _read().items():
        try:
            out[name] = float(value)
        except (TypeError, ValueError):
            continue
    return dict(sorted(out.items()))


def track_get(artist, track_id):
    """Lo que este TEMA corrigió y todavía no se guardó para el artista.

    Va aparte de `get()` porque son dos cosas distintas: `get` es lo que el
    artista se ganó (sobrevive al reinicio), esto es lo que este tema pidió y
    todavía nadie confirmó."""
    if not artist or not track_id:
        return 0.0
    return _pending.get(artist, {}).get(track_id, 0.0)


def effective(artist, track_id):
    """El offset que hay que aplicarle a este tema: lo del artista más lo suyo."""
    return round(get(artist) + track_get(artist, track_id), 3)


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


def record(artist, delta, track_id):
    """Anota una corrección de `delta` segundos sobre `track_id` de `artist`.

    Devuelve el offset EFECTIVO de ese tema (lo persistido del artista más lo
    que este tema lleva pedido), que es lo que el daemon tiene que aplicar: así
    el salto de la persistencia y el rebase se cancelan solos y nadie afuera
    tiene que llevar la cuenta."""
    if not artist or not track_id:
        return 0.0
    tracks = _pending.setdefault(artist, {})
    tracks[track_id] = round(tracks.get(track_id, 0.0) + delta, 3)
    # ¿hay dos temas DISTINTOS pidiendo lo mismo? El signo de cada tema sale de
    # su neto, no de cada golpe: tocar +,+,- en un tema es un tema que pide +0.1
    sign = 1 if tracks[track_id] > 0 else (-1 if tracks[track_id] < 0 else 0)
    if sign:
        voters = [t for t, v in tracks.items()
                  if abs(v) > _EPS and (1 if v > 0 else -1) == sign]
        if len(voters) >= 2:
            learned = round(sum(tracks[t] for t in voters) / len(voters), 3)
            artists = _read()
            artists[artist] = round(float(artists.get(artist, 0.0)) + learned, 3)
            _write(artists)
            log(f"offsets: {artist} learned {learned:+.2f}s "
                f"from {len(voters)} tracks (now {artists[artist]:+.2f}s)")
            # rebase: lo que se guardó ya no lo pide el tema. Sin esto el tema
            # que suena se corre otro `learned` en el mismo golpe que persistió.
            for t in voters:
                tracks[t] = round(tracks[t] - learned, 3)
    return effective(artist, track_id)


def reset(artist):
    """Olvida lo aprendido de un artista: lo guardado y lo que iba juntando.

    Devuelve True si había algo que olvidar."""
    had = _pending.pop(artist, None) is not None
    artists = _read()
    if artist in artists:
        del artists[artist]
        _write(artists)
        had = True
    return had


def reset_all():
    """Olvida todo. Devuelve cuántos artistas había guardados."""
    n = len(_read())
    _pending.clear()
    _write({})
    return n


# ------------------------------------------------- `fatal sync show|reset`
# Corren en un proceso corto (`python3 cartelitos.py --sync-show`), NO adentro
# del daemon: el daemon vivo no es alcanzable desde afuera salvo por archivo, y
# acá el archivo ES el estado. Por eso tampoco hace falta que el daemon esté
# corriendo para mirar o borrar lo aprendido.
def show_lines():
    """Lo guardado, listo para imprimir. Lo que está en `_pending` NO sale:
    es de este proceso, y este proceso no es el daemon."""
    saved = all_offsets()
    if not saved:
        return [f"no artist offsets learned yet ({OFFSETS_PATH})",
                "they appear on their own: nudge the same way on two different "
                "tracks by the same artist (fatal sync + | -)"]
    width = max(len(name) for name in saved)
    lines = [f"learned artist offsets  ({OFFSETS_PATH})", ""]
    lines += [f"  {name.ljust(width)}   {value:+.2f} s" for name, value in saved.items()]
    return lines
