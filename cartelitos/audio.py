"""DSP del audio del sistema y el perfil de energia del tema."""
import hashlib
import json
import math
import os
import shutil
import subprocess
import threading
import time

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
        except Exception:
            return False
        if not data.get("rms"):
            return False
        self.rms = data["rms"]
        self.cen = data.get("cen", [])
        self.known = True
        return True

    def save(self):
        if len(self.rms) < 20:
            return False       # medio tema no sirve de mapa
        try:
            os.makedirs(PROFILE_DIR, exist_ok=True)
            tmp = self.path() + ".tmp"
            with open(tmp, "w") as f:
                json.dump({"step": PROFILE_STEP, "len": self.length,
                           "rms": [round(v, 4) for v in self.rms],
                           "cen": [round(v, 3) for v in self.cen]}, f)
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
        self.rms[i] = rms if self.rms[i] == 0.0 else (self.rms[i] * 0.6 + rms * 0.4)
        self.cen[i] = cen if self.cen[i] == 0.5 else (self.cen[i] * 0.6 + cen * 0.4)

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

    def coming(self, pos, ahead=2.0):
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
        self.peak = 1e-4
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
        self.peak = max(rms, self.peak * 0.995, 1e-4)
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
        if (rms > max(self.slow * 1.6, 0.012)
                and now - self.last_beat > 0.25):
            beat = True
            # golpe que sobresale MUCHO: es lo único que se puede usar como pico
            # cuando el tema todavía no tiene mapa (recién empieza, o no hay
            # posición del reproductor y no se sabe dónde estamos)
            hard = rms > max(self.slow * PEAK_HARD, 0.02)
            self.last_beat = now
        self.slow = self.slow * 0.9 + rms * 0.1

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
    except Exception:
        pass
    return None


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
    except Exception:
        pass
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


def audio_loop():
    """Graba y manda eventos mientras el tubo esté prendido. Fuera del modo CRT
    no se abre ni el proceso: cero consumo cuando no se ve."""
    while True:
        if not (config.CFG["crt"]["audio"] and config.crt_on()):
            time.sleep(0.5)
            continue
        cmd = _audio_command()
        if not cmd:
            log("no way to capture audio (pw-record/parec), the tube won't react")
            time.sleep(10)
            continue
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL)
        except Exception as e:
            log(f"couldn't capture audio ({e})")
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
        last_save = time.monotonic()
        quiet_since = time.monotonic()
        warned = False
        try:
            while config.CFG["crt"]["audio"] and config.crt_on():
                chunk = proc.stdout.read(AUDIO_HOP * 2)
                if not chunk or len(chunk) < AUDIO_HOP * 2:
                    break     # se cayó la captura (cambio de salida, sink muerto)
                now = time.monotonic()
                ev = an.feed(chunk, now)
                if not ev:
                    continue
                # captura muda un rato largo: casi siempre es que la salida por
                # default no es la que suena. Se avisa una vez y se sigue.
                if ev["l"] > 0.02:
                    quiet_since = now
                elif not warned and now - quiet_since > 20:
                    warned = True
                    log("audio: only silence on the default output, "
                        "the tube won't react to the music")
                # ¿este golpe es de los que valen? Lo decide el portero: sólo la
                # pantalla lo dibuja, pero quién late y cuándo se resuelve acá.
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
                # se guarda cada tanto, no sólo al cambiar de tema: si el daemon
                # se cae en la mitad, el mapa de lo escuchado no se pierde
                if now - last_save > 30:
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
                if now - last_cue > 2.0:
                    nxt = prof.coming(pos)
                    if nxt and nxt != kind:
                        last_cue = now
                        log(f"coming: {nxt}")
                        ipc.send_soft({"cmd": "cue", "kind": nxt, "in": 2.0})
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except Exception:
                proc.kill()
        log("audio: capture stopped")
