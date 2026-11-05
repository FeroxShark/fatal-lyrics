"""El reloj de cuadros (`crt.frames`): los dos modos y que nada dibuje con el reloj viejo."""
import os
import re
import unittest

from cartelitos import config as c
from cartelitos import settings

SHELL = os.path.join(os.path.dirname(__file__), "..", "shell")


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


class FrameTick(unittest.TestCase):
    def test_perilla_en_config_y_ajustes(self):
        self.assertEqual(c.DEFAULTS["crt"]["frames"], "sync")
        row = settings.ROWS["crt.frames"]
        self.assertEqual({o["value"] if isinstance(o, dict) else o[1] for o in row["options"]},
                         {"sync", "max"})

    def test_los_motivos_no_usan_frameanimation(self):
        # el reloj global late a la primaria: con uno suelto, ese dibujo no sigue la perilla
        for name in ("Dunes", "Ocean", "Pond", "Plasma", "Rorschach", "Tunnel", "Stars",
                     "TextSea", "Static", "MotifBase", "Motif"):
            self.assertNotIn("FrameAnimation {", read(name + ".qml"), name)

    def test_sin_techos_que_se_traben_en_el_latido(self):
        self.assertRegex(read("Motif.qml"), r"readonly property real stepMin: 0\n")
        self.assertNotIn("tubeStep", read("Crt.qml"))

    def test_la_pantalla_sin_letra_no_baja_a_20_fps(self):
        tick = re.search(r"FrameTick \{\s*running:(.*?)onTriggered", read("Crt.qml"), re.S).group(1)
        self.assertNotIn("showsText", tick)


if __name__ == "__main__":
    unittest.main()
