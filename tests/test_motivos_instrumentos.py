"""radar, scope, ekg, rain y eye: sin Canvas, con su shader compilado, y cableados en Motif.qml."""
import os
import re
import unittest

SHELL = os.path.join(os.path.dirname(__file__), "..", "shell")


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


class TestInstrumentos(unittest.TestCase):
    def test_none_paints_on_the_cpu(self):
        for name in ("Radar.qml", "Rain.qml", "Scope.qml", "Ekg.qml", "Eye.qml"):
            self.assertIsNone(re.search(r"^\s*Canvas\s*\{", read(name), re.M), name)

    def test_motif_has_no_inline_canvas_left_for_them(self):
        motif = read("Motif.qml")
        for kind, comp in (("radar", "Radar"), ("rain", "Rain"), ("scope", "Scope"), ("ekg", "Ekg")):
            self.assertRegex(motif, r"id: %sC\n\s*\n?\s*%s \{" % (kind, comp))

    def test_every_shader_they_load_is_compiled(self):
        for qml, frags in (("Radar.qml", ["radar"]), ("Rain.qml", ["rain"]), ("Eye.qml", ["eye"]),
                           ("Scope.qml", ["scopegrid"]), ("Ekg.qml", ["scopegrid"])):
            for f in frags:
                self.assertIn('"%s.frag.qsb"' % f, read(qml))
                self.assertTrue(os.path.exists(os.path.join(SHELL, f + ".frag.qsb")), f)

    def test_scope_and_ekg_step_from_the_motif_clock(self):
        # el reloj del motivo, no un Timer propio: `pace`, pausa y banco valen igual
        for name in ("Scope.qml", "Ekg.qml"):
            src = read(name)
            self.assertIn("onClockChanged: if (running && visible) step()", src, name)
            self.assertNotIn("Timer {", src, name)

    def test_ekg_hr_is_the_song_tempo(self):
        self.assertIn("Math.round(60000 / Math.max(m.beatMs, 1))", read("Ekg.qml"))


if __name__ == "__main__":
    unittest.main()
