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

    def test_mark_ready_writes_the_pid(self):
        ready = os.path.join(self.tmp, "run", "daemon.ready")
        os.makedirs(os.path.dirname(ready))
        util.mark_ready(ready)
        with open(ready) as f:
            self.assertEqual(f.read().strip(), str(os.getpid()))

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
kids = []
if os.environ.get("FAKE_QS_CHILD"):
    # el "relanzado por el crash handler": un `quickshell` que sobrevive al padre
    kids.append(subprocess.Popen([os.environ["FAKE_QS_CHILD"], "120"], close_fds=False).pid)
if os.environ.get("FAKE_QS_BYSTANDER"):
    # una app cualquiera que qs lanzó (un navegador): NO es quickshell
    kids.append(subprocess.Popen(["sleep", "120"], close_fds=False).pid)
with open(os.path.join(os.environ["XDG_RUNTIME_DIR"], "kids"), "w") as f:
    f.write(" ".join(map(str, kids)))
time.sleep(120)
"""

FAKE_DAEMON = """#!/usr/bin/env python3
import os, sys, time
if "--check" in sys.argv:
    sys.exit(0)
sys.path.insert(0, %r)
from cartelitos import util
lock = util.acquire_instance_lock()
if lock is None:
    sys.exit(1)
# como el real: escribe el flag del CRT de la config un rato DESPUÉS de arrancar
# y recién ahí avisa que está listo
time.sleep(float(os.environ.get("FAKE_DAEMON_DELAY", "0")))
with open(os.path.join(os.environ["XDG_RUNTIME_DIR"], "cartelitos-crt"), "w") as f:
    f.write("0")
util.mark_ready()
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
        # un "quickshell" (el relanzado/reporter del crash handler): comm quickshell
        self.fake_quickshell = os.path.join(self.tmp, "bin", "quickshell")
        os.symlink(shutil.which("sleep"), self.fake_quickshell)
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

    def kids(self):
        end = time.time() + 5
        path = os.path.join(self.run_dir, "kids")
        while time.time() < end:
            try:
                with open(path) as f:
                    got = [int(x) for x in f.read().split()]
                if got:
                    return got
            except (OSError, ValueError):
                pass
            time.sleep(0.1)
        self.fail("the fake qs never reported its children")

    @staticmethod
    def kill_quiet(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    def wait_lock_free(self, path, secs=5):
        import fcntl
        end = time.time() + secs
        while time.time() < end:
            with open(path, "a+") as f:
                try:
                    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    return
                except BlockingIOError:
                    pass
            time.sleep(0.1)
        self.fail("%s never got released" % path)

    def wait_gone(self, pid, secs=5):
        end = time.time() + secs
        while time.time() < end and self.alive(pid):
            time.sleep(0.1)
        return not self.alive(pid)

    def crt_flag(self):
        with open(os.path.join(self.run_dir, "cartelitos-crt")) as f:
            return f.read()

    def test_crt_on_right_after_restart_is_not_clobbered_by_the_daemon(self):
        # TRAMPAS corrida 8: el daemon escribe el flag al arrancar; `restart`
        # tiene que volver recién cuando lo hizo
        slow = dict(FAKE_DAEMON_DELAY="1.5")
        self.assertEqual(self.fatal("on", **slow).returncode, 0)
        self.fatal("crt", "on")
        self.assertEqual(self.crt_flag(), "1")
        r = self.fatal("restart", **slow)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.crt_flag(), "1")   # restart lo conserva
        self.fatal("crt", "off")
        self.fatal("restart", **slow)
        self.fatal("crt", "on")
        self.assertEqual(self.crt_flag(), "1")
        time.sleep(2)   # el daemon ya había escrito: nada lo pisa después
        self.assertEqual(self.crt_flag(), "1")

    def test_start_does_not_hang_if_the_daemon_dies_before_ready(self):
        with open(os.path.join(self.home, "cartelitos.py"), "w") as f:
            f.write("#!/usr/bin/env python3\nimport sys\nsys.exit(0 if '--check' in sys.argv else 1)\n")
        t0 = time.time()
        self.fatal("on")
        self.assertLess(time.time() - t0, 8)

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
        # el crash handler relanza el shell fuera del pidfile: vive en la sesión
        # del wrapper que tiene el lock, lo delata y `stop` lo baja también
        r = self.fatal("on", FAKE_QS_CHILD=self.fake_quickshell)
        self.assertEqual(r.returncode, 0, r.stderr)
        qs = self.pidfile("qs.pid")
        kid = self.kids()[0]
        os.kill(qs, signal.SIGKILL)  # el padre cae, el hijo queda
        self.assertTrue(self.wait_gone(qs))
        r = self.fatal("on")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("already running", r.stderr)
        self.fatal("stop")
        self.assertTrue(self.wait_gone(kid))
        self.assertEqual(self.fatal("on").returncode, 0)

    def test_stop_spares_a_bystander_and_it_never_holds_the_lock(self):
        # lo que qs lanza (un navegador, xdg-open) no hereda el lock: ni frena un
        # `on` cuando qs cae ni se lo lleva puesto un `stop`
        r = self.fatal("on", FAKE_QS_BYSTANDER="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        qs = self.pidfile("qs.pid")
        bystander = self.kids()[0]
        self.addCleanup(self.kill_quiet, bystander)
        lock = os.path.join(self.run_dir, "cartelitos", "qs.lock")
        held = [os.readlink("/proc/%d/fd/%s" % (bystander, fd)) for fd in os.listdir("/proc/%d/fd" % bystander)]
        self.assertFalse([h for h in held if h.endswith(".lock")], held)
        os.kill(qs, signal.SIGKILL)
        self.assertTrue(self.wait_gone(qs))
        self.wait_lock_free(lock)
        r = self.fatal("on", FAKE_QS_BYSTANDER="1")
        self.assertEqual(r.returncode, 0, r.stderr)   # el bystander vivo no cuenta como instancia
        self.assertTrue(self.alive(bystander))
        self.fatal("stop")
        self.wait_lock_free(lock)
        self.assertTrue(self.alive(bystander))        # stop no lo tocó
        for pid in self.kids():
            self.kill_quiet(pid)

    def test_the_lock_records_the_owner_pid(self):
        self.assertEqual(self.fatal("on").returncode, 0)
        self.wait_daemon_locked()
        for name, pid_name in (("qs.lock", "qs.pid"), ("daemon.lock", "daemon.pid")):
            with open(os.path.join(self.run_dir, "cartelitos", name)) as f:
                owner = int(f.read().strip())
            self.assertTrue(self.alive(owner), name)
        with open(os.path.join(self.run_dir, "cartelitos", "qs.lock")) as f:
            wrapper = int(f.read().strip())
        # qs cuelga del dueño del lock, que no es el mismo proceso
        self.assertNotEqual(wrapper, self.pidfile("qs.pid"))

    def test_stop_from_another_checkout_takes_down_the_instance(self):
        # `fatal on` desde un worktree levanta ESA copia: `stop` desde otra tiene que bajarla
        # igual (el pidfile no la reconoce por ruta, el lock sí)
        self.assertEqual(self.fatal("on").returncode, 0)
        self.wait_daemon_locked()
        qs, d = self.pidfile("qs.pid"), self.pidfile("daemon.pid")
        other = os.path.join(self.tmp, "other")
        os.makedirs(os.path.join(other, "shell"))
        for name in ("shell/shell.qml", "cartelitos.py"):
            with open(os.path.join(other, name), "w") as f:
                f.write("")
        self.fatal("stop", CARTELITOS_HOME=other)
        self.assertTrue(self.wait_gone(qs))
        self.assertTrue(self.wait_gone(d))

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
