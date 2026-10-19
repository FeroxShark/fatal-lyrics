"""CRT, tanda de mejoras 2026-10-19 (vidrio del tubo): contorno, reflejo y convergencia, por texto sobre crt.frag."""
import os
import re
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")


def read(name, mode="r"):
    with open(name if os.path.isabs(name) else os.path.join(SHELL, name), mode, **({} if "b" in mode else {"encoding": "utf-8"})) as f:
        return f.read()


def code(src):
    return re.sub(r"//[^\n]*", "", src)


class TestVidrioDelTubo(unittest.TestCase):
    def setUp(self):
        self.f = code(read("crt.frag"))

    def test_outline_is_a_rounded_antialiased_box_not_a_step(self):
        f = self.f
        self.assertNotIn("step(vec2(0.0), uv)", f)
        self.assertIn("sdf = length(max(qb, 0.0))", f)
        # un píxel de PANTALLA de borde, no la escalera de 1 px del step()
        self.assertIn("aaw = max(kx, ky) / sSide", f)
        self.assertIn("tubeCut = clamp(0.5 - sdf / aaw", f)

    def test_no_inverted_smoothstep_edges(self):
        # GLSL deja indefinido smoothstep(e0, e1, x) con e0 >= e1
        for m in re.finditer(r"smoothstep\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,", self.f):
            self.assertLess(float(m.group(1)), float(m.group(2)), m.group(0))

    def test_reflection_and_rim_die_with_the_dry_cut(self):
        f = self.f
        self.assertIn("col += refl * (1.0 - cutDim) * tubeCut;", f)
        # el reflejo va después del corte y del golpe de vuelta
        self.assertLess(f.index("col *= 1.0 - cutDim;"), f.index("col += refl"))

    def test_convergence_grows_outwards_and_follows_the_knob(self):
        f = self.f
        self.assertIn("float conv = 0.3 + 0.7 * 0.5 * dot(cq, cq);", f)
        self.assertIn("chroma * 0.0016 * conv + glitch * 0.007", f)
        # en pantalla, no en el uv deformado: las bandas del glitch no la arrastran
        self.assertIn("cq = qt_TexCoord0 * 2.0 - 1.0", f)

    def test_qsb_matches_the_source(self):
        qsb = "/usr/lib/qt6/bin/qsb"
        if not os.path.exists(qsb):
            self.skipTest("sin qsb")
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "crt.frag.qsb")
            subprocess.run([qsb, "--glsl", "100 es,120,150", "-o", out, os.path.join(SHELL, "crt.frag")],
                           check=True, capture_output=True)
            self.assertEqual(read("crt.frag.qsb", "rb"), read(out, "rb"),
                             "crt.frag.qsb viejo: recompilar con el comando del header de crt.frag")


if __name__ == "__main__":
    unittest.main()
