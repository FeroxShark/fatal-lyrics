"""Tests de los shaders de los motivos (tanda de shaders, 2026-10-19).

No corren la placa: miran que lo que se promete en el código esté en el código y que el .qsb
(lo que carga Quickshell) sea de la versión del .frag. El diff de cuadros de verdad vive en
`previews/crt-motifs/framediff.py`."""
import os
import re
import subprocess
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(__file__), "..")
SHELL = os.path.join(ROOT, "shell")
QSB = "/usr/lib/qt6/bin/qsb"


def read(name, mode="r"):
    with open(os.path.join(SHELL, name), mode) as f:
        return f.read()


class TestComentariosDelSorteo(unittest.TestCase):
    def test_los_motivos_que_ya_estan_en_el_sorteo_no_dicen_que_no(self):
        shell = read("shell.qml")
        grupos = re.search(r"motifGroups: \(\{(.*?)\}\)", shell, re.S).group(1)
        for kind in ("membrana", "cintas", "giroscopio"):
            self.assertIn(f'"{kind}"', grupos, f"{kind} salió del sorteo: actualizar este test")
            primera = read(kind.capitalize() + ".qml").splitlines()[0]
            self.assertNotIn("NO está en el sorteo", primera)
            self.assertIn("ya está en el sorteo", primera)


class TestDunasConLuzRasante(unittest.TestCase):
    def test_el_frag_sombrea_por_pendiente_con_un_sol_por_semilla(self):
        src = read("dunes.frag")
        self.assertIn("vec3 dune(vec2 p)", src)          # devuelve altura y gradiente
        self.assertIn("saz = 6.2831853 * fract(seed", src)  # el sol sale de la semilla
        self.assertNotIn("clamp(h * 6.0 + 0.5", src)       # ya no es un mapa de altura

    @unittest.skipUnless(os.path.exists(QSB), "qsb de Qt no instalado")
    def test_el_qsb_es_de_esta_version_del_frag(self):
        # si alguien edita el .frag y se olvida de regenerar el .qsb (header del archivo), el
        # overlay sigue con la versión vieja: se recompila y se compara byte a byte
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "dunes.frag.qsb")
            subprocess.run([QSB, "--glsl", "100 es,120,150", "-o", out,
                            os.path.join(SHELL, "dunes.frag")], check=True, capture_output=True)
            self.assertEqual(open(out, "rb").read(), read("dunes.frag.qsb", "rb"))


if __name__ == "__main__":
    unittest.main()
