"""Cableado audio.py -> shell.qml del CRT (Ferox 2026-10-19): cada `cmd` que manda el audio
tiene su rama en el QML, `char` llega como evento suelto (no dentro de `aud`), y `rise`/`fall`
se leen y se usan. Cableado por texto, como test_golpe.py: el QML no corre acá."""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CART = os.path.join(ROOT, "cartelitos")
SHELL = os.path.join(ROOT, "shell")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def sent_cmds(src):
    """Los `cmd` que el módulo manda: los literales `"cmd": "x"`."""
    return set(re.findall(r'"cmd":\s*"(\w+)"', src))


def dispatched(qml):
    """Los `cmd` que el QML despacha: `ev.cmd === "x"`."""
    return set(re.findall(r'ev\.cmd\s*===\s*"(\w+)"', qml))


def func_body(qml, head):
    m = re.search(re.escape(head) + r"\s*\{(.*?)\n    \}", qml, re.S)
    assert m, "no encuentro " + head
    return m.group(1)


class TestCmdsDelAudio(unittest.TestCase):
    def test_every_cmd_audio_sends_has_a_branch_in_shell(self):
        sent = sent_cmds(read(os.path.join(CART, "audio.py")))
        self.assertIn("char", sent)
        missing = sent - dispatched(read(os.path.join(SHELL, "shell.qml")))
        self.assertFalse(missing, "audio.py manda cmd que shell.qml no despacha: %s" % sorted(missing))

    def test_char_is_its_own_event_and_sets_song_char_when_positive(self):
        qml = read(os.path.join(SHELL, "shell.qml"))
        branch = re.search(r'ev\.cmd === "char"\) \{(.*?)\} else if', qml, re.S)
        self.assertIsNotNone(branch, 'falta la rama ev.cmd === "char"')
        self.assertRegex(branch.group(1), r"if \(ev\.v > 0\)\s*root\.songChar = ev\.v;")


class TestRiseFall(unittest.TestCase):
    def test_audio_sends_rise_and_fall_in_aud(self):
        src = read(os.path.join(CART, "audio.py"))
        self.assertRegex(src, r'"rise": round\(max\(rise_m, rise_l\)')
        self.assertRegex(src, r'"fall": round\(max\(fall_m, fall_l\)')

    def test_shell_reads_rise_and_fall_from_aud(self):
        qml = read(os.path.join(SHELL, "shell.qml"))
        self.assertIn("if (ev.rise > 0)\n                                root.riseHit(ev.rise);", qml)
        self.assertIn("if (ev.fall > 0)\n                                root.fallHold(ev.fall);", qml)

    def test_rise_moves_one_screen_only_past_the_pace_hold_floor(self):
        body = func_body(read(os.path.join(SHELL, "shell.qml")), "function riseHit(amt)")
        self.assertIn("crtMotifRefresh(false, false, pace.motifHoldMs)", body)
        # si la pantalla no tuvo el hold mínimo, no hay pulso: el return va antes del bassGen++
        self.assertLess(body.index("return;"), body.index("bassGen++"))
        self.assertIn("pace.kickRise", body)

    def test_rise_pulse_goes_through_the_bass_channel(self):
        qml = read(os.path.join(SHELL, "shell.qml"))
        self.assertIn("readonly property real kickAmp:", qml)
        self.assertIn("* kickKnob * bassMul", qml)     # el pulso escala por carácter y por bassMul
        self.assertIn("if (!crtMotifRefresh(false, false, pace.motifHoldMs))", qml)

    def test_fall_extends_the_hold_and_is_capped_at_now(self):
        body = func_body(read(os.path.join(SHELL, "shell.qml")), "function fallHold(amt)")
        self.assertIn("pace.fallHoldMs * (0.5 + 0.5 * amt)", body)
        self.assertIn("Math.min(t + ext, now)", body)

    def test_motif_refresh_reports_whether_it_changed(self):
        qml = read(os.path.join(SHELL, "shell.qml"))
        self.assertIn("function crtMotifRefresh(force, one, floorMs)", qml)
        self.assertIn("floorMs !== undefined ? floorMs", qml)
        self.assertIn("        return changed;\n    }", qml)

    def test_every_pace_row_has_rise_and_fall_columns(self):
        qml = read(os.path.join(SHELL, "shell.qml"))
        block = re.search(r"crtPaceTable:\s*\(\{(.*?)\n    \}\)", qml, re.S).group(1)
        block = re.sub(r"//[^\n]*", "", block)
        rows = dict(re.findall(r"^\s{8}(\w+):\s*\{(.*?)\n\s{8}\},", block, re.S | re.M))
        self.assertEqual(sorted(rows), ["calm", "normal", "wild"])
        for name, body in rows.items():
            self.assertRegex(body, r"kickRise:\s*[\d.]+", name)
            self.assertRegex(body, r"fallHoldMs:\s*[\d.]+", name)
        # `wild` no alarga holds: es el modo rápido y la tanda 3 no tenía `fall`
        self.assertRegex(rows["wild"], r"fallHoldMs:\s*0\b")


if __name__ == "__main__":
    unittest.main()
