"""Guardia de instancia única (corrida 7b, paso 0): un solo daemon y un solo
overlay por sesión. Lo del daemon se prueba en proceso; lo del overlay corre
`bin/fatal` de verdad contra un `qs` y un `cartelitos.py` de mentira que viven en
un directorio temporal, con su propio XDG_RUNTIME_DIR (no toca la sesión real)."""
import contextlib
import io
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, ROOT)

from cartelitos import daemon, util  # noqa: E402

FATAL = os.path.join(ROOT, "bin", "fatal")


class InstanceLockTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "run", "daemon.lock")
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_second_acquire_fails_until_the_first_lets_go(self):
        first = util.acquire_instance_lock(self.path)
        self.assertTrue(first)
        self.assertIsNone(util.acquire_instance_lock(self.path))
        first.close()
        again = util.acquire_instance_lock(self.path)
        self.assertTrue(again)
        again.close()

    def test_holder_pid_is_written(self):
        f = util.acquire_instance_lock(self.path)
        self.addCleanup(f.close)
        self.assertEqual(util.instance_lock_holder(self.path), str(os.getpid()))

    def test_unwritable_dir_does_not_block_startup(self):
        # la guardia es una red de seguridad: si no puede ni crear el archivo, el
        # daemon arranca igual en vez de quedar mudo
        with mock.patch.object(util.os, "makedirs", side_effect=PermissionError):
            self.assertTrue(util.acquire_instance_lock(self.path))

    def test_lock_dies_with_the_process(self):
        code = ("import sys; sys.path.insert(0, %r); from cartelitos import util;"
                "f = util.acquire_instance_lock(%r); print('ok' if f else 'no', flush=True);"
                "import time; time.sleep(30)" % (ROOT, self.path))
        p = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, text=True)
        self.addCleanup(p.stdout.close)
        self.addCleanup(p.kill)
        self.assertEqual(p.stdout.readline().strip(), "ok")
        self.assertIsNone(util.acquire_instance_lock(self.path))
        p.kill()
        p.wait()
        f = util.acquire_instance_lock(self.path)
        self.assertTrue(f)  # el kernel soltó el lock: nada que limpiar a mano
        f.close()

    def test_daemon_main_refuses_a_second_instance(self):
        holder = util.acquire_instance_lock(self.path)
        self.addCleanup(holder.close)
        with mock.patch.object(daemon, "acquire_instance_lock",
                               lambda: util.acquire_instance_lock(self.path)), \
             mock.patch.object(daemon, "instance_lock_holder",
                               lambda: util.instance_lock_holder(self.path)), \
             mock.patch.object(daemon, "DaemonLoop") as loop:
            with self.assertRaises(SystemExit) as cm, contextlib.redirect_stderr(io.StringIO()) as err:
                daemon.main()
        self.assertIn("already running", err.getvalue())
        self.assertEqual(cm.exception.code, 1)
        loop.assert_not_called()


FAKE_QS = """#!/usr/bin/env python3
import os, socket, subprocess, sys, time
s = socket.socket(socket.AF_UNIX)
s.bind(os.path.join(os.environ["XDG_RUNTIME_DIR"], "cartelitos.sock"))
if os.environ.get("FAKE_QS_CHILD"):
    # el "relanzado por el crash handler": un hijo que sobrevive al padre
    subprocess.Popen([sys.executable, "-c", "import time; time.sleep(120)", "shell.qml"], close_fds=False)
time.sleep(120)
"""

FAKE_DAEMON = """#!/usr/bin/env python3
import sys, time
if "--check" in sys.argv:
    sys.exit(0)
sys.path.insert(0, %r)
from cartelitos import util
lock = util.acquire_instance_lock()
if lock is None:
    sys.exit(1)
time.sleep(120)
""" % ROOT


class FatalGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(os.path.join(self.home, "shell"))
        os.makedirs(os.path.join(self.tmp, "bin"))
        self.run_dir = os.path.join(self.tmp, "xdg")
        os.makedirs(self.run_dir)
        with open(os.path.join(self.home, "shell", "shell.qml"), "w") as f:
            f.write("// fake\n")
        with open(os.path.join(self.home, "cartelitos.py"), "w") as f:
            f.write(FAKE_DAEMON)
        qs = os.path.join(self.tmp, "bin", "qs")
        with open(qs, "w") as f:
            f.write(FAKE_QS)
        os.chmod(qs, 0o755)
        self.env = dict(os.environ, CARTELITOS_HOME=self.home, XDG_RUNTIME_DIR=self.run_dir,
                        PATH=os.path.join(self.tmp, "bin") + os.pathsep + os.environ["PATH"],
                        HOME=self.tmp, XDG_CONFIG_HOME=os.path.join(self.tmp, "cfg"))
        self.addCleanup(self.fatal, "stop")

    def fatal(self, *args, **env):
        return subprocess.run([FATAL, *args], capture_output=True, text=True, timeout=60,
                              env=dict(self.env, **env))

    def pidfile(self, name):
        try:
            with open(os.path.join(self.run_dir, "cartelitos", name)) as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return None

    @staticmethod
    def alive(pid):
        try:
            os.kill(pid, 0)
        except OSError:
            return False
        # un zombie sin cosechar cuenta como muerto
        try:
            with open(f"/proc/{pid}/stat") as f:
                return f.read().rsplit(")", 1)[1].split()[0] != "Z"
        except OSError:
            return False

    def wait_daemon_locked(self, secs=5):
        """`fatal on` vuelve con el daemon recién forkeado: hasta que no tomó el
        lock, un segundo `on` compite con él en vez de ser rechazado."""
        path = os.path.join(self.run_dir, "cartelitos", "daemon.lock")
        end = time.time() + secs
        while time.time() < end:
            try:
                with open(path) as f:
                    if f.read().strip():
                        return
            except OSError:
                pass
            time.sleep(0.1)
        self.fail("the fake daemon never took its lock")

    def wait_gone(self, pid, secs=5):
        end = time.time() + secs
        while time.time() < end and self.alive(pid):
            time.sleep(0.1)
        return not self.alive(pid)

    def test_second_start_is_a_noop_and_keeps_the_pids(self):
        r = self.fatal("on")
        self.assertEqual(r.returncode, 0, r.stderr)
        qs, d = self.pidfile("qs.pid"), self.pidfile("daemon.pid")
        self.assertTrue(qs and d)
        r = self.fatal("on")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.pidfile("qs.pid"), self.pidfile("daemon.pid")), (qs, d))

    def test_orphan_overlay_blocks_start_without_clobbering_and_stop_kills_it(self):
        self.assertEqual(self.fatal("on").returncode, 0)
        qs = self.pidfile("qs.pid")
        # el overlay sigue vivo pero el pidfile ya no lo conoce (caso relanzado)
        os.unlink(os.path.join(self.run_dir, "cartelitos", "qs.pid"))
        r = self.fatal("on")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("already running", r.stderr)
        self.assertIsNone(self.pidfile("qs.pid"))  # no pisó nada
        self.assertTrue(self.alive(qs))
        self.fatal("stop")
        self.assertTrue(self.wait_gone(qs))
        self.assertEqual(self.fatal("on").returncode, 0)

    def test_stop_takes_down_a_child_that_outlived_the_overlay(self):
        # el crash handler relanza el shell fuera del pidfile: el lock heredado
        # lo delata y `stop` lo baja también
        r = self.fatal("on", FAKE_QS_CHILD="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        qs = self.pidfile("qs.pid")
        time.sleep(0.5)
        os.kill(qs, signal.SIGKILL)  # el padre cae, el hijo queda con el lock
        self.assertTrue(self.wait_gone(qs))
        r = self.fatal("on")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("already running", r.stderr)
        self.fatal("stop")
        self.assertEqual(self.fatal("on").returncode, 0)

    def test_second_daemon_exits_while_the_first_lives(self):
        self.assertEqual(self.fatal("on").returncode, 0)
        self.wait_daemon_locked()
        d = self.pidfile("daemon.pid")
        os.unlink(os.path.join(self.run_dir, "cartelitos", "daemon.pid"))
        r = self.fatal("on")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("daemon is already running", r.stderr)
        self.assertTrue(self.alive(d))


if __name__ == "__main__":
    unittest.main()
