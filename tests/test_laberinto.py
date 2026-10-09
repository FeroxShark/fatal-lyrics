"""Tanda 8 / slice "laberinto": la marcha con la música y los huevos de pascua.

Ver docs/tanda8-estado/laberinto.md. Cableado de la perilla `crt.maze_eggs` de punta
a punta, el cableado QML (`rate`, `cut`, `hf`) y, con node si está, las funciones puras
de `shell/Maze.js`.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")
sys.path.insert(0, ROOT)

from cartelitos import config, ipc, settings  # noqa: E402


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


class TestPerilla(unittest.TestCase):
    def test_maze_eggs_knob_is_wired_end_to_end(self):
        self.assertIs(config.DEFAULTS["crt"]["maze_eggs"], True)
        self.assertIn("maze_eggs", config._CONFIG_COMMENTS["crt"])
        self.assertIn(("crt_maze_eggs", "crt", "maze_eggs"), ipc.CONFIG_EVENT_MAP)
        qml = read("shell.qml")
        self.assertRegex(qml, r"property bool crtMazeEggs:\s*true\b")
        self.assertIn('crt_maze_eggs: "crtMazeEggs"', qml)
        self.assertIn("crt.maze_eggs", settings.ROWS)
        self.assertIn("eggs: crt.ctl.crtMazeEggs", read("Crt.qml"))


class TestCableado(unittest.TestCase):
    def test_maze_block_gets_rate_cut_hf_and_eggs(self):
        m = re.search(r"id: mazeC\s*Maze\s*\{(.*?)\n        \}", read("Motif.qml"), re.S)
        self.assertIsNotNone(m)
        for line in ("rate: motif.rate", "cut: motif.cut", "hf: motif.hf", "eggs: motif.eggs"):
            self.assertIn(line, m.group(1))

    def test_maze_does_not_shadow_rate(self):
        src = read("Maze.qml")
        self.assertNotRegex(src, r"function rate\b")
        self.assertNotRegex(src, r"property\s+\w+\s+rate\b")

    def test_march_is_a_counter_not_a_clock(self):
        # nada de `clock * rate`: los pasos se cuentan por tiempo (TRAMPAS: "El ritmo de los dibujos")
        src = re.sub(r"//[^\n]*", "", read("Maze.qml"))
        self.assertNotRegex(src, r"(clock|lt)\s*\*\s*rate|rate\s*\*\s*(clock|lt)")


@unittest.skipUnless(shutil.which("node"), "node no está instalado")
class TestMazeJs(unittest.TestCase):
    def run_js(self, expr):
        src = read("Maze.js").replace(".pragma library", "")
        out = subprocess.run(["node", "-e", src + "\nconsole.log(JSON.stringify(" + expr + "))"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def test_credit_at_rate_one_is_one_step_per_beat(self):
        self.assertEqual(self.run_js("credit(0, 1, 1)"), {"steps": 1, "acc": 0})
        self.assertEqual(self.run_js("credit(0, 5, 1)"), {"steps": 5, "acc": 0})

    def test_credit_is_conserved_at_other_rates(self):
        r = self.run_js("(() => { let a = 0, n = 0; for (let i = 0; i < 100; i++) "
                        "{ const c = credit(a, 1, 0.6); a = c.acc; n += c.steps; } return [n, a]; })()")
        self.assertAlmostEqual(r[0] + r[1], 60.0, places=6)
        self.assertGreater(self.run_js("credit(0, 1, 1.6).steps + credit(0.9, 1, 1.6).steps"), 2)

    def test_loop_closes_and_pose_is_continuous(self):
        st = self.run_js("[STATES[0], STATES[LOOP_STEPS]]")
        self.assertEqual(st[0][:2], st[1][:2])
        self.assertEqual(self.run_js("pose(3)"), self.run_js("pose(3 + LOOP_STEPS)"))

    def test_plan_is_deterministic_and_rare(self):
        self.assertEqual(self.run_js("plan(0.37, 5, '')"), self.run_js("plan(0.37, 5, '')"))
        n = self.run_js("(() => { let n = 0; for (let l = 0; l < 2000; l++) if (plan(1.234, l, '')) n++; "
                        "return n; })()")
        self.assertTrue(0.15 < n / 2000 < 0.30, n)

    def test_forced_plan_repeats_every_lap_and_sits_on_open_cells(self):
        for kind in ("smiley", "dialog", "exit", "rat", "rock"):
            act = self.run_js(f"plan(0.37, 0, '{kind}')")["act"]
            a = self.run_js(f"active(0.37, 200 * LOOP_STEPS + {act}, '{kind}')")
            b = self.run_js(f"active(0.37, 7 * LOOP_STEPS + {act}, '{kind}')")
            self.assertIsNotNone(a, kind)
            self.assertEqual(a["cell"], b["cell"])
        for kind in ("rat", "rock"):
            p = self.run_js(f"plan(0.37, 0, '{kind}')")
            self.assertTrue(self.run_js(f"OPEN_ACTIONS.indexOf({p['act']}) >= 0"))


if __name__ == "__main__":
    unittest.main()
