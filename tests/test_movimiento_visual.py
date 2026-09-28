"""Tanda 8 / slice "movimiento", parte visual: el RITMO de los dibujos sigue `mov`.

Ver docs/tanda8-estado/movimiento-visual.md. Se testea la tabla de pace, la perilla
`crt.mov_speed` de punta a punta, el cableado (shell.qml → Crt.qml → Motif.qml →
MotifBase / física propia) y, con node si está, las funciones puras de
`shell/Speed.js` — incluido que un cambio de ritmo NO salta la fase y que el
producto `t · rate` sí (el control).
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


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


def pace_rows():
    block = re.search(r"crtPaceTable:\s*\(\{(.*?)\n    \}\)", read("shell.qml"), re.S).group(1)
    rows = dict(re.findall(r"^\s{8}(\w+):\s*\{(.*?)\n\s{8}\},", block, re.S | re.M))
    return {k: re.sub(r"//[^\n]*", "", v) for k, v in rows.items()}


class TestMovPaceTable(unittest.TestCase):
    def test_every_row_has_a_range_around_one_calm_narrow_wild_wide(self):
        span = {}
        for name, body in pace_rows().items():
            lo = float(re.search(r"movMin:\s*([\d.]+)", body).group(1))
            hi = float(re.search(r"movMax:\s*([\d.]+)", body).group(1))
            self.assertLess(lo, 1.0, name)
            self.assertGreater(lo, 0.0, name)    # nunca se para del todo
            self.assertGreater(hi, 1.0, name)
            span[name] = hi - lo
        self.assertEqual(set(span), {"calm", "normal", "wild"})
        self.assertLess(span["calm"], span["normal"])
        self.assertLess(span["normal"], span["wild"])


class TestMovKnob(unittest.TestCase):
    def test_mov_speed_travels_from_the_toml_to_the_overlay(self):
        from cartelitos import config, ipc, setup
        self.assertEqual(config.DEFAULTS["crt"]["mov_speed"], 1.0)
        self.assertIn("mov_speed", config._CONFIG_COMMENTS["crt"])
        self.assertIn(("crt_mov_speed", "crt", "mov_speed"), ipc.CONFIG_EVENT_MAP)
        self.assertIn("mov_speed", {key for key, section, _, _ in setup.SETTINGS if section == "crt"})
        qml = read("shell.qml")
        self.assertRegex(qml, r"property real crtMovAmount:\s*1\.0\b")
        self.assertIn('crt_mov_speed: "crtMovAmount"', qml)
        with open(os.path.join(ROOT, "README.md"), encoding="utf-8") as f:
            self.assertIn("`mov_speed`", f.read())


class TestMovWiring(unittest.TestCase):
    def test_shell_reads_mov_and_rate_is_exactly_one_without_live_audio(self):
        qml = read("shell.qml")
        self.assertIn("root.audMov = ev.mov || 0;", qml)
        self.assertIn('import "Speed.js" as Speed', qml)
        self.assertRegex(qml, r"property real crtMovRate: audLive\s*\n\s*\? Speed\.rate\(audMov, "
                              r"pace\.movMin, pace\.movMax, crtMovAmount\) : 1\n")

    def test_crt_integrates_the_offset_where_tube_time_advances_and_never_scales_it(self):
        crt = read("Crt.qml")
        # los dos avances de `tubeTime` (FrameAnimation y Timer) suman al desplazamiento
        self.assertEqual(len(re.findall(r"crt\.movOff = Speed\.advance\(crt\.movOff, ", crt)), 2)
        self.assertEqual(len(re.findall(r"crt\.tubeTime \+= ", crt)), 2)
        # el reloj real no se escala en ningún lado
        self.assertNotRegex(crt, r"tubeTime\s*\*\s*[\w.]*[Rr]ate")
        self.assertNotRegex(crt, r"tubeTime\s*\+=[^\n]*[Rr]ate")
        self.assertIn("rollPhaseFor(crt.tubeTime + crt.movOff)", crt)
        self.assertIn("rate: crt.ctl.crtMovRate", crt)
        self.assertIn("movOff: crt.movOff", crt)

    def test_roll_phase_keeps_the_beat_locked_branch_on_the_wall_clock(self):
        fn = re.search(r"function rollPhaseFor\(tt\) \{(.*?)\n    \}", read("shell.qml"), re.S).group(1)
        locked = fn.split("const q =")[0]
        self.assertIn("Date.now()", locked)
        self.assertNotIn("tt", locked)

    def test_every_child_motif_with_its_own_clock_gets_the_rate(self):
        motif = read("Motif.qml")
        for kind in ("Ocean", "Dunes", "Rorschach", "Plasma", "Tunnel", "Static", "TextSea", "Pond",
                     "Swarm", "Splitflap", "Maze", "Pipes", "Defrag", "Mystify", "Vector", "Harmonograph"):
            body = re.search(r"\n        %s \{\n(.*?)\n        \}" % kind, motif, re.S)
            self.assertIsNotNone(body, kind)
            self.assertIn("rate: motif.rate", body.group(1), kind)
        # radar y lluvia dibujan con el reloj de dibujo; las estrellas acumulan con rate
        self.assertIn("rotation: motif.mclock *", motif)
        self.assertIn("y: ((motif.mclock * speed", motif)
        self.assertIn("frameTime * stars.speed * motif.rate", motif)
        self.assertIn("readonly property real mclock: clock + movOff", motif)

    def test_no_motif_base_child_shadows_rate_or_mov_off(self):
        # Un método del hijo con el mismo nombre PISA la propiedad heredada: Mystify tenía
        # `function rate(p, v, axis)` y `base.rate` en MotifBase leía la función → NaN.
        # Un `property ... rate` repetido es error de compilación. Ninguno de los dos.
        for name in sorted(os.listdir(SHELL)):
            if not name.endswith(".qml") or name == "MotifBase.qml":
                continue
            src = read(name)
            if not re.search(r"^MotifBase \{", src, re.M):
                continue
            self.assertNotRegex(src, r"function\s+(rate|movOff|lt)\s*\(", name)
            self.assertNotRegex(src, r"property\s+\w+\s+(rate|movOff)\b", name)

    def test_physics_motifs_scale_the_accumulated_dt_never_the_clock(self):
        for name, pat in (("Dunes", r"sand\.clock \+= sand\.pending \* sand\.rate;"),
                          ("Ocean", r"sea\.clock \+= sea\.pending \* sea\.rate;"),
                          ("Pond", r"dish\.clock \+= dish\.pending \* dish\.rate;"),
                          ("Static", r"snow\.clock \+= snow\.pending \* snow\.rate;"),
                          ("Rorschach", r"blot\.pending \+= frameTime \* Math\.max\(blot\.energy, 0\.35\) \* blot\.rate;"),
                          ("Plasma", r"lamp\.step\(Math\.min\(lamp\.acc \* lamp\.rate, 0\.05\)\);"),
                          ("Tunnel", r"tube\.travel \+= tube\.pending \* speed \* tube\.rate;"),
                          ("TextSea", r"\(sea\.bpmLive \? 1 : sea\.rate\)")):
            src = read(name + ".qml")
            self.assertRegex(src, pat, name)
            self.assertRegex(src, r"property real rate: 1\n", name)
            self.assertNotRegex(src, r"clock\s*\*\s*\w*\.?rate", name)
        # el túnel cuenta su luz con el reloj REAL (el fallback del compás)
        self.assertIn("tube.clock += tube.pending;", read("Tunnel.qml"))

    def test_motif_base_only_moves_lt_with_the_offset(self):
        base = read("MotifBase.qml")
        self.assertIn("readonly property real lt: E.wrap(clock + movOff, loopS)", base)
        self.assertIn("base.movOff = Speed.advance(base.movOff, base.clockAcc, base.rate);", base)
        # compás, golpes y la entrada del drop: tiempo real
        self.assertRegex(base, r"readonly property real sinceTick: Math\.max\(0, clock - tickAt\)")
        self.assertRegex(base, r"readonly property real sinceKick: Math\.max\(0, clock - kickAt\)")
        self.assertRegex(base, r"onDropChanged: dropAt = clock\n")
        self.assertRegex(base, r"onTubeClockChanged: if \(Math\.abs\(clock - tubeClock\) > 0\.25\) clock = tubeClock\n")

    def test_what_marks_real_time_does_not_hear_about_the_rate(self):
        # el aro-cronómetro, el lenguaje de movimiento y el reloj del tubo
        for name in ("Ring.qml", "Motion.qml", "HopRay.qml", "WordSlot.qml"):
            src = read(name)
            self.assertNotIn("crtMovRate", src, name)
            self.assertNotIn("movOff", src, name)
        qml = read("shell.qml")
        code = re.sub(r"//[^\n]*", "", read("Crt.qml"))
        self.assertEqual(len(re.findall(r"crtMovRate", code)), 3)   # 2 avances + Motif
        self.assertNotRegex(qml, r"Motion\.\w+Ms\s*\*\s*crtMovRate")


NODE = shutil.which("node")


@unittest.skipUnless(NODE, "node no está instalado")
class TestSpeedJs(unittest.TestCase):
    def run_js(self, expr):
        src = read("Speed.js").replace(".pragma library", "")
        out = subprocess.run([NODE, "-e", src + "\nconsole.log(JSON.stringify(" + expr + "));"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def test_rate_is_piecewise_linear_around_the_pivot(self):
        v = self.run_js("[rate(0, 0.75, 1.35, 1), rate(PIVOT, 0.75, 1.35, 1), rate(1, 0.75, 1.35, 1),"
                        " rate(-3, 0.75, 1.35, 1), rate(7, 0.75, 1.35, 1), PIVOT]")
        self.assertAlmostEqual(v[0], 0.75)
        self.assertAlmostEqual(v[1], 1.0)
        self.assertAlmostEqual(v[2], 1.35)
        self.assertAlmostEqual(v[3], 0.75)      # clamp
        self.assertAlmostEqual(v[4], 1.35)
        # un tema fuerte y PAREJO da mov ≈ 0.2 (movimiento.md): el pivote tiene que
        # quedar por encima, pero no tanto que el tema parejo se arrastre
        self.assertGreater(v[5], 0.2)
        self.assertLess(v[5], 0.5)

    def test_amount_scales_the_deviation_and_zero_is_off(self):
        v = self.run_js("[rate(0, 0.75, 1.35, 0), rate(1, 0.75, 1.35, 0), rate(1, 0.75, 1.35, 0.5),"
                        " rate(0, 0.75, 1.35, -1)]")
        self.assertEqual(v[0], 1)
        self.assertEqual(v[1], 1)
        self.assertAlmostEqual(v[2], 1.175)
        self.assertEqual(v[3], 1)

    def test_advance_ignores_clock_jumps_and_is_still_at_rate_one(self):
        v = self.run_js("[advance(2, 1/60, 1), advance(2, -1, 1.3), advance(2, 0.8, 1.3),"
                        " advance(2, NaN, 1.3), advance(0, 0.5, 1.2)]")
        self.assertEqual(v[0], 2)
        self.assertEqual(v[1], 2)
        self.assertEqual(v[2], 2)
        self.assertEqual(v[3], 2)
        self.assertAlmostEqual(v[4], 0.1)

    def test_a_rate_step_changes_speed_not_position_and_the_product_jumps(self):
        # 300 s de tema a ritmo 0.75 y un escalón a 1.35: con el desplazamiento
        # integrado la fase avanza a lo sumo 1.35·dt por cuadro; el producto `t·rate`
        # salta 0.6·300 = 180 s de dibujo en el cuadro del escalón
        v = self.run_js("""(() => {
            const dt = 1 / 60; let t = 300, off = 0, worstInt = 0, worstProd = 0;
            let prevInt = t + off, prevProd = t * 0.75;
            for (let i = 0; i < 120; i++) {
                const r = i < 60 ? 0.75 : 1.35;
                t += dt; off = advance(off, dt, r);
                const pInt = t + off, pProd = t * r;
                worstInt = Math.max(worstInt, Math.abs(pInt - prevInt) / dt);
                worstProd = Math.max(worstProd, Math.abs(pProd - prevProd) / dt);
                prevInt = pInt; prevProd = pProd;
            }
            return [worstInt, worstProd];
        })()""")
        self.assertLessEqual(v[0], 1.35 + 1e-6)
        self.assertGreater(v[1], 1000)


if __name__ == "__main__":
    unittest.main()
