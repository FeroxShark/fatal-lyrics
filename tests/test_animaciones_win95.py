"""Los motivos de 2026-10-22: cascada, estela, pixelsort (ventanas de Win95) y julia, truchet, vitral.

No corren la placa: miran que cada una esté registrada en todos los lugares que pide la receta
de CLAUDE.md ("Cómo se agrega una animación") y que el .qsb de pixelsort sea de su .frag."""
import os
import re
import subprocess
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(__file__), "..")
SHELL = os.path.join(ROOT, "shell")
QSB = "/usr/lib/qt6/bin/qsb"
KINDS = ("cascada", "estela", "pixelsort", "julia", "truchet", "vitral")
SHADERS = ("pixelsort", "julia", "truchet", "vitral")


def read(path):
    with open(os.path.join(ROOT, path)) as f:
        return f.read()


class TestRegistro(unittest.TestCase):
    def test_estan_en_kinds_grupos_y_fit(self):
        shell = read("shell/shell.qml")
        kinds = re.search(r"motifKinds: \[(.*?)\]", shell, re.S).group(1)
        grupos = re.search(r"motifGroups: \(\{(.*?)\}\)", shell, re.S).group(1)
        fit = re.search(r"motifFit: \(\{(.*?)\}\)", shell, re.S).group(1)
        for k in KINDS:
            self.assertIn(f'"{k}"', kinds)
            self.assertEqual(grupos.count(f'"{k}"'), 1, f"{k} en un solo grupo")
            self.assertRegex(fit, rf"\b{k}:\s*\{{ e: [\d.]+, b: [\d.]+, t: [\d.]+ \}}")

    def test_el_loader_los_carga_y_los_alimenta_igual_que_a_membrana(self):
        motif = read("shell/Motif.qml")
        for k in KINDS:
            self.assertIn(f'motif.kind === "{k}" ? {k}C', motif)
            comp = re.search(rf"id: {k}C\s+(\w+) \{{(.*?)\n        \}}", motif, re.S)
            self.assertIsNotNone(comp, k)
            for prop in ("thump: motif.bass", "thumpAmt: motif.thumpAmt", "hat: motif.hat",
                         "mov: motif.density", "character: motif.character",
                         "tubeClock: motif.clock", "tick: motif.tick", "running: motif.spinning"):
                self.assertIn(prop, comp.group(2), f"{k} sin {prop}")

    def test_cada_motivo_vive_en_shell_y_usa_la_base_del_golpe(self):
        for k in KINDS:
            src = read(f"shell/{k.capitalize()}.qml")
            self.assertIn("ThumpBase", src)
            self.assertIsNone(re.search(r"^\s*Canvas\s*\{", src, re.M))


class TestShaders(unittest.TestCase):
    def test_el_qsb_existe(self):
        for k in SHADERS:
            self.assertTrue(os.path.exists(os.path.join(SHELL, f"{k}.frag.qsb")), k)

    @unittest.skipUnless(os.path.exists(QSB), "qsb de Qt no instalado")
    def test_el_qsb_es_de_la_version_del_frag(self):
        for k in SHADERS:
            with tempfile.TemporaryDirectory() as d:
                out = os.path.join(d, "p.qsb")
                subprocess.run([QSB, "--glsl", "100 es,120,150", "-o", out,
                                os.path.join(SHELL, f"{k}.frag")], check=True, capture_output=True)
                with open(out, "rb") as a, open(os.path.join(SHELL, f"{k}.frag.qsb"), "rb") as b:
                    self.assertEqual(a.read(), b.read(), f"recompilar: {k}.frag.qsb está viejo")

    def test_el_reloj_de_compas_no_se_hashea_crudo(self):
        # beatN llega en los miles: sin mod() el seno del hash pierde la precisión y da 0
        for k in ("julia", "truchet", "vitral"):
            src = read(f"shell/{k}.frag")
            self.assertIn("mod(", src, k)


if __name__ == "__main__":
    unittest.main()
