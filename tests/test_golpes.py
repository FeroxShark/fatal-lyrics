"""Señales del evento `aud` para que el golpe se vea adaptado al tema (2026-10-19):
`k` (bombo), `ht` (agudos), `nov` (novedad), `rise`/`fall` (tendencia) y `char`
(carácter del tema). Ver los comentarios junto a KICK_* en audio.py.

Audio sintético nomás: cero pantalla, cero reproducción real.
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
DT = N / RATE

_rng = random.Random(3)
# hi-hat: ocho senos entre 5.5 y 7.6 kHz con fase al azar (ruido de agudos sin
# graves: un ruido blanco crudo también tiene bombo, y un hi-hat de verdad no)
HAT_PARTIALS = [(5500.0 + 300.0 * j, _rng.random() * 2 * math.pi) for j in range(8)]


def groove(seconds, kick_every=None, hat_every=None, kick_amp=0.6, hat_amp=0.25):
    """Bombo de 60 Hz (150 ms, cae en 50 ms) y/o hi-hat (40 ms, cae en 10 ms),
    el hi-hat en el contratiempo. Devuelve las muestras float."""
    n = int(seconds * RATE)
    out = [0.0] * n
    if kick_every:
        t = 0.0
        while t < seconds:
            s0 = int(t * RATE)
            for i in range(min(int(0.15 * RATE), n - s0)):
                tt = i / RATE
                out[s0 + i] += kick_amp * math.exp(-tt / 0.05) * math.sin(2 * math.pi * 60 * tt)
            t += kick_every
    if hat_every:
        t = hat_every / 2
        while t < seconds:
            s0 = int(t * RATE)
            for i in range(min(int(0.04 * RATE), n - s0)):
                tt = i / RATE
                env = hat_amp * math.exp(-tt / 0.01)
                out[s0 + i] += env * sum(math.sin(2 * math.pi * f * tt + p)
                                         for f, p in HAT_PARTIALS) / 4
            t += hat_every
    return out


def tones(seconds, parts, i0=0):
    """Tonos de fase continua (ver `sustained` en test_senales.py)."""
    return [sum(a * math.sin(2 * math.pi * f * (i0 + i) / RATE) for f, a in parts)
            for i in range(int(seconds * RATE))]


def run(samples, a=None, t0=0.0):
    a = a or audio.AudioAnalyzer()
    evs = []
    for b in range(len(samples) // N):
        blk = struct.pack(f"<{N}h", *[max(-32768, min(32767, int(round(x * 32768))))
                                       for x in samples[b * N:(b + 1) * N]])
        t = t0 + b * DT
        evs.append((t, a.feed(blk, t)))
    return a, evs


def fired(evs, key, after=0.0):
    return [(t, e[key]) for t, e in evs if e[key] and t >= after]


class KickHatTests(unittest.TestCase):
    """`k` y `ht` no se confunden: el bombo es bombo y el hi-hat es hi-hat."""

    def test_a_kick_alone_fires_k_once_per_hit_and_never_ht(self):
        _, evs = run(groove(4.0, kick_every=0.5))
        self.assertEqual(len(fired(evs, "k")), 8)
        self.assertEqual(fired(evs, "ht"), [])

    def test_a_hat_alone_fires_ht_and_never_k(self):
        _, evs = run(groove(4.0, hat_every=0.25))
        self.assertEqual(fired(evs, "k"), [])
        self.assertGreaterEqual(len(fired(evs, "ht")), 14)   # 16 golpes

    def test_kick_over_hat_keeps_them_apart(self):
        _, evs = run(groove(4.0, kick_every=0.5, hat_every=0.25))
        kicks = [t for t, _ in fired(evs, "k")]
        hats = [t for t, _ in fired(evs, "ht")]
        self.assertEqual(len(kicks), 8)
        self.assertGreaterEqual(len(hats), 14)
        # cada bombo cae en su tiempo (múltiplo de 0.5 s) y cada hi-hat en el
        # contratiempo (0.125 + múltiplo de 0.25): ninguno se lee como el otro
        for t in kicks:
            self.assertLess(abs(t - round(t / 0.5) * 0.5), 0.07, t)
        for t in hats:
            off = (t - 0.125) / 0.25
            self.assertLess(abs(off - round(off)) * 0.25, 0.07, t)

    def test_b_cannot_tell_them_apart_but_k_can(self):
        # el porqué de `k`: el golpe de banda completa también salta con el hi-hat
        _, evs = run(groove(4.0, hat_every=0.25))
        self.assertGreater(len(fired(evs, "b")), 0)
        self.assertEqual(fired(evs, "k"), [])

    def test_kick_force_is_bounded_and_a_buried_kick_is_softer(self):
        _, loud = run(groove(4.0, kick_every=0.5, kick_amp=0.6))
        # mismo bombo, enterrado debajo de un pad fuerte de 500 Hz
        pad = tones(4.0, [(500.0, 0.6)])
        soft_mix = [x + y for x, y in zip(groove(4.0, kick_every=0.5, kick_amp=0.15), pad)]
        _, soft = run(soft_mix)
        lk = [v for _, v in fired(loud, "k")]
        sk = [v for _, v in fired(soft, "k", after=0.4)]
        self.assertTrue(lk and sk)
        for v in lk + sk:
            self.assertTrue(0.0 < v <= 1.0)
        self.assertLess(sum(sk) / len(sk), sum(lk) / len(lk))

    def test_a_sustained_bass_note_is_not_a_kick_train(self):
        _, evs = run(tones(4.0, [(80.0, 0.5)]))
        self.assertLessEqual(len(fired(evs, "k")), 1)   # a lo sumo la entrada

    def test_silence_fires_nothing(self):
        _, evs = run([0.0] * int(2 * RATE))
        for key in ("k", "ht", "nov", "rise", "fall"):
            self.assertEqual(fired(evs, key), [], key)


class NoveltyTests(unittest.TestCase):
    def test_a_layer_that_enters_at_the_same_volume_fires_nov(self):
        before = tones(6.0, [(100.0, 0.5)])
        after = tones(6.0, [(100.0, 0.354), (3000.0, 0.354)], i0=len(before))
        _, evs = run(before + after)
        # mismo rms (0.354 = 0.5/√2 en cada uno): `l` no se entera
        steady = [e["nov"] for t, e in evs if 4.3 < t < 6.0]
        entering = [e["nov"] for t, e in evs if 6.0 < t < 10.0]
        self.assertLess(max(steady), 0.05)
        self.assertGreater(max(entering), 0.3)
        # y cuando la capa nueva ya es "lo de siempre", vuelve a 0
        self.assertLess(evs[-1][1]["nov"], 0.05)

    def test_a_steady_groove_is_not_novel(self):
        _, evs = run(groove(10.0, kick_every=0.5, hat_every=0.25))
        self.assertLess(max(e["nov"] for t, e in evs if t > 4.5), 0.15)


class TrendTests(unittest.TestCase):
    def test_a_sustained_level_step_up_fires_one_rise(self):
        lo = tones(10.0, [(220.0, 0.1)])
        hi = tones(10.0, [(220.0, 0.5)], i0=len(lo))
        _, evs = run(lo + hi)
        rises = fired(evs, "rise")
        self.assertEqual(len(rises), 1)
        t, v = rises[0]
        self.assertTrue(10.5 < t < 13.0, t)    # sostenido >1 s, no al instante
        self.assertTrue(0.0 < v <= 1.0)
        self.assertEqual(fired(evs, "fall"), [])

    def test_a_sustained_level_step_down_fires_one_fall(self):
        hi = tones(10.0, [(220.0, 0.5)])
        lo = tones(10.0, [(220.0, 0.08)], i0=len(hi))
        _, evs = run(hi + lo)
        self.assertEqual(len(fired(evs, "fall")), 1)
        self.assertEqual(fired(evs, "rise"), [])

    def test_a_short_dry_cut_is_not_a_fall(self):
        a = tones(10.0, [(220.0, 0.5)])
        b = tones(10.0, [(220.0, 0.5)], i0=len(a) + int(0.3 * RATE))
        _, evs = run(a + [0.0] * int(0.3 * RATE) + b)
        self.assertEqual(fired(evs, "fall"), [])
        self.assertEqual(fired(evs, "rise"), [])

    def test_opening_the_capture_mid_song_is_not_a_rise(self):
        _, evs = run(groove(10.0, kick_every=0.5, hat_every=0.25))
        self.assertEqual(fired(evs, "rise"), [])
        self.assertEqual(fired(evs, "fall"), [])


class CharTests(unittest.TestCase):
    def test_target_maps_calm_and_wild_to_the_ends(self):
        calm = audio.char_target(72.0, 0.9, 0.1, 1.0)
        wild = audio.char_target(168.0, 0.9, 0.9, 10.0)
        self.assertLess(calm, 0.2)
        self.assertGreater(wild, 0.8)

    def test_target_without_data_is_neutral_and_ignores_unreliable_bpm(self):
        self.assertEqual(audio.char_target(0.0, 0.0, None, None), 0.5)
        self.assertEqual(audio.char_target(170.0, 0.2, None, None), 0.5)
        self.assertAlmostEqual(audio.char_target(170.0, 0.2, 0.3, None), 0.3)

    def test_tracker_is_stable_and_only_sends_real_changes(self):
        tr = audio.CharTracker()
        msgs = []
        t = 0.0
        for i in range(60):       # un minuto, una vez por segundo, golpe a golpe
            target = 0.3 + (0.1 if i % 2 else -0.1)   # salta ±0.1 cada segundo
            m = tr.step(target, t)
            if m:
                msgs.append(m)
            t += 1.0
        self.assertEqual(msgs[0]["cmd"], "char")
        self.assertLessEqual(len(msgs), 2)            # el jitter no se manda
        # un cambio de verdad (el tema se agita) sí, y llega en unos segundos
        sent = None
        for _ in range(20):
            m = tr.step(0.9, t)
            t += 1.0
            if m:
                sent = m
        self.assertIsNotNone(sent)
        self.assertGreater(tr.value, 0.8)

    def test_seed_from_a_known_profile_starts_at_its_value(self):
        tr = audio.CharTracker()
        tr.seed(0.8)
        self.assertEqual(tr.step(0.8, 0.0)["v"], 0.8)

    def test_live_onset_rate_tells_a_busy_track_from_a_sparse_one(self):
        busy, _ = run(groove(12.0, kick_every=0.25, hat_every=0.125))
        sparse, _ = run(groove(12.0, kick_every=1.0))
        self.assertIsNotNone(busy.onset_rate())
        self.assertGreater(busy.onset_rate(), sparse.onset_rate() * 2)
        self.assertGreater(audio.char_target(0, 0, None, busy.onset_rate()),
                           audio.char_target(0, 0, None, sparse.onset_rate()))

    def test_onset_rate_needs_some_music_first(self):
        a, _ = run([0.0] * int(5 * RATE))
        self.assertIsNone(a.onset_rate())

    def test_char_energy_uses_the_live_profile_once_there_is_enough(self):
        prof = audio.TrackProfile("x")
        self.assertIsNone(audio._char_energy(prof))
        prof.rms = [0.1] * audio.PROFILE_MIN_SAMPLES
        self.assertIsNotNone(audio._char_energy(prof))


class EventShapeTests(unittest.TestCase):
    def test_new_fields_are_json_bounded(self):
        _, evs = run(groove(6.0, kick_every=0.5, hat_every=0.25))
        for _, e in evs:
            for key in ("k", "ht", "nov", "rise", "fall"):
                self.assertTrue(0.0 <= e[key] <= 1.0, (key, e[key]))
            # `b` y `hf` siguen ahí, como siempre
            self.assertIn(e["b"], (0, 1))
            self.assertTrue(0.0 <= e["hf"] <= 1.0)


if __name__ == "__main__":
    unittest.main()
