"""Tests del mood determinístico (tanda 6, corrida 3): sin red, sin IA."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))  # noqa: E402

from cartelitos import mood  # noqa: E402


class TestValence(unittest.TestCase):
    def test_love_and_sun_and_party_score_positive(self):
        self.assertGreater(mood.valence(["te amo", "sol y fiesta"]), 0.3)

    def test_hate_death_and_pain_score_negative(self):
        self.assertLess(mood.valence(["odio", "muerte", "dolor"]), -0.3)

    def test_no_lines_is_neutral(self):
        self.assertEqual(mood.valence([]), 0)

    def test_accents_still_match(self):
        # "sueño" normaliza a "sueno", que está en el léxico sin tilde
        self.assertGreater(mood.valence(["un sueño hermoso"]), 0)


class TestEnergy(unittest.TestCase):
    def test_unknown_profile_without_bpm_is_neutral(self):
        self.assertEqual(mood.energy({"known": False}, 0), 0.5)

    def test_unknown_profile_with_fast_bpm_maxes_out(self):
        self.assertEqual(mood.energy({"known": False}, 180), 1.0)

    def test_unknown_profile_with_slow_bpm_bottoms_out(self):
        self.assertEqual(mood.energy({"known": False}, 70), 0.0)

    def test_known_profile_quiet_and_even_scores_low(self):
        # rms bajo y parejo (balada/lofi): tiene que quedar bien abajo del
        # piso ENERGY_RMS_FLOOR, no cerca de 0.35-0.40 como con el percentil
        # autorreferencial viejo (ver docs/plans/2026-09-15-crt-tanda6-dinamismo.md).
        quiet = {"known": True, "rms": [0.015] * 20}
        self.assertLess(mood.energy(quiet, 0), 0.35)

    def test_known_profile_loud_scores_high(self):
        # rms alto y parejo (masterizado fuerte): tiene que superar el techo.
        loud = {"known": True, "rms": [0.18] * 20}
        self.assertGreater(mood.energy(loud, 0), 0.65)

    def test_known_profile_favors_the_loud_one_over_the_quiet_one(self):
        loud = {"known": True, "rms": [0.18] * 20}
        flat = {"known": True, "rms": [0.05] * 20}
        self.assertGreater(mood.energy(loud, 0), mood.energy(flat, 0))

    def test_known_profile_with_no_samples_falls_back_to_neutral(self):
        self.assertEqual(mood.energy({"known": True, "rms": []}, 0), 0.5)

    def test_a_profile_without_gain_uses_the_old_thresholds_unchanged(self):
        # Perfil de antes de este arreglo (docs/PENDIENTES.md: "Mood sesgado
        # por volumen"): sin "gain" en el summary, mood.energy() no reescala
        # nada -- si no fuera así, los cuatro tests de arriba (escritos antes
        # de que existiera "gain") habrían dejado de valer lo mismo.
        no_gain = {"known": True, "rms": [0.09] * 20}
        span = mood.ENERGY_RMS_CEIL - mood.ENERGY_RMS_FLOOR
        expected = max(0.0, min(1.0, (0.09 - mood.ENERGY_RMS_FLOOR) / span))
        self.assertAlmostEqual(mood.energy(no_gain, 0), expected)

    def test_same_track_at_different_volume_gives_the_same_energy(self):
        # El mismo tema, escuchado a volumen 1.0 y a 0.3 (la escala de
        # PipeWire es cúbica: ganancia = volumen**3): el rms crudo capturado
        # sale distinto, pero normalizado por la ganancia guardada tiene que
        # dar aproximadamente lo mismo. Esta es la razón de ser del arreglo.
        true_rms = 0.09    # el rms "real" del tema, a ganancia 1.0
        gain_loud = 1.0 ** 3
        gain_quiet = 0.3 ** 3
        loud = {"known": True, "rms": [true_rms * gain_loud] * 20, "gain": gain_loud}
        quiet = {"known": True, "rms": [true_rms * gain_quiet] * 20, "gain": gain_quiet}
        self.assertAlmostEqual(mood.energy(loud, 0), mood.energy(quiet, 0), delta=0.05)

    def test_zero_gain_falls_back_to_bpm(self):
        # Volumen muteado (o casi): dividir por una ganancia ~0 dispararía el
        # rms normalizado a cualquier valor absurdo, así que ni se intenta --
        # se cae al bpm, como si no hubiera perfil.
        muted = {"known": True, "rms": [0.09] * 20, "gain": 0.0}
        self.assertAlmostEqual(mood.energy(muted, 180), 1.0)

    def test_zero_gain_without_bpm_falls_back_to_neutral(self):
        muted = {"known": True, "rms": [0.09] * 20, "gain": 0.0}
        self.assertEqual(mood.energy(muted, 0), 0.5)

    def test_a_typical_gain_stays_comparable_to_a_mid_track(self):
        # Con la ganancia de referencia (la típica medida en vivo, ver
        # docs/NUMEROS-MEDIDOS.md), un rms crudo "mediano" de siempre (~0.09,
        # la mediana real de los ~300 perfiles) tiene que seguir cayendo cerca
        # del medio de la escala, no saturado en 0 o en 1.
        mid = {"known": True, "rms": [0.09] * 20, "gain": mood.ENERGY_GAIN_REF}
        self.assertGreater(mood.energy(mid, 0), 0.3)
        self.assertLess(mood.energy(mid, 0), 0.7)


class TestBrightness(unittest.TestCase):
    def test_unknown_profile_is_neutral(self):
        self.assertEqual(mood.brightness({"known": False}), 0.5)

    def test_known_profile_averages_the_centroid(self):
        self.assertAlmostEqual(mood.brightness({"known": True, "cen": [0.2, 0.8]}), 0.5)


class TestMoodFor(unittest.TestCase):
    def test_it_has_the_five_keys(self):
        ev = mood.mood_for(["te amo"], {"known": False}, 0)
        self.assertEqual(set(ev), {"cmd", "valence", "energy", "bright", "known"})
        self.assertEqual(ev["cmd"], "mood")

    def test_known_flag_reflects_the_profile(self):
        self.assertFalse(mood.mood_for([], {"known": False}, 0)["known"])
        self.assertTrue(mood.mood_for([], {"known": True, "rms": [], "cen": []}, 0)["known"])


if __name__ == "__main__":
    unittest.main()
