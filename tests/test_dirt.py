"""`dirt`: qué tan sucio suena (planitud espectral), corrida 7b de la tanda 7.
Señales sintéticas: seno -> limpio, ruido -> sucio, seno + ruido fuerte -> sucio,
silencio (y ruido bajísimo) -> 0, y la EMA que sube rápido y baja lento."""
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


def pcm(samples):
    return struct.pack(f"<{len(samples)}h",
                       *[max(-32768, min(32767, int(round(x * 32768)))) for x in samples])


def sine(freq=1000.0, amp=0.3, phase=0):
    return [amp * math.sin(2 * math.pi * freq * (i + phase) / RATE) for i in range(N)]


def noise(rng, sd=0.1):
    return [rng.gauss(0, sd) for _ in range(N)]


def settle(blocks, secs=6.0):
    """Alimenta un analizador nuevo con `blocks()` durante `secs` y devuelve el dirt final."""
    a = audio.AudioAnalyzer()
    t, out = 0.0, None
    while t < secs:
        out = a.feed(pcm(blocks()), t)
        t += N / RATE
    return out["d"]


class FlatnessTests(unittest.TestCase):
    def test_pure_tone_is_tonal(self):
        self.assertLess(audio.spectral_flatness_local(sine(), RATE), 0.05)
        self.assertLess(audio.spectral_flatness_local(sine(437.0), RATE), 0.05)

    def test_white_noise_is_flat(self):
        self.assertGreater(audio.spectral_flatness_local(noise(random.Random(1)), RATE), 0.4)

    def test_tone_plus_strong_noise_is_flat(self):
        rng = random.Random(2)
        mix = [a + b for a, b in zip(sine(), noise(rng, 0.2))]
        self.assertGreater(audio.spectral_flatness_local(mix, RATE), 0.4)

    def test_tone_plus_faint_noise_stays_tonal(self):
        rng = random.Random(3)
        mix = [a + b for a, b in zip(sine(), noise(rng, 0.03))]
        self.assertLess(audio.spectral_flatness_local(mix, RATE), 0.1)

    def test_tilted_noise_is_still_flat_locally(self):
        # música real tiene el espectro inclinado: ruido "rosa" (integrando el
        # blanco) no puede leerse como tonal sólo por la pendiente
        rng = random.Random(4)
        acc, pink = 0.0, []
        for _ in range(N):
            acc = 0.95 * acc + rng.gauss(0, 0.05)
            pink.append(acc)
        self.assertGreater(audio.spectral_flatness_local(pink, RATE), 0.3)

    def test_silence_and_short_blocks_are_zero(self):
        self.assertEqual(audio.spectral_flatness_local([0.0] * N, RATE), 0.0)
        self.assertEqual(audio.spectral_flatness_local([0.1] * 8, RATE), 0.0)

    def test_power_spectrum_puts_a_tone_in_its_bin(self):
        spec = audio.power_spectrum(sine(1000.0))
        self.assertEqual(len(spec), N // 2 + 1)
        self.assertEqual(max(range(len(spec)), key=spec.__getitem__), round(1000 * N / RATE))


class DirtTests(unittest.TestCase):
    def test_sine_is_clean(self):
        self.assertLess(settle(lambda: sine()), 0.05)

    def test_noise_is_dirty(self):
        rng = random.Random(5)
        self.assertGreater(settle(lambda: noise(rng)), 0.85)

    def test_sine_plus_strong_noise_is_dirty(self):
        rng = random.Random(6)
        self.assertGreater(settle(lambda: [a + b for a, b in zip(sine(), noise(rng, 0.2))]), 0.85)

    def test_silence_is_not_dirty(self):
        self.assertEqual(settle(lambda: [0.0] * N), 0.0)

    def test_very_quiet_noise_is_not_dirty(self):
        # ruido de fondo debajo del umbral de señal: no hay nada que juzgar
        rng = random.Random(7)
        self.assertLess(settle(lambda: noise(rng, 0.0008)), 0.02)

    def test_rises_faster_than_it_falls(self):
        rng = random.Random(8)
        a = audio.AudioAnalyzer()
        step = N / RATE
        t = 0.0
        for _ in range(int(3 / step)):
            a.feed(pcm(sine()), t)
            t += step
        t_up = 0.0
        while a.dirt < 0.63 and t_up < 10:          # 1 - 1/e: ~una constante de tiempo
            a.feed(pcm(noise(rng)), t)
            t += step
            t_up += step
        for _ in range(int(3 / step)):
            a.feed(pcm(noise(rng)), t)
            t += step
        t_down = 0.0
        while a.dirt > 0.37 and t_down < 10:
            a.feed(pcm(sine()), t)
            t += step
            t_down += step
        self.assertLess(t_up, t_down)
        self.assertLess(t_up, 1.0)          # ~0.5 s de subida
        self.assertGreater(t_down, 0.8)     # ~1.5 s de bajada

    def test_a_gap_in_capture_does_not_jump(self):
        # un hueco de segundos (captura caída) no cuenta como tiempo transcurrido
        rng = random.Random(9)
        a = audio.AudioAnalyzer()
        a.feed(pcm(sine()), 0.0)
        out = a.feed(pcm(noise(rng)), 60.0)
        self.assertLess(out["d"], 0.5)

    def test_event_carries_dirt_in_range(self):
        ev = audio.AudioAnalyzer().feed(pcm(sine()), 0.0)
        self.assertEqual(ev["cmd"], "aud")
        self.assertIn("d", ev)
        self.assertTrue(0.0 <= ev["d"] <= 1.0)
        # los campos de siempre siguen ahí (el overlay no cambió de forma)
        for k in ("l", "lo", "mid", "hi", "c", "b", "h"):
            self.assertIn(k, ev)

    def test_other_block_sizes_do_not_crash(self):
        a = audio.AudioAnalyzer()
        for n in (1, 7, 100, 300, 1024):
            ev = a.feed(pcm([0.1 * math.sin(i) for i in range(n)]), 0.1 * n)
            self.assertTrue(0.0 <= ev["d"] <= 1.0)


if __name__ == "__main__":
    unittest.main()
