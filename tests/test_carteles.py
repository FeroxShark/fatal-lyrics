"""`[display] dialogs`: el interruptor de los carteles del modo normal (Ferox 2026-10-21).
La perilla, su fila en Ajustes, su viaje al overlay y su efecto en shell.qml (por texto, como
test_cableado.py: el QML no corre acá); `fatal carteles`, la bandeja, el atajo y la franja
"Rápido" de la ventana de Ajustes."""
import os
import re
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from cartelitos import config, ipc, settings  # noqa: E402


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as f:
        return f.read()


class TestPerilla(unittest.TestCase):
    def test_default_is_on_and_it_has_a_comment_and_a_row(self):
        self.assertIs(config.DEFAULTS["display"]["dialogs"], True)
        self.assertIn("dialogs", config._CONFIG_COMMENTS["display"])
        self.assertEqual(settings.ROWS["display.dialogs"]["kind"], "toggle")

    def test_it_travels_to_the_overlay_and_is_mapped_in_shell(self):
        self.assertIn(("dialogs", "display", "dialogs"), ipc.CONFIG_EVENT_MAP)
        self.assertIn('dialogs: "dialogsOn"', read("shell", "shell.qml"))

    def test_the_settings_window_can_write_it(self):
        self.assertEqual(settings.parse("1 display.dialogs=false\n"),
                         [(1, "display", "dialogs", False)])


class TestShellApaga(unittest.TestCase):
    qml = read("shell", "shell.qml")

    def test_pushDialog_is_the_one_door_and_it_is_closed(self):
        m = re.search(r"function pushDialog\(entry, markCurrent\) \{\s*(?://[^\n]*\n\s*)*"
                      r"if \(!root\.dialogsOn\)\s*return;", self.qml)
        self.assertIsNotNone(m, "pushDialog tiene que cortar con dialogsOn apagado")

    def test_live_dialogs_leave_with_their_normal_death(self):
        self.assertRegex(self.qml, r"readonly property bool shouldDie:[^{}]*\|\| !root\.dialogsOn")

    def test_the_sleeve_and_the_keys_tip_go_quiet(self):
        self.assertIn("npShown = !crtOn && dialogsOn;", self.qml)
        self.assertIn("visible: root.npShown && !root.crtOn && root.dialogsOn", self.qml)
        self.assertIn("!root.crtOn && root.dialogsOn && root.keysHint", self.qml)

    def test_the_tube_does_not_read_it(self):
        crt = read("shell", "Crt.qml")
        self.assertNotIn("dialogsOn", crt)


if __name__ == "__main__":
    unittest.main()
