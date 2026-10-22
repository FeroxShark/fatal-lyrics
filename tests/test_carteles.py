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


class TestFatalCarteles(unittest.TestCase):
    """`fatal carteles on|off|toggle|status`: el timbre que levanta el daemon."""
    fatal = read("bin", "fatal")

    def test_help_lists_it_and_the_case_routes_it(self):
        out = subprocess.run([os.path.join(ROOT, "bin", "fatal"), "--help"],
                             capture_output=True, text=True).stdout
        self.assertRegex(out, r"carteles on \| off \| toggle \| status")
        self.assertRegex(self.fatal, r"carteles\|dialogs\) carteles \"\$2\" ;;")

    def test_toggle_is_decided_from_the_knob_and_the_status_line_shows_it(self):
        self.assertRegex(self.fatal, r'\[ "\$\(carteles_state\)" = ON \] && want=off \|\| want=on')
        self.assertIn('echo "dialogs: $(carteles_state)"', self.fatal)
        self.assertRegex(self.fatal, r"dialogs\[\[:space:\]\]\*=\[\[:space:\]\]\*false")

    def test_the_bell_file_matches_the_one_the_daemon_watches(self):
        name = os.path.basename(config.CARTELES_PATH)
        self.assertEqual(name, "cartelitos-carteles")
        self.assertIn('/%s"' % name, self.fatal)
        self.assertIn("watch_carteles", read("cartelitos", "daemon.py"))

    def test_the_bell_writes_the_knob(self):
        calls, ticks = [], []
        bell = os.path.join(os.environ.get("TMPDIR", "/tmp"), "carteles-test-%d" % os.getpid())

        def fake_sleep(_):
            ticks.append(1)
            if len(ticks) == 1:
                with open(bell, "w") as f:
                    f.write("off")
            elif len(ticks) == 3:
                raise KeyboardInterrupt

        from unittest import mock
        try:
            with mock.patch.object(config.time, "sleep", fake_sleep), \
                    mock.patch.object(config, "set_option", lambda *a: calls.append(a)), \
                    mock.patch.object(config, "CARTELES_PATH", bell):
                with self.assertRaises(KeyboardInterrupt):
                    config.watch_carteles()
        finally:
            if os.path.exists(bell):
                os.remove(bell)
        self.assertEqual(calls, [("dialogs", "display", False)])


class TestBandeja(unittest.TestCase):
    def test_dialogs_is_a_check_item_that_toggles_and_shows_the_real_state(self):
        from unittest import mock
        import threading
        from cartelitos import tray

        self.assertIn(("dialogs", "display", "Dialogs"), tray.TRAY_TOGGLES)

        class Item:
            def __init__(self, label=None):
                self.label, self.active, self.on_click = label, False, None
            def connect(self, _sig, cb): self.on_click = cb
            def set_sensitive(self, *a): pass
            def get_label(self): return self.label
            def set_label(self, t): self.label = t
            def get_active(self): return self.active
            def set_active(self, v): self.active = v

        made = []
        repo = mock.MagicMock()
        repo.Gtk.CheckMenuItem.side_effect = lambda label=None: made.append(Item(label)) or made[-1]
        repo.Gtk.MenuItem.side_effect = lambda label=None: made.append(Item(label)) or made[-1]
        created, real = [], threading.Thread

        def spy(*a, **k):
            t = real(*a, **k)
            created.append(t)
            return t

        saved = {k: sys.modules.get(k) for k in ("gi", "gi.repository")}
        sys.modules["gi"], sys.modules["gi.repository"] = mock.MagicMock(), repo
        sets = []
        try:
            with mock.patch("cartelitos.tray.threading.Thread", side_effect=spy), \
                    mock.patch.object(config, "set_option", lambda *a: sets.append(a)), \
                    mock.patch.object(config, "_tray_refresh", None), \
                    mock.patch.dict(config.CFG["display"], {"dialogs": False}):
                tray.start_tray()
                created[0].join(timeout=5)
                item = next(i for i in made if i.label and i.label.startswith("Dialogs"))
                self.assertEqual(item.label, "Dialogs: off")
                self.assertFalse(item.active)
                item.on_click()
                self.assertEqual(sets, [("dialogs", "display", True)])
                config.CFG["display"]["dialogs"] = True   # lo que haría set_option
                tick = repo.GLib.timeout_add.call_args[0][1]
                tick()
                self.assertEqual(item.label, "Dialogs: on")
                self.assertTrue(item.active)
        finally:
            for k, v in saved.items():
                if v is None:
                    sys.modules.pop(k, None)
                else:
                    sys.modules[k] = v
