"""El tono del color: cuánto se corre la paleta de la tapa según LA CANCIÓN.

La tapa pone el tono base (`art.py`); esto decide hacia dónde lo corre lo que
suena, con las señales que ya calcula `AudioAnalyzer` (centroide, agudos del
evento `aud`). Dos números, los dos en -1..1, que viajan en el evento `tone`:

  warm  — el REGISTRO. Agudo claro y brillante (voz alta, platillos) = +1, tira a
          cálido y luminoso (ámbar); grave, hondo, oscuro = -1, tira a frío y
          más oscuro (azul profundo). Es continuo y lento (segundos).
  shift — el MOOD. Cuando el tema cambia de verdad (estribillo, drop, bajón) y
          el cambio SE SOSTIENE, el tono se corre hacia otro lado: + si sube,
          - si baja. Tiene histéresis: entra a lo grande, sale a lo chico, y
          nada que dure menos de `SHIFT_HOLD_S` lo mueve.

Cómo se aplica (rueda de color, luz de cada cara, contraste) vive en
`shell/Faces.js` (`toneHue`, `albumFaces`); acá sólo se mide. PURO: sin hilos ni
sockets, el tiempo entra por parámetro, así los tests lo manejan con señales
sintéticas (`tests/test_tono.py`).

Calibración: los centroides reales (29 perfiles en ~/.cache/cartelitos/audio)
tienen media por tema entre 0.18 y 0.49, mediana 0.29, y dentro de un tema el
p5-p95 va de 0.08 a 0.5. Por eso el pivote está en 0.30 y no en 0.5: con 0.5
casi toda la música sería "grave" y el tubo viviría frío."""
import math

# ---- el registro (warm)
BRIGHT_PIVOT = 0.30       # el brillo "neutro" de la música real (mediana de los centroides)
BRIGHT_SPAN = 0.22        # cuánto se separa del pivote para llegar a ±1
HI_WEIGHT = 0.25          # cuánto pesan los agudos del evento (`hi`) frente al centroide
HI_GAIN = 2.0             # `hi` suele ser <0.5 de la energía: se estira a 0..1
REG_TAU_S = 3.0           # el registro AHORA (ruido de un segundo no lo mueve)
REF_TAU_S = 25.0          # referencia lenta del propio tema
REL_WEIGHT = 0.4          # cuánto pesa el registro relativo al tema, contra el absoluto
WARM_TAU_S = 2.5          # suavizado de salida
WARM_DEAD = 0.08          # zona muerta: lo casi neutro es neutro, no un tinte permanente
LEVEL_GATE = 0.05         # bajo este nivel (normalizado) no hay música que medir

# ---- el mood (shift)
MOOD_NOW_S = 1.5          # el mood de ahora: corto, que un golpe de 2 s no se arrastre cinco más
MOOD_SLOW_S = 40.0        # el mood del tema hasta ahora
MOOD_WARMUP_S = 8.0       # sin base todavía: no se decide nada
W_LEVEL, W_DENS, W_BRIGHT = 0.5, 0.3, 0.2
DB_FLOOR, DB_SPAN = -45.0, 30.0   # el volumen en dBFS: -45 es 0, -15 es 1 (6 dB = 0.2)
SHIFT_ENTER = 0.10        # cuánto se tiene que separar el mood para que cuente...
SHIFT_EXIT = 0.04         # ...y a cuánto tiene que volver para que se suelte (histéresis)
SHIFT_HOLD_S = 5.0        # ...y cuántos segundos seguidos, o no es una sección: es un golpe
SHIFT_FULL = 0.25         # separación a la que el corrimiento llega a ±1
SHIFT_TAU_S = 3.0         # el corrimiento entra y sale suave

# ---- el envío
SEND_STEP = 0.02          # no se manda un cambio menor a esto
SEND_MIN_GAP_S = 0.5      # ni más seguido que esto
SEND_BEAT_S = 2.0         # ni se calla más que esto (el overlay lo toma por vivo)
SILENCE_S = 3.0           # tanto silencio y los números vuelven despacio a 0


def _clamp(x, lo=-1.0, hi=1.0):
    return lo if x < lo else (hi if x > hi else x)


def brightness(ev):
    """0..1: el brillo de un bloque. Centroide (log, por amplitud) más los agudos."""
    hi = _clamp(ev.get("hi", 0.0) * HI_GAIN, 0.0, 1.0)
    return (1.0 - HI_WEIGHT) * ev.get("c", 0.5) + HI_WEIGHT * hi


class ToneTracker:
    def __init__(self):
        self.warm = 0.0
        self.shift = 0.0
        self.sent = (0.0, 0.0)
        self.sent_at = None
        self.at = None
        self.silent_since = None
        self.reset()

    def reset(self):
        """Tema nuevo: las bases se miden de nuevo. Lo que ya se ve (`warm`,
        `shift`) se queda y se desliza solo hacia el tema que empieza."""
        self.reg = BRIGHT_PIVOT
        self.ref = BRIGHT_PIVOT
        self.mood_now = self.mood_slow = None
        self.t0 = None
        self.target = 0.0          # corrimiento al que apunta el pestillo
        self.dev_since = None      # desde cuándo está afuera del umbral
        self.calm_since = None     # desde cuándo está adentro del umbral de salida

    # ------------------------------------------------------------ pasos
    def _ema(self, cur, x, dt, tau):
        return cur + (x - cur) * (1.0 - math.exp(-dt / tau))

    def _mood(self, ev, peak):
        b = _clamp((brightness(ev) - BRIGHT_PIVOT) / (2 * BRIGHT_SPAN) + 0.5, 0.0, 1.0)
        # El volumen sale del rms CRUDO (`l` viene normalizado contra un pico que
        # decae: tras un estribillo fuerte, una estrofa normal da `l` bajo hasta
        # que el pico se olvida, y eso se leería como un bajón que no existió).
        # Dentro de un tema el volumen de escucha no cambia, así que sirve.
        rms = ev.get("l", 0.0) * (peak if peak else 1.0)
        db = 20.0 * math.log10(max(rms, 1e-6))
        lvl = _clamp((db - DB_FLOOR) / DB_SPAN, 0.0, 1.0)
        return W_LEVEL * lvl + W_DENS * ev.get("mov", 0.0) + W_BRIGHT * b

    def _latch(self, d, now):
        """El pestillo del mood: `d` es mood de ahora menos mood del tema."""
        ad = abs(d)
        sign = 1.0 if d > 0 else -1.0
        if ad > SHIFT_ENTER and (self.target == 0.0 or sign != (1.0 if self.target > 0 else -1.0)):
            self.calm_since = None
            if self.dev_since is None:
                self.dev_since = now
            if now - self.dev_since >= SHIFT_HOLD_S:
                self.target = sign * _clamp(ad / SHIFT_FULL, 0.4, 1.0)
        else:
            self.dev_since = None
            if self.target != 0.0:
                # latcheado: sólo se suelta cuando el mood volvió cerca de la base
                if ad < SHIFT_EXIT:
                    if self.calm_since is None:
                        self.calm_since = now
                    if now - self.calm_since >= SHIFT_HOLD_S:
                        self.target = 0.0
                        self.calm_since = None
                else:
                    self.calm_since = None

    def feed(self, ev, now, peak=None):
        """Un evento `aud` (y `AudioAnalyzer.peak`, para el volumen crudo).
        Devuelve el evento `tone` si toca mandarlo, o None."""
        if self.at is None:
            self.at = now
        dt = min(max(now - self.at, 0.0), 0.25)
        self.at = now
        if dt <= 0.0:
            return None
        if self.t0 is None:
            self.t0 = now
        live = ev.get("l", 0.0) > LEVEL_GATE
        if live:
            self.silent_since = None
            b = brightness(ev)
            self.reg = self._ema(self.reg, b, dt, REG_TAU_S)
            self.ref = self._ema(self.ref, self.reg, dt,
                                 min(REF_TAU_S, max(now - self.t0, 1.0)))
            absolute = (self.reg - BRIGHT_PIVOT) / BRIGHT_SPAN
            relative = (self.reg - self.ref) / BRIGHT_SPAN
            raw = _clamp((1.0 - REL_WEIGHT) * absolute + REL_WEIGHT * relative)
            # zona muerta: lo que no llega al piso es neutro, lo que pasa crece desde 0
            goal = math.copysign(max(0.0, abs(raw) - WARM_DEAD) / (1.0 - WARM_DEAD), raw)
            m = self._mood(ev, peak)
            if self.mood_now is None:
                self.mood_now = self.mood_slow = m
            self.mood_now = self._ema(self.mood_now, m, dt, MOOD_NOW_S)
            # la base va más rápida mientras se está armando: el primer cuadro de un
            # tema no es "el mood del tema", y 40 s fijos la dejarían clavada ahí
            self.mood_slow = self._ema(self.mood_slow, m, dt,
                                       min(MOOD_SLOW_S, max(now - self.t0, 1.0)))
            if now - self.t0 >= MOOD_WARMUP_S:
                self._latch(self.mood_now - self.mood_slow, now)
        else:
            if self.silent_since is None:
                self.silent_since = now
            # una pausa corta no pinta nada: se queda como está, y si dura, vuelve a 0
            goal = self.warm
            if now - self.silent_since >= SILENCE_S:
                goal = 0.0
                self.target = 0.0
        self.warm = self._ema(self.warm, goal, dt, WARM_TAU_S)
        self.shift = self._ema(self.shift, self.target, dt, SHIFT_TAU_S)
        return self._maybe_send(now)

    def _maybe_send(self, now):
        w, s = round(self.warm, 2), round(self.shift, 2)
        if self.sent_at is not None:
            gap = now - self.sent_at
            moved = max(abs(w - self.sent[0]), abs(s - self.sent[1])) >= SEND_STEP
            if gap < SEND_MIN_GAP_S or (not moved and gap < SEND_BEAT_S):
                return None
        self.sent = (w, s)
        self.sent_at = now
        return {"cmd": "tone", "warm": w, "shift": s}
