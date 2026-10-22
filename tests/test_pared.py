"""La PARED de motivos (`docs/PARED.md`): con dos pantallas o más, truchet, mystify y pipes
dibujan UN lienzo del tamaño de toda la pared y cada pantalla muestra su recorte.

No corren la placa (eso es `previews/crt-motifs/pared.py --check`): miran la cuenta del lienzo
en `Wall.js` con node, la perilla `crt.wall` de punta a punta y el cableado por texto."""
import json
import os
import re
import shutil
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")
BANCO = os.path.join(ROOT, "previews", "crt-motifs")
QSB = "/usr/lib/qt6/bin/qsb"
NODE = shutil.which("node")
sys.path.insert(0, ROOT)

from cartelitos import config, ipc, settings  # noqa: E402

# el equipo de Ferox, en px lógicos (como `hyprctl monitors`)
DP2 = "{x: 0, y: -370, w: 1080, h: 1920}"
HDMI = "{x: 1080, y: 0, w: 1920, h: 1080}"
DP1 = "{x: 3000, y: 247, w: 1920, h: 1080}"
WALL_KINDS = ("truchet", "mystify", "pipes")


def read(name, base=SHELL):
    with open(os.path.join(base, name), encoding="utf-8") as f:
        return f.read()


class TestPerilla(unittest.TestCase):
    def test_wall_knob_is_wired_end_to_end(self):
        self.assertIs(config.DEFAULTS["crt"]["wall"], True)
        self.assertIn("wall", config._CONFIG_COMMENTS["crt"])
        self.assertIn(("crt_wall", "crt", "wall"), ipc.CONFIG_EVENT_MAP)
        qml = read("shell.qml")
        self.assertRegex(qml, r"property bool crtWall:\s*true\b")
        self.assertIn('crt_wall: "crtWall"', qml)
        self.assertIn("crt.wall", settings.ROWS)
        # apagarla rehace el reparto (cada pantalla vuelve a su dibujo)
        self.assertIn("onCrtWallChanged: crtMotifRefresh(true)", qml)


@unittest.skipUnless(NODE, "node no está instalado")
class TestLienzo(unittest.TestCase):
    def run_js(self, expr):
        src = read("Wall.js").replace(".pragma library", "")
        out = subprocess.run([NODE, "-e", src + "\nconsole.log(JSON.stringify(" + expr + "));"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def test_canvas_is_the_box_of_every_screen_and_span_the_smallest_side(self):
        self.assertEqual(self.run_js("canvas([%s, %s, %s])" % (DP2, HDMI, DP1)),
                         {"x": 0, "y": -370, "w": 4920, "h": 1920, "span": 1080})
        self.assertEqual(self.run_js("canvas([])"), {"x": 0, "y": 0, "w": 1, "h": 1, "span": 1})

    def test_without_camera_each_screen_draws_its_own_rectangle(self):
        v = self.run_js("view({x: 247, y: 617}, {w: 1920, h: 1080}, {x: 1080, y: 910},"
                        " {x: 0, y: 293}, 1, 1)")
        self.assertEqual(v, {"x": 247, "y": 617, "w": 1920, "h": 1080})

    def test_every_canvas_point_lands_where_the_whole_wall_would_scale_it(self):
        # el motivo dibuja `view` en su pantalla, la cámara escala `s` sobre `local`: el punto P
        # del lienzo tiene que verse en pv + s·z·(P − pv), desde cualquier pantalla
        s, z = 1.03, 1.05
        bad = self.run_js(
            "(() => { const rs = [%s, %s, %s], cv = canvas(rs), pg = pivot(rs);"
            " const pv = {x: pg.x - cv.x, y: pg.y - cv.y}, out = [];"
            " for (const r of rs) {"
            "  const off = {x: r.x - cv.x, y: r.y - cv.y}, o = local(r, pg);"
            "  const w = view(off, {w: r.w, h: r.h}, pv, o, %s, %s);"
            "  for (const P of [[0, 0], [1234, 567], [2900, 1500], [4920, 1920], [off.x, off.y]]) {"
            "   const qx = (P[0] - w.x) * r.w / w.w, qy = (P[1] - w.y) * r.h / w.h;"
            "   const dx = off.x + o.x + %s * (qx - o.x), dy = off.y + o.y + %s * (qy - o.y);"
            "   const ex = pv.x + %s * (P[0] - pv.x), ey = pv.y + %s * (P[1] - pv.y);"
            "   if (Math.abs(dx - ex) > 1e-6 || Math.abs(dy - ey) > 1e-6) out.push([r, P, dx, ex]); } }"
            " return out; })()" % (DP2, HDMI, DP1, s, z, s, s, s * z, s * z))
        self.assertEqual(bad, [])


class TestCableado(unittest.TestCase):
    def test_wall_kinds_are_drawings_of_the_draw(self):
        qml = read("shell.qml")
        kinds = re.search(r"motifKinds:\s*\[(.*?)\]", qml, re.S).group(1)
        wall = re.search(r"readonly property var motifWall:\s*\[(.*?)\]", qml).group(1)
        self.assertEqual(tuple(re.findall(r'"(\w+)"', wall)), WALL_KINDS)
        for k in WALL_KINDS:
            self.assertIn(f'"{k}"', kinds, k)

    def test_motif_blocks_pass_the_canvas_and_the_camera(self):
        src = read("Motif.qml")
        for k in WALL_KINDS:
            m = re.search(r"\n\s+%s\s*\{(.*?)\n        \}" % k.capitalize(), src, re.S)
            self.assertIsNotNone(m, k)
            self.assertIn("wall: motif.wall", m.group(1), k)
            self.assertIn("wallCam: motif.wallCam", m.group(1), k)
        # en pared el tirón va por la ventana (`Wall.view`), no por el Scale del item
        self.assertIn("xScale: motif.wall ? 1 : motif.zoomNow", src)

    def test_crt_latches_the_wall_at_the_bridge(self):
        src = read("Crt.qml")
        self.assertIn("wall: crt.wallSpec", src)
        # al nacer, en el primer dibujo y en el puente: nunca a mitad de un dibujo
        self.assertEqual(len(re.findall(r"wallLatch\(\);", src)), 3)
        self.assertIn("sh.seed === undefined", src)

    def test_no_shader_property_is_called_focus(self):
        # `focus` es FINAL en Item: un ShaderEffect con esa propiedad no carga (TRAMPAS)
        for name in os.listdir(SHELL):
            if name.endswith(".qml"):
                self.assertNotRegex(read(name), r"property\s+\w+\s+focus\b", name)

    def test_single_screen_paths_stay(self):
        self.assertIn("portrait ? [7, 12, 6] : [12, 7, 6]", read("Pipes.qml"))
        self.assertIn("walled ? Math.max(1, Math.round(b * (axis === 0 ? wallKx : wallKy))) : b",
                      read("Mystify.qml"))
        self.assertIn("wallK > 0.5 ?", read("truchet.frag"))


class TestShaders(unittest.TestCase):
    UNIFORMS = {"truchet": ("view", "foc", "wallK"), "mystify": ("win", "orig")}

    def test_frags_declare_the_canvas(self):
        for k, names in self.UNIFORMS.items():
            block = re.search(r"uniform buf \{(.*?)\};", read(f"{k}.frag"), re.S).group(1)
            for u in names:
                self.assertRegex(block, r"\b%s;" % u, f"{k}.frag sin `{u}`")

    @unittest.skipUnless(os.path.exists(QSB), "qsb no está instalado")
    def test_qsb_carries_the_canvas(self):
        for k, names in self.UNIFORMS.items():
            dump = subprocess.run([QSB, "--dump", os.path.join(SHELL, f"{k}.frag.qsb")],
                                  capture_output=True, text=True, check=True).stdout
            for u in names:
                self.assertIn(f'"name": "{u}"', dump, f"{k}.frag.qsb no trae `{u}`: recompilar")


class TestBancoSinDeriva(unittest.TestCase):
    """`shell/` es la fuente; el banco tiene copias (`./sync-shell.sh`)."""

    def test_qml_copies_match_up_to_imports(self):
        for name in ("MotifBase", "ThumpBase", "Truchet", "Mystify", "Pipes"):
            src = re.sub(r'import "([A-Za-z]*)\.js"', r'import "../\1.js"', read(name + ".qml"))
            src = src.replace("Motion.levelMs", "420")
            self.assertEqual(src, read(name + ".qml", os.path.join(BANCO, "motifs")),
                             f"motifs/{name}.qml difiere de shell/: correr previews/crt-motifs/sync-shell.sh")

    def test_js_and_shader_copies_are_identical(self):
        self.assertEqual(read("Wall.js"), read("Wall.js", BANCO))
        for name in ("truchet.frag", "truchet.frag.qsb", "mystify.frag", "mystify.frag.qsb"):
            with open(os.path.join(SHELL, name), "rb") as a, \
                    open(os.path.join(BANCO, "motifs", name), "rb") as b:
                self.assertEqual(a.read(), b.read(), name)


if __name__ == "__main__":
    unittest.main()
