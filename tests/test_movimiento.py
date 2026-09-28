"""Tanda 8 / slice "movimiento": la señal `mov` (0..1) del evento `aud`.

Ver docs/tanda8-estado/movimiento.md para el porqué de cada pieza.
Señales sintéticas nomás (regla de la tanda: cero pantalla, cero reproducción real).
"""
import math
import os
import random
import struct
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from cartelitos import audio  # noqa: E402

N = audio.AUDIO_HOP
RATE = audio.AUDIO_RATE
DT = N / RATE     # segundos por bloque, ~0.032


def pcm(samples):
    return struct.pack(f"<{len(samples)}h",
                       *[max(-32768, min(32767, int(round(x * 32768)))) for x in samples])


def tone(freq=440.0, amp=0.5, n=N):
    return pcm([amp * math.sin(2 * math.pi * freq * i / RATE) for i in range(n)])


def silence():
    return pcm([0.0] * N)


def pulses(a, rate_hz, freq, amp, seconds, t0=0.0, pct=None):
    """Alimenta `a` con un tren de pulsos (nota corta + silencio) a `rate_hz`
    onsets por segundo, mismo pico `amp` siempre. Devuelve (t final, último `ev`)."""
    period = 1.0 / rate_hz
    pulse_dur = min(0.02, period * 0.4)
    t = t0
    ev = None
    for _ in range(int(seconds / DT)):
        active = (t - t0) % period < pulse_dur
        blk = tone(freq, amp) if active else silence()
        ev = a.feed(blk, t, pct=pct)
        t += DT
    return t, ev


def sustained(a, freq, amp, seconds, t0=0.0, pct=None, phase0=0):
    """Tono de FASE CONTINUA (no `tone()`, que arranca de la muestra 0 en cada
    llamada y da bloques bit-idénticos: un flujo espectral trivialmente 0 sin
    importar si la normalización de abajo está bien o mal). Simula sostenido
    real: cada bloque sigue la fase donde dejó el anterior. Devuelve (t final,
    índice de muestra final, último `ev`)."""
    i0 = phase0
    t = t0
    ev = None
    for _ in range(int(seconds / DT)):
        blk = pcm([amp * math.sin(2 * math.pi * freq * (i0 + i) / RATE) for i in range(N)])
        ev = a.feed(blk, t, pct=pct)
        i0 += N
        t += DT
    return t, i0, ev


def noise(a, seconds, amp, t0=0.0, pct=None, seed=1):
    """Ruido blanco parejo: lo más parecido a una textura densa SIN onsets (guitarras
    distorsionadas, un pad). El flujo espectral entre dos bloques de ruido no es 0
    (mediana ~0.3): un detector de onsets con umbral bajo lo cuenta como ataques."""
    rng = random.Random(seed)
    t = t0
    ev = None
    for _ in range(int(seconds / DT)):
        ev = a.feed(pcm([amp * (rng.random() * 2 - 1) for _ in range(N)]), t, pct=pct)
        t += DT
    return t, ev


class MovTests(unittest.TestCase):
    """`mov`: cuánto se está moviendo la música ahora (densidad de onsets en todo
    el espectro + hf + energía relativa al propio tema, pesado y suavizado)."""

    def test_speeding_up_without_changing_peak_volume_raises_mov(self):
        """Vivaldi: cuerdas que aceleran. Mismo pico de amplitud, más onsets por
        segundo -> `mov` tiene que subir."""
        a = audio.AudioAnalyzer()
        t, ev_slow = pulses(a, rate_hz=2.5, freq=300.0, amp=0.5, seconds=4.0, t0=0.0)
        t, ev_fast = pulses(a, rate_hz=12.0, freq=300.0, amp=0.5, seconds=4.0, t0=t)
        self.assertGreater(ev_fast["mov"], ev_slow["mov"])

    def test_string_tremolo_without_any_bass_still_raises_mov(self):
        """Trémolo agudo/medio, sin nada de bajo: `mov` tiene que reaccionar igual
        (no depende del bombo, a diferencia del `beat` de rms crudo)."""
        a = audio.AudioAnalyzer()
        _, ev = pulses(a, rate_hz=10.0, freq=1500.0, amp=0.4, seconds=4.0)
        self.assertGreater(ev["mov"], 0.4)

    def test_silence_keeps_mov_at_zero(self):
        a = audio.AudioAnalyzer()
        t = 0.0
        ev = None
        for _ in range(int(4.0 / DT)):
            ev = a.feed(silence(), t)
            t += DT
            self.assertEqual(ev["mov"], 0.0)

    def test_a_loud_but_steady_track_does_not_stay_pinned_high(self):
        """Pedido de Ferox: un tema fuerte y PAREJO no tiene que quedar clavado
        arriba. Peor caso: se le pasa pct=1.0 (percentil máximo posible contra el
        perfil) todo el tiempo, y el tono no cambia nunca (sin onsets, sin brillo
        que cambie). Sólo el término de energía (peso 0.2) puede empujar `mov`,
        así que el techo es ~0.2, lejos de 1.0.

        Usa `sustained()`, NO `tone()`: `tone()` reinicia la fase en la muestra 0
        en cada llamada y dos bloques quedan bit-idénticos, dando flujo espectral
        0 por construcción — el test pasaría igual aunque la normalización de
        abajo estuviera mal (bug real encontrado en este slice: ver
        docs/tanda8-estado/movimiento.md). `sustained()` arrastra la fase real
        entre bloques, como un tono sostenido de verdad."""
        a = audio.AudioAnalyzer()
        _, _, ev = sustained(a, freq=220.0, amp=0.7, seconds=6.0, pct=1.0)
        self.assertLess(ev["mov"], 0.35)

    def test_loud_then_quiet_onsets_at_the_same_rate_give_similar_mov(self):
        """El caso Vivaldi de verdad: un pasaje fuerte (`ff`) seguido de uno
        flojo (`mf`) con la MISMA densidad de onsets. Si la detección normaliza
        contra un pico absoluto que todavía está alto por el pasaje fuerte
        anterior, los onsets del pasaje flojo no llegan a cruzar el umbral y
        `mov` se queda sordo justo cuando la música bajó de volumen (bug real
        encontrado y corregido en este slice, ver movimiento.md). Con
        `spectral_flux_ratio` (normaliza contra la energía DE ESE BLOQUE) los
        dos pasajes, misma densidad, tienen que dar un `mov` parecido."""
        a = audio.AudioAnalyzer()
        t, ev_loud = pulses(a, rate_hz=10.0, freq=800.0, amp=0.8, seconds=3.0, t0=0.0, pct=0.9)
        t, ev_quiet = pulses(a, rate_hz=10.0, freq=800.0, amp=0.15, seconds=3.0, t0=t, pct=0.2)
        self.assertGreater(ev_quiet["mov"], ev_loud["mov"] * 0.6)

    def test_without_a_track_profile_mov_falls_back_to_raw_level(self):
        """Sin `pct` (perfil todavía no conocido: arranque del tema, o sin
        posición del reproductor), `feed()` no explota y `mov` sigue en 0..1."""
        a = audio.AudioAnalyzer()
        t = 0.0
        ev = None
        for _ in range(int(2.0 / DT)):
            ev = a.feed(tone(220.0, 0.6), t)     # sin pct
            t += DT
        self.assertGreaterEqual(ev["mov"], 0.0)
        self.assertLessEqual(ev["mov"], 1.0)

    def test_mov_rises_within_about_a_second_of_a_busy_passage(self):
        """Un pasaje ocupado que arranca de la nada tiene que mover la aguja en el
        primer segundo."""
        a = audio.AudioAnalyzer()
        t = 0.0
        for _ in range(int(1.0 / DT)):    # un segundo "quieto" primero
            ev = a.feed(silence(), t)
            t += DT
        t, ev_1s = pulses(a, rate_hz=12.0, freq=800.0, amp=0.5, seconds=1.0, t0=t)
        self.assertGreater(ev_1s["mov"], 0.15)

    def test_mov_falls_slower_than_it_rises(self):
        """Ventana asimétrica: al cortarse el pasaje ocupado, `mov` tiene que
        seguir alto un ratito (no es otro parpadeo). Ronda 3: ese ratito es de
        ~1 s hasta la mitad, no de 3 (medido: 0.555 del pico al segundo)."""
        a = audio.AudioAnalyzer()
        t, ev_busy = pulses(a, rate_hz=12.0, freq=800.0, amp=0.5, seconds=3.0)
        t, ev_1s_after = pulses(a, rate_hz=0.01, freq=800.0, amp=0.0, seconds=1.0, t0=t)
        self.assertGreater(ev_1s_after["mov"], ev_busy["mov"] * 0.4)
        self.assertLess(ev_1s_after["mov"], ev_busy["mov"] * 0.7)

    def test_mov_rises_in_half_a_second(self):
        """Ronda 3 (Ferox: "se ve el cambio pero es mínimo"): a los 0.5 s de arrancar
        un pasaje nervioso `mov` ya recorrió más de la mitad de lo que va a subir."""
        a = audio.AudioAnalyzer()
        t = 0.0
        for _ in range(int(1.0 / DT)):
            a.feed(silence(), t)
            t += DT
        t, ev_half = pulses(a, rate_hz=12.0, freq=800.0, amp=0.5, seconds=0.5, t0=t)
        _, ev_end = pulses(a, rate_hz=12.0, freq=800.0, amp=0.5, seconds=4.0, t0=t)
        self.assertGreater(ev_half["mov"], 0.5 * ev_end["mov"])

    def test_mov_is_calm_again_two_seconds_after_the_passage_ends(self):
        """...y baja: dos segundos después de cortarse queda en menos de un tercio."""
        a = audio.AudioAnalyzer()
        t, ev_busy = pulses(a, rate_hz=12.0, freq=800.0, amp=0.5, seconds=3.0)
        _, ev_after = pulses(a, rate_hz=0.01, freq=800.0, amp=0.0, seconds=2.0, t0=t)
        self.assertLess(ev_after["mov"], ev_busy["mov"] / 3)

    def test_onset_density_is_not_saturated(self):
        """El bug de la ronda 3: con umbral 0.12 el detector contaba ~14 onsets/s en
        CUALQUIER pasaje con sonido (real, medido) y la densidad quedaba clavada en
        1.0 — `mov` vivía en una franja de 0.1. Pasajes de 1, 3, 8 y 12 onsets/s
        tienen que dar `mov` distintos y crecientes, con un salto notorio entre el
        más quieto y el más nervioso."""
        movs = []
        for hz in (1.0, 3.0, 8.0, 12.0):
            _, ev = pulses(audio.AudioAnalyzer(), rate_hz=hz, freq=800.0, amp=0.5, seconds=6.0)
            movs.append(ev["mov"])
        self.assertEqual(movs, sorted(movs))
        self.assertGreater(movs[-1] - movs[0], 0.4)

    def test_dense_textured_noise_is_not_counted_as_onsets(self):
        """Ruido parejo (textura, no ataques): el detector no lo cuenta como una
        lluvia de onsets. Con el umbral viejo (0.12) daba ~9 de densidad y `mov`
        0.59; con el nuevo casi nada de densidad y `mov` bajo."""
        a = audio.AudioAnalyzer()
        _, ev = noise(a, seconds=6.0, amp=0.3)
        self.assertLess(a.mov_rate, 1.0)
        self.assertLess(ev["mov"], 0.4)

    def test_beat_train_feeds_the_beat_density_term(self):
        """Ronda 3: la densidad de golpes (`beat`, ventana ~1.5 s) es un término
        propio de `mov`, aparte de los onsets."""
        a = audio.AudioAnalyzer()
        pulses(a, rate_hz=2.0, freq=100.0, amp=0.6, seconds=6.0)
        self.assertGreater(a.mov_beat_rate, 1.0)
        a2 = audio.AudioAnalyzer()
        sustained(a2, freq=220.0, amp=0.5, seconds=6.0)
        self.assertLess(a2.mov_beat_rate, 0.1)


if __name__ == "__main__":
    unittest.main()
