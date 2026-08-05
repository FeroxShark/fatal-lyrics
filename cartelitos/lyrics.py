"""Letra: lrclib, cache en disco y el corte de la linea en golpes."""
import hashlib
import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from .util import FIELD_SEP, UA, log

CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "cartelitos", "lyrics")
NONE_TTL = 7 * 86400   # cuánto vale un "este tema no tiene letra" cacheado

TS_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")

def parse_lrc(text):
    lines = []
    for raw in text.splitlines():
        stamps = TS_RE.findall(raw)
        if not stamps:
            continue
        content = TS_RE.sub("", raw).strip()
        for mins, secs in stamps:
            lines.append((int(mins) * 60 + float(secs), content))
    lines.sort(key=lambda x: x[0])
    return lines or None


def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.load(resp)


def fetch_lyrics(track):
    """Letra sincronizada de lrclib: match exacto y si no, búsqueda.

    Devuelve (estado, líneas) con TRES resultados, no dos: "ok", "none" (lrclib
    contestó y este tema no tiene letra sincronizada) y "error" (no se pudo
    llegar a lrclib). Mezclarlos rompe el cache y el reintento, que necesitan
    lo contrario uno del otro: el "no hay" se cachea y no se reintenta, la
    caída de red se reintenta y no se cachea nunca."""
    reached = False

    def try_url(url):
        nonlocal reached
        try:
            data = http_json(url)
        except urllib.error.HTTPError:
            reached = True      # contestó "no lo tengo": es una respuesta, no una caída
            return None
        except Exception:
            return None
        reached = True
        return data

    params = urllib.parse.urlencode({
        "artist_name": track["artist"],
        "track_name": track["title"],
        "album_name": track["album"],
        "duration": str(int(round(track["length"]))),
    })
    data = try_url("https://lrclib.net/api/get?" + params)
    if data and data.get("syncedLyrics"):
        lines = parse_lrc(data["syncedLyrics"])
        if lines:
            return "ok", lines

    params = urllib.parse.urlencode({
        "track_name": track["title"],
        "artist_name": track["artist"],
    })
    for data in try_url("https://lrclib.net/api/search?" + params) or []:
        if data.get("syncedLyrics"):
            lines = parse_lrc(data["syncedLyrics"])
            if lines:
                return "ok", lines

    return ("none", None) if reached else ("error", None)


def _cache_path(track):
    key = FIELD_SEP.join([track["artist"], track["title"], track["album"],
                          str(int(round(track["length"])))])
    return os.path.join(CACHE_DIR, hashlib.sha1(key.encode()).hexdigest() + ".json")


def cache_get(track):
    """Resultado guardado, o None si no hay / caducó."""
    try:
        with open(_cache_path(track)) as f:
            data = json.load(f)
    except Exception:
        return None
    if not data.get("lines"):
        # el "no hay letra" caduca: lrclib suma letras con el tiempo y un tema
        # instrumental hoy puede tenerla el mes que viene
        if time.time() - data.get("at", 0) > NONE_TTL:
            return None
        return "none", None
    return "ok", [(ts, text) for ts, text in data["lines"]]


def cache_put(track, status, lines):
    """Guarda "ok" y "none". Una caída de red NO se guarda: si no, cada tema que
    sonó sin internet queda marcado como sin letra."""
    if status == "error":
        return
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        path = _cache_path(track)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"lines": lines, "at": int(time.time())}, f)
        os.replace(tmp, path)   # atómico: nadie lee un archivo a medio escribir
    except Exception as e:
        log(f"couldn't cache the lyrics ({e})")


# resultado de la búsqueda en curso. `gen` sube en cada cambio de tema: el hilo
# sólo publica si sigue siendo el suyo, y lo chequea con el lock tomado — sin eso,
# un hilo que pasó el chequeo justo antes del cambio pisa el tema nuevo.
_fetch_lock = threading.Lock()
_fetch = {"gen": 0, "id": None, "lyrics": None, "done": False}
RETRY_DELAY = 10
RETRIES = 2


def fetch_lyrics_async(track):
    """Busca la letra en un hilo. Son dos requests con timeout de 10s cada uno:
    hechos en el loop principal, un lrclib lento o caído congelaba todo —
    detección de juego, eventos de progreso y limpieza incluidos."""
    with _fetch_lock:
        _fetch["gen"] += 1
        gen = _fetch["gen"]
        _fetch.update(id=track["id"], lyrics=None, done=False)

    def mine():
        return _fetch["gen"] == gen

    def publish(lines):
        with _fetch_lock:
            if not mine():
                return False
            _fetch.update(lyrics=lines, done=True)
        return True

    def work():
        hit = cache_get(track)
        if hit:
            if publish(hit[1]):
                log(f"cached lyrics: {len(hit[1])} lines" if hit[1]
                    else "no synced lyrics (cached)")
            return
        for attempt in range(RETRIES + 1):
            status, lines = fetch_lyrics(track)
            if status != "error":
                break
            if attempt == RETRIES:
                log("lrclib unreachable, giving up on this track")
                return
            # red caída: esperar y reintentar, salvo que ya haya cambiado de tema
            log(f"lrclib unreachable, retrying in {RETRY_DELAY}s")
            for _ in range(RETRY_DELAY * 2):
                time.sleep(0.5)
                if not mine():
                    return
        cache_put(track, status, lines)
        if publish(lines):
            log(f"synced lyrics: {len(lines)} lines" if lines
                else "no synced lyrics (no dialogs)")

    threading.Thread(target=work, daemon=True, name="lyrics").start()

def current_line_index(lyrics, pos):
    idx = -1
    for i, (ts, _) in enumerate(lyrics):
        if ts <= pos:
            idx = i
        else:
            break
    return idx

# ------------------------------------------------------- cortes de la línea
# Una línea de letra no siempre es una frase: muchas veces son golpes repetidos
# ("take-take-take me to the beach", "down, down, down, down", "take me, take me,
# take me"). Cada golpe se merece su propia pantalla, así que la línea se corta
# acá — en el daemon, donde se puede probar de verdad — y viaja ya cortada.
SEG_PUNCT = re.compile(r"[\s.,;:!¡?¿\"'“”‘’()\[\]{}…·•\-–—*~`+/|\\]+")
SEG_SPLIT = re.compile(r"\s*[/|]\s*")
SEG_MAX = 6                 # más pedazos que esto y cada uno dura un suspiro
SEG_MAX_SHORT = 9           # salvo que sean cortitos: deletrear pide más lugar


def seg_key(word):
    """Palabra normalizada para comparar: sin puntuación y sin mayúsculas.

    NO se filtra por alfabeto: sacando todo lo que no fuera a–z, una letra en
    japonés o en cirílico quedaba en blanco y dos palabras distintas parecían la
    misma repetición."""
    return SEG_PUNCT.sub("", word.lower())


def expand_repeats(word):
    """Abre las repeticiones pegadas con guiones: "Take-take-take" son tres.

    Sólo si los pedazos se repiten de verdad — "T-A-K-E" es una palabra
    deletreada y "people-pleasing" es una compuesta, y ésas no se tocan."""
    if "-" not in word:
        return [word]
    parts = [p for p in word.split("-") if p]
    if len(parts) < 2:
        return [word]
    keys = [seg_key(p) for p in parts]
    # antes se exigía que el pedazo tuviera más de una letra, para no romper
    # "T-A-K-E"; de eso ahora se ocupa expand_spelled, así que "D-D-D-DJ" también
    # se abre
    repeated = any(keys[i] and keys[i] == keys[i - 1] for i in range(1, len(keys)))
    return parts if repeated else [word]


SPELL_SEP = re.compile(r"[-.·•]")


def expand_spelled(word):
    """Abre una palabra DELETREADA: "T-A-K-E" se canta letra por letra, o sea son
    cuatro golpes, no una palabra.

    Se pide que TODOS los pedazos sean de un solo carácter y que haya al menos
    tres: así entran "R-E-S-P-E-C-T" y "9-1-1", y quedan afuera "e-mail",
    "T-shirt", "K-pop" o "U-turn", que tienen una letra suelta pero no se
    deletrean."""
    parts = [p for p in SPELL_SEP.split(word) if p]
    if len(parts) < 3:
        return [word]
    if not all(len(seg_key(p)) == 1 for p in parts):
        return [word]
    return parts


def spelled_run(keys, i):
    """Largo de la tirada de letras sueltas que arranca en i ("T A K E" separado
    por espacios es lo mismo que deletreado con guiones)."""
    n = 0
    while i + n < len(keys) and len(keys[i + n]) == 1:
        n += 1
    return n


def split_repeats(text):
    """Corta una línea en golpes. Devuelve la lista de pedazos, en orden.

    Busca grupos de hasta tres palabras que se repitan pegados: cubre desde
    "na na na" hasta "take me, take me, take me". Si no hay repeticiones queda
    un solo pedazo y la línea sigue entera."""
    out = []
    for part in SEG_SPLIT.split(text):
        words = []
        for raw in part.split():
            for piece in expand_repeats(raw):
                words.extend(expand_spelled(piece))
        keys = [seg_key(w) for w in words]
        cur = []
        i = 0
        while i < len(words):
            # una palabra deletreada: cada letra es un golpe propio
            run = spelled_run(keys, i)
            if run >= 3:
                if cur:
                    out.append(" ".join(cur))
                    cur = []
                for k in range(run):
                    out.append(words[i + k])
                i += run
                continue

            group = 0
            # De MENOR a mayor: "take take take take" son cuatro golpes, no dos
            # pares. El grupo grande sólo gana cuando el chico no repite, que es
            # justo el caso de "take me, take me".
            for n in range(1, min(3, (len(words) - i) // 2) + 1):
                if keys[i:i + n] == keys[i + n:i + 2 * n] and any(keys[i:i + n]):
                    group = n
                    break
            if group == 0:
                cur.append(words[i])
                i += 1
                continue
            if cur:
                out.append(" ".join(cur))
                cur = []
            base = keys[i:i + group]
            while i + group <= len(words) and keys[i:i + group] == base:
                out.append(" ".join(words[i:i + group]))
                i += group
        if cur:
            out.append(" ".join(cur))
    out = [sg for sg in (s.strip() for s in out) if sg]
    # demasiados pedazos no se leen: los últimos se juntan. Una palabra
    # deletreada entra con más, porque cada golpe es una letra sola.
    cap = SEG_MAX_SHORT if all(len(sg) <= 2 for sg in out) else SEG_MAX
    if len(out) > cap:
        out = out[:cap - 1] + [" ".join(out[cap - 1:])]
    return out
