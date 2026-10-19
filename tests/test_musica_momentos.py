"""Tanda música y momentos (2026-10-19): salpicón/burbuja/fogonazo salen del bombo, la
novedad entra al ritmo, cámara de pared con un solo pivote y el "no responde" en CRT.
Cableado por texto, como los demás tests de shell/."""
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


def pace_rows(qml):
    block = re.search(r"crtPaceTable:\s*\(\{(.*?)\n    \}\)", qml, re.S).group(1)
    block = re.sub(r"//[^\n]*", "", block)
    return {n: b for n, b in re.findall(r"^\s{8}(\w+):\s*\{(.*?)\n\s{8}\},", block, re.S | re.M)}


class TestBoom(unittest.TestCase):
    def test_boom_counter_follows_k_with_b_as_fallback(self):
        qml = read("shell.qml")
        self.assertIn("property int audBoom: 0", qml)
        m = re.search(r"if \(kSeen \? ev\.k : ev\.b\) \{(.*?)\n\s{28}\}", qml, re.S)
        self.assertIn("root.audBoom++", m.group(1))

    def test_motif_beat_and_ring_kick_use_the_boom(self):
        crt = read("Crt.qml")
        self.assertIn("beat: crt.ctl.audBoom", crt)
        self.assertIn("kick: crt.ctl.audBoom", crt)
        self.assertNotIn("crt.ctl.audBeat", crt)


class TestNovedad(unittest.TestCase):
    def test_nov_weight_is_a_pace_column_and_feeds_the_rate(self):
        qml = read("shell.qml")
        rows = pace_rows(qml)
        vals = {n: float(re.search(r"movNov:\s*([\d.]+)", b).group(1)) for n, b in rows.items()}
        self.assertEqual(vals["wild"], 0)                    # wild = lo de antes
        self.assertGreater(vals["normal"], vals["calm"])
        self.assertIn("Math.min(1, movFit.mov + pace.movNov * audNov)", qml)
        self.assertIn("Speed.rate(movNovIn,", qml)


NODE = shutil.which("node")
DP2 = "{x:0,y:-370,w:1080,h:1920}"
HDMI = "{x:1080,y:0,w:1920,h:1080}"
DP1 = "{x:3000,y:247,w:1920,h:1080}"


@unittest.skipUnless(NODE, "node no está instalado")
class TestWall(unittest.TestCase):
    def run_js(self, expr):
        src = read("Wall.js").replace(".pragma library", "")
        out = subprocess.run([NODE, "-e", src + "\nconsole.log(JSON.stringify(" + expr + "));"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def test_pivot_of_the_real_pair_sits_on_the_seam_at_the_middle_of_the_shared_edge(self):
        self.assertEqual(self.run_js("pivot([%s, %s])" % (DP2, HDMI)), {"x": 1080, "y": 540})

    def test_single_screen_and_loose_screens_pivot_on_the_center(self):
        self.assertEqual(self.run_js("pivot([%s])" % HDMI), {"x": 2040, "y": 540})
        self.assertEqual(self.run_js("pivot([{x:0,y:0,w:100,h:100},{x:500,y:0,w:100,h:100}])"),
                         {"x": 300, "y": 50})
        self.assertEqual(self.run_js("pivot([])"), {"x": 0, "y": 0})

    def test_seam_stays_whole_with_the_wall_pivot_but_not_with_each_own_center(self):
        # el punto de la costura (x global 1080) con el golpe al 2 %, visto desde cada tubo
        s = 1.02
        wall = self.run_js(
            "(() => { const pv = pivot([%s, %s]);"
            " const a = local(%s, pv), b = local(%s, pv);"
            " return [0 + scaleAbout(1080, a.x, %s), 1080 + scaleAbout(0, b.x, %s)]; })()"
            % (DP2, HDMI, DP2, HDMI, s, s)
        )
        self.assertEqual(wall[0], wall[1])
        own = [0 + (540 + s * (1080 - 540)), 1080 + (960 + s * (0 - 960))]
        self.assertAlmostEqual(abs(own[0] - own[1]), 30, delta=1)   # el desfase de antes: ~30 px

    def test_local_pivot_never_lets_the_background_show(self):
        rects = [DP2, HDMI, DP1]
        for s in (1.004, 1.03, 1.1):
            v = self.run_js(
                "(() => { const rs = [%s]; const pv = pivot(rs);"
                " return rs.map(r => { const o = local(r, pv);"
                " return [scaleAbout(0, o.x, %s), scaleAbout(r.w, o.x, %s),"
                " scaleAbout(0, o.y, %s), scaleAbout(r.h, o.y, %s), r.w, r.h]; }); })()"
                % (", ".join(rects), s, s, s, s)
            )
            for x0, x1, y0, y1, w, h in v:
                self.assertLessEqual(x0, 1e-9)
                self.assertGreaterEqual(x1, w - 1e-9)
                self.assertLessEqual(y0, 1e-9)
                self.assertGreaterEqual(y1, h - 1e-9)

    def test_crt_and_shell_use_the_wall_pivot(self):
        crt, qml = read("Crt.qml"), read("shell.qml")
        self.assertIn("crtWallPivot: Wall.pivot(", qml)
        self.assertIn("origin.x: crt.camOrigin.x", crt)
        self.assertIn("(crt.camOrigin.x - crt.width / 2) * pivK", crt)


if __name__ == "__main__":
    unittest.main()
