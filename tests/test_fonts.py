"""Fuentes de la letra del CRT (tanda 8): lo que carga `shell.qml` existe,
tiene su licencia al lado, y lo que sortea el set sale de ahí."""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, "shell", "fonts")


def _qml():
    with open(os.path.join(ROOT, "shell", "shell.qml"), encoding="utf-8") as f:
        return f.read()


def _block(qml, name):
    m = re.search(name + r":\s*\(\{(.*?)\}\)", qml, re.S)
    assert m, name
    return m.group(1)


class TestCrtFonts(unittest.TestCase):
    def test_every_font_loader_points_to_a_bundled_file(self):
        srcs = re.findall(r'FontLoader \{ id: \w+; source: Qt\.resolvedUrl\("fonts/([^"]+)"\)', _qml())
        self.assertGreaterEqual(len(srcs), 7)
        for name in srcs:
            self.assertTrue(os.path.isfile(os.path.join(FONTS, name)), name)

    def test_every_bundled_font_ships_its_license(self):
        # repo público: cada ttf con su LICENSE-<nombre>.txt al lado
        for name in os.listdir(FONTS):
            if not name.endswith(".ttf"):
                continue
            stem = name.split("-")[0].lower()
            lic = os.path.join(FONTS, "LICENSE-%s.txt" % stem)
            self.assertTrue(os.path.isfile(lic), lic)
            with open(lic, encoding="utf-8") as f:
                self.assertIn("SIL Open Font License", f.read())

    def test_no_orphan_licenses(self):
        stems = {n.split("-")[0].lower() for n in os.listdir(FONTS) if n.endswith(".ttf")}
        for name in os.listdir(FONTS):
            if name.startswith("LICENSE-"):
                self.assertIn(name[len("LICENSE-"):-len(".txt")], stems, name)

    def test_set_pools_cover_every_family_and_font(self):
        qml = _qml()
        fams = set(re.findall(r"(\w+):", _block(qml, "crtFontFamilies")))
        pools = dict(re.findall(r"(\w+):\s*\[([^\]]*)\]", _block(qml, "crtFontPools")))
        entry = set(re.findall(r"^\s{8}(\w+):", _block(qml, "crtEntryFamilies"), re.M))
        self.assertEqual(set(pools), entry)   # un mazo por familia de entradas
        used = set()
        for keys in pools.values():
            keys = re.findall(r'"(\w+)"', keys)
            self.assertTrue(keys)
            self.assertTrue(set(keys) <= fams, keys)
            used |= set(keys)
        self.assertNotIn("dot", used)          # DotGothic16 es sólo el camino de CJK
        self.assertEqual(used, fams - {"dot"})  # ninguna fuente cargada queda sin mazo

    def test_press_start_2p_is_gone(self):
        # tanda 8: Ferox no quiere la pixel de bloques gruesos
        self.assertFalse([n for n in os.listdir(FONTS) if "pressstart" in n.lower()])
        for sub in ("shell", "previews"):
            for dirpath, _, files in os.walk(os.path.join(ROOT, sub)):
                for n in files:
                    if n.endswith((".qml", ".py", ".js")):
                        with open(os.path.join(dirpath, n), encoding="utf-8") as f:
                            self.assertNotIn("PressStart2P", f.read(), n)


if __name__ == "__main__":
    unittest.main()
