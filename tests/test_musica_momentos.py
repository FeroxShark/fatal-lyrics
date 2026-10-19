"""Tanda música y momentos (2026-10-19): salpicón/burbuja/fogonazo salen del bombo, la
novedad entra al ritmo, cámara de pared con un solo pivote y el "no responde" en CRT.
Cableado por texto, como los demás tests de shell/."""
import os
import re
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


if __name__ == "__main__":
    unittest.main()
