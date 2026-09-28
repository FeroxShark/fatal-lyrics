"""Tanda 8 / slice "movimiento": la señal `mov` (0..1) del evento `aud`.

Ver docs/tanda8-estado/movimiento.md para el porqué de cada pieza.
Señales sintéticas nomás (regla de la tanda: cero pantalla, cero reproducción real).
"""
import math
import os
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
        así que el techo es ~0.2, lejos de 1.0."""
        a = audio.AudioAnalyzer()
        t = 0.0
        ev = None
        for _ in range(int(6.0 / DT)):
            ev = a.feed(tone(220.0, 0.7), t, pct=1.0)
            t += DT
        self.assertLess(ev["mov"], 0.35)

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
        """La ventana de subida es de ~1s: un pasaje ocupado que arranca de la
        nada tiene que mover la aguja bastante antes de que pasen 2s enteros."""
        a = audio.AudioAnalyzer()
        t = 0.0
        for _ in range(int(1.0 / DT)):    # un segundo "quieto" primero
            ev = a.feed(silence(), t)
            t += DT
        t, ev_1s = pulses(a, rate_hz=12.0, freq=800.0, amp=0.5, seconds=1.0, t0=t)
        self.assertGreater(ev_1s["mov"], 0.15)

    def test_mov_falls_slower_than_it_rises(self):
        """Ventana asimétrica: al cortarse el pasaje ocupado, `mov` tiene que
        seguir alto un ratito (no es otro parpadeo)."""
        a = audio.AudioAnalyzer()
        t, ev_busy = pulses(a, rate_hz=12.0, freq=800.0, amp=0.5, seconds=3.0)
        t, ev_1s_after = pulses(a, rate_hz=0.01, freq=800.0, amp=0.0, seconds=1.0, t0=t)
        self.assertGreater(ev_1s_after["mov"], ev_busy["mov"] * 0.4)


if __name__ == "__main__":
    unittest.main()
