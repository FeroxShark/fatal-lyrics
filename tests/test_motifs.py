"""Tests del parseo de `fatal crt motif` (cartelitos.motifs).

`parse_force` es pura a propósito: los kinds y los monitores se le pasan, así
que acá no hace falta ni shell.qml ni un compositor. Lo único que sí mira el
archivo de verdad es `read_kinds`, que ES la razón de ser del módulo: la lista
de dibujos válidos sale de `motifKinds` en shell/shell.qml y no de una copia."""
import contextlib
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))  # noqa: E402

from cartelitos import motifs  # noqa: E402

KINDS = ["eye", "dunes", "tunnel", "plasma"]
SCREENS = ["HDMI-A-2", "DP-4", "DP-5"]


class TestReadKinds(unittest.TestCase):
    def test_reads_the_pool_from_the_real_shell_qml(self):
        kinds = motifs.read_kinds()
        self.assertIn("dunes", kinds)
        self.assertIn("eye", kinds)
        self.assertGreater(len(kinds), 10)

    def test_a_shell_qml_that_is_not_there_gives_an_empty_list(self):
        self.assertEqual(motifs.read_kinds("/nope/shell.qml"), [])

    def test_the_kinds_land_in_the_usage_text(self):
        self.assertIn("dunes", motifs.usage(KINDS))


class TestParseForce(unittest.TestCase):
    def test_a_bare_kind_goes_to_every_screen(self):
        ev, err = motifs.parse_force(["dunes"], kinds=KINDS, screens=SCREENS)
        self.assertIsNone(err)
        self.assertEqual(ev, {"cmd": "motif", "kind": "dunes", "screen": "all"})

    def test_a_screen_name_travels_as_the_name(self):
        ev, err = motifs.parse_force(["dunes", "--screen", "DP-4"],
                                     kinds=KINDS, screens=SCREENS)
        self.assertIsNone(err)
        self.assertEqual(ev["screen"], "DP-4")

    def test_the_equals_form_of_the_flag_works_too(self):
        ev, _ = motifs.parse_force(["dunes", "--screen=DP-5"],
                                   kinds=KINDS, screens=SCREENS)
        self.assertEqual(ev["screen"], "DP-5")

    def test_a_numeric_screen_travels_as_an_int(self):
        ev, err = motifs.parse_force(["dunes", "-s", "2"],
                                     kinds=KINDS, screens=SCREENS)
        self.assertIsNone(err)
        self.assertEqual(ev["screen"], 2)
        self.assertIsInstance(ev["screen"], int)

    def test_off_turns_the_force_off_and_carries_no_screen(self):
        for word in ("off", "none", "clear"):
            ev, err = motifs.parse_force([word], kinds=KINDS, screens=SCREENS)
            self.assertIsNone(err)
            self.assertEqual(ev, {"cmd": "motif", "kind": None})

    def test_an_unknown_kind_is_an_error_that_lists_the_valid_ones(self):
        ev, err = motifs.parse_force(["desierto"], kinds=KINDS, screens=SCREENS)
        self.assertIsNone(ev)
        self.assertIn("desierto", err)
        self.assertIn("dunes", err)

    def test_an_unknown_screen_name_is_an_error_that_lists_the_real_ones(self):
        ev, err = motifs.parse_force(["dunes", "--screen", "DP-9"],
                                     kinds=KINDS, screens=SCREENS)
        self.assertIsNone(ev)
        self.assertIn("DP-9", err)
        self.assertIn("DP-4", err)

    def test_an_index_past_the_last_screen_is_an_error(self):
        ev, err = motifs.parse_force(["dunes", "--screen", "3"],
                                     kinds=KINDS, screens=SCREENS)
        self.assertIsNone(ev)
        self.assertIn("out of range", err)

    def test_a_negative_index_is_an_error_even_without_knowing_the_screens(self):
        # -1 es "todas" del lado del QML: dejarlo pasar desde el CLI sería
        # forzar la pared entera creyendo que se pidió una sola pantalla
        ev, err = motifs.parse_force(["dunes", "--screen", "-1"], kinds=KINDS)
        self.assertIsNone(ev)
        self.assertIn("out of range", err)

    def test_without_the_screen_list_a_name_goes_through_as_is(self):
        # sin hyprctl no hay con qué validar: se manda y decide el overlay
        ev, err = motifs.parse_force(["dunes", "--screen", "DP-9"], kinds=KINDS)
        self.assertIsNone(err)
        self.assertEqual(ev["screen"], "DP-9")

    def test_the_word_all_is_not_read_as_a_screen_name(self):
        ev, err = motifs.parse_force(["dunes", "--screen", "all"],
                                     kinds=KINDS, screens=SCREENS)
        self.assertIsNone(err)
        self.assertEqual(ev["screen"], "all")

    def test_the_flag_without_a_value_is_an_error(self):
        ev, err = motifs.parse_force(["dunes", "--screen"], kinds=KINDS)
        self.assertIsNone(ev)
        self.assertIn("--screen", err)

    def test_an_unknown_flag_is_an_error(self):
        ev, err = motifs.parse_force(["dunes", "--pantalla", "DP-4"], kinds=KINDS)
        self.assertIsNone(ev)
        self.assertIn("--pantalla", err)

    def test_no_arguments_prints_the_usage(self):
        ev, err = motifs.parse_force([], kinds=KINDS)
        self.assertIsNone(ev)
        self.assertIn("usage:", err)

    def test_help_prints_the_usage_with_the_kinds(self):
        for flag in ("-h", "--help"):
            ev, err = motifs.parse_force([flag], kinds=KINDS)
            self.assertIsNone(ev)
            self.assertIn("tunnel", err)

    def test_off_does_not_need_the_kind_to_be_a_valid_motif(self):
        # "off" no está en motifKinds y no tiene que estarlo
        self.assertNotIn("off", motifs.read_kinds())


class TestForceCli(unittest.TestCase):
    """El código de salida: lo que ve bin/fatal. La salida se traga: el módulo
    imprime para la persona, y el reporte de los tests no es para eso."""

    def cli(self, argv):
        with contextlib.redirect_stdout(io.StringIO()):
            return motifs.force_cli(argv, screens=SCREENS)

    def test_help_exits_clean(self):
        self.assertEqual(self.cli(["--help"]), 0)

    def test_a_bad_kind_exits_with_an_error(self):
        self.assertEqual(self.cli(["noexiste"]), 1)

    def test_a_dead_overlay_is_an_error_and_not_a_traceback(self):
        real = motifs.SOCK_PATH
        motifs.SOCK_PATH = "/nope/cartelitos.sock"
        try:
            self.assertEqual(self.cli(["off"]), 1)
        finally:
            motifs.SOCK_PATH = real


if __name__ == "__main__":
    unittest.main()
