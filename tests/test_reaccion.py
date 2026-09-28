"""Tanda 8 / slice "reaccion": el vidrio responde a `cut`/`cutf`/`hf` del `aud` y el
grano sucio tiene movimiento propio. Ver docs/tanda8-estado/reaccion.md.

Se testea el cableado (daemon → shell.qml → Crt.qml → crt.frag → .qsb), la tabla de
pace y las funciones puras de `shell/React.js` (con node, si está).
"""
import json
import os
import re
import shutil
import subprocess
import unittest

SHELL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shell")
QSB = "/usr/lib/qt6/bin/qsb"
NEW = ("cutDim", "backFlash", "fizz", "grain", "grainPhase")
KEYS = ("cutDepth", "cutFlash", "fizzAmt", "grainMove")


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


def pace_rows():
    block = re.search(r"crtPaceTable:\s*\(\{(.*?)\n    \}\)", read("shell.qml"), re.S).group(1)
    rows = dict(re.findall(r"^\s{8}(\w+):\s*\{(.*?)\n\s{8}\},", block, re.S | re.M))
    return {k: re.sub(r"//[^\n]*", "", v) for k, v in rows.items()}


class TestReaccionWiring(unittest.TestCase):
    def test_new_glass_uniforms_are_fed_by_crt_qml(self):
        # un uniform que el ShaderEffect no declara queda en 0 sin avisar
        frag = read("crt.frag")
        block = re.search(r"uniform buf \{(.*?)\};", frag, re.S).group(1)
        names = set(re.findall(r"^\s*(?:float|vec2|vec3|mat4)\s+(\w+);", block, re.M))
        names -= {"qt_Matrix", "qt_Opacity"}
        crt = read("Crt.qml")
        glass = re.search(r'fragmentShader: Qt\.resolvedUrl\("crt\.frag\.qsb"\)', crt)
        self.assertIsNotNone(glass)
        for n in NEW:
            self.assertIn(n, names)
            self.assertRegex(crt, r"property (?:real|variant) %s: crt\.%s" % (n, n + "Now" if n != "grainPhase" else n))

    @unittest.skipUnless(os.path.exists(QSB), "qsb no está instalado")
    def test_crt_qsb_has_the_reaction_uniforms(self):
        dump = subprocess.run([QSB, "--dump", os.path.join(SHELL, "crt.frag.qsb")],
                              capture_output=True, text=True, check=True).stdout
        for n in NEW:
            self.assertIn('"name": "%s"' % n, dump, "crt.frag.qsb no trae `%s`: recompilar" % n)

    def test_shell_reads_the_new_aud_fields(self):
        qml = read("shell.qml")
        self.assertIn("root.audHf = ev.hf || 0;", qml)
        self.assertIn("if (ev.cutf > 0) {", qml)
        self.assertIn("root.audCutGen++;", qml)
        self.assertIn("root.audCut = !!ev.cut;", qml)
        self.assertRegex(qml, r"readonly property bool crtCut:\s*audLive && audCut")

    def test_crt_uses_motion_durations_and_the_pace_row(self):
        crt = read("Crt.qml")
        self.assertIn('import "React.js" as React', crt)
        self.assertRegex(crt, r"React\.cutDim\(crt\.tubeTime, crt\.cutAt, crt\.ctl\.crtCut, crt\.ctl\.pace\.cutDepth,\s*"
                              r"Motion\.exitMs, Motion\.holdMs, Motion\.levelMs\)")
        self.assertIn("crt.ctl.pace.cutFlash", crt)
        self.assertIn("crt.ctl.pace.fizzAmt", crt)
        self.assertIn("crt.ctl.pace.grainMove", crt)
        # la fase del grano se acumula en QML, no es t·velocidad en el shader
        self.assertIn("React.grainAdvance(grainPhase", crt)
        self.assertNotRegex(read("crt.frag"), r"t \* \(0\.35 \+ 0\.9 \* grain\)")

    def test_reaction_keys_in_the_three_pace_rows_calm_to_wild(self):
        rows = pace_rows()
        self.assertEqual(set(rows), {"calm", "normal", "wild"})
        for key in KEYS:
            v = {}
            for name, body in rows.items():
                m = re.search(r"\b%s:\s*([\d.]+)" % key, body)
                self.assertIsNotNone(m, "falta %s en la fila %s" % (key, name))
                v[name] = float(m.group(1))
                self.assertGreater(v[name], 0, key)
                self.assertLessEqual(v[name], 1, key)
            self.assertLess(v["calm"], v["normal"], key)
            self.assertLess(v["normal"], v["wild"], key)


NODE = shutil.which("node")


@unittest.skipUnless(NODE, "node no está instalado")
class TestReactJs(unittest.TestCase):
    # `.pragma library` no es JS válido para node: se saca y se evalúa el resto
    def run_js(self, expr):
        src = read("React.js").replace(".pragma library", "")
        out = subprocess.run([NODE, "-e", src + "\nconsole.log(JSON.stringify(" + expr + "));"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def test_cut_dim_goes_down_in_exit_ms_and_releases_after_hold(self):
        v = self.run_js("[0, 0.07, 0.14, 1.0, 1.5 + 0.42, 1.0].map((a, i) =>"
                        " cutDim(10 + a, 10, i < 5, 0.55, 140, 1500, 420))")
        self.assertEqual(v[0], 0)
        self.assertAlmostEqual(v[1], 0.55 * 0.25)
        self.assertAlmostEqual(v[2], 0.55)
        self.assertAlmostEqual(v[3], 0.55)
        self.assertAlmostEqual(v[4], 0)          # pasado el tope: una pausa, no un corte
        self.assertEqual(v[5], 0)                # el corte terminó

    def test_back_flash_scales_with_force_and_dies_in_enter_ms(self):
        v = self.run_js("[backFlash(5, 5, 0.9, 0.3, 320), backFlash(5, 5, 0.3, 0.3, 320),"
                        " backFlash(5.32, 5, 0.9, 0.3, 320), backFlash(5, -1, 0.9, 0.3, 320)]")
        self.assertAlmostEqual(v[0], 0.27)
        self.assertAlmostEqual(v[1], 0.09)
        self.assertEqual(v[2], 0)
        self.assertEqual(v[3], 0)

    def test_fizz_ignores_the_background_hf(self):
        v = self.run_js("[0.08, 0.12, 0.5, 1.0].map(h => fizz(h, 0.7))")
        self.assertEqual(v[0], 0)
        self.assertEqual(v[1], 0)
        self.assertGreater(v[2], 0.1)
        self.assertAlmostEqual(v[3], 0.7)

    def test_grain_phase_accumulates_and_ignores_clock_jumps(self):
        v = self.run_js("(() => { let p = 0; for (let i = 0; i < 60; i++) p = grainAdvance(p, 1/60, 1);"
                        " return [p, grainAdvance(p, -3, 1), grainAdvance(p, 2, 1), grainAdvance(63.9, 0.2, 1)]; })()")
        self.assertAlmostEqual(v[0], 1.25, places=6)
        self.assertEqual(v[1], v[0])
        self.assertEqual(v[2], v[0])
        self.assertLess(v[3], 1)


if __name__ == "__main__":
    unittest.main()
