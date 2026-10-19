"""Letra en el tubo (tanda CRT 2026-10-19): renglones centrados de `shell/Rows.js` en las líneas
largas de allMode. Cuentas puras con node si está, y el cableado en `Crt.qml` / `WordSlot.qml`."""
import json
import os
import re
import shutil
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


@unittest.skipUnless(shutil.which("node"), "node no está instalado")
class TestRowsJs(unittest.TestCase):
    def run_js(self, expr):
        src = read("Rows.js").replace(".pragma library", "")
        out = subprocess.run(["node", "-e", src + "\nconsole.log(JSON.stringify(" + expr + "))"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def pick(self, text, w, h):
        words = json.dumps(text.split())
        short = min(w, h)
        return self.run_js(f"pick({words}, {w - 2 * round(short * 0.06)}, {h - 2 * round(short * 0.06)}, "
                           f"{short * 0.46}, 0.6, 0.94)")

    def test_two_words_or_fewer_stay_stacked(self):
        self.assertEqual(self.pick("Hello world", 1920, 1080), [[0], [1]])
        self.assertEqual(self.pick("Hi", 1920, 1080), [[0]])

    def test_long_line_on_wide_screen_gets_rows(self):
        rows = self.pick("Just as you take my hand and write my number down tonight", 1920, 1080)
        self.assertLess(len(rows), 12)
        self.assertEqual([i for r in rows for i in r], list(range(12)))

    def test_every_word_appears_once_and_in_order(self):
        for text in ("a b c", "I want to break free from your lies", "x " * 20):
            n = len(text.split())
            rows = self.pick(text, 1920, 1080)
            self.assertEqual([i for r in rows for i in r], list(range(n)), text)

    def test_rows_are_balanced_not_a_stub(self):
        # el codicioso solo dejaba "you" colgando entre dos renglones llenos
        rows = self.run_js('split(["Just","as","you","take","my","hand"], 3).rows')
        self.assertEqual(rows, [[0, 1], [2, 3], [4, 5]])

    def test_tall_screen_keeps_stacked_when_stacking_is_not_worse(self):
        # 1080x1920: el ancho manda, apilar ya es lo mejor
        rows = self.pick("Come back in focus again", 1080, 1920)
        self.assertEqual(rows, [[i] for i in range(5)])

    def test_rows_enlarge_the_letter_on_wide_screen(self):
        # misma cuenta que el banco: el reparto elegido sube el tamaño estimado >= 25 %
        n = 12
        est = self.run_js(
            "(() => { const w = " + json.dumps(("x" * 4 + " ") * 11 + "xxxx") + ".split(' ');"
            "const rows = pick(w, 1790, 950, 496, 0.6, 0.94);"
            "const st = estimate(w.length, 4, 1790, 950, 496, 0.6, 0.94);"
            "const s = split(w, rows.length);"
            "return [estimate(rows.length, s.maxChars, 1790, 950, 496, 0.6, 0.94) / st, rows.length]; })()")
        self.assertGreater(est[0], 1.25)
        self.assertLess(est[1], n)


class TestCableado(unittest.TestCase):
    def setUp(self):
        self.crt = re.sub(r"//[^\n]*", "", read("Crt.qml"))
        self.slot = re.sub(r"//[^\n]*", "", read("WordSlot.qml"))

    def test_measure_uses_the_rows_not_one_word_per_line(self):
        self.assertIn('import "Rows.js" as Rows', self.crt)
        self.assertRegex(self.crt, re.compile(r"id: measure.*?crt\.lyricRows", re.S))
        self.assertNotIn('crt.myWords.join("\\n")', self.crt)

    def test_rows_only_with_whole_words(self):
        # el director y el modo de calidad baja siguen apilados: un solo reparto, el de siempre
        self.assertRegex(self.crt, r"lyricRows:\s*wholeWordsOn\s*\?\s*Rows\.pick\(")
        self.assertIn("myWords.map((w, i) => [i])", self.crt)

    def test_slots_keep_the_line_index(self):
        # el índice del Repeater anidado es el del renglón: dueFrac y burnStep quieren el de la línea
        body = self.crt[self.crt.index("id: wholeSlot"):]
        body = body[:body.index("onOverburnHit")]
        self.assertIn("crt.dueFrac(modelData)", body)
        self.assertNotIn("dueFrac(index)", body)
        self.assertIn("fitWidth: true", body)

    def test_reveal_clock_is_fast_only_while_words_are_pending(self):
        self.assertRegex(self.crt, r"Timer\s*\{\s*interval:\s*crt\.reveal\s*<\s*1\s*\?\s*33\s*:\s*80")

    def test_wordslot_fits_its_width_only_when_asked(self):
        self.assertRegex(self.slot, r"width:\s*fitWidth\s*\|\|\s*!parent\s*\?\s*label\.implicitWidth\s*:\s*parent\.width")

    def test_tracking_is_proportional_to_the_measured_body(self):
        # una sola regla (0.03 em del cuerpo que mide `measure`), nada de 3 px fijos
        self.assertRegex(self.crt, r"lyricTrackingEm:\s*0\.03")
        self.assertRegex(self.crt, r"lyricLetterSpacing:\s*measure\.fontInfo\.pixelSize\s*\*\s*lyricTrackingEm")
        # primera pasada sin tracking para sacar el cuerpo del que sale el de `measure`
        self.assertRegex(self.crt, re.compile(r"id: measure0.*?id: measure\b.*?measure0\.fontInfo\.pixelSize\s*\*\s*crt\.lyricTrackingEm", re.S))
        body = self.crt[self.crt.index("id: wholeSlot"):]
        self.assertIn("letterSpacing: crt.lyricLetterSpacing", body[:body.index("onOverburnHit")])
        self.assertIn("letterSpacing: crt.lyricLetterSpacing", self.crt[self.crt.index("id: slot"):])


if __name__ == "__main__":
    unittest.main()
