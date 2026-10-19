"""install.sh se niega a seguir con un python3 < 3.11 (config.py usa tomllib): antes
instalaba todo y el daemon reventaba al arrancar. El chequeo corre antes de tocar
HOME, así que con un python viejo no queda nada instalado."""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _exe(path, body):
    with open(path, "w", encoding="utf-8") as f:
        f.write("#!/bin/sh\n" + body)
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)


class TestInstalador(unittest.TestCase):
    def setUp(self):
        self.bindir = tempfile.mkdtemp()
        self.home = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.bindir, True)
        self.addCleanup(shutil.rmtree, self.home, True)
        # las dependencias están; lo que falla es el python
        _exe(os.path.join(self.bindir, "qs"), "exit 0\n")
        _exe(os.path.join(self.bindir, "playerctl"), "exit 0\n")
        # si el chequeo se rompe, install.sh llegaría a habilitar la unit de verdad:
        # un systemctl falso que dice "no hay sesión" lo corta
        _exe(os.path.join(self.bindir, "systemctl"), "exit 1\n")

    def _install(self):
        env = {"PATH": f"{self.bindir}:/usr/bin:/bin", "HOME": self.home,
               "XDG_CONFIG_HOME": os.path.join(self.home, ".config")}
        return subprocess.run(["bash", os.path.join(ROOT, "install.sh")], env=env,
                              capture_output=True, text=True, timeout=60)

    def test_python_older_than_311_stops_the_install(self):
        # `python3 -c 'sys.exit(version < 3.11)'` sale con 1 en un 3.10
        _exe(os.path.join(self.bindir, "python3"),
             'if [ "$1" = "-V" ]; then echo "Python 3.10.12"; exit 0; fi\nexit 1\n')
        out = self._install()
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("python3 >= 3.11", out.stdout)
        self.assertIn("Python 3.10.12", out.stdout)
        # nada instalado: el chequeo corta antes de crear ~/.local/bin
        self.assertFalse(os.path.exists(os.path.join(self.home, ".local")))


if __name__ == "__main__":
    unittest.main()
