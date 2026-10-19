"""Control y primer uso (tanda 50): la bandeja dice el estado real, `fatal on` no dice ON
con media instancia, `fatal crt on` no miente con todo apagado, el uso inválido sale por
stderr, el instalador acepta `quickshell` y cierra con el chequeo. Todo con un
XDG_RUNTIME_DIR temporal y un `qs`/daemon de mentira (los de test_guard): no toca la
sesión real."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cartelitos import tray, util  # noqa: E402
import test_guard  # noqa: E402

FATAL = os.path.join(ROOT, "bin", "fatal")
# lo que bin/fatal e install.sh usan, para armar un PATH SIN qs ni quickshell
# (en esta máquina están en /usr/bin, junto con todo lo demás)
TOOLS = ("env", "sh", "bash", "tr", "grep", "cat", "seq", "sleep", "setsid", "flock",
         "pgrep", "mv", "rm", "mkdir", "tail", "readlink", "dirname", "python3", "sed",
         "ln", "chmod", "install", "head", "kill", "cp")


def _toolbox(root, extra=()):
    d = os.path.join(root, "tools")
    os.makedirs(d, exist_ok=True)
    for name in TOOLS + tuple(extra):
        src = shutil.which(name)
        if src and not os.path.exists(os.path.join(d, name)):
            os.symlink(src, os.path.join(d, name))
    return d


class TestBandeja(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.state = os.path.join(self.tmp, "lyrics")

    def _state(self, text):
        with open(self.state, "w", encoding="utf-8") as f:
            f.write(text + "\n")

    def test_on_shows_the_lyrics_state(self):
        self._state("lyrics: lrclib (synced, 54 lines)")
        self.assertEqual(tray.status_text(True, self.state),
                         "Fatal Lyrics: ON · lyrics: lrclib (synced, 54 lines)")

    def test_half_says_the_overlay_died_and_drops_the_stale_line(self):
        self._state("lyrics: lrclib (synced, 54 lines)")
        text = tray.status_text(False, self.state)
        self.assertIn("HALF", text)
        self.assertNotIn("lrclib", text)

    def test_no_state_file_is_just_the_head(self):
        self.assertEqual(tray.status_text(True, self.state), "Fatal Lyrics: ON")

    def test_a_long_line_is_cut_so_the_menu_does_not_widen(self):
        self._state("lyrics: " + "x" * 200)
        line = tray.status_text(True, self.state).split(" · ", 1)[1]
        self.assertLessEqual(len(line), tray.STATUS_MAX)
        self.assertTrue(line.endswith("…"))

    def test_overlay_detection_follows_the_qs_lock(self):
        lock = os.path.join(self.tmp, "qs.lock")
        self.assertFalse(tray._lock_held(lock))
        holder = util.acquire_instance_lock(lock)
        self.addCleanup(holder.close)
        self.assertTrue(tray._lock_held(lock))

    def test_the_icon_is_the_brand_one_only_if_installed(self):
        old = os.environ.get("XDG_DATA_HOME")
        self.addCleanup(lambda: os.environ.pop("XDG_DATA_HOME", None) if old is None
                        else os.environ.__setitem__("XDG_DATA_HOME", old))
        os.environ["XDG_DATA_HOME"] = self.tmp
        if not os.path.exists("/usr/share/icons/hicolor/scalable/apps/fatal-lyrics.svg"):
            self.assertEqual(tray.icon_name(), "dialog-warning")
        apps = os.path.join(self.tmp, "icons", "hicolor", "scalable", "apps")
        os.makedirs(apps)
        open(os.path.join(apps, "fatal-lyrics.svg"), "w").close()
        self.assertEqual(tray.icon_name(), "fatal-lyrics")


class TestFatalControl(test_guard.FatalGuardTests):
    """Hereda el montaje (qs y daemon de mentira) pero NO sus tests: se descartan abajo."""

    def test_help_goes_to_stdout_and_exits_0(self):
        for arg in ("help", "--help", "-h"):
            r = self.fatal(arg)
            self.assertEqual(r.returncode, 0, arg)
            self.assertIn("usage: fatal", r.stdout)
            self.assertEqual(r.stderr, "")

    def test_an_invalid_command_goes_to_stderr_and_exits_1(self):
        r = self.fatal("nada")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout, "")
        self.assertIn("usage: fatal", r.stderr)

    def test_crt_on_with_everything_off_warns_and_writes_nothing(self):
        for sub in ("on", "toggle"):
            r = self.fatal("crt", sub)
            self.assertEqual(r.returncode, 1, sub)
            self.assertIn("isn't running", r.stderr)
            self.assertNotIn("CRT on", r.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.run_dir, "cartelitos-crt")))

    def test_crt_off_works_with_everything_off(self):
        r = self.fatal("crt", "off")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("CRT off", r.stdout)

    def test_status_reports_the_tube(self):
        self.assertIn("crt: off", self.fatal("status").stdout)
        self.assertEqual(self.fatal("on").returncode, 0)
        self.fatal("crt", "on")
        self.assertIn("crt: on", self.fatal("status").stdout)

    def test_on_confirms_both_halves(self):
        r = self.fatal("on")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("fatal ON", r.stdout)

    def test_on_says_why_when_the_daemon_dies(self):
        with open(os.path.join(self.home, "cartelitos.py"), "w") as f:
            f.write("#!/usr/bin/env python3\nimport sys\n"
                    "if '--check' in sys.argv: sys.exit(0)\n"
                    "print('boom: no module named x', file=sys.stderr)\nsys.exit(1)\n")
        r = self.fatal("on")
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("fatal ON", r.stdout)
        self.assertIn("daemon didn't start", r.stderr)
        self.assertIn("daemon.log", r.stderr)
        self.assertIn("boom", r.stderr)   # la última línea del log

    def test_on_without_quickshell_says_so(self):
        self.env["PATH"] = _toolbox(self.tmp)
        r = self.fatal("on")
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("fatal ON", r.stdout)
        self.assertIn("Quickshell", r.stderr)

    def test_on_accepts_quickshell_when_qs_is_missing(self):
        tools = _toolbox(self.tmp)
        shutil.copy(os.path.join(self.tmp, "bin", "qs"), os.path.join(tools, "quickshell"))
        self.env["PATH"] = tools
        r = self.fatal("on")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("fatal ON", r.stdout)


# la herencia trae los tests de FatalGuardTests: acá sólo corren los propios
for _name in [n for n in dir(test_guard.FatalGuardTests) if n.startswith("test_")]:
    if _name not in TestFatalControl.__dict__:
        setattr(TestFatalControl, _name, None)


class TestUnidadNoArranca(unittest.TestCase):
    """systemctl --user start devuelve 0 aunque la unit se salte por su Condition."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        bindir = os.path.join(self.tmp, "bin")
        os.makedirs(bindir)
        sc = os.path.join(bindir, "systemctl")
        with open(sc, "w") as f:
            f.write(test_guard.FAKE_SYSTEMCTL)
        os.chmod(sc, 0o755)
        self.env = dict(os.environ, XDG_RUNTIME_DIR=self.tmp, HOME=self.tmp,
                        SYSTEMCTL_LOG=os.path.join(self.tmp, "calls"),
                        PATH=bindir + os.pathsep + os.environ["PATH"])
        self.env.pop("FATAL_NO_UNIT", None)

    def _on(self, state):
        return subprocess.run([FATAL, "on"], capture_output=True, text=True, timeout=60,
                              env=dict(self.env, UNIT_STATE=state))

    def test_inactive_after_start_is_a_failure(self):
        r = self._on("inactive")
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("fatal ON", r.stdout)
        self.assertIn("WAYLAND_DISPLAY", r.stderr)

    def test_active_after_start_is_on(self):
        r = self._on("active")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("fatal ON", r.stdout)


if __name__ == "__main__":
    unittest.main()
