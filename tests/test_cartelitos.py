"""Tests for the parts that are easy to break without noticing: the LRC parser,
the TOML writer that has to preserve your comments, config reloading, and the
three-way lyrics result that the cache and the retry both depend on.

Run with:  python3 -m unittest discover -s tests
"""
import json
import os
import sys
import tempfile
import threading
import time
import unittest
import urllib.error

# El módulo lee la config al importarse, y la CREA si no existe: sin esto un
# test tocaría la config real de quien corra la suite.
_TMP = tempfile.TemporaryDirectory()
os.environ["XDG_CONFIG_HOME"] = os.path.join(_TMP.name, "config")
os.environ["XDG_CACHE_HOME"] = os.path.join(_TMP.name, "cache")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cartelitos as c  # noqa: E402


class TestParseLrc(unittest.TestCase):
    def test_parses_timestamps_in_order(self):
        lines = c.parse_lrc("[00:12.50]second\n[00:05.00]first\n")
        self.assertEqual([ts for ts, _ in lines], [5.0, 12.5])
        self.assertEqual([text for _, text in lines], ["first", "second"])

    def test_minutes_add_up(self):
        (ts, _), = c.parse_lrc("[02:03.25]x")
        self.assertEqual(ts, 123.25)

    def test_repeated_timestamps_become_separate_lines(self):
        # un mismo verso marcado en varios momentos: una entrada por marca
        lines = c.parse_lrc("[00:01.00][00:09.00]chorus")
        self.assertEqual([ts for ts, _ in lines], [1.0, 9.0])

    def test_lines_without_timestamps_are_dropped(self):
        self.assertIsNone(c.parse_lrc("[ar:someone]\nplain text\n"))

    def test_empty_input(self):
        self.assertIsNone(c.parse_lrc(""))

    def test_keeps_blank_content_as_a_gap(self):
        # una marca sin texto es un silencio: se conserva, el loop la saltea
        lines = c.parse_lrc("[00:04.00]")
        self.assertEqual(lines, [(4.0, "")])


class TestCurrentLineIndex(unittest.TestCase):
    def setUp(self):
        self.lyrics = [(0.0, "a"), (10.0, "b"), (20.0, "c")]

    def test_before_the_first_line(self):
        self.assertEqual(c.current_line_index(self.lyrics, -1.0), -1)

    def test_exactly_on_a_timestamp(self):
        self.assertEqual(c.current_line_index(self.lyrics, 10.0), 1)

    def test_between_two(self):
        self.assertEqual(c.current_line_index(self.lyrics, 19.9), 1)

    def test_past_the_end_stays_on_the_last(self):
        self.assertEqual(c.current_line_index(self.lyrics, 9999.0), 2)


SAMPLE = """\
# fatal-lyrics — configuration
# a comment that must survive

[display]
scale = 1.0            # base size for all dialogs
spawn_area = "full"    # full | top | bottom

[effects]
glitch = "normal"      # off | soft | normal | aggressive
tearing = true

[behavior]
player = "spotify"
offset = 0.15
"""


class TestSaveConfig(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "config.toml")
        with open(self.path, "w") as f:
            f.write(SAMPLE)
        self._old = c.CONFIG_PATH
        c.CONFIG_PATH = self.path
        self.addCleanup(lambda: setattr(c, "CONFIG_PATH", self._old))

    def read(self):
        with open(self.path) as f:
            return f.read()

    def test_writes_nothing_when_there_are_no_changes(self):
        c._save_config({})
        self.assertEqual(self.read(), SAMPLE)

    def test_keeps_comments_and_alignment(self):
        c._save_config({"glitch": ("effects", "soft")})
        self.assertIn('glitch = "soft"      # off | soft | normal | aggressive',
                      self.read())
        self.assertIn("# a comment that must survive", self.read())

    def test_only_touches_the_key_in_its_own_section(self):
        # misma clave en dos secciones: se pisa la de la sección pedida
        with open(self.path, "a") as f:
            f.write("scale = 9.0\n")          # un `scale` intruso en [behavior]
        c._save_config({"scale": ("display", 2.0)})
        body = self.read()
        self.assertIn("scale = 2.0", body)
        self.assertIn("scale = 9.0", body)     # el de [behavior] queda intacto

    def test_adds_a_missing_key_to_its_section(self):
        c._save_config({"karaoke": ("display", True)})
        body = self.read()
        self.assertIn("karaoke = true", body)
        # dentro de [display], no al final del archivo
        self.assertLess(body.index("karaoke"), body.index("[effects]"))

    def test_creates_a_section_that_does_not_exist(self):
        c._save_config({"whatever": ("extra", 3)})
        self.assertIn("[extra]\nwhatever = 3", self.read())

    def test_types_are_written_as_toml(self):
        c._save_config({"tearing": ("effects", False),
                        "player": ("behavior", "vlc"),
                        "offset": ("behavior", -0.5)})
        body = self.read()
        self.assertIn("tearing = false", body)
        self.assertIn('player = "vlc"', body)
        self.assertIn("offset = -0.5", body)

    def test_a_list_round_trips(self):
        c._save_config({"screen": ("display", ["DP-1", "DP-2"])})
        self.assertIn('screen = ["DP-1", "DP-2"]', self.read())

    def test_what_it_writes_is_valid_toml(self):
        c._save_config({"scale": ("display", 1.5), "karaoke": ("display", True),
                        "screen": ("display", ["DP-1"])})
        import tomllib
        with open(self.path, "rb") as f:
            parsed = tomllib.load(f)
        self.assertEqual(parsed["display"]["scale"], 1.5)
        self.assertIs(parsed["display"]["karaoke"], True)
        self.assertEqual(parsed["display"]["screen"], ["DP-1"])


class TestReloadConfig(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "config.toml")
        with open(self.path, "w") as f:
            f.write(SAMPLE)
        self._old_path, self._old_cfg = c.CONFIG_PATH, c.CFG
        c.CONFIG_PATH = self.path
        c.CFG = c.load_config()

        def restore():
            c.CONFIG_PATH, c.CFG = self._old_path, self._old_cfg
        self.addCleanup(restore)

    def write(self, body):
        with open(self.path, "w") as f:
            f.write(body)

    def test_picks_up_a_change(self):
        self.write(SAMPLE.replace('glitch = "normal"', 'glitch = "off"'))
        self.assertTrue(c.reload_config())
        self.assertEqual(c.CFG["effects"]["glitch"], "off")

    def test_no_change_reports_false(self):
        self.assertFalse(c.reload_config())

    def test_a_broken_file_keeps_the_running_config(self):
        c.CFG["effects"]["glitch"] = "aggressive"
        self.write("[effects]\nglitch = \n")
        self.assertFalse(c.reload_config())
        # ni se resetea a los defaults ni se aplica basura
        self.assertEqual(c.CFG["effects"]["glitch"], "aggressive")

    def test_a_removed_key_goes_back_to_its_default(self):
        self.write(SAMPLE.replace('glitch = "normal"      # off | soft | normal | aggressive\n', ""))
        c.reload_config()
        self.assertEqual(c.CFG["effects"]["glitch"], c.DEFAULTS["effects"]["glitch"])

    def test_unknown_sections_are_ignored(self):
        self.write(SAMPLE + "\n[nonsense]\nfoo = 1\n")
        c.reload_config()
        self.assertNotIn("nonsense", c.CFG)

    def test_the_live_dict_is_mutated_in_place(self):
        # todo el proceso guarda referencias a CFG: si se reemplazara el dict,
        # los lectores viejos se quedarían con la config vieja para siempre
        before = c.CFG
        self.write(SAMPLE.replace("scale = 1.0", "scale = 2.0"))
        c.reload_config()
        self.assertIs(c.CFG, before)
        self.assertEqual(before["display"]["scale"], 2.0)


TRACK = {"id": "/t/1", "title": "Song", "artist": "Band", "album": "Album",
         "length": 200.0, "status": "Playing", "pos": 0.0, "art": ""}
LRC = "[00:01.00]one\n[00:02.00]two\n"


class TestFetchLyrics(unittest.TestCase):
    """El resultado tiene que distinguir "no tiene letra" de "no llegué a lrclib":
    el cache guarda el primero y el reintento sólo aplica al segundo."""

    def patch_http(self, fn):
        old = c.http_json
        c.http_json = fn
        self.addCleanup(lambda: setattr(c, "http_json", old))

    def test_found(self):
        self.patch_http(lambda url: {"syncedLyrics": LRC})
        status, lines = c.fetch_lyrics(TRACK)
        self.assertEqual(status, "ok")
        self.assertEqual(len(lines), 2)

    def test_server_says_no_match_is_none_not_error(self):
        def not_found(url):
            raise urllib.error.HTTPError(url, 404, "Not Found", {}, None)
        self.patch_http(not_found)
        self.assertEqual(c.fetch_lyrics(TRACK), ("none", None))

    def test_network_down_is_error(self):
        def down(url):
            raise urllib.error.URLError("no route to host")
        self.patch_http(down)
        self.assertEqual(c.fetch_lyrics(TRACK), ("error", None))

    def test_falls_back_to_search_when_the_exact_match_has_no_synced_lyrics(self):
        def http(url):
            if "/get?" in url:
                return {"syncedLyrics": None}
            return [{"syncedLyrics": None}, {"syncedLyrics": LRC}]
        self.patch_http(http)
        status, lines = c.fetch_lyrics(TRACK)
        self.assertEqual(status, "ok")
        self.assertEqual(len(lines), 2)

    def test_answered_but_nothing_synced_anywhere_is_none(self):
        self.patch_http(lambda url: [] if "/search?" in url else {"syncedLyrics": None})
        self.assertEqual(c.fetch_lyrics(TRACK), ("none", None))

    def test_unsynced_text_does_not_count_as_a_hit(self):
        # letra sin marcas de tiempo: parse_lrc devuelve None, no sirve
        self.patch_http(lambda url: {"syncedLyrics": "just words\nno timestamps"}
                        if "/get?" in url else [])
        self.assertEqual(c.fetch_lyrics(TRACK), ("none", None))


class TestLyricsCache(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self._old = c.CACHE_DIR
        c.CACHE_DIR = self.dir.name
        self.addCleanup(lambda: setattr(c, "CACHE_DIR", self._old))

    def test_miss_on_an_empty_cache(self):
        self.assertIsNone(c.cache_get(TRACK))

    def test_round_trip(self):
        c.cache_put(TRACK, "ok", [(1.0, "one"), (2.0, "two")])
        status, lines = c.cache_get(TRACK)
        self.assertEqual(status, "ok")
        self.assertEqual(lines, [(1.0, "one"), (2.0, "two")])

    def test_a_network_failure_is_never_cached(self):
        # si no, cada tema que sonó sin internet queda marcado como sin letra
        c.cache_put(TRACK, "error", None)
        self.assertIsNone(c.cache_get(TRACK))

    def test_no_lyrics_is_cached(self):
        c.cache_put(TRACK, "none", None)
        self.assertEqual(c.cache_get(TRACK), ("none", None))

    def test_no_lyrics_expires(self):
        # lrclib suma letras con el tiempo: el "no hay" no puede ser para siempre
        c.cache_put(TRACK, "none", None)
        path = c._cache_path(TRACK)
        with open(path) as f:
            data = json.load(f)
        data["at"] = int(time.time()) - c.NONE_TTL - 1
        with open(path, "w") as f:
            json.dump(data, f)
        self.assertIsNone(c.cache_get(TRACK))

    def test_a_found_result_does_not_expire(self):
        c.cache_put(TRACK, "ok", [(1.0, "one")])
        path = c._cache_path(TRACK)
        with open(path) as f:
            data = json.load(f)
        data["at"] = 0
        with open(path, "w") as f:
            json.dump(data, f)
        self.assertEqual(c.cache_get(TRACK)[0], "ok")

    def test_different_tracks_do_not_collide(self):
        other = dict(TRACK, title="Another")
        c.cache_put(TRACK, "ok", [(1.0, "one")])
        self.assertIsNone(c.cache_get(other))

    def test_a_different_length_is_a_different_entry(self):
        # el largo entra en la clave: otra versión del tema no reusa la letra
        c.cache_put(TRACK, "ok", [(1.0, "one")])
        self.assertIsNone(c.cache_get(dict(TRACK, length=300.0)))

    def test_a_corrupt_file_is_a_miss_not_a_crash(self):
        os.makedirs(c.CACHE_DIR, exist_ok=True)
        with open(c._cache_path(TRACK), "w") as f:
            f.write("{ not json")
        self.assertIsNone(c.cache_get(TRACK))


class TestFetchAsync(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self._old = c.CACHE_DIR
        c.CACHE_DIR = self.dir.name
        self.addCleanup(lambda: setattr(c, "CACHE_DIR", self._old))
        with c._fetch_lock:
            c._fetch.update(gen=0, id=None, lyrics=None, done=False)

    def patch_fetch(self, fn):
        old = c.fetch_lyrics
        c.fetch_lyrics = fn
        self.addCleanup(lambda: setattr(c, "fetch_lyrics", old))

    def wait_done(self, timeout=3.0):
        end = time.time() + timeout
        while time.time() < end:
            if c._fetch["done"]:
                return True
            time.sleep(0.01)
        return False

    def test_publishes_the_result(self):
        self.patch_fetch(lambda t: ("ok", [(1.0, "one")]))
        c.fetch_lyrics_async(TRACK)
        self.assertTrue(self.wait_done())
        self.assertEqual(c._fetch["lyrics"], [(1.0, "one")])
        self.assertEqual(c._fetch["id"], TRACK["id"])

    def test_a_slow_result_for_an_old_track_is_dropped(self):
        # la carrera real: el hilo del tema A termina después de cambiar a B.
        # Sin el chequeo de generación, A pisaría la letra de B.
        started = threading.Event()

        def slow(track):
            started.set()
            time.sleep(0.3)
            return "ok", [(1.0, "from A")]
        self.patch_fetch(slow)
        c.fetch_lyrics_async(TRACK)
        started.wait(1.0)
        self.patch_fetch(lambda t: ("ok", [(1.0, "from B")]))
        c.fetch_lyrics_async(dict(TRACK, id="/t/2", title="B"))
        self.assertTrue(self.wait_done())
        time.sleep(0.5)   # que el hilo viejo termine y trate de publicar
        self.assertEqual(c._fetch["lyrics"], [(1.0, "from B")])
        self.assertEqual(c._fetch["id"], "/t/2")

    def test_a_cache_hit_skips_the_network(self):
        c.cache_put(TRACK, "ok", [(1.0, "cached")])

        def boom(track):
            raise AssertionError("should not have hit the network")
        self.patch_fetch(boom)
        c.fetch_lyrics_async(TRACK)
        self.assertTrue(self.wait_done())
        self.assertEqual(c._fetch["lyrics"], [(1.0, "cached")])

    def test_a_result_is_cached_for_next_time(self):
        self.patch_fetch(lambda t: ("ok", [(1.0, "one")]))
        c.fetch_lyrics_async(TRACK)
        self.assertTrue(self.wait_done())
        self.assertEqual(c.cache_get(TRACK), ("ok", [(1.0, "one")]))

    def test_retries_a_network_failure_then_succeeds(self):
        calls = []
        old_delay = c.RETRY_DELAY
        c.RETRY_DELAY = 0
        self.addCleanup(lambda: setattr(c, "RETRY_DELAY", old_delay))

        def flaky(track):
            calls.append(1)
            return ("error", None) if len(calls) == 1 else ("ok", [(1.0, "one")])
        self.patch_fetch(flaky)
        c.fetch_lyrics_async(TRACK)
        self.assertTrue(self.wait_done())
        self.assertEqual(len(calls), 2)
        self.assertEqual(c._fetch["lyrics"], [(1.0, "one")])

    def test_gives_up_after_the_retries_without_caching(self):
        old_delay = c.RETRY_DELAY
        c.RETRY_DELAY = 0
        self.addCleanup(lambda: setattr(c, "RETRY_DELAY", old_delay))
        calls = []

        def down(track):
            calls.append(1)
            return "error", None
        self.patch_fetch(down)
        c.fetch_lyrics_async(TRACK)
        time.sleep(0.5)
        self.assertEqual(len(calls), c.RETRIES + 1)
        self.assertFalse(c._fetch["done"])
        self.assertIsNone(c.cache_get(TRACK))

    def test_no_lyrics_publishes_an_empty_result(self):
        self.patch_fetch(lambda t: ("none", None))
        c.fetch_lyrics_async(TRACK)
        self.assertTrue(self.wait_done())
        self.assertIsNone(c._fetch["lyrics"])


if __name__ == "__main__":
    unittest.main()
