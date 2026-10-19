"""CRT, tanda de mejoras 2026-10-19 (movimiento y tubo): cableado por texto, como test_golpe.py."""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


def code(qml):
    return re.sub(r"//[^\n]*", "", qml)


class TestPuenteDeDibujo(unittest.TestCase):
    def test_motif_change_is_a_glitch_bridge_not_a_long_fade(self):
        b = code(read("Crt.qml"))
        m = re.search(r"id: motifBridge(.*?)\n    }\n", b, re.S).group(1)
        self.assertIn("Motion.bridgeMs / 2", m)
        self.assertIn("Motion.enterFastMs", m)
        self.assertNotIn("Motion.enterMs", m)
        self.assertNotIn("Motion.exitMs", m)
        # el golpe de tubo cae en el swap (urgent: con beat_lock no se difiere)
        self.assertRegex(m, r'crt\.hit\(0\.4, "motif", true\)')
        self.assertLess(m.index("motifShown = crt.motifKind"), m.index('"motif"'))

    def test_bridge_glitch_only_when_the_motif_is_on_screen(self):
        b = code(read("Crt.qml"))
        self.assertRegex(b, r"if \(crt\.motifSeen\)\s*crt\.hit\(0\.4")
        self.assertIn("visible: crt.motifSeen", b)


class TestSorteoSinRepetir(unittest.TestCase):
    def test_draw_skips_the_last_wall_motifs_and_falls_back_when_empty(self):
        q = code(read("shell.qml"))
        d = re.search(r"function crtMotifDraw\(i, taken\) \{(.*?)crtMotifRoll\+\+", q, re.S).group(1)
        self.assertIn("crtMotifRecent.indexOf(k) < 0", d)
        self.assertRegex(d, r"fresh\.length > 0 \? fresh : free\.length > 0 \? free : base")
        self.assertRegex(q, r"crtMotifRecentN: 5")

    def test_every_pick_is_recorded_and_the_keyword_does_not_repeat_the_screen(self):
        q = code(read("shell.qml"))
        self.assertRegex(q, r"crtMotifRecent = crtMotifRecent\.filter\(k => k !== pick\)")
        self.assertIn('wanted !== "" && taken.indexOf(wanted) < 0 && wanted !== kinds[i]', q)


class TestEmpujonDelDrop(unittest.TestCase):
    def test_drop_zoom_is_a_pace_column_with_a_floor_and_scales_by_character(self):
        q = read("shell.qml")
        block = code(re.search(r"crtPaceTable:\s*\(\{(.*?)\n    \}\)", q, re.S).group(1))
        rows = re.findall(r"^\s{8}(\w+):\s*\{(.*?)\n\s{8}\},", block, re.S | re.M)
        self.assertEqual([r[0] for r in rows], ["calm", "normal", "wild"])
        for name, body in rows:
            z = float(re.search(r"dropZoom:\s*([\d.]+)", body).group(1))
            mn = float(re.search(r"dropZoomMin:\s*([\d.]+)", body).group(1))
            self.assertGreaterEqual(mn, 0.5, name)
            self.assertLessEqual(mn, 1.0, name)
            self.assertGreater(z, 0.05, name)
        wild = dict(rows)["wild"]
        self.assertRegex(wild, r"dropZoom:\s*0\.12,\s*dropZoomMin:\s*1\.00")   # tanda 3: 12 % fijo
        self.assertRegex(code(q), r"dropZoomAmt: pace\.dropZoom\s*\* \(pace\.dropZoomMin \+ \(1 - pace\.dropZoomMin\) \* crtCharacter\)")

    def test_crt_uses_the_scaled_zoom_and_cue_starts_from_where_it_is(self):
        c = code(read("Crt.qml"))
        self.assertIn("to: 1 + crt.ctl.dropZoomAmt * crt.cam", c)
        self.assertNotIn("0.12 * crt.cam", c)
        anim = re.search(r"id: cueAnim(.*?)\n    }", c, re.S).group(1)
        self.assertNotRegex(anim, r"\bfrom:")
        self.assertIn("1 + 0.75 * crt.ctl.dropZoomAmt", c)


class TestVidrio(unittest.TestCase):
    def test_grain_is_30hz_2px_cells_and_the_kick_has_no_11hz_jitter(self):
        f = code(read("crt.frag"))
        self.assertIn("hash21(floor(fc * 0.5) + floor(t * 30.0))", f)
        self.assertNotIn("floor(t * 60.0)", f)
        self.assertNotIn("floor(t * 11.0)", f)
        self.assertNotIn("floor(t * 24.0)", f)
        self.assertIn("col *= 1.0 + pulse * 0.15;", f)


if __name__ == "__main__":
    unittest.main()


class TestTarjetaSuaveAlSaltear(unittest.TestCase):
    def test_intro_start_soft_cierra_la_tarjeta_vieja(self):
        # saltear de tema antes de introCardSoftMs dejaba la tarjeta en "card" sin plazo
        qml = code(read("shell.qml"))
        body = re.search(r"function crtIntroStart\(\) \{(.*?)\n    \}\n", qml, re.S).group(1)
        m = re.search(r"if \(!crtScreenOff\) \{(.*?)return;", body, re.S).group(1)
        self.assertRegex(m, r'if \(crtIntroPhase !== ""\)\s*crtIntroEnd\(\);')


class TestCorteDeLetraAlCambiarDeTema(unittest.TestCase):
    def test_linea_vacia_deja_un_quemado_con_exitms(self):
        # el `clear` no sube crtSerial: sin esto la letra se cortaba seca
        b = code(read("Crt.qml"))
        h = re.search(r"onNoLyricChanged: \{(.*?)\n    \}\n", b, re.S).group(1)
        self.assertIn("ghostText = lastShownText", h)
        self.assertIn("ghostCutAnim.restart()", h)
        a = re.search(r"id: ghostCutAnim(.*?)\n    \}\n", b, re.S).group(1)
        self.assertIn("Motion.exitMs", a)
        self.assertIn("Easing.InQuad", a)
        self.assertRegex(b, r"visible: crt\.ghostFade > 0\.01 && \(crt\.showsText \|\| crt\.ghostCutOn\)")
