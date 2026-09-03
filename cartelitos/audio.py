"""DSP del audio del sistema y el perfil de energia del tema."""
import hashlib
import json
import math
import os
import shutil
import subprocess
import threading
import time
import traceback

from . import config
from . import ipc
from .util import FIELD_SEP, log

# --------------------------------------------------------- perfil del tema
# El tubo no reacciona sólo al instante: mide la canción entera y ubica cada
# momento DENTRO de ella. "Fuerte" no es un número de volumen, es estar arriba
# de lo que viene siendo este tema — un lofi entero no puede ser todo "bajo" ni
# un tema de metal todo "drop".
#
# El perfil se guarda: la segunda vez que suena el tema, el modo ya sabe dónde
# están los silencios y los golpes ANTES de que pasen, y puede prepararse.
PROFILE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                           "cartelitos", "audio")
PROFILE_STEP = 0.5          # un punto cada medio segundo
SECTION_HOLD = 4.0          # segundos antes de aceptar que cambió de parte
SECTION_SMOOTH = 0.12       # cuánto pesa cada muestra en la curva suavizada
SECTIONS = ("quiet", "verse", "build", "drop")

# Al re-escuchar un tema la muestra se promedia con la que ya había: si el tema
# se escuchó otras veces, el mapa se afina en vez de pisarse. Lo viejo pesa más
# que lo nuevo, así una pasada rara (un volumen distinto) no borra el mapa.
PROFILE_BLEND_OLD = 0.6
PROFILE_BLEND_NEW = 0.4

PROFILE_MIN_SAMPLES = 20    # menos que esto es medio tema: no sirve de mapa

# Cuánto adelante mira el mapa. Sin esto la reacción siempre llega tarde: el
# golpe se ve DESPUÉS de que sonó; con el mapa cargado el tubo empieza a apretar
# antes. Es también el aviso que se le manda a la pantalla ("esto entra en N").
CUE_AHEAD = 2.0
CUE_MIN_GAP = 2.0           # no más de un aviso cada tanto: si no, es un chorro


def classify_level(rms, samples):
    """En qué parte de SU PROPIA canción está este momento.

    Devuelve (parte, percentil 0..1). Con menos de un puñado de muestras todavía
    no hay canción con qué comparar, así que se contesta "verse" y se espera."""
    # los ceros son tramos que todavía no se escucharon, no silencio del tema:
    # contarlos como parte de la canción hace que TODO parezca fuerte
    heard = [v for v in samples if v > 0.0]
    if len(heard) < 8:
        return "verse", 0.5
    ordered = sorted(heard)
    below = equal = 0
    for v in ordered:
        if v < rms:
            below += 1
        elif v == rms:
            equal += 1
        else:
            break
    # los empates cuentan a la mitad: si no, un tema parejo (un lofi, un drone)
    # da percentil 1.0 en todo momento y queda marcado como un drop eterno
    pct = (below + equal / 2) / len(ordered)
    if pct < 0.25:
        return "quiet", pct
    if pct < 0.62:
        return "verse", pct
    if pct < 0.86:
        return "build", pct
    return "drop", pct


class TrackProfile:
    """Curva de energía y de tono del tema, con memoria entre reproducciones."""

    def __init__(self, key, length=0.0):
        self.key = key
        self.length = length
        self.rms = []        # una muestra cada PROFILE_STEP, en orden
        self.cen = []
        self.known = False   # True si vino del cache: entonces se puede anticipar
        # el compás medido la vez pasada: la segunda escucha arranca sabiendo a
        # qué velocidad va el tema, sin los primeros segundos de tanteo
        self.bpm = 0.0
        self.conf = 0.0
        self.section = "verse"
        self.since = 0.0
        # Curva suavizada aparte para decidir la PARTE. Con el rms crudo, un tema
        # cambiaba de "parte" cada dos segundos: eso no es una sección, es el
        # bombo. Una sección dura estrofas, no compases.
        self.smooth = 0.0

    # ---- persistencia
    def path(self):
        return os.path.join(PROFILE_DIR, hashlib.sha1(self.key.encode()).hexdigest() + ".json")

    def load(self):
        try:
            with open(self.path()) as f:
                data = json.load(f)
        except OSError:
            return False       # todavía no se escuchó nunca: no hay cache
        except ValueError as e:
            # JSON roto o cortado a la mitad (el daemon murió escribiendo): se
            # descarta y se vuelve a medir, pero queda dicho cuál era el archivo
            log(f"broken track profile, remeasuring ({type(e).__name__}: {e})")
            return False
        if not data.get("rms"):
            return False
        self.rms = data["rms"]
        self.cen = data.get("cen", [])
        self.bpm = data.get("bpm", 0.0) or 0.0
        self.conf = data.get("conf", 0.0) or 0.0
        self.known = True
        return True

    def save(self):
        if len(self.rms) < PROFILE_MIN_SAMPLES:
            return False       # medio tema no sirve de mapa
        try:
            os.makedirs(PROFILE_DIR, exist_ok=True)
            tmp = self.path() + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"step": PROFILE_STEP, "len": self.length,
                           "rms": [round(v, 4) for v in self.rms],
                           "cen": [round(v, 3) for v in self.cen],
                           "bpm": round(self.bpm, 1), "conf": round(self.conf, 2)}, f)
            os.replace(tmp, self.path())
            return True
        except OSError as e:
            log(f"couldn't save the track profile ({e})")
            return False

    # ---- en vivo
    def at(self, pos):
        """Índice de muestra para un momento de la canción."""
        return max(0, int(pos / PROFILE_STEP))

    def record(self, pos, rms, cen):
        """Guarda la muestra de este momento (la del tema que está sonando)."""
        i = self.at(pos)
        while len(self.rms) <= i:
            self.rms.append(0.0)
            self.cen.append(0.5)
        # promedio con lo que ya había: si el tema se escuchó otras veces, el
        # mapa se afina en vez de pisarse
        self.rms[i] = rms if self.rms[i] == 0.0 else (
            self.rms[i] * PROFILE_BLEND_OLD + rms * PROFILE_BLEND_NEW)
        self.cen[i] = cen if self.cen[i] == 0.5 else (
            self.cen[i] * PROFILE_BLEND_OLD + cen * PROFILE_BLEND_NEW)

    def update(self, pos, rms, now):
        """Parte actual, con histéresis. Devuelve (parte, percentil, cambió)."""
        self.smooth = (self.smooth * (1 - SECTION_SMOOTH) + rms * SECTION_SMOOTH
                       if self.smooth > 0 else rms)
        kind, pct = classify_level(self.smooth, self.rms)
        if kind == self.section:
            self.since = now
            return kind, pct, False
        if now - self.since < SECTION_HOLD:
            return self.section, pct, False
        self.section = kind
        self.since = now
        return kind, pct, True

    def coming(self, pos, ahead=CUE_AHEAD):
        """Qué se viene en los próximos segundos, si el tema ya se conoce.

        Sin esto la reacción siempre llega tarde: el golpe se ve DESPUÉS de que
        sonó. Con el mapa cargado, el tubo puede empezar a apretar antes."""
        if not self.known or not self.rms:
            return None
        here = self.at(pos)
        there = self.at(pos + ahead)
        if there >= len(self.rms) or here >= len(self.rms):
            return None
        if self.rms[here] <= 0.0 or self.rms[there] <= 0.0:
            return None      # ese pedazo del tema todavía no se escuchó nunca
        now_kind, _ = classify_level(self.rms[here], self.rms)
        then_kind, _ = classify_level(self.rms[there], self.rms)
        if then_kind == now_kind:
            return None
        return then_kind


_profile = None
_profile_lock = threading.Lock()


def profile_for(track):
    """Perfil del tema que suena; lo carga del cache si ya se escuchó."""
    key = FIELD_SEP.join([track.get("artist", ""), track.get("title", ""),
                          str(int(round(track.get("length", 0))))])
    prof = TrackProfile(key, track.get("length", 0.0))
    if prof.load():
        log("track profile: known, the tube can see what's coming")
    return prof


def set_profile(prof):
    global _profile
    with _profile_lock:
        old = _profile
        _profile = prof
    if old is not None:
        old.save()

# ------------------------------------------------------------------ audio
# El tubo late con la música de verdad. Se graba el monitor de la placa con
# pw-record (o parec) y se analiza acá, en Python pelado: sin numpy, sin cava,
# sin dependencias nuevas — pipewire ya está o no hay sonido en la máquina.
AUDIO_RATE = 16000
AUDIO_HOP = 512                                   # 32 ms por análisis
AUDIO_BANDS = (60.0, 150.0, 400.0, 1000.0, 2500.0, 5000.0)
AUDIO_MIN_SEND = 0.04                             # ~25 eventos por segundo

# Captura muda un rato largo: casi siempre es que la salida por default no es la
# que suena. Se avisa una vez y se sigue (no se corta: puede ser una pausa).
QUIET_LEVEL = 0.02          # debajo de esto la captura está muda
QUIET_WARN = 20.0           # segundos de mudez antes de avisar
# El mapa se guarda cada tanto, no sólo al cambiar de tema: si el daemon se cae
# en la mitad, lo escuchado hasta ahí no se pierde.
PROFILE_SAVE_EVERY = 30.0

# ---- el pico: el golpe que SÍ merece que la pantalla se rompa
# Un golpe es cada bombo que sobresale — hay cientos por tema, y si la pantalla
# late en todos, late todo el tiempo y cansa. El pico es otra cosa: el momento
# más alto de ESTA canción, no el más alto de los últimos dos segundos. Se pide
# percentil contra el tema entero, distancia mínima entre uno y otro, y un tope
# por tema, para que sean un par de veces y se sientan como algo que pasa.
# Medido sobre dos minutos de audio real: 162 golpes -> 3 picos con 0.92 y 2 con
# 0.95. La pantalla latía en los 162.
PEAK_PCT = 0.95          # arriba del 95% de la canción
PEAK_GAP = 15.0          # segundos mínimos entre dos picos
PEAK_MAX = 4             # cuántos picos como mucho por tema
PEAK_HARD = 2.0          # sin mapa del tema: el golpe tiene que doblar la media
PEAK_HARD_FLOOR = 0.02   # ...y además sonar: doblar un silencio no es un golpe

# ---- normalización del nivel
# El nivel va contra un pico que decae solo: la música no viene con un volumen
# fijo y sin esto el tubo late fuerte o no late según el master del sistema.
LEVEL_PEAK_DECAY = 0.995   # cuánto sobrevive el pico en cada bloque (~32 ms)
LEVEL_PEAK_FLOOR = 1e-4    # piso del pico: sin él, silencio => división por ~0

# ---- el golpe (no el pico: eso lo filtra PeakGate)
# Un golpe es algo que SOBRESALE del momento, no cada bombo: con el umbral bajo,
# en un tema con batería marcada se dispara tres veces por segundo y la pantalla
# queda vibrando todo el tiempo.
BEAT_RATIO = 1.6           # cuánto tiene que superar al promedio corto
BEAT_FLOOR = 0.012         # piso absoluto: en silencio, cualquier ruido "sobresale"
BEAT_REFRACTORY = 0.25     # segundos mudos después de un golpe (mismo bombo, 3 veces)
BEAT_SLOW_KEEP = 0.9       # el promedio corto contra el que se compara: memoria...
BEAT_SLOW_MIX = 0.1        # ...y cuánto entra de cada bloque nuevo


_BAND_TABLES = {}


def _band_table(n, rate, freq):
    """Seno/coseno de la banda, ya multiplicados por una ventana de Hann.

    Se calcula una vez por (largo, frecuencia) y se reusa: sin esto el análisis
    haría 500 senos por banda y por bloque, 30 veces por segundo."""
    key = (n, rate, freq)
    table = _BAND_TABLES.get(key)
    if table is None:
        w = 2.0 * math.pi * freq / rate
        cos_t, sin_t = [], []
        for i in range(n):
            # Hann: sin la ventana, un tono agudo se derrama sobre las bandas
            # graves y el centroide miente feo
            win = 0.5 - 0.5 * math.cos(2.0 * math.pi * i / max(n - 1, 1))
            cos_t.append(math.cos(w * i) * win)
            sin_t.append(math.sin(w * i) * win)
        table = (cos_t, sin_t)
        _BAND_TABLES[key] = table
    return table


def band_energy(samples, rate, freq):
    """Energía de UNA frecuencia, con la DFT de ese bin nomás.

    Se probó Goertzel (más barato) y hay que dejar dicho por qué no quedó: en las
    bandas graves, con bloques de 512, el término `s1² + s2² - coeff·s1·s2` pierde
    toda la precisión (coeff ≈ 2) y un tono de 4 kHz aparecía con la mitad de su
    energía en la banda de 60 Hz. Acá se suman seno y coseno y listo — el costo
    real está en las tablas, y ésas se precalculan."""
    n = len(samples)
    if n == 0:
        return 0.0
    cos_t, sin_t = _band_table(n, rate, freq)
    re = im = 0.0
    for i, x in enumerate(samples):
        re += x * cos_t[i]
        im += x * sin_t[i]
    return (re * re + im * im) / (n * n)


class AudioAnalyzer:
    """PCM crudo → nivel, bandas, centroide (proxy del tono) y golpes.

    El nivel va normalizado contra un pico que decae solo: la música no viene con
    un volumen fijo y sin eso el tubo late fuerte o no late según el master del
    sistema. El golpe se mide aparte, contra el rms crudo, con refractario para no
    disparar tres veces el mismo bombo."""

    def __init__(self, rate=AUDIO_RATE):
        self.rate = rate
        self.peak = LEVEL_PEAK_FLOOR
        self.slow = 0.0
        self.last_beat = 0.0

    def feed(self, pcm, now):
        """pcm: bytes s16 mono. Devuelve el dict del evento, o None si vino vacío."""
        n = len(pcm) // 2
        if n == 0:
            return None
        samples = [int.from_bytes(pcm[i * 2:i * 2 + 2], "little", signed=True) / 32768.0
                   for i in range(n)]
        rms = math.sqrt(sum(x * x for x in samples) / n)

        # pico con decaimiento: se adapta al volumen del sistema sin saltos
        self.peak = max(rms, self.peak * LEVEL_PEAK_DECAY, LEVEL_PEAK_FLOOR)
        level = min(rms / self.peak, 1.0)

        energies = [band_energy(samples, self.rate, f) for f in AUDIO_BANDS]
        total = sum(energies)
        if total > 0:
            # Centroide en escala logarítmica (el oído oye octavas, no hertz) y
            # pesado por amplitud, no por energía: la música tiene espectro ~1/f
            # y con energía cruda TODO da grave, no se distingue una voz de otra.
            amps = [math.sqrt(e) for e in energies]
            atot = sum(amps)
            logf = sum(math.log(f) * a for f, a in zip(AUDIO_BANDS, amps)) / atot
            lo, hi = math.log(AUDIO_BANDS[0]), math.log(AUDIO_BANDS[-1])
            centroid = min(max((logf - lo) / (hi - lo), 0.0), 1.0)
            bands = [e / total for e in energies]
        else:
            centroid = 0.5
            bands = [0.0] * len(AUDIO_BANDS)

        # El golpe se mide contra el rms CRUDO, no contra el nivel normalizado:
        # el nivel se adapta al volumen, así que un tema bajito y parejo también
        # marca 1.0 y contra eso ningún golpe sobresale.
        # Un golpe es algo que SOBRESALE, no cada bombo: con el umbral bajo, en un
        # tema con batería marcada se dispara tres veces por segundo y la pantalla
        # queda vibrando todo el tiempo.
        beat = False
        hard = False
        if (rms > max(self.slow * BEAT_RATIO, BEAT_FLOOR)
                and now - self.last_beat > BEAT_REFRACTORY):
            beat = True
            # golpe que sobresale MUCHO: es lo único que se puede usar como pico
            # cuando el tema todavía no tiene mapa (recién empieza, o no hay
            # posición del reproductor y no se sabe dónde estamos)
            hard = rms > max(self.slow * PEAK_HARD, PEAK_HARD_FLOOR)
            self.last_beat = now
        self.slow = self.slow * BEAT_SLOW_KEEP + rms * BEAT_SLOW_MIX

        return {
            "cmd": "aud",
            "l": round(level, 3),
            "lo": round(bands[0] + bands[1], 3),
            "mid": round(bands[2] + bands[3], 3),
            "hi": round(bands[4] + bands[5], 3),
            "c": round(centroid, 3),
            "b": 1 if beat else 0,
            "h": 1 if hard else 0,
        }


# ---- el compás: a qué velocidad va el tema, de verdad
# Los golpes ya se detectan (AudioAnalyzer.feed), pero un golpe suelto no es un
# tempo: hay bombos que faltan, palmas que sobran y el intervalo entre dos
# golpes se mueve unas decenas de ms aunque el tema esté cuadrado. El tempo es
# el intervalo que MÁS SE REPITE, no el último ni el promedio — un promedio con
# un solo golpe perdido (el doble de intervalo) se va veinte BPM.
BPM_MIN_MS = 300.0        # 200 BPM
BPM_MAX_MS = 1200.0       # 50 BPM
BPM_BIN_MS = 10.0         # el ancho del bin del histograma
BPM_HISTORY = 24          # cuántos intervalos entran en la cuenta
BPM_TOL = 0.08            # ±8%: qué tan cerca del período cuenta como "en tiempo"
BPM_MIN_INTERVALS = 6     # menos que esto no es un histograma, son dos números
BPM_HARMONIC_SHARE = 0.4  # cuánto tiene que pesar el pico rápido para ganarle al modal
# Un hueco más largo que esto no es un compás lento: es una pausa, un silencio o
# la captura que se cayó. Doblarlo/partirlo daría un número inventado — se tira
# y el conteo arranca del golpe siguiente.
BPM_MAX_GAP = 2 * BPM_MAX_MS / 1000.0
BPM_SEND_DELTA = 2.0      # BPM de diferencia que ameritan avisar antes de tiempo
BPM_SEND_EVERY = 5.0      # ...y cada cuánto se avisa igual aunque no cambie


def _fold_interval(dt_ms):
    """Mete un intervalo en el rango musical doblándolo o partiéndolo al medio.

    Un tema a 120 puede marcar cada corchea (250 ms) o perder un bombo y marcar
    cada dos tiempos (1000 ms): las tres cosas son el MISMO compás. Sin plegar,
    los 250 ms se caen del rango y el tema queda sin tempo."""
    if dt_ms <= 0:
        return None
    for _ in range(8):
        if dt_ms < BPM_MIN_MS:
            dt_ms *= 2
        elif dt_ms > BPM_MAX_MS:
            dt_ms /= 2
        else:
            return dt_ms
    return None


class BpmTracker:
    """De los golpes al compás: cuántos BPM y con cuánta confianza.

    La confianza importa tanto como el número. Con un tema sin batería marcada
    los golpes salen donde quieren y el histograma da cualquier cosa; el overlay
    sólo se cuelga del compás si la confianza pasa el umbral, y si no sigue
    moviéndose con la letra como siempre."""

    def __init__(self):
        self.intervals = []
        self.bpm = 0.0
        self.conf = 0.0
        self.last_beat = None
        self.last_sent = 0.0
        self.sent_bpm = 0.0

    def reset(self):
        """Tema nuevo: el compás anterior no dice nada del que arranca."""
        self.intervals = []
        self.bpm = 0.0
        self.conf = 0.0
        self.last_beat = None
        self.sent_bpm = 0.0

    def seed(self, bpm, conf):
        """Arranca sabiendo lo que se midió la vez pasada (viene del perfil del
        tema). No mete intervalos falsos: es sólo el número que se manda hasta
        que los golpes de esta pasada digan otra cosa."""
        if bpm and conf:
            self.bpm = float(bpm)
            self.conf = float(conf)

    def beat(self, now):
        """Un golpe. Devuelve el período estimado en ms, o 0 si todavía no hay."""
        if self.last_beat is not None:
            gap = now - self.last_beat
            if 0 < gap <= BPM_MAX_GAP:
                folded = _fold_interval(gap * 1000.0)
                if folded is not None:
                    self.intervals.append(folded)
                    del self.intervals[:-BPM_HISTORY]
        self.last_beat = now
        return self._estimate()

    def _bin(self, ms):
        return int((ms - BPM_MIN_MS) // BPM_BIN_MS)

    def _weight(self, counts, b):
        """Cuánto pesa un bin contando a sus vecinos: con jitter de unos ms el
        mismo compás cae en dos o tres bins pegados, y sin sumarlos el modal es
        el que tuvo suerte."""
        return counts.get(b - 1, 0) + counts.get(b, 0) + counts.get(b + 1, 0)

    def _estimate(self):
        if len(self.intervals) < BPM_MIN_INTERVALS:
            return 0.0
        counts = {}
        for ms in self.intervals:
            b = self._bin(ms)
            counts[b] = counts.get(b, 0) + 1
        best = max(counts, key=lambda b: (self._weight(counts, b), -b))
        # Armónico al revés del plegado: los intervalos pueden estar repartidos
        # entre el compás y su mitad (bombos que se pierden). Si la mitad tiene
        # un pico propio con peso, el compás es el RÁPIDO — el lento es el que
        # se armó con los golpes que faltaron.
        half = self._bin((self._center(best)) / 2.0)
        if (self._center(best)) / 2.0 >= BPM_MIN_MS and \
                self._weight(counts, half) >= self._weight(counts, best) * BPM_HARMONIC_SHARE:
            best = half
        # El centro del bin es un número redondo de 10 ms; el promedio de los
        # intervalos que caen cerca es el período de verdad (la tolerancia es
        # más ancha que el bin, así que esto usa todas las muestras buenas).
        # Se re-centra un par de veces: con la ventana clavada en el bin, un
        # centro corrido 10 ms recorta una de las dos colas y el promedio se va
        # detrás del recorte (medido: 3 BPM de error con jitter de ±20 ms).
        period = self._center(best)
        for _ in range(3):
            near = [ms for ms in self.intervals if abs(ms - period) <= period * BPM_TOL]
            if not near:
                return 0.0
            moved = sum(near) / len(near)
            if abs(moved - period) < 0.05:
                period = moved
                break
            period = moved
        self.bpm = 60000.0 / period
        self.conf = len([ms for ms in self.intervals
                         if abs(ms - period) <= period * BPM_TOL]) / len(self.intervals)
        return period

    def _center(self, b):
        return BPM_MIN_MS + (b + 0.5) * BPM_BIN_MS

    def event(self, now):
        """El evento para el overlay, o None si no toca mandar nada todavía.

        `phase` va como la EDAD del último golpe, no como su marca de tiempo: el
        reloj del daemon (`time.monotonic`) y el del overlay (`Date.now`) no son
        el mismo, así que un instante crudo del daemon allá no significa nada.
        La edad sí: el overlay hace `Date.now() - phase*1000` y queda anclado."""
        if self.bpm <= 0 or self.conf <= 0:
            return None
        if (abs(self.bpm - self.sent_bpm) <= BPM_SEND_DELTA
                and now - self.last_sent < BPM_SEND_EVERY):
            return None
        self.last_sent = now
        self.sent_bpm = self.bpm
        age = 0.0 if self.last_beat is None else max(now - self.last_beat, 0.0)
        return {"cmd": "bpm", "v": round(self.bpm, 1), "conf": round(self.conf, 2),
                "phase": round(age, 3)}


class PeakGate:
    """El portero de los picos: de todos los golpes del tema deja pasar unos
    pocos, los más altos.

    Un golpe es cada bombo que sobresale del momento — hay cientos por tema. Un
    pico es estar en lo más alto de ESTA canción, y encima separado de los otros
    picos: eso es lo que se siente como "acá pegó", en vez de una pantalla que
    late todo el tiempo hasta que uno la apaga."""

    def __init__(self, pct=PEAK_PCT, gap=PEAK_GAP, cap=PEAK_MAX, now=0.0):
        self.pct = pct
        self.gap = gap
        self.cap = cap
        self.key = None
        # El reloj arranca ACÁ, no en cero. Con `last = 0` el primer frame ya
        # está a horas del último pico, y como el análisis todavía no tiene
        # promedio contra qué comparar, ese frame parece un golpazo: la pantalla
        # pegaba un fogonazo a los 30 ms de prender el tubo — justo el síntoma
        # que se está arreglando. Lo mismo al cambiar de tema o de salida.
        self.last = now
        self.count = 0

    def track(self, key, now=0.0):
        """Tema nuevo: el cupo arranca de cero. Si no, un tema que entra justo
        después de un estribillo se queda sin ningún pico."""
        if key == self.key:
            return
        self.key = key
        self.last = now
        self.count = 0

    def hit(self, now, beat, hard, pct):
        """¿Este golpe es un pico? `pct` es el percentil dentro del tema, o None
        si todavía no hay mapa — ahí el único dato disponible es si el golpe
        sobresale mucho del promedio."""
        if not beat or self.count >= self.cap or now - self.last < self.gap:
            return False
        if not (hard if pct is None else pct >= self.pct):
            return False
        self.last = now
        self.count += 1
        return True


def _default_sink():
    """Nombre de la salida por default. Se pregunta en cada captura: si Ferox se
    cambia de auriculares a parlantes, el nombre viejo ya no existe."""
    try:
        out = subprocess.run(["pactl", "get-default-sink"],
                             capture_output=True, text=True, timeout=3)
        name = out.stdout.strip()
        if out.returncode == 0 and name:
            return name
    except (OSError, subprocess.SubprocessError, UnicodeDecodeError) as e:
        # pactl que no está (OSError) o que se colgó (TimeoutExpired). Cualquier
        # otra cosa —args mal armados, por ejemplo— es un bug y tiene que explotar
        log(f"couldn't ask for the default sink ({type(e).__name__}: {e})")
    return None


SINK_CHECK_EVERY = 10.0    # segundos entre cada chequeo de la salida por default


def sink_changed(prev, now_fn=_default_sink):
    """True si la salida por default cambió desde que se abrió la captura.

    Un None de `now_fn` (pactl que falló esta vez nomás) no cuenta como
    cambio: si no, una falla transitoria reabriría la captura sin necesidad."""
    current = now_fn()
    return current is not None and current != prev


def sink_node_id(listing, name):
    """Id de nodo de un sink dentro de la salida de `pactl list sinks short`."""
    for line in listing.splitlines():
        cols = line.split("\t")
        if len(cols) >= 2 and cols[1] == name and cols[0].strip().isdigit():
            return cols[0].strip()
    return None


def _sink_node_id(name):
    try:
        out = subprocess.run(["pactl", "list", "sinks", "short"],
                             capture_output=True, text=True, timeout=3)
        if out.returncode == 0:
            return sink_node_id(out.stdout, name)
    except (OSError, subprocess.SubprocessError, UnicodeDecodeError) as e:
        # idem: sin id se cae a parec por nombre, pero que se sepa por qué
        log(f"couldn't list the sinks ({type(e).__name__}: {e})")
    return None


def _audio_command():
    """Con qué grabar lo que suena.

    OJO con pw-record: `--target=<nombre>.monitor` conecta sin quejarse y graba
    SILENCIO — hay que pasarle el id del nodo. Medido acá: 0.0012 de rms con el
    nombre contra 0.0757 con el id, con la misma música sonando. Por eso primero
    se resuelve el id, y parec (que sí acepta el nombre del monitor) queda de
    respaldo."""
    name = _default_sink()
    if not name:
        return None
    if shutil.which("pw-record"):
        node = _sink_node_id(name)
        if node:
            return ["pw-record", "--format=s16", f"--rate={AUDIO_RATE}",
                    "--channels=1", "--latency=20ms", f"--target={node}", "-"]
    if shutil.which("parec"):
        return ["parec", "--format=s16le", f"--rate={AUDIO_RATE}",
                "--channels=1", "-d", name + ".monitor"]
    return None


# ---------------------------------------------------- el micrófono (T5.1)
# El modo karaoke escucha lo que canta Ferox, no lo que sale de la placa: es
# una SEGUNDA captura, sobre la fuente de entrada por default, y sólo existe
# mientras `[behavior] sing` está prendida. Por default está apagada: es lo
# único de todo el programa que abre el micrófono.
VOICE_HOP = AUDIO_RATE // 10      # un bloque cada 100 ms (10 Hz, como el plan)


def voice_rms(pcm):
    """Cuánto suena este bloque de mic. s16 mono, igual que la otra captura.

    Acá NO se usa AudioAnalyzer a propósito: el análisis completo son seis DFT
    por bloque (bandas + centroide) y del micrófono no se lee ninguna — sólo el
    volumen. Con bloques de 1600 muestras eso sería trabajo puro para tirar."""
    n = len(pcm) // 2
    if n == 0:
        return 0.0
    total = 0.0
    for i in range(n):
        x = int.from_bytes(pcm[i * 2:i * 2 + 2], "little", signed=True) / 32768.0
        total += x * x
    return math.sqrt(total / n)


def _default_source():
    """Nombre de la ENTRADA por default (el micrófono), o None."""
    try:
        out = subprocess.run(["pactl", "get-default-source"],
                             capture_output=True, text=True, timeout=3)
        name = out.stdout.strip()
        if out.returncode == 0 and name:
            return name
    except (OSError, subprocess.SubprocessError, UnicodeDecodeError) as e:
        log(f"couldn't ask for the default source ({type(e).__name__}: {e})")
    return None


def _source_node_id(name):
    # `pactl list sources short` tiene el mismo formato que el de los sinks, así
    # que el parser (sink_node_id) es el mismo — uno solo, probado una vez
    try:
        out = subprocess.run(["pactl", "list", "sources", "short"],
                             capture_output=True, text=True, timeout=3)
        if out.returncode == 0:
            return sink_node_id(out.stdout, name)
    except (OSError, subprocess.SubprocessError, UnicodeDecodeError) as e:
        log(f"couldn't list the sources ({type(e).__name__}: {e})")
    return None


def _voice_command():
    """Con qué grabar el micrófono, o None si no se puede.

    Si la entrada por default es el MONITOR de una salida, no se graba: lo que
    entraría por ahí es la propia música, y el modo diría "está cantando" cada
    vez que suena un tema. Mejor no hacer nada y decirlo en el log."""
    name = _default_source()
    if not name:
        return None
    if name.endswith(".monitor"):
        log(f"voice: the default input is a monitor ({name}), not a mic — "
            "sing mode has nothing to listen to")
        return None
    if shutil.which("pw-record"):
        node = _source_node_id(name)
        if node:
            return ["pw-record", "--format=s16", f"--rate={AUDIO_RATE}",
                    "--channels=1", "--latency=20ms", f"--target={node}", "-"]
    if shutil.which("parec"):
        return ["parec", "--format=s16le", f"--rate={AUDIO_RATE}",
                "--channels=1", "-d", name]
    return None


# Quién se come el nivel del micrófono. Lo registra el daemon (SingGate, T5.2):
# es el mismo proceso, así que no hay razón para que 10 mensajes por segundo den
# la vuelta por el socket para volver acá al lado. Sin nadie registrado la
# captura igual anda (y no hace nada), que es lo que quiere un test.
_voice_sink = None


def set_voice_sink(fn):
    global _voice_sink
    _voice_sink = fn


def voice_loop():
    """Supervisor del hilo del micrófono. Mismo motivo que audio_loop: si se
    escapa una excepción, el hilo muere y el modo karaoke deja de funcionar
    para siempre sin decir nada."""
    while True:
        try:
            _voice_capture()
        except Exception:
            log("voice thread blew up, restarting it:\n" + traceback.format_exc())
            time.sleep(5)


def _voice_capture():
    """Graba el mic mientras `sing` esté prendida. Apagada, no se abre ni el
    proceso: el micrófono no queda abierto cuando nadie lo pidió."""
    while True:
        if not config.CFG["behavior"]["sing"]:
            time.sleep(0.5)
            continue
        cmd = _voice_command()
        if not cmd:
            time.sleep(10)
            continue
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL)
        except OSError as e:
            log(f"couldn't capture the mic ({type(e).__name__}: {e})")
            time.sleep(5)
            continue
        log("voice: listening to the mic (sing mode)")
        try:
            while config.CFG["behavior"]["sing"]:
                chunk = proc.stdout.read(VOICE_HOP * 2)
                if not chunk or len(chunk) < VOICE_HOP * 2:
                    break        # se cayó la captura (mic desenchufado, etc.)
                sink = _voice_sink
                if sink:
                    sink(voice_rms(chunk), time.monotonic())
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
        log("voice: mic released")


def audio_loop():
    """Supervisor del hilo de audio.

    daemon.py lanza esto en un Thread pelado: si una excepción se escapa, el hilo
    muere y el tubo se queda sin reaccionar a la música PARA SIEMPRE, sin ruido
    ni error visible, hasta reiniciar el daemon. Los except de acá abajo son
    angostos a propósito (un typo en los args de un subprocess tiene que verse),
    así que el reintento vive acá: se loguea entero y se vuelve a levantar."""
    while True:
        try:
            _capture_loop()
        except Exception:
            log("audio thread blew up, restarting it:\n" + traceback.format_exc())
            time.sleep(5)


def _capture_loop():
    """Graba y manda eventos mientras el tubo esté prendido. Fuera del modo CRT
    no se abre ni el proceso: cero consumo cuando no se ve."""
    while True:
        if not (config.CFG["crt"]["audio"] and config.crt_on()):
            time.sleep(0.5)
            continue
        cur_sink = _default_sink()
        cmd = _audio_command()
        if not cmd:
            log("no way to capture audio (pw-record/parec), the tube won't react")
            time.sleep(10)
            continue
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL)
        except OSError as e:
            # el grabador no está o no se pudo lanzar. Un TypeError/ValueError acá
            # sería un error de programación en la lista de args: que se vea.
            log(f"couldn't capture audio ({type(e).__name__}: {e})")
            time.sleep(5)
            continue
        log("audio: reacting to what's playing")
        an = AudioAnalyzer()
        last = 0.0
        last_sec = 0.0
        last_cue = 0.0
        # el pico se decide acá, no en la pantalla: es la única parte que sabe
        # dónde está este momento dentro de la canción entera
        cur_pct = None
        gate = PeakGate(now=time.monotonic())
        # el compás: lo alimentan los mismos golpes que ya se detectan
        bpm = BpmTracker()
        last_bpm_logged = 0.0
        last_save = time.monotonic()
        quiet_since = time.monotonic()
        last_sink_check = time.monotonic()
        warned = False
        try:
            while config.CFG["crt"]["audio"] and config.crt_on():
                chunk = proc.stdout.read(AUDIO_HOP * 2)
                if not chunk or len(chunk) < AUDIO_HOP * 2:
                    break     # se cayó la captura (cambio de salida, sink muerto)
                now = time.monotonic()
                if now - last_sink_check > SINK_CHECK_EVERY:
                    last_sink_check = now
                    if sink_changed(cur_sink, _default_sink):
                        log("audio: default sink changed, reopening the capture")
                        break
                ev = an.feed(chunk, now)
                if not ev:
                    continue
                # captura muda un rato largo: casi siempre es que la salida por
                # default no es la que suena. Se avisa una vez y se sigue.
                if ev["l"] > QUIET_LEVEL:
                    quiet_since = now
                elif not warned and now - quiet_since > QUIET_WARN:
                    warned = True
                    log("audio: only silence on the default output, "
                        "the tube won't react to the music")
                # ¿este golpe es de los que valen? Lo decide el portero: sólo la
                # pantalla lo dibuja, pero quién late y cuándo se resuelve acá.
                if ev["b"]:
                    bpm.beat(now)
                    msg = bpm.event(now)
                    if msg:
                        # queda en el log: si algún día el tubo va a destiempo,
                        # esto dice qué compás creyó ver y con cuánta confianza
                        if abs(msg["v"] - last_bpm_logged) > 2:
                            last_bpm_logged = msg["v"]
                            log(f"tempo: {msg['v']:.0f} BPM (conf {msg['conf']:.0%})")
                        ipc.send_soft(msg)
                if gate.hit(now, ev["b"] == 1, ev["h"] == 1, cur_pct):
                    ev["pk"] = 1
                    # queda en el log: si algún día "no late nunca" o "late todo
                    # el tiempo", esto dice cuántos picos hubo y en qué momento
                    log(f"peak {gate.count}/{gate.cap}"
                        + (f" ({cur_pct:.0%} of the track)" if cur_pct is not None
                           else " (no map yet)"))
                if ev["b"] or now - last >= AUDIO_MIN_SEND:
                    last = now
                    ipc.send_soft(ev)

                # dónde estamos DENTRO de la canción (no cuánto suena ahora)
                with _profile_lock:
                    prof = _profile
                if prof is None or now - last_sec < PROFILE_STEP:
                    continue
                last_sec = now
                if prof.key != gate.key:
                    cur_pct = None
                    gate.track(prof.key, now)
                    # tema nuevo: el compás anterior no dice nada del que
                    # arranca, pero el del perfil (si ya se escuchó) sí
                    bpm.reset()
                    bpm.seed(prof.bpm, prof.conf)
                # el número vive en el perfil, que es quien lo guarda: set_profile
                # salva el perfil VIEJO desde el hilo del daemon, así que el valor
                # ya tiene que estar escrito acá cuando eso pase
                if bpm.bpm > 0:
                    prof.bpm = bpm.bpm
                    prof.conf = bpm.conf
                # se guarda cada tanto, no sólo al cambiar de tema: si el daemon
                # se cae en la mitad, el mapa de lo escuchado no se pierde
                if now - last_save > PROFILE_SAVE_EVERY:
                    last_save = now
                    prof.save()
                pos = ipc._song_pos()
                if pos is None:
                    continue
                rms = ev["l"] * an.peak      # el rms crudo, sin la normalización
                prof.record(pos, rms, ev["c"])
                kind, pct, changed = prof.update(pos, rms, now)
                # La PARTE se decide con la curva suavizada (una sección dura
                # estrofas, no compases), pero el PICO no: el suavizado va
                # siempre por detrás de los golpes, así que medido contra la
                # canción entera nunca pasaba del percentil 73 y el pico no se
                # disparaba jamás. El pico se mide con el rms crudo, que es lo
                # que uno oye como "acá es lo más alto del tema".
                cur_pct = classify_level(rms, prof.rms)[1]
                if changed:
                    log(f"section: {kind} ({pct:.0%})")
                    ipc.send_soft({"cmd": "sec", "kind": kind, "p": round(pct, 2)})
                # y lo que se viene, si el tema ya se escuchó antes
                if now - last_cue > CUE_MIN_GAP:
                    nxt = prof.coming(pos)
                    if nxt and nxt != kind:
                        last_cue = now
                        log(f"coming: {nxt}")
                        ipc.send_soft({"cmd": "cue", "kind": nxt, "in": CUE_AHEAD})
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()     # no se murió solo con terminate: a la fuerza
        log("audio: capture stopped")
