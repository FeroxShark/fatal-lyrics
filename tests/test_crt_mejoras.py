"""CRT, tanda de mejoras 2026-10-19 (movimiento y tubo): cableado por texto, como test_golpe.py."""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


def code(qml):
    return re.sub(r"//[^\n]*", "", qml)


class TestPuenteDeDibujo(unittest.TestCase):
    def test_motif_change_is_a_glitch_bridge_not_a_long_fade(self):
        b = code(read("Crt.qml"))
        m = re.search(r"id: motifBridge(.*?)\n    }\n", b, re.S).group(1)
        self.assertIn("Motion.bridgeMs / 2", m)
        self.assertIn("Motion.enterFastMs", m)
        self.assertNotIn("Motion.enterMs", m)
        self.assertNotIn("Motion.exitMs", m)
        # el golpe de tubo cae en el swap (urgent: con beat_lock no se difiere)
        self.assertRegex(m, r'crt\.hit\(0\.4, "motif", true\)')
        self.assertLess(m.index("motifShown = crt.motifKind"), m.index('"motif"'))

    def test_bridge_glitch_only_when_the_motif_is_on_screen(self):
        b = code(read("Crt.qml"))
        self.assertRegex(b, r"if \(crt\.motifSeen\)\s*crt\.hit\(0\.4")
        self.assertIn("visible: crt.motifSeen", b)


if __name__ == "__main__":
    unittest.main()
