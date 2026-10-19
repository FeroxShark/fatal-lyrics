"""CRT: el golpe del bajo por bombo escalado por carácter, la densidad en el sorteo y sin
pantallas planas (Ferox 2026-10-19). Ver docs/TRAMPAS.md "El golpe del bajo".
Cableado por texto, como los demás tests de shell/; el banco visual es previews/golpe/."""
import glob
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


def lst(qml, name):
    m = re.search(name + r":\s*\[(.*?)\]", qml, re.S)
    return re.findall(r'"(\w+)"', re.sub(r"//[^\n]*", "", m.group(1)))


class TestSinPantallasPlanas(unittest.TestCase):
    def test_splitflap_and_testcard_are_out_of_the_draw(self):
        qml = read("shell.qml")
        kinds = lst(qml, r"readonly property var motifKinds")
        self.assertGreater(len(kinds), 15)
        groups = re.search(r"motifGroups:\s*\(\{(.*?)\}\)", qml, re.S).group(1)
        for flat in ("splitflap", "testcard"):
            self.assertNotIn(flat, kinds)
            self.assertNotIn('"%s"' % flat, groups)

    def test_no_fatal_lyrics_filler_text_in_the_crt(self):
        for f in glob.glob(os.path.join(SHELL, "*.qml")):
            with open(f, encoding="utf-8") as fh:
                for n, line in enumerate(fh, 1):
                    code = line.split("//")[0]
                    self.assertNotIn("FATAL LYRICS", code, "%s:%d" % (os.path.basename(f), n))


class TestGolpe(unittest.TestCase):
    def test_every_pace_row_has_the_kick_columns(self):
        qml = read("shell.qml")
        block = re.search(r"crtPaceTable:\s*\(\{(.*?)\n    \}\)", qml, re.S).group(1)
        block = re.sub(r"//[^\n]*", "", block)
        rows = re.findall(r"^\s{8}(\w+):\s*\{(.*?)\n\s{8}\},", block, re.S | re.M)
        self.assertEqual([r[0] for r in rows], ["calm", "normal", "wild"])
        for name, body in rows:
            for col in ("kickCam", "kickTube", "kickMotif", "kickHat", "kickAmpMin",
                        "kickSlowMs", "kickFastMs", "kickRise", "kickThump"):
                self.assertRegex(body, col + r":\s*[\d.]+", "%s sin %s" % (name, col))
        vals = {n: {k: float(v) for k, v in re.findall(r"(kick\w+):\s*([\d.]+)", b)} for n, b in rows}
        # calm < normal < wild en amplitud; la caída de un tema lento es más larga que la de uno agitado
        for col in ("kickCam", "kickTube", "kickMotif"):
            self.assertLess(vals["calm"][col], vals["normal"][col])
            self.assertLess(vals["normal"][col], vals["wild"][col])
        for v in vals.values():
            self.assertGreater(v["kickSlowMs"], v["kickFastMs"])
            self.assertLess(v["kickAmpMin"], 1.0)

    def test_hooks_for_the_new_audio_signals_default_to_zero_and_fall_back(self):
        qml = read("shell.qml")
        for decl in ("property int audKick: 0", "property real audHat: 0", "property real audNov: 0",
                     "property real songChar: 0"):
            self.assertIn(decl, qml)
        self.assertIn("audHatSeen ? audHat : audHf", qml)
        self.assertIn("kSeen ? ev.k : ev.b", qml)      # k si llega, si no b
        self.assertIn("ev.ht !== undefined", qml)
        self.assertIn('ev.cmd === "char"', qml)        # el carácter llega como evento suelto
        self.assertNotIn('ev["char"]', qml)

    def test_character_scales_amplitude_and_decay_and_falls_back_to_bpm_and_mood(self):
        qml = read("shell.qml")
        char = re.search(r"readonly property real crtCharacter:\s*\{(.*?)\n    \}", qml, re.S).group(1)
        self.assertIn("songChar > 0", char)
        self.assertIn("bpm - 70", char)
        self.assertIn("energy", char)
        self.assertIn("pace.kickAmpMin + (1 - pace.kickAmpMin) * crtCharacter", qml)
        self.assertIn("pace.kickSlowMs + (pace.kickFastMs - pace.kickSlowMs) * crtCharacter", qml)
        # ya no al cuadrado del flicker
        self.assertNotIn("flickerAmt", re.search(r"readonly property real kickKnob:.*", qml).group(0))

    def test_crt_pulses_camera_tube_and_motif_on_every_bass_hit(self):
        crt = read("Crt.qml")
        self.assertIn("function onBassGenChanged()", crt)
        self.assertIn("kickAnim.restart()", crt)
        self.assertIn("* (1 + ctl.kickCamAmt * kickPulse)", crt)
        self.assertIn("crt.kickPulse * crt.ctl.kickTubeAmt", crt)
        self.assertIn("bass: crt.ctl.bassGen", crt)
        self.assertIn("hat: crt.live ? crt.ctl.hatLevel : 0", crt)
        mo = read("Motif.qml")
        self.assertIn("motif.bassAmt * motif.bump", mo)
        self.assertIn("id: glints", mo)

    def test_scope_turns_follow_the_target_not_the_tween(self):
        mo = read("Motif.qml")
        turns = re.search(r"readonly property int turns:(.*?)\n\n", mo, re.S).group(1)
        self.assertIn("Math.abs(target - 1.5)", turns)
        self.assertNotIn("ratio", turns)


class TestDensidad(unittest.TestCase):
    def test_density_feeds_the_draw_the_hold_and_the_scene(self):
        qml = read("shell.qml")
        self.assertRegex(qml, r"readonly property real crtDensity: audLive \? Math\.min\(1, movFit\.mov \+ 0\.25 \* audNov\)")
        sound = re.search(r"function crtSoundNow\(\) \{(.*?)\n    \}", qml, re.S).group(1)
        self.assertIn("crtDensity", sound)
        self.assertIn("(1.12 - 0.24 * crtDensity)", qml)
        self.assertIn("function crtSceneFor(section, outro, n, focus, dens)", qml)
        self.assertEqual(len(re.findall(r"crtSceneFor\([^)]*crtDensity\)", qml)), 3)


SPRING = ("membrana", "cintas", "giroscopio")


class TestMotivosDeResorte(unittest.TestCase):
    """membrana, cintas y giroscopio (previews/crt-motifs, integrados 2026-10-19): un resorte por
    golpe de bombo (`ThumpBase.qml` + `Thump.js`), atados a las señales reales."""

    def test_registered_in_kinds_fit_and_groups(self):
        qml = read("shell.qml")
        kinds = lst(qml, r"readonly property var motifKinds")
        groups = re.search(r"motifGroups:\s*\(\{(.*?)\}\)", qml, re.S).group(1)
        fit = re.search(r"readonly property var motifFit:\s*\(\{(.*?)\}\)", qml, re.S).group(1)
        for k in SPRING:
            self.assertIn(k, kinds)
            self.assertIn('"%s"' % k, groups)
            m = re.search(k + r":\s*\{\s*e:\s*([\d.]+),\s*b:\s*([\d.]+),\s*t:\s*([\d.]+)", fit)
            self.assertIsNotNone(m, k)
            self.assertTrue(all(0.5 <= float(x) <= 0.8 for x in m.groups()), k)   # energía media-alta
        # todo kind del sorteo tiene perfil, y todo kind del sorteo está en algún grupo
        for k in kinds:
            self.assertRegex(fit, r"\b%s:" % k)
            self.assertIn('"%s"' % k, groups)

    def test_motif_dispatches_each_kind_and_wires_the_real_signals(self):
        mo = read("Motif.qml")
        for k in SPRING:
            self.assertIn('motif.kind === "%s" ? %sC' % (k, k), mo)
            body = re.search(r"\n        %s \{\n(.*?)\n        \}" % k.capitalize(), mo, re.S).group(1)
            for wire in ("thump: motif.bass", "thumpAmt: motif.thumpAmt", "hat: motif.hat",
                         "mov: motif.density", "character: motif.character", "tubeClock: motif.clock",
                         "rate: motif.rate", "running: motif.spinning"):
                self.assertIn(wire, body, k)
            self.assertTrue(os.path.exists(os.path.join(SHELL, "%s.frag.qsb" % k)), k)
            self.assertTrue(os.path.exists(os.path.join(SHELL, "%s.frag" % k)), k)
            self.assertIn("%s.frag.qsb" % k, read(k.capitalize() + ".qml"))

    def test_crt_feeds_amount_density_character_and_valence(self):
        crt = read("Crt.qml")
        self.assertIn("thumpAmt: crt.ctl.kickThumpAmt", crt)
        self.assertIn("density: crt.ctl.crtDensity", crt)
        self.assertIn("character: crt.ctl.crtCharacter", crt)
        self.assertIn("crtMood.valence", crt)
        qml = read("shell.qml")
        self.assertIn("pace.kickThump * kickKnob * bassMul", qml)

    def test_thump_base_counts_only_hits_after_birth_and_follows_character(self):
        tb = read("ThumpBase.qml")
        self.assertIn("Component.onCompleted: thumpSeen = thump", tb)     # el contador nace acumulado
        self.assertIn("character >= 0 ? E.clamp01(character)", tb)         # crtCharacter manda
        self.assertIn("hat >= 0 ? hat : hf", tb)                           # agudos reales, `hf` de respaldo
        # el golpe de bombo sale de `bass` (k, o b de respaldo, resuelto en shell.qml), no de `kick`
        self.assertNotIn("kickAt", tb)

    def test_spring_math_is_closed_form_and_character_scales_it(self):
        js = read("Thump.js")
        self.assertIn(".pragma library", js)
        self.assertIn("function params(temper, valence, bpm)", js)
        self.assertIn("function resp(p, age)", js)


if __name__ == "__main__":
    unittest.main()
