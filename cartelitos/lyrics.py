"""Letra: lrclib, cache en disco y el corte de la linea en golpes."""
import hashlib
import json
import os
import random
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from .util import FIELD_SEP, UA, log

CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "cartelitos", "lyrics")
NONE_TTL = 7 * 86400    # cuánto vale un "este tema no tiene letra" cacheado
OK_TTL = 180 * 86400    # una letra encontrada tampoco es para siempre: el cache no crece sin límite

TS_RE = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")
# LRC "enhanced": además de la marca de la línea, cada palabra puede traer la
# suya entre `<>`. Cuando están, el karaoke deja de estimar por largo.
WORD_TS_RE = re.compile(r"<(\d+):(\d+(?:\.\d+)?)>")

# lo que lrclib no matchea: sufijos de edición que van en el título de Spotify
# pero no en el nombre "canónico" con el que está guardada la letra
_CLEAN_TITLE_PATTERNS = [re.compile(p, re.IGNORECASE) for p in (
    r" - Remaster(ed)?( \d{4})?",
    r" - Radio Edit",
    r" - Live.*",
    r"\(feat\. .*?\)",
    r"\(with .*?\)",
    r"\[.*?\]",
    r" - \d{4} Remaster",
)]


def clean_title(s):
    for pat in _CLEAN_TITLE_PATTERNS:
        s = pat.sub("", s)
    return s.strip()

def _stamp(mins, secs):
    return int(mins) * 60 + float(secs)


def _parse_words(body):
    """Palabras con tiempo propio de una línea "enhanced", o None si no tiene.

    Cada marca `<mm:ss.xx>` abre un tramo y TODAS las palabras del tramo se
    quedan con ese tiempo. Así `len(words) == len(texto.split())` por
    construcción, que es la única forma de que el overlay pueda mapear palabra
    ↔ tiempo por índice: si un tramo con dos palabras contara como una, todo
    lo que viene después quedaría corrido."""
    marks = list(WORD_TS_RE.finditer(body))
    if not marks:
        return None
    words = []
    # lo que va ANTES de la primera marca arranca con la línea: el tiempo se
    # completa en parse_lrc, que es quien sabe el de cada marca de línea
    for w in body[:marks[0].start()].split():
        words.append((None, w))
    for k, m in enumerate(marks):
        end = marks[k + 1].start() if k + 1 < len(marks) else len(body)
        t = _stamp(m.group(1), m.group(2))
        # una marca al final sin texto detrás cierra la línea: no es palabra
        for w in body[m.end():end].split():
            words.append((t, w))
    return words or None


def parse_lrc(text):
    """Líneas `(t0, texto, words)`, ordenadas por tiempo.

    `words` es `[(t, palabra), ...]` sólo en el formato "enhanced"; en el LRC
    de siempre queda None y el karaoke estima el reparto por largo. El tercer
    campo va SIEMPRE (aunque valga None) para que nadie tenga que preguntar
    cuántos campos trae la línea."""
    lines = []
    for raw in text.splitlines():
        stamps = TS_RE.findall(raw)
        if not stamps:
            continue
        body = TS_RE.sub("", raw)
        words = _parse_words(body)
        # sin palabras cronometradas, las marcas `<>` que hubiera igual se
        # sacan: una marca suelta no es texto de la letra
        content = (" ".join(w for _, w in words) if words
                   else WORD_TS_RE.sub("", body).strip())
        base = _stamp(*stamps[0])
        for mins, secs in stamps:
            t0 = _stamp(mins, secs)
            # los tiempos por palabra son absolutos y valen para la PRIMERA
            # marca de la línea: un verso marcado en varios momentos repite el
            # mismo patrón corrido, no los mismos segundos
            shifted = None if words is None else [
                (t0 if t is None else round(t + (t0 - base), 3), w) for t, w in words]
            lines.append((t0, content, shifted))
    lines.sort(key=lambda x: x[0])
    return lines or None


def http_json(url, timeout=10, headers=None):
    hdrs = {"User-Agent": UA}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def _json_or(url, **kw):
    """(datos, por_qué_no). El segundo campo distingue "el servidor contestó
    que no lo tiene" (`none`) de "no se llegó" (`error`): el primero se cachea
    y no se reintenta, el segundo se reintenta y no se cachea nunca."""
    try:
        return http_json(url, **kw), "none"
    except urllib.error.HTTPError:
        return None, "none"     # es una respuesta, no una caída
    except Exception:
        return None, "error"


# ------------------------------------------------------------- proveedores
# Cada uno recibe (track, título) y devuelve (estado, líneas) con los mismos
# cuatro estados que fetch_lyrics. Ninguno sabe de los otros ni del orden: la
# cadena la arma PROVIDERS y la recorre fetch_lyrics.

def lrclib_get(track, title):
    """Match exacto de lrclib: artista + tema + álbum + duración."""
    params = urllib.parse.urlencode({
        "artist_name": track["artist"],
        "track_name": title,
        "album_name": track["album"],
        "duration": str(int(round(track["length"]))),
    })
    data, why = _json_or("https://lrclib.net/api/get?" + params)
    if data is None:
        return why, None
    if data.get("syncedLyrics"):
        lines = parse_lrc(data["syncedLyrics"])
        if lines:
            return "ok", lines
    # sin sincronizar, pero lrclib a veces tiene el texto plano: mejor que nada
    if data.get("plainLyrics"):
        return "plain", [(0.0, data["plainLyrics"], None)]
    return "none", None


def lrclib_search(track, title):
    """Búsqueda de lrclib: sin álbum ni duración, el primero que esté sincronizado."""
    params = urllib.parse.urlencode({"track_name": title, "artist_name": track["artist"]})
    data, why = _json_or("https://lrclib.net/api/search?" + params)
    if data is None:
        return why, None
    for hit in data or []:
        if hit.get("syncedLyrics"):
            lines = parse_lrc(hit["syncedLyrics"])
            if lines:
                return "ok", lines
    return "none", None


NETEASE_TIMEOUT = 6
NETEASE_LIMIT = 5
NETEASE_SLACK = 3.0     # segundos de diferencia de duración que se toleran
# con el User-Agent del proyecto contesta distinto: acá hay que parecer un
# navegador, que es el único cliente para el que esta API pública está pensada
NETEASE_HEADERS = {
    "User-Agent": ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"),
    "Referer": "https://music.163.com/",
}

# NetEase mete la ficha técnica adentro del LRC y CON marca de tiempo, así que
# parse_lrc la toma por versos: "作词 : Thom Yorke" (letrista), "作曲" (compositor),
# "制作人" (productor)... y el tema arranca con tres cartelitos de créditos.
NETEASE_CREDIT_RE = re.compile(
    r"^\s*(作词|作曲|编曲|制作人|出品人|出品|监制|混音|录音|母带|统筹|策划|和声|"
    r"吉他|贝斯|鼓|键盘|弦乐|produced|written|composed|arranged|lyrics|lyricist|"
    r"mixed|mastered|recorded)\b\s*(by)?\s*[:：]", re.IGNORECASE)


def netease_pick(songs, length):
    """El id del resultado que dura lo mismo que el tema (±NETEASE_SLACK).

    La búsqueda de NetEase es difusa a lo bruto: con una consulta que no existe
    igual devuelve cinco temas cualesquiera. El largo es lo único que separa el
    match de verdad del relleno."""
    for song in songs or []:
        try:
            dur = float(song["duration"]) / 1000.0
        except (KeyError, TypeError, ValueError):
            continue
        if abs(dur - length) <= NETEASE_SLACK:
            return song.get("id")
    return None


def netease(track, title):
    """NetEase (music.163.com): sin API key y con LRC de verdad.

    Va SIEMPRE `lrc.lyric`, que es el idioma en el que se canta la canción.
    `tlyric` es la traducción al chino y no se usa ni cuando es lo único que
    está sincronizado: la letra tiene que decir lo que se está escuchando."""
    q = urllib.parse.quote(f"{track['artist']} {title}".strip())
    data, why = _json_or(
        f"https://music.163.com/api/search/get?s={q}&type=1&limit={NETEASE_LIMIT}",
        timeout=NETEASE_TIMEOUT, headers=NETEASE_HEADERS)
    if data is None:
        return why, None
    # el HTTP dice 200 y el "de verdad me fue mal" viene adentro del cuerpo:
    # eso no es "este tema no tiene letra", es que no hubo respuesta útil
    if data.get("code") != 200:
        return "error", None
    song_id = netease_pick((data.get("result") or {}).get("songs"), track["length"])
    if song_id is None:
        return "none", None

    data, why = _json_or(
        f"https://music.163.com/api/song/lyric?id={song_id}&lv=1&kv=1&tv=-1",
        timeout=NETEASE_TIMEOUT, headers=NETEASE_HEADERS)
    if data is None:
        return why, None
    if data.get("code") != 200:
        return "error", None
    # instrumental (`pureMusic`) o id que no tiene nada cargado: `lyric` vacío
    lines = parse_lrc((data.get("lrc") or {}).get("lyric") or "")
    if not lines:
        return "none", None
    lines = [ln for ln in lines if not NETEASE_CREDIT_RE.match(ln[1])]
    return ("ok", lines) if lines else ("none", None)


# El orden es el de la confianza, no el de la velocidad: lrclib primero porque
# el match exacto de artista + álbum + duración no se equivoca, y NetEase al
# final porque su búsqueda es difusa y hay que filtrarla por duración.
PROVIDERS = (
    ("lrclib", lrclib_get),
    ("lrclib", lrclib_search),
    ("netease", netease),
)


def fetch_lyrics(track):
    """Letra sincronizada, probando la cadena de proveedores con el título
    original y después con el limpio.

    Devuelve (estado, líneas, proveedor) con CUATRO estados: "ok"
    (sincronizada), "plain" (sólo el texto sin marcas de tiempo), "none"
    (contestaron todos y este tema no tiene letra) y "error" (alguno no
    contestó). Mezclar "none" con "error" rompe el cache y el reintento, que
    necesitan lo contrario uno del otro: el "no hay" se cachea y no se
    reintenta, la caída de red se reintenta y no se cachea nunca. Por eso
    alcanza con que UNO no llegue para que el resultado sea "error": si no,
    un proveedor caído deja el tema marcado como instrumental por una semana.

    El primer "ok" gana. "plain" es sólo el resguardo: aunque llegue primero,
    se sigue buscando la sincronizada."""
    titles = [track["title"]]
    # "Song - Remastered 2011" no matchea en ningún lado pero "Song" sí; sólo
    # vale la pena repetir la vuelta si el título limpio es de verdad otro
    clean = clean_title(track["title"])
    if clean and clean != track["title"]:
        titles.append(clean)

    plain = None
    unreachable = False
    for title in titles:
        for name, provider in PROVIDERS:
            try:
                status, lines = provider(track, title)
            except Exception as e:
                # un proveedor que revienta no puede llevarse puestos a los
                # otros: cuenta como no haber llegado y la cadena sigue
                log(f"lyrics provider {name} blew up ({e})")
                status, lines = "error", None
            if status == "ok":
                return "ok", lines, name
            if status == "plain" and plain is None:
                plain = (lines, name)
            elif status == "error":
                unreachable = True

    if plain:
        return "plain", plain[0], plain[1]
    return ("error", None, None) if unreachable else ("none", None, None)


def _cache_path(track):
    key = FIELD_SEP.join([track["artist"], track["title"], track["album"],
                          str(int(round(track["length"])))])
    return os.path.join(CACHE_DIR, hashlib.sha1(key.encode()).hexdigest() + ".json")


def cache_get(track):
    """(estado, líneas, proveedor) guardado, o None si no hay / caducó.

    El status se guarda explícito desde T0.14: "ok" y "plain" son ambos
    `lines` con contenido, y sin el campo no se podrían distinguir al leer
    de vuelta. Un cache viejo (de antes de T0.14) no tiene "status": se
    infiere de si trae líneas, igual que se comportaba antes."""
    try:
        with open(_cache_path(track)) as f:
            data = json.load(f)
    except Exception:
        return None
    status = data.get("status") or ("ok" if data.get("lines") else "none")
    # un cache escrito antes de T1.2 no tiene proveedor: lrclib era el único
    provider = data.get("provider") or ("lrclib" if data.get("lines") else None)
    if status == "none":
        # el "no hay letra" caduca: lrclib suma letras con el tiempo y un tema
        # instrumental hoy puede tenerla el mes que viene
        if time.time() - data.get("at", 0) > NONE_TTL:
            return None
        return "none", None, provider
    return status, [_cached_line(row) for row in data["lines"]], provider


def _cached_line(row):
    """Una línea del JSON a la forma `(t0, texto, words)`.

    Un cache escrito antes de T1.1 tiene dos campos por línea: se completa con
    None en vez de tirarlo, que si no la primera vez que suena cada tema viejo
    vuelve a pegarle a lrclib para nada."""
    words = row[2] if len(row) > 2 else None
    return (row[0], row[1], [(t, w) for t, w in words] if words else None)


def cache_put(track, status, lines, provider):
    """Guarda "ok", "plain" y "none". Una caída de red NO se guarda: si no,
    cada tema que sonó sin internet queda marcado como sin letra."""
    if status == "error":
        return
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        path = _cache_path(track)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"lines": lines, "status": status, "provider": provider,
                       "at": int(time.time())}, f)
        os.replace(tmp, path)   # atómico: nadie lee un archivo a medio escribir
    except Exception as e:
        log(f"couldn't cache the lyrics ({e})")


def purge_cache(now):
    """Borra del cache lo que ya no vale la pena guardar: un "no hay letra"
    más viejo que NONE_TTL, o una letra encontrada de hace más de OK_TTL —
    ninguna de las dos vive para siempre, o el cache crece sin límite."""
    try:
        names = os.listdir(CACHE_DIR)
    except OSError:
        return
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(CACHE_DIR, name)
        try:
            with open(path) as f:
                data = json.load(f)
        except (OSError, ValueError):
            continue
        age = now - data.get("at", 0)
        ttl = NONE_TTL if not data.get("lines") else OK_TTL
        if age > ttl:
            try:
                os.remove(path)
            except OSError:
                pass


# resultado de la búsqueda en curso. `gen` sube en cada cambio de tema: el hilo
# sólo publica si sigue siendo el suyo, y lo chequea con el lock tomado — sin eso,
# un hilo que pasó el chequeo justo antes del cambio pisa el tema nuevo.
_fetch_lock = threading.Lock()
_fetch = {"gen": 0, "id": None, "lyrics": None, "status": None,
          "provider": None, "done": False}
RETRY_DELAY = 10
RETRY_JITTER = 0.2      # ±20%: dos temas que fallan juntos no vuelven al mismo segundo
RETRIES = 2

# Techo de hilos vivos. `gen` invalida el resultado viejo, pero no mata al hilo:
# un hilo colgado en un request sigue vivo hasta el timeout, y saltando temas
# rápido se apilaban tantos como cambios de tema. Con el techo puesto, el tema
# que no encuentra lugar espera en `_pending` — y como sólo importa el último,
# el que llega pisa al que estaba esperando.
MAX_INFLIGHT = 2
_inflight = 0           # hilos vivos, protegido por _fetch_lock
_pending = None         # (track, gen) esperando lugar, protegido por _fetch_lock


def _retry_delay():
    """RETRY_DELAY con un ruido de ±20%.

    Sin el ruido, todos los reintentos caen en el mismo instante: si lrclib se
    cae con varios temas en cola, vuelven todos juntos y en sincronía, que es
    justo la forma de martillarlo mientras se está levantando."""
    return RETRY_DELAY * (1 + random.uniform(-RETRY_JITTER, RETRY_JITTER))


def _mine(gen):
    return _fetch["gen"] == gen


def _publish(gen, status, lines, provider):
    with _fetch_lock:
        if not _mine(gen):
            return False
        _fetch.update(lyrics=lines, status=status, provider=provider, done=True)
    return True


def _work(track, gen):
    hit = cache_get(track)
    if hit:
        status, lines, provider = hit
        if _publish(gen, status, lines, provider):
            log(f"cached lyrics: {len(lines)} lines ({provider})" if lines
                else "no synced lyrics (cached)")
        return
    for attempt in range(RETRIES + 1):
        t0 = time.monotonic()
        status, lines, provider = fetch_lyrics(track)
        ms = (time.monotonic() - t0) * 1000
        log(f"lyrics {status} in {ms:.0f} ms ({provider or 'no provider'})")
        if status != "error":
            break
        if attempt == RETRIES:
            log("no lyrics provider answered, giving up on this track")
            return
        # red caída: esperar y reintentar, salvo que ya haya cambiado de tema
        delay = _retry_delay()
        log(f"no lyrics provider answered, retrying in {delay:.0f}s")
        for _ in range(int(delay * 2)):
            time.sleep(0.5)
            if not _mine(gen):
                return
    cache_put(track, status, lines, provider)
    if _publish(gen, status, lines, provider):
        log(f"synced lyrics: {len(lines)} lines ({provider})" if status == "ok"
            else f"plain lyrics: {len(lines)} lines ({provider})" if status == "plain"
            else "no synced lyrics (no dialogs)")


def _worker(track, gen):
    """Atiende un tema y, si quedó otro esperando, sigue con ése sin morirse:
    el hilo es el lugar, no el trabajo."""
    global _inflight, _pending
    while True:
        try:
            if _mine(gen):   # el que esperaba puede haber quedado viejo
                _work(track, gen)
        except Exception as e:
            log(f"lyrics thread died ({e})")
        with _fetch_lock:
            # bajar el contador y decidir la salida van juntos bajo el lock: si
            # no, alguien ve el cupo lleno y deja un `_pending` que no levanta nadie
            if _pending is None:
                _inflight -= 1
                return
            track, gen = _pending
            _pending = None


def fetch_lyrics_async(track):
    """Busca la letra en un hilo. Son dos requests con timeout de 10s cada uno:
    hechos en el loop principal, un lrclib lento o caído congelaba todo —
    detección de juego, eventos de progreso y limpieza incluidos."""
    global _inflight, _pending
    with _fetch_lock:
        _fetch["gen"] += 1
        gen = _fetch["gen"]
        _fetch.update(id=track["id"], lyrics=None, status=None, provider=None, done=False)
        if _inflight >= MAX_INFLIGHT:
            _pending = (track, gen)
            return
        _inflight += 1

    try:
        threading.Thread(target=_worker, args=(track, gen), daemon=True, name="lyrics").start()
    except RuntimeError as e:
        # sin lugar para un hilo más: devolver el cupo, o queda tomado para
        # siempre y la letra no vuelve nunca
        with _fetch_lock:
            _inflight -= 1
        log(f"couldn't start the lyrics thread ({e})")

def current_line_index(lyrics, pos):
    idx = -1
    for i, line in enumerate(lyrics):
        if line[0] <= pos:
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
