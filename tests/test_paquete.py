"""packaging/PKGBUILD instala todo lo que el overlay lee de shell/. Con la lista fija
se le escaparon Motion.qml, los motifs y la membrana: el instalable de AUR arrancaba
sin CRT y sin error claro. Ahora son globs; este test expande los mismos globs con
bash (como makepkg) y los compara con lo que git versiona bajo shell/."""
import os
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKGBUILD = os.path.join(ROOT, "packaging", "PKGBUILD")


def _shell_globs():
    with open(PKGBUILD, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith("for f in shell/"):
                return s[len("for f in "):s.index("; do")]
    raise AssertionError("PKGBUILD: no hay el for de shell/")


def _run(args):
    return subprocess.run(args, cwd=ROOT, capture_output=True, text=True, check=True).stdout


class TestPaquete(unittest.TestCase):
    def test_pkgbuild_installs_every_tracked_shell_file(self):
        try:
            tracked = _run(["git", "ls-files", "shell/"]).split()
        except (OSError, subprocess.CalledProcessError):
            self.skipTest("sin git: no hay qué comparar")
        # bash expande el glob igual que makepkg; un patrón sin match queda literal y
        # aparece como faltante acá
        installed = _run(["bash", "-c", f'for f in {_shell_globs()}; do echo "$f"; done']).split()
        self.assertEqual(sorted(installed), sorted(tracked))

    def test_the_overlay_entry_points_are_installed(self):
        # shell.qml carga Motion.qml y sus motifs: si alguno no entra al paquete, el
        # overlay no arranca (el caso que se escapó con la lista fija)
        installed = _run(["bash", "-c", f'for f in {_shell_globs()}; do echo "$f"; done']).split()
        for name in ("shell/shell.qml", "shell/Motion.qml", "shell/Crt.qml", "shell/crt.frag.qsb"):
            self.assertIn(name, installed)


if __name__ == "__main__":
    unittest.main()
