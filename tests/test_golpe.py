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
                        "kickSlowMs", "kickFastMs", "kickRise"):
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


if __name__ == "__main__":
    unittest.main()
