"""Tanda 8 / slice "mystify-señales": `cut` y `hf` llegan a Mystify.

Ver docs/tanda8-estado/mystify.md. Cableado QML (`cut`, `hf`), el shader compilado con su
uniform nuevo, la copia del banco sin deriva, y con node si está las dos cuentas puras de
`shell/Mystify.js` (agarre y atraso de fase del corte seco).
"""
import json
import os
import re
import shutil
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")
BANCO = os.path.join(ROOT, "previews", "crt-motifs")
QSB = "/usr/lib/qt6/bin/qsb"


def read(name, base=SHELL):
    with open(os.path.join(base, name), encoding="utf-8") as f:
        return f.read()


class TestCableado(unittest.TestCase):
    def test_mystify_block_gets_cut_and_hf(self):
        m = re.search(r"id: mystifyC\s*Mystify\s*\{(.*?)\n        \}", read("Motif.qml"), re.S)
        self.assertIsNotNone(m)
        for line in ("rate: motif.rate", "cut: motif.cut", "hf: motif.hf"):
            self.assertIn(line, m.group(1))

    def test_mystify_does_not_shadow_the_base_clock(self):
        src = re.sub(r"//[^\n]*", "", read("Mystify.qml"))
        self.assertNotRegex(src, r"function\s+(rate|movOff|lt)\s*\(")
        # (el `property real lt` del ShaderEffect, a 8 espacios, es el uniform del shader)
        self.assertNotRegex(src, r"(?m)^    (readonly )?property\s+\w+\s+(rate|movOff|lt)\b")
        # el corte atrasa la fase, no escala el reloj: nada de `clock * rate`
        self.assertNotRegex(src, r"(clock|lt)\s*\*\s*rate|rate\s*\*\s*(clock|lt)")

    def test_hf_goes_through_the_tube_curve_and_the_shader_gets_the_held_phase(self):
        src = read("Mystify.qml")
        self.assertIn("React.fizz(m.hf, 1)", src)
        self.assertIn("property real lt: m.ltShow", src)

    def test_no_cut_yet_means_not_held(self):
        # el arranque es "ya volvió hace mucho": con backAt/thawAt en 1e9 el dibujo nacía agarrado
        # y la costura del loop del banco daba media 16
        src = read("Mystify.qml")
        self.assertRegex(src, r"property real backAt: -1e6")
        self.assertRegex(src, r"property real thawAt: -1e6")

    def test_no_animation_or_behavior_in_the_motif(self):
        # el banco exige que cada cuadro sea función pura del reloj y de las estampas
        src = re.sub(r"//[^\n]*", "", read("Mystify.qml"))
        self.assertNotRegex(src, r"\b(Behavior|NumberAnimation|SequentialAnimation|Timer)\b")


class TestShader(unittest.TestCase):
    def test_frag_declares_hf(self):
        self.assertRegex(read("mystify.frag"), r"float hf;")

    @unittest.skipUnless(os.path.exists(QSB), "qsb no está instalado")
    def test_qsb_is_in_sync_with_its_source(self):
        dump = subprocess.run([QSB, "--dump", os.path.join(SHELL, "mystify.frag.qsb")],
                              capture_output=True, text=True, check=True).stdout
        src = read("mystify.frag")
        block = re.search(r"uniform buf \{(.*?)\};", src, re.S).group(1)
        names = re.findall(r"^\s*(?:mat4|vec[234]|float)\s+(\w+);", block, re.M)
        self.assertIn("hf", names)
        for u in names:
            self.assertIn(f'"name": "{u}"', dump, f"mystify.frag.qsb no trae `{u}`: recompilar")


class TestBancoSinDeriva(unittest.TestCase):
    """`shell/` es la fuente; el banco tiene copias (`./sync-shell.sh`)."""

    def test_qml_copies_match_up_to_imports(self):
        for name in ("Mystify", "MotifBase"):
            src = re.sub(r'import "([A-Za-z]*)\.js"', r'import "../\1.js"', read(name + ".qml"))
            self.assertEqual(src, read(name + ".qml", os.path.join(BANCO, "motifs")),
                             f"motifs/{name}.qml difiere de shell/: correr previews/crt-motifs/sync-shell.sh")

    def test_js_and_shader_copies_are_identical(self):
        for name in ("Mystify.js", "React.js"):
            self.assertEqual(read(name), read(name, BANCO), name)
        self.assertEqual(read("mystify.frag"), read("mystify.frag", os.path.join(BANCO, "motifs")))
        for name in ("mystify.frag.qsb",):
            with open(os.path.join(SHELL, name), "rb") as a, \
                    open(os.path.join(BANCO, "motifs", name), "rb") as b:
                self.assertEqual(a.read(), b.read(), name)


@unittest.skipUnless(shutil.which("node"), "node no está instalado")
class TestMystifyJs(unittest.TestCase):
    def run_js(self, expr):
        src = read("Mystify.js").replace(".pragma library", "")
        out = subprocess.run(["node", "-e", src + "\nconsole.log(JSON.stringify(" + expr + "))"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def test_hold_is_zero_before_and_after_a_cut_and_one_in_the_middle(self):
        # llegó en 100 s, todavía no volvió (backAt = 1e9)
        self.assertEqual(self.run_js("hold(99, 100, 1e9, 0.12, 0.32)"), 0)
        self.assertEqual(self.run_js("hold(100, 100, 1e9, 0.12, 0.32)"), 0)
        self.assertEqual(self.run_js("hold(100.12, 100, 1e9, 0.12, 0.32)"), 1)
        self.assertEqual(self.run_js("hold(105, 100, 1e9, 0.12, 0.32)"), 1)
        # volvió en 100.3: suelta y llega a 0 EXACTO (no una cola: cierra la costura del loop)
        self.assertEqual(self.run_js("hold(100.3, 100, 100.3, 0.12, 0.32)"), 1)
        self.assertEqual(self.run_js("hold(100.62, 100, 100.3, 0.12, 0.32)"), 0)
        self.assertEqual(self.run_js("hold(115, 100, 100.3, 0.12, 0.32)"), 0)

    def test_hold_is_monotone_on_the_way_out_and_continuous_for_a_short_cut(self):
        ys = self.run_js("[0, 0.05, 0.1, 0.2, 0.3, 0.32].map(d => hold(100.3 + d, 100, 100.3, 0.12, 0.32))")
        self.assertEqual(ys, sorted(ys, reverse=True))
        # un corte de 60 ms (más corto que la subida) suelta desde donde llegó, sin salto
        up = self.run_js("hold(100.06, 100, 100.06, 0.12, 0.32)")
        just_after = self.run_js("hold(100.0601, 100, 100.06, 0.12, 0.32)")
        self.assertTrue(0 < up < 1)
        self.assertAlmostEqual(up, just_after, places=2)

    def test_the_initial_state_before_any_cut_is_neither_held_nor_lagging(self):
        # cutAt/backAt/freezeAt/thawAt = -1e6 / -1e6 / 0 / -1e6, como los deja Mystify.qml
        self.assertEqual(self.run_js("hold(3000, -1e6, -1e6, 0.12, 0.32)"), 0)
        self.assertEqual(self.run_js("lag(3000, 0, -1e6, 0.6)"), 0)

    def test_lag_grows_while_cut_holds_then_stops_and_is_capped(self):
        self.assertEqual(self.run_js("lag(50, 50, 1e9, 0.6)"), 0)
        self.assertAlmostEqual(self.run_js("lag(50.3, 50, 1e9, 0.6)"), 0.3)
        # volvió en 50.4: el atraso se queda en 0.4 aunque la fase siga corriendo
        self.assertAlmostEqual(self.run_js("lag(60, 50, 50.4, 0.6)"), 0.4)
        # una pausa larga no deja al polígono atrás más que `cap`
        self.assertEqual(self.run_js("lag(80, 50, 1e9, 0.6)"), 0.6)
        self.assertEqual(self.run_js("lag(80, 50, 79, 0.6)"), 0.6)
        # nunca negativo (fase anterior a la estampa)
        self.assertEqual(self.run_js("lag(49, 50, 1e9, 0.6)"), 0)

    def test_lag_uses_the_monotone_phase_so_the_wrap_never_takes_the_long_way(self):
        # el corte cruza el 15 del loop: con la fase envuelta 14.8 → 0.2 daría -14.6
        self.assertAlmostEqual(self.run_js("lag(60.2, 59.8, 1e9, 0.6)"), 0.4)


if __name__ == "__main__":
    unittest.main()
