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

    def test_every_row_has_a_kick_amplitude_calm_small_wild_big(self):
        kick = {name: float(re.search(r"movKick:\s*([\d.]+)", body).group(1))
                for name, body in pace_rows().items()}
        self.assertEqual(set(kick), {"calm", "normal", "wild"})
        for name, k in kick.items():
            self.assertGreater(k, 0.0, name)
            self.assertLess(k, 1.5, name)        # con KICK_CAP, nunca más de ~2.2x el ritmo base
        self.assertLess(kick["calm"], kick["normal"])
        self.assertLess(kick["normal"], kick["wild"])


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
        self.assertRegex(qml, r"property real crtMovRate: audLive\s*\n\s*\? Speed\.push\(Speed\.rate\(movFit\.mov, "
                              r"pace\.movMin, pace\.movMax, crtMovAmount, movFit\.pivot\),\s*\n"
                              r"\s*crtMovKick, crtMovAmount\) : 1\n")
        # ronda 3: el Behavior de 420 ms encima del suavizado se comía el empujón del golpe
        self.assertNotRegex(qml, r"Behavior on crtMovRate")
        self.assertIn("root.movStat = Speed.newStat();", qml)   # percentiles por tema

    def test_the_beat_kick_is_fed_by_the_aud_event_and_only_runs_while_it_lasts(self):
        qml = read("shell.qml")
        self.assertIn("root.movKickHit(Speed.kickStrength(!!ev.h));", qml)
        self.assertIn("Speed.kickAdd(", qml)
        self.assertIn("pace.movKick", qml)
        # el reloj del empujón se apaga solo cuando decayó (no es un FrameAnimation eterno)
        tick = re.search(r"FrameAnimation\s*\{\s*id: movKickTick\s*running: false(.*?)\n    \}", qml, re.S)
        self.assertIsNotNone(tick)
        self.assertIn("running = false", tick.group(1))
        # sin la perilla o sin audio vivo no hay empujón
        self.assertRegex(qml, r"function movKickHit\(strength\) \{\s*if \(!\(crtMovAmount > 0\) \|\| !audLive\)\s*return;")

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
        self.assertIn("rotation: radar.angle", motif)
        self.assertIn("rain.base + rain.kph", motif)
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
        # ronda 3: la música con pulso ronda 0.6-0.7, sin saturar: el pivote sube
        self.assertAlmostEqual(v[5], 0.45)

    def test_narrow_mov_band_is_stretched_to_the_whole_range(self):
        # Vivaldi real (qs.log): mov 0.63–0.80. Absoluto: rate 1.0–1.2; con percentiles: todo el rango
        v = self.run_js("""(() => { const st = newStat();
            for (let i = 0; i < 1200; i++) observe(st, 0.63 + 0.17 * (i % 100) / 99, 0.1);
            const sp = span(st); const f = (m) => { const q = fit(m, sp);
              return rate(q.mov, 0.4, 2.2, 1, q.pivot); };
            const st0 = newStat(); const s0 = span(st0);
            return [f(0.63), f(0.715), f(0.80), sp.conf, fit(0.7, s0).mov, fit(0.7, s0).pivot,
                    rate(0.8, 0.4, 2.2, 1)]; })()""")
        self.assertLess(v[0], 0.55)
        self.assertAlmostEqual(v[1], 1.0, delta=0.15)
        self.assertGreater(v[2], 1.9)
        self.assertEqual(v[3], 1)
        self.assertAlmostEqual(v[4], 0.7)     # sin muestras: absoluto de siempre
        self.assertAlmostEqual(v[5], 0.45)

    def test_a_skewed_theme_still_puts_its_median_at_rate_one_and_uses_both_extremes(self):
        # ronda 3: música con pulso (mov 0.58-0.68, 80 % del tiempo) y un final que se calma
        # (0.15-0.30, 20 %). El estirado lineal de p5..p95 dejaba la mediana casi arriba de
        # todo (el tema "corría" siempre); con el mapa por tres cuantiles el ritmo habitual
        # queda en 1 y los dos extremos del rango se tocan
        v = self.run_js("""(() => { const st = newStat();
            for (let i = 0; i < 800; i++)
              observe(st, i % 5 === 4 ? 0.15 + 0.15 * ((i * 7) % 10) / 9 : 0.58 + 0.10 * ((i * 3) % 10) / 9, 0.1);
            const sp = span(st);
            const f = (m) => { const q = fit(m, sp); return rate(q.mov, 0.4, 2.2, 1, q.pivot); };
            return [f(sp.mid), f(sp.lo), f(0.01), f(sp.hi), f(0.99), sp.lo, sp.mid, sp.hi,
                    fit(sp.mid - 0.02, sp).mov, fit(sp.mid + 0.02, sp).mov]; })()""")
        self.assertAlmostEqual(v[0], 1.0, delta=0.02)      # la mediana es ritmo 1
        self.assertAlmostEqual(v[1], 0.4, delta=0.02)      # P_LO y por debajo: movMin
        self.assertAlmostEqual(v[2], 0.4, delta=0.02)
        self.assertAlmostEqual(v[3], 2.2, delta=0.02)      # P_HI y por encima: movMax
        self.assertAlmostEqual(v[4], 2.2, delta=0.02)
        self.assertLess(v[5], v[6] - 0.10 + 1e-9)          # cada mitad mide al menos MIN_HALF
        self.assertGreater(v[7], v[6] + 0.10 - 1e-9)
        self.assertLess(v[8], 0.5)                         # monótono alrededor de la mediana
        self.assertGreater(v[9], 0.5)

    def test_a_flat_theme_does_not_amplify_noise(self):
        # un tema parejo (mov 0.60 ± 0.01): cada mitad ensanchada a MIN_HALF → ±0.01 mueve el
        # ritmo unos pocos %, no el rango entero
        v = self.run_js("""(() => { const st = newStat();
            for (let i = 0; i < 800; i++) observe(st, 0.60 + 0.01 * Math.sin(i), 0.1);
            const sp = span(st); const f = (m) => { const q = fit(m, sp);
              return rate(q.mov, 0.4, 2.2, 1, q.pivot); };
            return [f(0.59), f(0.61)]; })()""")
        self.assertLess(abs(v[0] - v[1]), 0.45)

    def test_kick_decays_to_zero_along_outquad_and_never_starts_from_nothing(self):
        v = self.run_js("[kickAt(0.7, 0), kickAt(0.7, KICK_S / 2), kickAt(0.7, KICK_S),"
                        " kickAt(0.7, KICK_S + 5), kickAt(0.7, -1), kickAt(0, 0.1), kickAt(NaN, 0.1), KICK_S]")
        self.assertAlmostEqual(v[0], 0.7)
        self.assertAlmostEqual(v[1], 0.7 * 0.25)         # (1 - 1/2)^2
        self.assertEqual(v[2], 0)
        self.assertEqual(v[3], 0)
        self.assertEqual(v[4], 0)                         # el reloj no anda para atrás
        self.assertEqual(v[5], 0)
        self.assertEqual(v[6], 0)
        # dura ~medio segundo: se nota y no arrastra al golpe siguiente
        self.assertGreater(v[7], 0.3)
        self.assertLess(v[7], 0.6)

    def test_kick_is_monotone_decreasing_and_stacked_hits_are_capped(self):
        v = self.run_js("""(() => { let prev = 1e9, mono = true;
            for (let i = 0; i <= 50; i++) { const k = kickAt(1, i * KICK_S / 50); mono = mono && k <= prev; prev = k; }
            let cur = 0; for (let i = 0; i < 20; i++) cur = kickAdd(cur, kickStrength(true), 0.7);
            return [mono, cur, KICK_CAP * 0.7, kickAdd(0.3, 0.4, 0.7), kickAdd(0, 1, 0), kickAdd(0.2, 0, 0.7),
                    kickStrength(true) > kickStrength(false)]; })()""")
        self.assertTrue(v[0])
        self.assertAlmostEqual(v[1], v[2])               # 20 golpes fuertes encimados: tope
        self.assertAlmostEqual(v[3], 0.3 + 0.4 * 0.7)    # dos golpes se suman
        self.assertEqual(v[4], 0)                        # amplitud 0 (fila sin empujón): nada
        self.assertAlmostEqual(v[5], 0.2)
        self.assertTrue(v[6])

    def test_push_multiplies_the_base_and_amount_zero_leaves_rate_one(self):
        v = self.run_js("[push(1.4, 0.7, 1), push(0.4, 0.7, 1), push(1.4, 0.7, 0.5), push(1, 0.7, 0),"
                        " push(1.4, -3, 1), push(1.4, 0, 1)]")
        self.assertAlmostEqual(v[0], 1.4 * 1.7)
        self.assertAlmostEqual(v[1], 0.4 * 1.7)           # multiplica: pesa lo mismo en lo quieto
        self.assertAlmostEqual(v[2], 1.4 * 1.35)
        self.assertEqual(v[3], 1)                          # perilla en 0: ritmo 1 EXACTO
        self.assertEqual(v[4], 1.4)
        self.assertEqual(v[5], 1.4)

    def test_a_beat_kick_is_speed_not_position(self):
        # 300 s de tema, un golpe fuerte cada 0.5 s sobre ritmo base 1.4 (normal): la fase
        # integrada nunca avanza más de rate·dt por cuadro (velocidad acotada); con `t·rate`
        # cada golpe teletransporta ~ t · (Δrate) = 300 · 1.4 · 0.7 s de dibujo
        v = self.run_js("""(() => {
            const dt = 1 / 60; let t = 300, off = 0, prevInt = t, prevProd = t * 1.4;
            let worstInt = 0, worstProd = 0, peak = 0, hitAt = -1, k0 = 0;
            for (let i = 0; i < 600; i++) {
                const now = i * dt;
                if (i % 30 === 0) { k0 = kickAdd(kickAt(k0, now - hitAt), 1, 0.7); hitAt = now; }
                const r = push(1.4, kickAt(k0, now - hitAt), 1);
                peak = Math.max(peak, r);
                t += dt; off = advance(off, dt, r);
                worstInt = Math.max(worstInt, (t + off - prevInt) / dt);
                worstProd = Math.max(worstProd, Math.abs(t * r - prevProd) / dt);
                prevInt = t + off; prevProd = t * r;
            }
            return [worstInt, worstProd, peak]; })()""")
        self.assertLessEqual(v[0], v[2] + 1e-6)            # velocidad de fase ≤ el pico de ritmo
        self.assertGreater(v[2], 2.3)                      # el golpe se nota: 1.4 → ~2.4
        self.assertGreater(v[1], 1000)                     # el control salta

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
