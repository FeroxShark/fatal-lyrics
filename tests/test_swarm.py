"""Swarm pasa a shader por instancias (r10, candidata 1): `swarm.vert` + `swarm.frag`.

Cableado QML sin animaciones, los dos shaders con el MISMO bloque de uniforms (std140: si
difieren, Qt lee basura sin avisar), los .qsb al día, y la copia del banco sin deriva.
"""
import os
import re
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")
BANCO = os.path.join(ROOT, "previews", "crt-motifs", "motifs")
QSB = "/usr/lib/qt6/bin/qsb"


def read(name, base=SHELL):
    with open(os.path.join(base, name), encoding="utf-8") as f:
        return f.read()


def block(src):
    return re.search(r"uniform buf \{(.*?)\};", src, re.S).group(1)


def names(src):
    return re.findall(r"^\s*(?:mat4|vec[234]|float)\s+(\w+);", block(src), re.M)


class TestCableado(unittest.TestCase):
    def test_swarm_block_keeps_its_inputs(self):
        m = re.search(r"id: swarmC\s*Swarm\s*\{(.*?)\n        \}", read("Motif.qml"), re.S)
        self.assertIsNotNone(m)
        self.assertIn("rate: motif.rate", m.group(1))

    def test_no_animation_or_behavior_in_the_motif(self):
        # el banco exige que cada cuadro sea función pura del reloj y de las estampas
        src = re.sub(r"//[^\n]*", "", read("Swarm.qml"))
        self.assertNotRegex(src, r"\b(Behavior|NumberAnimation|SequentialAnimation|Timer)\b")

    def test_word_is_packed_in_mat4_not_arrays(self):
        # un array QML como uniform no llega al shader (queda en negro): TRAMPAS.md
        src = re.sub(r"//[^\n]*", "", read("Swarm.qml"))
        self.assertNotRegex(src, r"property\s+var\s+\w+\s*:\s*\[")
        for i in range(18):
            self.assertIn(f"property variant p{i}:", src)

    def test_instancing_mesh_covers_the_whole_budget(self):
        # 4 bloques (estela 2, estela 1, fondo, escritoras) x 260 flechas x 4 columnas por instancia
        self.assertIn("Qt.size(4159, 1)", read("Swarm.qml"))
        self.assertIn("Math.min(260,", read("Swarm.qml"))


class TestShaders(unittest.TestCase):
    def test_both_shaders_declare_the_same_block(self):
        self.assertEqual(block(read("swarm.vert")), block(read("swarm.frag")))

    @unittest.skipUnless(os.path.exists(QSB), "qsb no está instalado")
    def test_qsb_are_in_sync_with_their_sources(self):
        for stage in ("vert", "frag"):
            dump = subprocess.run([QSB, "--dump", os.path.join(SHELL, f"swarm.{stage}.qsb")],
                                  capture_output=True, text=True, check=True).stdout
            for u in names(read(f"swarm.{stage}")):
                self.assertIn(f'"name": "{u}"', dump, f"swarm.{stage}.qsb no trae `{u}`: recompilar")

    def test_every_uniform_has_a_property_in_the_qml(self):
        src = read("Swarm.qml")
        for u in names(read("swarm.frag")):
            if u in ("qt_Matrix", "qt_Opacity"):
                continue
            self.assertRegex(src, rf"\bproperty\s+\w+\s+{u}\s*:", f"Swarm.qml no alimenta `{u}`")


class TestBancoSinDeriva(unittest.TestCase):
    def test_qml_copy_matches_up_to_imports(self):
        src = re.sub(r'import "([A-Za-z]*)\.js"', r'import "../\1.js"', read("Swarm.qml"))
        self.assertEqual(src, read("Swarm.qml", BANCO),
                         "motifs/Swarm.qml difiere de shell/: correr previews/crt-motifs/sync-shell.sh")

    def test_shader_copies_are_identical(self):
        for name in ("swarm.vert", "swarm.frag"):
            self.assertEqual(read(name), read(name, BANCO), name)
        for name in ("swarm.vert.qsb", "swarm.frag.qsb"):
            with open(os.path.join(SHELL, name), "rb") as a, open(os.path.join(BANCO, name), "rb") as b:
                self.assertEqual(a.read(), b.read(), name)


if __name__ == "__main__":
    unittest.main()
