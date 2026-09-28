"""Tanda 8 / slice "senales": corte seco (`cut`/`cutf`) y flujo de agudos (`hf`)
en el evento `aud`. Ver docs/tanda8-estado/senales.md para el porqué de cada uno.

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


def mix(*tones):
    """Suma sample-a-sample varios (freq, amp) puros, n=N."""
    out = [0.0] * N
    for freq, amp in tones:
        for i in range(N):
            out[i] += amp * math.sin(2 * math.pi * freq * i / RATE)
    return pcm(out)


def silence():
    return pcm([0.0] * N)


def sustained(a, freq, amp, seconds, t0=0.0, phase0=0):
    """Tono de FASE CONTINUA (no `tone()`, que arranca de la muestra 0 en cada
    llamada y da bloques bit-idénticos: flujo espectral trivialmente 0 sin
    importar si la normalización de abajo está bien o mal). Simula sostenido
    real: cada bloque sigue la fase donde dejó el anterior. Devuelve (t final,
    índice de muestra final, último `ev`). Mismo patrón que `sustained()` en
    `test_movimiento.py` (ese slice pisó el mismo tipo de bug)."""
    i0 = phase0
    t = t0
    ev = None
    for _ in range(int(seconds / DT)):
        blk = pcm([amp * math.sin(2 * math.pi * freq * (i0 + i) / RATE) for i in range(N)])
        ev = a.feed(blk, t)
        i0 += N
        t += DT
    return t, i0, ev


class CutTests(unittest.TestCase):
    """`cut`/`cutf`: silencio abrupto tras sonar fuerte, con histéresis."""

    def settle_loud(self, a, blocks=20, freq=220.0, amp=0.6):
        """Deja el analizador con `an.peak` calibrado y `loud_at` fresco."""
        t = 0.0
        ev = None
        for i in range(blocks):
            ev = a.feed(tone(freq, amp), t)
            t += DT
        return t, ev

    def test_a_dry_cut_of_200ms_is_flagged_and_the_return_has_force(self):
        a = audio.AudioAnalyzer()
        t, ev = self.settle_loud(a)
        self.assertEqual(ev["cut"], 0)
        # 200 ms de silencio total: 6-7 bloques
        saw_cut = False
        for _ in range(7):
            ev = a.feed(silence(), t)
            t += DT
            saw_cut = saw_cut or ev["cut"] == 1
        self.assertTrue(saw_cut, "un corte de ~200ms tiene que verse como cut=1 en algún bloque")
        # vuelve fuerte: el golpe de vuelta tiene que traer fuerza > 0 una vez
        ev = a.feed(tone(220.0, 0.6), t)
        self.assertEqual(ev["cut"], 0)
        self.assertGreater(ev["cutf"], 0.0)
        self.assertLessEqual(ev["cutf"], 1.0)
        # y no se repite en el bloque siguiente, sigue sonando
        t += DT
        ev = a.feed(tone(220.0, 0.6), t)
        self.assertEqual(ev["cutf"], 0.0)

    def test_a_blip_shorter_than_the_enter_time_does_not_flag_a_cut(self):
        a = audio.AudioAnalyzer()
        t, _ = self.settle_loud(a)
        # un solo bloque de silencio (32ms, bajo CUT_ENTER_S=0.10s) y vuelve
        ev = a.feed(silence(), t)
        t += DT
        self.assertEqual(ev["cut"], 0)
        ev = a.feed(tone(220.0, 0.6), t)
        self.assertEqual(ev["cut"], 0)
        self.assertEqual(ev["cutf"], 0.0, "no hubo corte confirmado, no hay golpe de vuelta que anunciar")

    def test_an_energy_valley_that_never_gets_near_silence_is_not_a_cut(self):
        """Distinto del `quiet` de sección: un pasaje que baja de volumen pero
        sigue sonando (level por encima de CUT_LOW) no es un corte seco."""
        a = audio.AudioAnalyzer()
        t, _ = self.settle_loud(a)
        for _ in range(60):     # ~2s de un valle audible, no silencio
            ev = a.feed(tone(220.0, 0.10), t)
            t += DT
            self.assertEqual(ev["cut"], 0)

    def test_silence_that_was_never_preceded_by_loud_is_not_a_cut(self):
        """Arranque del tema, o una pausa larga: sin `loud_at` reciente no hay
        "corte" que declarar — es sólo silencio."""
        a = audio.AudioAnalyzer()
        t = 0.0
        for _ in range(60):
            ev = a.feed(silence(), t)
            t += DT
            self.assertEqual(ev["cut"], 0)
            self.assertEqual(ev["cutf"], 0.0)

    def test_a_cut_long_after_the_last_loud_moment_does_not_fire(self):
        """CUT_RECENT_S: si pasó mucho desde que sonó fuerte (un fade-out real,
        una sección quieta larga), un silencio después NO es "el corte de este
        golpe" — sería inventar un evento. Se prueba directo sobre `_cut_step`:
        armar esta secuencia exacta con tonos reales depende de cómo decae
        `an.peak`, que es un detalle de implementación aparte."""
        a = audio.AudioAnalyzer()
        cut, cutf = a._cut_step(0.8, 0.0)          # sonó fuerte en t=0
        self.assertFalse(cut)
        stale_t = audio.CUT_RECENT_S + 1.0
        cut, cutf = a._cut_step(0.10, stale_t)     # zona muerta, mucho después: loud_at ya viejo
        self.assertFalse(cut)
        # dos golpes de silencio separados más que CUT_ENTER_S: si sólo mirara el
        # tiempo bajo, esto ya alcanzaría para declarar corte
        cut, cutf = a._cut_step(0.02, stale_t + 0.01)
        self.assertFalse(cut)
        cut, cutf = a._cut_step(0.02, stale_t + 0.01 + audio.CUT_ENTER_S + 0.01)
        self.assertFalse(cut, "loud_at está viejo: este silencio no es el corte de un golpe reciente")
        self.assertEqual(cutf, 0.0)

    def test_fields_are_json_bounded(self):
        import json
        a = audio.AudioAnalyzer()
        ev = a.feed(tone(220.0, 0.5), 0.0)
        json.dumps(ev)
        self.assertIn(ev["cut"], (0, 1))
        self.assertGreaterEqual(ev["cutf"], 0.0)
        self.assertLessEqual(ev["cutf"], 1.0)


class SpectralFluxTests(unittest.TestCase):
    def test_a_steady_tone_has_no_flux_after_the_first_block(self):
        spec_a = audio.power_spectrum([0.3 * math.sin(2 * math.pi * 220 * i / RATE) for i in range(N)])
        spec_b = audio.power_spectrum([0.3 * math.sin(2 * math.pi * 220 * i / RATE) for i in range(N)])
        self.assertEqual(audio.spectral_flux_band(spec_b, spec_a, RATE), 0.0)

    def test_a_new_treble_tone_on_top_of_bass_raises_flux(self):
        bass = [0.3 * math.sin(2 * math.pi * 100 * i / RATE) for i in range(N)]
        bass_plus_treble = [b + 0.3 * math.sin(2 * math.pi * 3000 * i / RATE) for i, b in enumerate(bass)]
        spec_before = audio.power_spectrum(bass)
        spec_after = audio.power_spectrum(bass_plus_treble)
        self.assertGreater(audio.spectral_flux_band(spec_after, spec_before, RATE), 0.0)

    def test_no_previous_spectrum_is_zero(self):
        spec = audio.power_spectrum([0.3] * N)
        self.assertEqual(audio.spectral_flux_band(spec, None, RATE), 0.0)


class HfTests(unittest.TestCase):
    """`hf`: pulso de agudos que cambian, independiente de que el bajo esté sonando."""

    def test_a_constant_bass_alone_settles_near_zero_hf(self):
        a = audio.AudioAnalyzer()
        t, ev = 0.0, None
        for _ in range(30):
            ev = a.feed(tone(80.0, 0.6), t)
            t += DT
        self.assertLess(ev["hf"], 0.1, "bajo constante, sin nada nuevo arriba: no debería \"parpadear\"")

    def test_a_treble_onset_over_a_steady_bass_pulses_hf(self):
        a = audio.AudioAnalyzer()
        t = 0.0
        for _ in range(20):     # asienta el bajo solo
            a.feed(tone(80.0, 0.6), t)
            t += DT
        peak_hf = 0.0
        for _ in range(6):      # el platillo/onset entra unos bloques
            ev = a.feed(mix((80.0, 0.6), (4000.0, 0.4)), t)
            t += DT
            peak_hf = max(peak_hf, ev["hf"])
        self.assertGreater(peak_hf, 0.3, "un onset de agudos tiene que levantar hf, no sólo el bajo")

    def test_hf_decays_after_the_onset_passes(self):
        a = audio.AudioAnalyzer()
        t = 0.0
        for _ in range(20):
            a.feed(tone(80.0, 0.6), t)
            t += DT
        peak_hf = 0.0
        for _ in range(4):
            ev = a.feed(mix((80.0, 0.6), (4000.0, 0.4)), t)
            t += DT
            peak_hf = max(peak_hf, ev["hf"])
        # el platillo se corta, vuelve a ser sólo el bajo constante
        for _ in range(25):
            ev = a.feed(tone(80.0, 0.6), t)
            t += DT
        self.assertLess(ev["hf"], peak_hf * 0.3, "tiene que bajar con cola, no quedarse prendido")

    def test_a_sustained_in_band_tone_does_not_stay_pinned_near_one(self):
        """Bug real (corregido en este slice, ver senales.md): con la
        normalización vieja (pico propio que decae, `spectral_flux_band`), un
        tono sostenido de FASE CONTINUA hace decaer el pico hasta la fuga
        espectral del propio Hann, y a partir de ahí cualquier bloque
        normalizaba cerca de 1.0 — `hf` quedaba clavado en ~0.88 en vez de caer
        a 0 (el caso de cuerdas nerviosas tipo Vivaldi, energía sostenida sin
        ataques nuevos). Usa `sustained()`, NO `tone()`: `tone()` reinicia la
        fase en la muestra 0 en cada llamada y da bloques bit-idénticos, flujo
        espectral 0 por construcción — el test pasaría igual con el bug."""
        a = audio.AudioAnalyzer()
        _, _, ev = sustained(a, freq=220.0, amp=0.7, seconds=8.0)
        self.assertLess(ev["hf"], 0.15, "tono sostenido sin ataques nuevos: hf tiene que caer, no quedar clavado")

    def test_a_treble_onset_after_the_track_gets_quiet_still_pulses_hf(self):
        """Bug real (corregido en este slice): con el pico que decae, un pasaje
        fuerte deja el pico viejo alto un rato; si el tema baja de volumen
        (`mf` después de `ff`) un onset nuevo pero flojo no llega a superarlo y
        el detector queda sordo justo cuando más hace falta. Con
        `spectral_flux_ratio` (normaliza contra la energía DE ESE BLOQUE) el
        onset flojo tiene que pulsar igual."""
        a = audio.AudioAnalyzer()
        t = 0.0
        for _ in range(15):     # pasaje fuerte: platillo grande sobre bajo fuerte
            a.feed(mix((80.0, 0.9), (4000.0, 0.7)), t)
            t += DT
        for _ in range(20):     # baja de volumen: sólo un bajo flojo, constante
            ev = a.feed(tone(80.0, 0.1), t)
            t += DT
        quiet_baseline = ev["hf"]
        peak_hf = 0.0
        for _ in range(6):      # onset de agudos flojo, sobre el bajo flojo
            ev = a.feed(mix((80.0, 0.1), (4000.0, 0.08)), t)
            t += DT
            peak_hf = max(peak_hf, ev["hf"])
        self.assertGreater(peak_hf, quiet_baseline + 0.2,
                            "el detector no puede quedar sordo tras bajar el volumen")

    def test_hf_is_json_bounded(self):
        import json
        a = audio.AudioAnalyzer()
        ev = a.feed(tone(1000.0, 0.5), 0.0)
        json.dumps(ev)
        self.assertGreaterEqual(ev["hf"], 0.0)
        self.assertLessEqual(ev["hf"], 1.0)


if __name__ == "__main__":
    unittest.main()
