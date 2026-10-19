"""Rendimiento del análisis de audio (tanda de mejoras de Fatal Lyrics, 2026-10-19).

Los cambios de `band_energy` y del decode de `feed` no pueden mover ni un número
del evento `aud`; `test_the_event_for_a_fixed_pcm_is_the_same_as_before` lo fija
con un PCM determinista (los valores salen del código anterior a la tanda)."""
import hashlib
import json
import math
import os
import struct
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from cartelitos import audio  # noqa: E402

N = audio.AUDIO_HOP
RATE = audio.AUDIO_RATE


def fixed_blocks(count):
    """PCM s16 mono determinista: tonos de 60/220/1000 Hz con la amplitud que sube y
    baja, más ruido de un LCG. Mismo generador que se usó para medir antes/después."""
    out, seed = [], 12345
    for i in range(count):
        amp = 0.05 + 0.5 * abs(math.sin(i * 0.1))
        bombo = 0.6 if i % 8 == 7 else 0.0     # un golpe cada tanto: se ven beat/kick
        vals = []
        for j in range(N):
            seed = (seed * 1103515245 + 12345) & 0x7fffffff
            noise = seed / 0x7fffffff * 2 - 1
            t = (i * N + j) / RATE
            x = amp * (0.5 * math.sin(2 * math.pi * 60 * t) + 0.3 * math.sin(2 * math.pi * 220 * t)
                       + 0.2 * math.sin(2 * math.pi * 1000 * t)) + 0.02 * noise
            x += bombo * math.sin(2 * math.pi * 60 * t) * math.exp(-j / 128.0)
            vals.append(max(-32768, min(32767, int(round(x * 32768)))))
        out.append(struct.pack(f"<{N}h", *vals))
    return out


class TestFeedIsPinned(unittest.TestCase):
    def test_the_event_for_a_fixed_pcm_is_the_same_as_before(self):
        an = audio.AudioAnalyzer()
        evs = [an.feed(pcm, i * 0.032) for i, pcm in enumerate(fixed_blocks(40))]
        # valores de la versión anterior a la tanda (HEAD 68f8c2c), bloque 39
        self.assertEqual(evs[39], {
            "cmd": "aud", "l": 0.882, "lo": 0.936, "mid": 0.064, "hi": 0.0, "c": 0.137,
            "b": 1, "h": 1, "d": 0.294, "cut": 0, "cutf": 0.0, "hf": 0.26, "mov": 0.227,
            "k": 0.34, "ht": 0.0, "nov": 0.0, "rise": 0.0, "fall": 0.0,
        })
        digest = hashlib.sha1(json.dumps(evs, sort_keys=True).encode()).hexdigest()
        self.assertEqual(digest, "21634a4b17425f89fefd16482d3b1ab2c660034f")


    def test_a_stray_byte_at_the_end_is_ignored(self):
        pcm = fixed_blocks(1)[0]
        self.assertEqual(audio.AudioAnalyzer().feed(pcm + b"\x01", 0.0),
                         audio.AudioAnalyzer().feed(pcm, 0.0))


class TestBandEnergyIsTheLoop(unittest.TestCase):
    """La suma de Python (`sum(map(mul, ...))`) redondea distinto que el bucle en el
    último bit: se pide 1e-9, no igualdad exacta."""

    def test_the_sum_form_matches_the_plain_loop(self):
        for pcm in fixed_blocks(5):
            s = [v / 32768.0 for v in struct.unpack(f"<{N}h", pcm)]
            for f in audio.AUDIO_BANDS:
                cos_t, sin_t = audio._band_table(N, RATE, f)
                re = im = 0.0
                for i, x in enumerate(s):
                    re += x * cos_t[i]
                    im += x * sin_t[i]
                ref = (re * re + im * im) / (N * N)
                self.assertLess(abs(audio.band_energy(s, RATE, f) - ref), 1e-9)


if __name__ == "__main__":
    unittest.main()
