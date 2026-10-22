"""El bucle de recarga de la config (Ferox 2026-10-21): poner `display.dialogs = false` en
Ajustes dejó ~700 "config reloaded" por segundo y el TOML reescrito sin parar.

Causa: en GTK3 `CheckMenuItem.set_active` emite "activate" además de "toggled". El
refresh de la bandeja movía el tilde, eso corría el on_click (invertía la perilla), eso
recargaba la config, eso refrescaba la bandeja... El fake de test_carteles.py no emitía
"activate" y por eso no lo vio: acá el fake se porta como GTK. Todo en archivos
temporales: no toca la config real ni el daemon."""
import os
import sys
import tempfile
import threading
import unittest
from unittest import mock

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, ROOT)

from cartelitos import config, ipc, system, tray  # noqa: E402


class GtkItem:
    """Como Gtk.CheckMenuItem: set_active, si cambia algo, dispara "activate"."""
    def __init__(self, label=None):
        self.label, self.active, self.handlers = label, False, []

    def connect(self, _sig, cb): self.handlers.append(cb)
    def set_sensitive(self, *a): pass
    def get_label(self): return self.label
    def set_label(self, t): self.label = t
    def get_active(self): return self.active

    def set_active(self, v):
        if v != self.active:
            self.active = v
            for cb in list(self.handlers):
                cb()


class BucleConfig(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = os.path.join(self.tmp.name, "config.toml")
        self.stack = []
        self.reloads, self.writes = [], []

    def start(self, dialogs):
        """Config temporal con `dialogs`, CFG alineado, y la bandeja de verdad
        andando sobre ítems que se portan como GTK."""
        with open(self.path, "w") as f:
            f.write(config.DEFAULT_CONFIG.replace("dialogs = true", f"dialogs = {str(dialogs).lower()}"))
        real_save, real_log = config._save_config, config.log

        def save(changes):
            wrote = real_save(changes)
            if wrote:
                self.writes.append(changes)
            return wrote

        def log(msg):
            if msg == "config reloaded":
                self.reloads.append(msg)
                if len(self.reloads) > 25:
                    raise AssertionError("bucle de recarga: más de 25 'config reloaded'")
            real_log(msg)

        made = []
        repo = mock.MagicMock()
        repo.Gtk.CheckMenuItem.side_effect = lambda label=None: made.append(GtkItem(label)) or made[-1]
        repo.Gtk.MenuItem.side_effect = lambda label=None: made.append(GtkItem(label)) or made[-1]
        repo.GLib.idle_add.side_effect = lambda fn: fn()   # el hilo de GTK, en seco
        created, real_thread = [], threading.Thread
        spy = lambda *a, **k: created.append(real_thread(*a, **k)) or created[-1]

        saved = {k: sys.modules.get(k) for k in ("gi", "gi.repository")}
        sys.modules["gi"], sys.modules["gi.repository"] = mock.MagicMock(), repo
        self.addCleanup(lambda: [sys.modules.pop(k, None) if v is None else sys.modules.__setitem__(k, v)
                                 for k, v in saved.items()])
        patches = [
            mock.patch.object(config, "CONFIG_PATH", self.path),
            mock.patch.object(config, "_save_config", save),
            mock.patch.object(config, "log", log),
            mock.patch.object(config, "_tray_refresh", None),
            mock.patch.object(ipc, "send", lambda *a, **k: None),
            mock.patch.object(system, "apply_key_binds", lambda *a, **k: None),
            mock.patch.object(config, "set_crt", lambda *a, **k: True),
            mock.patch("cartelitos.tray.threading.Thread", side_effect=spy),
        ] + [mock.patch.dict(config.CFG[s]) for s in config.CFG]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        for sec, vals in config.read_config().items():   # CFG = lo que dice el TOML temporal
            config.CFG[sec].clear()
            config.CFG[sec].update(vals)
        tray.start_tray()
        created[0].join(timeout=5)
        self.item = next(i for i in made if i.label and i.label.startswith("Dialogs"))
        self.reloads.clear()
        self.writes.clear()

    def toml_dialogs(self):
        with open(self.path) as f:
            return [l.split("#")[0].strip() for l in f.read().splitlines() if l.startswith("dialogs")]

    def watch_config_ticks(self, n):
        """n vueltas del watcher del archivo (mtime), sin dormir de verdad."""
        ticks = []

        def fake_sleep(_):
            ticks.append(1)
            if len(ticks) > n * 2:   # dos sleeps por cambio de mtime
                raise KeyboardInterrupt

        with mock.patch.object(config.time, "sleep", fake_sleep):
            with self.assertRaises(KeyboardInterrupt):
                config.watch_config()

    # ---- Ajustes (settings.watch_settings: _save_config + apply_config)
    def settings_write(self, value):
        config._save_config({"dialogs": ("display", value)})
        config.apply_config()

    def test_settings_dialogs_false_reloads_once(self):
        self.start(True)
        self.settings_write(False)
        self.assertEqual(len(self.reloads), 1)
        self.assertEqual(len(self.writes), 1)
        self.assertEqual(self.toml_dialogs(), ["dialogs = false"])
        self.assertFalse(self.item.active)
        self.watch_config_ticks(10)   # y el watcher, tras la escritura, no recarga más
        self.assertEqual(len(self.reloads), 1)

    def test_settings_dialogs_true_reloads_once(self):
        self.start(False)
        self.settings_write(True)
        self.assertEqual(len(self.reloads), 1)
        self.assertEqual(len(self.writes), 1)
        self.assertEqual(self.toml_dialogs(), ["dialogs = true"])
        self.assertTrue(self.item.active)
        self.watch_config_ticks(10)
        self.assertEqual(len(self.reloads), 1)

    def test_same_value_again_neither_writes_nor_reloads(self):
        self.start(False)
        before = os.stat(self.path).st_mtime_ns
        for _ in range(10):
            self.settings_write(False)
            config.set_option("dialogs", "display", False)
        self.assertEqual((len(self.reloads), len(self.writes)), (0, 0))
        self.assertEqual(os.stat(self.path).st_mtime_ns, before)

    # ---- timbre de `fatal carteles`
    def bell(self, text, n=10):
        bell = os.path.join(self.tmp.name, "bell")
        ticks = []

        def fake_sleep(_):
            ticks.append(1)
            if len(ticks) == 1:
                with open(bell, "w") as f:
                    f.write(text)
            elif len(ticks) > n:
                raise KeyboardInterrupt

        with mock.patch.object(config.time, "sleep", fake_sleep), \
                mock.patch.object(config, "CARTELES_PATH", bell):
            with self.assertRaises(KeyboardInterrupt):
                config.watch_carteles()

    def test_bell_toggle_applies_once(self):
        self.start(True)
        self.bell("toggle")
        self.assertEqual((len(self.reloads), len(self.writes)), (1, 1))
        self.assertEqual(self.toml_dialogs(), ["dialogs = false"])
        self.assertFalse(self.item.active)

    def test_bell_asking_for_the_current_state_does_nothing(self):
        self.start(False)
        self.bell("off")
        self.assertEqual((len(self.reloads), len(self.writes)), (0, 0))

    # ---- la bandeja sola
    def test_syncing_the_tick_does_not_click(self):
        self.start(True)
        config.CFG["display"]["dialogs"] = False   # cambió por fuera (editor, Ajustes)
        tray_tick = config._tray_refresh
        for _ in range(5):
            tray_tick()
        self.assertFalse(self.item.active)
        self.assertEqual((len(self.reloads), len(self.writes)), (0, 0))

    def test_a_real_click_still_toggles(self):
        self.start(True)
        self.item.active = False   # GTK ya movió el tilde...
        for cb in self.item.handlers:   # ...y después dispara activate
            cb()
        self.assertEqual((len(self.reloads), len(self.writes)), (1, 1))
        self.assertEqual(self.toml_dialogs(), ["dialogs = false"])


if __name__ == "__main__":
    unittest.main()
