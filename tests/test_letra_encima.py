"""La letra encima del motivo (`crt.lyric_over`, docs/TRAMPAS.md)."""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(*p):
    with open(os.path.join(ROOT, *p), encoding="utf-8") as f:
        return f.read()


class TestLetraEncima(unittest.TestCase):
    def test_every_pace_has_the_numbers(self):
        src = read("shell", "shell.qml")
        table = src[src.index("crtPaceTable: ({"):]
        for name in ("calm", "normal", "wild"):
            body = table[table.index("%s: {" % name):]
            self.assertRegex(body[:200], r"overDim: [\d.]+, overDimLong: [\d.]+, overScrim: [\d.]+", name)

    def test_kinds_exist(self):
        src = read("shell", "shell.qml")
        over = re.search(r"crtOverKinds: \[(.*?)\]", src, re.S).group(1)
        groups = re.search(r"motifGroups: \(\{(.*?)\}\)", src, re.S).group(1)
        for kind in re.findall(r'"(\w+)"', over):
            self.assertIn('"%s"' % kind, groups, kind)

    def test_changing_motif_under_a_verse_does_not_glitch_it(self):
        self.assertIn('crt.motifSeen && !crt.lyricOver)\n                    crt.hit(0.4, "motif", true)',
                      read("shell", "Crt.qml"))


class TestTuboEnSync(unittest.TestCase):
    def test_textures_are_pushed_by_the_clock_in_sync(self):
        src = read("shell", "Crt.qml")
        self.assertEqual(src.count("live: crt.visible && !crt.tubeIdle && Motion.framesMax"), 2)
        self.assertIn("stageTex.scheduleUpdate()", src)
        self.assertIn("signalTex.scheduleUpdate()", src)


class TestDunasHorneadas(unittest.TestCase):
    def test_bake_and_march_share_the_terrain(self):
        march, bake = read("shell", "dunes.frag"), read("shell", "dunebake.frag")
        for fn in ("float dune(vec2 p)", "float profile(float u)", "float pnoise(vec2 p, float per)"):
            self.assertEqual(march[march.index(fn):].split("\n}\n")[0], bake[bake.index(fn):].split("\n}\n")[0], fn)


if __name__ == "__main__":
    unittest.main()
