"""Tests for the parts that are easy to break without noticing: the LRC parser,
the TOML writer that has to preserve your comments, config reloading, and the
three-way lyrics result that the cache and the retry both depend on.

Run with:  python3 -m unittest discover -s tests
"""
import atexit
import builtins
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
from unittest import mock

# El módulo lee la config al importarse, y la CREA si no existe: sin esto un
# test tocaría la config real de quien corra la suite.
_TMP = tempfile.TemporaryDirectory()
atexit.register(_TMP.cleanup)  # si no, el finalizer avisa que quedó sin limpiar
os.environ["XDG_CONFIG_HOME"] = os.path.join(_TMP.name, "config")
os.environ["XDG_CACHE_HOME"] = os.path.join(_TMP.name, "cache")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cartelitos as c  # noqa: E402
# Los globals se parchean en SU módulo: `config.CFG` es una copia de la
# referencia y pisarla no cambia lo que lee el resto del paquete.
from cartelitos import audio, config, ipc, lyrics, system, tray, util  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _wait_cmdline(pid, timeout=5.0):
    """El /proc de un hijo recién forkeado tiene el cmdline VACÍO hasta que
    termina el exec: sin esperarlo, el guard de PID reciclado da falso negativo."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                if f.read().strip(b"\x00"):
                    return True
        except OSError:
            return False
        time.sleep(0.01)
    return False


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
        self._old = config.CONFIG_PATH
        config.CONFIG_PATH = self.path
        self.addCleanup(lambda: setattr(config, "CONFIG_PATH", self._old))

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
        self._old_path, self._old_cfg = config.CONFIG_PATH, config.CFG
        config.CONFIG_PATH = self.path
        config.CFG = c.load_config()

        def restore():
            config.CONFIG_PATH, config.CFG = self._old_path, self._old_cfg
        self.addCleanup(restore)

    def write(self, body):
        with open(self.path, "w") as f:
            f.write(body)

    def test_picks_up_a_change(self):
        self.write(SAMPLE.replace('glitch = "normal"', 'glitch = "off"'))
        self.assertTrue(c.reload_config())
        self.assertEqual(config.CFG["effects"]["glitch"], "off")

    def test_no_change_reports_false(self):
        self.assertFalse(c.reload_config())

    def test_a_broken_file_keeps_the_running_config(self):
        config.CFG["effects"]["glitch"] = "aggressive"
        self.write("[effects]\nglitch = \n")
        self.assertFalse(c.reload_config())
        # ni se resetea a los defaults ni se aplica basura
        self.assertEqual(config.CFG["effects"]["glitch"], "aggressive")

    def test_a_removed_key_goes_back_to_its_default(self):
        self.write(SAMPLE.replace('glitch = "normal"      # off | soft | normal | aggressive\n', ""))
        c.reload_config()
        self.assertEqual(config.CFG["effects"]["glitch"], c.DEFAULTS["effects"]["glitch"])

    def test_unknown_sections_are_ignored(self):
        self.write(SAMPLE + "\n[nonsense]\nfoo = 1\n")
        c.reload_config()
        self.assertNotIn("nonsense", config.CFG)

    def test_the_live_dict_is_mutated_in_place(self):
        # todo el proceso guarda referencias a CFG: si se reemplazara el dict,
        # los lectores viejos se quedarían con la config vieja para siempre
        before = config.CFG
        self.write(SAMPLE.replace("scale = 1.0", "scale = 2.0"))
        c.reload_config()
        self.assertIs(config.CFG, before)
        self.assertEqual(before["display"]["scale"], 2.0)


TRACK = {"id": "/t/1", "title": "Song", "artist": "Band", "album": "Album",
         "length": 200.0, "status": "Playing", "pos": 0.0, "art": ""}
LRC = "[00:01.00]one\n[00:02.00]two\n"


class TestFetchLyrics(unittest.TestCase):
    """El resultado tiene que distinguir "no tiene letra" de "no llegué a lrclib":
    el cache guarda el primero y el reintento sólo aplica al segundo."""

    def patch_http(self, fn):
        old = lyrics.http_json
        lyrics.http_json = fn
        self.addCleanup(lambda: setattr(lyrics, "http_json", old))

    def test_found(self):
        self.patch_http(lambda url: {"syncedLyrics": LRC})
        status, lines = c.fetch_lyrics(TRACK)
        self.assertEqual(status, "ok")
        self.assertEqual(len(lines), 2)

    def test_server_says_no_match_is_none_not_error(self):
        def not_found(url):
            # con fp=None, HTTPError se abre un TemporaryFile propio: hay que cerrarlo
            err = urllib.error.HTTPError(url, 404, "Not Found", {}, None)
            self.addCleanup(err.close)
            raise err
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
        self._old = lyrics.CACHE_DIR
        lyrics.CACHE_DIR = self.dir.name
        self.addCleanup(lambda: setattr(lyrics, "CACHE_DIR", self._old))

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
        os.makedirs(lyrics.CACHE_DIR, exist_ok=True)
        with open(c._cache_path(TRACK), "w") as f:
            f.write("{ not json")
        self.assertIsNone(c.cache_get(TRACK))


class TestFetchAsync(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self._old = lyrics.CACHE_DIR
        lyrics.CACHE_DIR = self.dir.name
        self.addCleanup(lambda: setattr(lyrics, "CACHE_DIR", self._old))
        # un hilo de otro test que siga vivo se lleva un lugar del cupo y hace
        # fallar al que viene: se espera a que muera antes de tocar el contador
        self.wait_quiet()
        with c._fetch_lock:
            c._fetch.update(gen=0, id=None, lyrics=None, done=False)
            lyrics._inflight = 0
            lyrics._pending = None
        self.addCleanup(self.wait_quiet)

    def lyrics_threads(self):
        return [t for t in threading.enumerate() if t.name == "lyrics" and t.is_alive()]

    def wait_quiet(self, timeout=3.0):
        end = time.time() + timeout
        while time.time() < end and self.lyrics_threads():
            time.sleep(0.01)

    def patch_fetch(self, fn):
        old = lyrics.fetch_lyrics
        lyrics.fetch_lyrics = fn
        self.addCleanup(lambda: setattr(lyrics, "fetch_lyrics", old))

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
        old_delay = lyrics.RETRY_DELAY
        lyrics.RETRY_DELAY = 0
        self.addCleanup(lambda: setattr(lyrics, "RETRY_DELAY", old_delay))

        def flaky(track):
            calls.append(1)
            return ("error", None) if len(calls) == 1 else ("ok", [(1.0, "one")])
        self.patch_fetch(flaky)
        c.fetch_lyrics_async(TRACK)
        self.assertTrue(self.wait_done())
        self.assertEqual(len(calls), 2)
        self.assertEqual(c._fetch["lyrics"], [(1.0, "one")])

    def test_gives_up_after_the_retries_without_caching(self):
        old_delay = lyrics.RETRY_DELAY
        lyrics.RETRY_DELAY = 0
        self.addCleanup(lambda: setattr(lyrics, "RETRY_DELAY", old_delay))
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

    def test_a_burst_of_skips_doesnt_pile_up_threads(self):
        # saltando temas rápido con lrclib lento, antes quedaba un hilo por
        # cambio de tema: la generación tiraba el resultado, pero no el hilo
        release = threading.Event()
        self.addCleanup(release.set)
        started = threading.Semaphore(0)

        def slow(track):
            started.release()
            release.wait(5.0)
            return "ok", [(1.0, track["title"])]
        self.patch_fetch(slow)
        for i in range(6):
            c.fetch_lyrics_async(dict(TRACK, id=f"/t/{i}", title=f"T{i}"))
        for _ in range(c.MAX_INFLIGHT):
            self.assertTrue(started.acquire(timeout=2.0))
        time.sleep(0.2)   # que alcance a arrancar cualquier hilo de más
        self.assertLessEqual(len(self.lyrics_threads()), c.MAX_INFLIGHT)
        release.set()

    def test_the_last_track_of_the_burst_still_gets_its_lyrics(self):
        # el cupo no puede comerse el tema que quedó sonando: el que no
        # encuentra lugar espera, y lo levanta el primer hilo que se libera
        release = threading.Event()
        self.addCleanup(release.set)
        started = threading.Semaphore(0)

        def slow(track):
            started.release()
            release.wait(5.0)
            return "ok", [(1.0, track["title"])]
        self.patch_fetch(slow)
        for i in range(6):
            c.fetch_lyrics_async(dict(TRACK, id=f"/t/{i}", title=f"T{i}"))
        for _ in range(c.MAX_INFLIGHT):
            self.assertTrue(started.acquire(timeout=2.0))
        release.set()
        self.assertTrue(self.wait_done())
        self.assertEqual(c._fetch["id"], "/t/5")
        self.assertEqual(c._fetch["lyrics"], [(1.0, "T5")])

    def test_the_queue_keeps_the_newest_track_only(self):
        # esperando lugar hay UNO solo: el último cambio pisa al anterior
        release = threading.Event()
        self.addCleanup(release.set)
        started = threading.Semaphore(0)
        seen = []

        def slow(track):
            started.release()
            seen.append(track["title"])
            release.wait(5.0)
            return "ok", [(1.0, track["title"])]
        self.patch_fetch(slow)
        for i in range(5):
            c.fetch_lyrics_async(dict(TRACK, id=f"/t/{i}", title=f"T{i}"))
        for _ in range(c.MAX_INFLIGHT):
            self.assertTrue(started.acquire(timeout=2.0))
        release.set()
        self.assertTrue(self.wait_done())
        self.wait_quiet()
        # dos hilos + el que esperaba: T2 y T3 nunca se buscaron
        self.assertEqual(len(seen), c.MAX_INFLIGHT + 1)
        self.assertIn("T4", seen)
        self.assertNotIn("T3", seen)

    def test_a_thread_that_wont_start_gives_the_slot_back(self):
        # si no se devuelve el cupo, dos fallos así y no hay más letra hasta
        # reiniciar el daemon
        with mock.patch.object(lyrics.threading.Thread, "start",
                               side_effect=RuntimeError("can't start new thread")):
            c.fetch_lyrics_async(TRACK)
        self.assertEqual(lyrics._inflight, 0)
        self.patch_fetch(lambda t: ("ok", [(1.0, "one")]))
        c.fetch_lyrics_async(TRACK)
        self.assertTrue(self.wait_done())

    def test_the_retry_waits_the_jittered_delay(self):
        # el reintento duerme lo que dice el jitter, no el número pelado
        calls = []

        def flaky(track):
            calls.append(1)
            return ("error", None) if len(calls) == 1 else ("ok", [(1.0, "one")])
        self.patch_fetch(flaky)
        with mock.patch.object(lyrics, "_retry_delay", return_value=0.6) as delay:
            start = time.time()
            c.fetch_lyrics_async(TRACK)
            self.assertTrue(self.wait_done())
            elapsed = time.time() - start
        delay.assert_called_once_with()
        self.assertGreaterEqual(elapsed, 0.4)   # una vuelta de 0.5s
        self.assertLess(elapsed, 1.5)           # y no las dos que pediría 1.2s


class TestRetryJitter(unittest.TestCase):
    """El delay del reintento con ruido: sin él, dos temas que fallan juntos
    vuelven a lrclib en el mismo segundo, para siempre."""

    def test_the_jitter_is_symmetric_around_the_base(self):
        with mock.patch.object(lyrics.random, "uniform", return_value=0.2) as uniform:
            self.assertAlmostEqual(lyrics._retry_delay(), lyrics.RETRY_DELAY * 1.2)
        uniform.assert_called_once_with(-lyrics.RETRY_JITTER, lyrics.RETRY_JITTER)
        with mock.patch.object(lyrics.random, "uniform", return_value=-0.2):
            self.assertAlmostEqual(lyrics._retry_delay(), lyrics.RETRY_DELAY * 0.8)

    def test_the_delay_never_leaves_the_band(self):
        for _ in range(200):
            delay = lyrics._retry_delay()
            self.assertGreaterEqual(delay, lyrics.RETRY_DELAY * 0.8)
            self.assertLessEqual(delay, lyrics.RETRY_DELAY * 1.2)

    def test_two_retries_dont_land_on_the_same_second(self):
        self.assertGreater(len({lyrics._retry_delay() for _ in range(20)}), 1)

    def test_a_zero_delay_stays_zero(self):
        # los tests que apuran el reintento ponen RETRY_DELAY=0: el ruido no
        # puede convertir eso en una espera
        old = lyrics.RETRY_DELAY
        lyrics.RETRY_DELAY = 0
        self.addCleanup(lambda: setattr(lyrics, "RETRY_DELAY", old))
        self.assertEqual(lyrics._retry_delay(), 0)


if __name__ == "__main__":
    unittest.main()


class TestCrtSwitch(unittest.TestCase):
    """El interruptor del modo CRT es un archivo, no el socket: el overlay lo
    vigila él mismo, así que apagarlo tiene que funcionar con el daemon muerto."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self._old = config.CRT_PATH
        config.CRT_PATH = os.path.join(self.dir.name, "cartelitos-crt")
        self.addCleanup(lambda: setattr(config, "CRT_PATH", self._old))

    def test_off_when_the_file_is_not_there(self):
        self.assertFalse(c.crt_on())

    def test_on_and_off_round_trip(self):
        self.assertTrue(c.set_crt(True))
        self.assertTrue(c.crt_on())
        self.assertTrue(c.set_crt(False))
        self.assertFalse(c.crt_on())

    def test_the_file_holds_a_single_flag(self):
        c.set_crt(True)
        with open(config.CRT_PATH) as f:
            self.assertEqual(f.read(), "1")

    def test_garbage_reads_as_off(self):
        with open(config.CRT_PATH, "w") as f:
            f.write("whatever")
        self.assertFalse(c.crt_on())

    def test_no_leftover_temp_file(self):
        # se escribe con rename atómico: el overlay nunca lee un archivo a medias
        c.set_crt(True)
        self.assertEqual(sorted(os.listdir(self.dir.name)), ["cartelitos-crt"])

    def test_a_directory_that_does_not_exist_does_not_raise(self):
        config.CRT_PATH = os.path.join(self.dir.name, "nope", "cartelitos-crt")
        self.assertFalse(c.set_crt(True))
        self.assertFalse(c.crt_on())


class TestConfigEvent(unittest.TestCase):
    """El evento de config se arma con CONFIG_EVENT_MAP: una clave nueva en
    DEFAULTS que no se agregue a ese mapa nunca llega al overlay, y no falla
    nada — simplemente no anda."""

    def test_every_crt_key_reaches_the_overlay(self):
        ev = c._config_event()
        # `enabled` viaja por el archivo interruptor y `audio` es cosa del daemon
        # (levanta la captura): al overlay no le sirven, el resto sí tiene que llegar
        daemon_only = {"enabled", "audio"}
        for key in c.DEFAULTS["crt"]:
            if key in daemon_only:
                continue
            self.assertIn(f"crt_{key}", ev, f"crt.{key} no llega al overlay")

    def test_the_event_is_json(self):
        json.dumps(c._config_event())

    def test_config_event_map_points_at_real_defaults_keys(self):
        # cada (evento, sección, clave) del mapa tiene que apuntar a algo que
        # exista de verdad en DEFAULTS: una entrada con una sección/clave con
        # un typo rompería silenciosamente en runtime (KeyError) recién cuando
        # se manda el primer evento, no al importar el módulo
        for event_key, section, cfg_key in ipc.CONFIG_EVENT_MAP:
            self.assertIn(section, c.DEFAULTS, f"{event_key}: sección {section} no existe")
            self.assertIn(cfg_key, c.DEFAULTS[section],
                          f"{event_key}: {section}.{cfg_key} no existe en DEFAULTS")

    def test_config_event_map_has_no_duplicate_event_keys(self):
        event_keys = [ek for ek, _, _ in ipc.CONFIG_EVENT_MAP]
        self.assertEqual(len(event_keys), len(set(event_keys)),
                          "CONFIG_EVENT_MAP repite una clave de evento")

    def test_config_event_matches_the_map(self):
        # el evento no es más que el mapa evaluado contra CFG: si algún día
        # alguien vuelve a escribir _config_event a mano, esto lo detecta
        ev = c._config_event()
        expected = {"cmd": "config"}
        for event_key, section, cfg_key in ipc.CONFIG_EVENT_MAP:
            expected[event_key] = config.CFG[section][cfg_key]
        self.assertEqual(ev, expected)


class TestCrtOrder(unittest.TestCase):
    """El orden de las pantallas decide dónde cae cada pedazo de una línea
    partida, así que una entrada mal escrita no puede pasar como buena."""

    MONS = [("DP-4", "vertical, at x=0"), ("HDMI-A-2", "at x=1080"),
            ("DP-5", "at x=3000")]

    def setUp(self):
        self._mons = system._monitors_lr
        system._monitors_lr = lambda: list(self.MONS)
        self.addCleanup(lambda: setattr(system, "_monitors_lr", self._mons))
        self._input = builtins.input
        self.addCleanup(lambda: setattr(builtins, "input", self._input))

    def answer(self, *lines):
        """Responde el menú sin teclado. El "enter to go back" de los errores
        cuenta como una respuesta más."""
        it = iter(lines)
        builtins.input = lambda *a, **k: next(it, "")

    def test_numbers_become_names_in_that_order(self):
        self.answer("3,2,1")
        self.assertEqual(c._ask_crt_order("auto"), ["DP-5", "HDMI-A-2", "DP-4"])

    def test_spaces_work_too(self):
        self.answer("2 1 3")
        self.assertEqual(c._ask_crt_order("auto"), ["HDMI-A-2", "DP-4", "DP-5"])

    def test_a_means_automatic(self):
        self.answer("a")
        self.assertEqual(c._ask_crt_order(["DP-5"]), "auto")

    def test_enter_keeps_what_was_there(self):
        self.answer("")
        self.assertIsNone(c._ask_crt_order("auto"))

    def test_a_number_out_of_range_changes_nothing(self):
        self.answer("9", "")
        self.assertIsNone(c._ask_crt_order("auto"))

    def test_garbage_changes_nothing(self):
        self.answer("left,right", "")
        self.assertIsNone(c._ask_crt_order("auto"))

    def test_the_same_screen_twice_changes_nothing(self):
        self.answer("1,1,2", "")
        self.assertIsNone(c._ask_crt_order("auto"))

    def test_a_partial_order_is_allowed(self):
        # las que no nombró van al final solas: nadie se queda sin tubo
        self.answer("3")
        self.assertEqual(c._ask_crt_order("auto"), ["DP-5"])

    def test_one_screen_has_no_order_to_pick(self):
        system._monitors_lr = lambda: [("DP-4", "at x=0")]
        self.answer("")
        self.assertIsNone(c._ask_crt_order("auto"))


def tone(freq, seconds=0.032, rate=16000, amp=0.5):
    """PCM s16 mono de un tono puro, para probar el análisis sin tarjeta de sonido."""
    import math
    n = int(rate * seconds)
    out = bytearray()
    for i in range(n):
        v = int(amp * 32767 * math.sin(2 * math.pi * freq * i / rate))
        out += int(v).to_bytes(2, "little", signed=True)
    return bytes(out)


class TestBandEnergy(unittest.TestCase):
    """Sin numpy: se mide banda por banda, así que la banda tiene que encenderse
    con su propia frecuencia y quedarse quieta con las demás — y sobre todo un
    agudo NO puede aparecer en los graves (por eso se fue Goertzel)."""

    def samples(self, freq, seconds=0.032, amp=0.5):
        pcm = tone(freq, seconds, amp=amp)
        return [int.from_bytes(pcm[i:i + 2], "little", signed=True) / 32768.0
                for i in range(0, len(pcm), 2)]

    def test_the_band_lights_up_on_its_own_frequency(self):
        s = self.samples(1000)
        here = c.band_energy(s, 16000, 1000)
        far = c.band_energy(s, 16000, 150)
        self.assertGreater(here, far * 50)

    def test_silence_has_no_energy(self):
        self.assertAlmostEqual(c.band_energy([0.0] * 512, 16000, 1000), 0.0, places=9)

    def test_louder_means_more_energy(self):
        quiet = c.band_energy(self.samples(1000, amp=0.1), 16000, 1000)
        loud = c.band_energy(self.samples(1000, amp=0.8), 16000, 1000)
        self.assertGreater(loud, quiet * 10)

    def test_an_empty_buffer_does_not_divide_by_zero(self):
        self.assertEqual(c.band_energy([], 16000, 1000), 0.0)

    def test_a_high_tone_does_not_leak_into_the_bass(self):
        s = self.samples(4000)
        self.assertGreater(c.band_energy(s, 16000, 5000),
                           c.band_energy(s, 16000, 60) * 20)


class TestAudioAnalyzer(unittest.TestCase):
    def setUp(self):
        self.an = c.AudioAnalyzer()

    def test_nothing_to_analyse_returns_none(self):
        self.assertIsNone(self.an.feed(b"", 0.0))

    def test_a_low_tone_reads_low_and_a_high_one_reads_high(self):
        low = c.AudioAnalyzer().feed(tone(80), 0.0)
        high = c.AudioAnalyzer().feed(tone(4000), 0.0)
        self.assertLess(low["c"], 0.35)
        self.assertGreater(high["c"], 0.65)
        self.assertGreater(low["lo"], low["hi"])
        self.assertGreater(high["hi"], high["lo"])

    def test_the_level_adapts_to_the_system_volume(self):
        # el mismo tema bajito tiene que terminar latiendo igual que fuerte:
        # si no, el tubo late según el master del sistema y no según la música
        quiet = c.AudioAnalyzer()
        for i in range(40):
            ev = quiet.feed(tone(440, amp=0.02), i * 0.032)
        self.assertGreater(ev["l"], 0.8)

    def test_a_hit_after_silence_is_a_beat(self):
        for i in range(20):
            self.an.feed(tone(440, amp=0.001), i * 0.032)
        ev = self.an.feed(tone(60, amp=0.9), 20 * 0.032)
        self.assertEqual(ev["b"], 1)

    def test_the_same_hit_does_not_fire_twice(self):
        for i in range(20):
            self.an.feed(tone(440, amp=0.001), i * 0.032)
        first = self.an.feed(tone(60, amp=0.9), 1.0)
        again = self.an.feed(tone(60, amp=0.9), 1.02)   # 20 ms después
        self.assertEqual(first["b"], 1)
        self.assertEqual(again["b"], 0)

    def test_silence_is_not_a_beat(self):
        ev = self.an.feed(b"\x00\x00" * 512, 0.0)
        self.assertEqual(ev["b"], 0)
        self.assertLessEqual(ev["l"], 0.05)

    def test_the_event_is_json_and_bounded(self):
        ev = self.an.feed(tone(1000), 0.0)
        json.dumps(ev)
        for key in ("l", "lo", "mid", "hi", "c"):
            self.assertGreaterEqual(ev[key], 0.0)
            self.assertLessEqual(ev[key], 1.0)

    def test_a_normal_beat_is_not_a_hard_one(self):
        # `h` es el golpe que sobresale MUCHO, no cualquiera que pase el umbral:
        # es lo único con lo que se puede elegir un pico sin mapa del tema
        for i in range(20):
            self.an.feed(tone(440, amp=0.30), i * 0.032)
        ev = self.an.feed(tone(60, amp=0.45), 1.0)
        self.assertEqual(ev["b"], 1)
        self.assertEqual(ev["h"], 0)
        self.assertEqual(self.an.feed(tone(60, amp=0.95), 2.0)["h"], 1)


class TestPeakGate(unittest.TestCase):
    """El portero de los picos. Lo que se rompió una vez: la pantalla latía en
    cada golpe, así que latía todo el tiempo."""

    def setUp(self):
        self.gate = c.PeakGate(pct=0.92, gap=15.0, cap=5)
        self.gate.track("tema")

    def test_a_beat_at_the_top_of_the_song_is_a_peak(self):
        self.assertTrue(self.gate.hit(100.0, True, False, 0.95))

    def test_a_loud_beat_that_is_not_the_top_is_not_a_peak(self):
        self.assertFalse(self.gate.hit(100.0, True, True, 0.80))

    def test_something_that_is_not_a_beat_is_never_a_peak(self):
        self.assertFalse(self.gate.hit(100.0, False, True, 1.0))

    def test_two_peaks_do_not_land_on_top_of_each_other(self):
        self.assertTrue(self.gate.hit(100.0, True, False, 0.99))
        self.assertFalse(self.gate.hit(103.0, True, False, 0.99))
        self.assertTrue(self.gate.hit(120.0, True, False, 0.99))

    def test_a_whole_loud_song_still_gets_only_a_handful(self):
        # tres minutos de estribillo continuo, un golpe cada segundo
        got = sum(1 for i in range(180)
                  if self.gate.hit(100.0 + i, True, True, 0.99))
        self.assertEqual(got, 5)

    def test_without_a_map_only_a_hit_that_stands_out_counts(self):
        self.assertFalse(self.gate.hit(100.0, True, False, None))
        self.assertTrue(self.gate.hit(101.0, True, True, None))

    def test_a_new_track_gets_its_own_peaks(self):
        for i in range(5):
            self.gate.hit(100.0 + i * 20, True, True, 0.99)
        self.assertFalse(self.gate.hit(300.0, True, True, 0.99))
        self.gate.track("otro tema", 300.0)
        self.assertTrue(self.gate.hit(316.0, True, True, 0.99))

    def test_the_tube_does_not_flash_the_moment_it_comes_up(self):
        # el reloj del sistema son horas: con el último pico en cero, el primer
        # frame de captura ya cumplía la distancia mínima — y el análisis recién
        # arrancado toma cualquier cosa por un golpazo. Fogonazo al prender.
        fresh = c.PeakGate(now=98000.0)
        self.assertFalse(fresh.hit(98000.03, True, True, None))
        self.assertFalse(fresh.hit(98010.0, True, True, 0.99))
        self.assertTrue(fresh.hit(98020.0, True, True, 0.99))

    def test_changing_track_does_not_flash_on_the_first_note(self):
        self.gate.track("otro tema", 500.0)
        self.assertFalse(self.gate.hit(500.2, True, True, 0.99))

    def test_the_same_track_does_not_reset_the_quota(self):
        self.assertTrue(self.gate.hit(100.0, True, True, 0.99))
        self.gate.track("tema")
        self.assertFalse(self.gate.hit(103.0, True, True, 0.99))


class TestSinkNodeId(unittest.TestCase):
    """pw-record necesita el ID del nodo: con el nombre del monitor conecta igual
    pero graba SILENCIO (medido: 0.0012 de rms contra 0.0757 con el id)."""

    LISTING = ("32\taudiorelay-virtual-mic-sink\tPipeWire\tfloat32le 2ch 48000Hz\tSUSPENDED\n"
               "93\talsa_output.usb-Kingston.analog-stereo\tPipeWire\ts16le 2ch 48000Hz\tRUNNING\n"
               "114\talsa_output.pci-0000_01_00.1.hdmi-stereo\tPipeWire\ts32le 2ch\tIDLE\n")

    def test_finds_the_id_of_its_sink(self):
        self.assertEqual(c.sink_node_id(self.LISTING,
                                        "alsa_output.usb-Kingston.analog-stereo"), "93")

    def test_a_sink_that_is_not_there(self):
        self.assertIsNone(c.sink_node_id(self.LISTING, "nope"))

    def test_a_name_that_only_looks_alike_does_not_match(self):
        self.assertIsNone(c.sink_node_id(self.LISTING, "alsa_output.usb-Kingston"))

    def test_garbage_does_not_raise(self):
        self.assertIsNone(c.sink_node_id("", "whatever"))
        self.assertIsNone(c.sink_node_id("basura sin tabs\n", "whatever"))


class TestAlbumColours(unittest.TestCase):
    """Los colores del tubo salen de la tapa. Lo que importa es el ORDEN: la
    portada típica es mayormente oscura, y si se ordena por cantidad pelada el
    tubo termina pintado del color de una sombra."""

    HIST = ("  40000: (10,10,10)  #0A0A0A srgb(4%,4%,4%)\n"
            "   2000: (240,30,30) #F01E1E srgb(94%,12%,12%)\n"
            "   1800: (30,120,240) #1E78F0 srgb(12%,47%,94%)\n"
            "   9000: (250,250,250) #FAFAFA srgb(98%,98%,98%)\n")

    def test_a_saturated_colour_beats_a_bigger_grey(self):
        got = c.parse_histogram(self.HIST)
        self.assertEqual(got[0], "#f01e1e")
        self.assertIn("#1e78f0", got)

    def test_it_keeps_at_most_what_it_is_asked_for(self):
        self.assertEqual(len(c.parse_histogram(self.HIST, keep=2)), 2)

    def test_garbage_lines_are_skipped(self):
        text = "no soy un histograma\n123: sin numeral\n" + self.HIST
        self.assertEqual(c.parse_histogram(text)[0], "#f01e1e")

    def test_nothing_usable_gives_nothing(self):
        self.assertEqual(c.parse_histogram(""), [])

    def test_no_cover_no_colours(self):
        self.assertIsNone(c.album_colors(""))


class TestAlbumGreys(unittest.TestCase):
    """Un gris no sirve de color de pantalla: no tiene tono propio, y una tapa en
    blanco y negro terminaba pintando el tubo de un color inventado."""

    def test_tinted_colours_come_before_greys(self):
        hist = ("  50000: (200,200,200) #C8C8C8 srgb(78%,78%,78%)\n"
                "   3000: (20,180,90)  #14B45A srgb(8%,71%,35%)\n")
        got = c.parse_histogram(hist)
        self.assertEqual(got[0], "#14b45a")

    def test_an_all_grey_cover_still_returns_something(self):
        hist = ("  50000: (200,200,200) #C8C8C8 srgb(78%,78%,78%)\n"
                "  10000: (40,40,42)    #28282A srgb(15%,15%,16%)\n")
        self.assertEqual(len(c.parse_histogram(hist)), 2)


class TestSections(unittest.TestCase):
    """Fuerte y flojo son relativos AL TEMA: un lofi entero no puede quedar
    marcado como "bajo" ni un tema de metal como un drop de punta a punta."""

    def test_without_enough_song_it_does_not_guess(self):
        kind, pct = c.classify_level(0.9, [0.1, 0.2])
        self.assertEqual(kind, "verse")
        self.assertEqual(pct, 0.5)

    def test_the_loudest_moment_of_a_quiet_song_is_still_a_drop(self):
        quiet_song = [0.01 + i * 0.0005 for i in range(60)]
        kind, _ = c.classify_level(0.05, quiet_song)
        self.assertEqual(kind, "drop")

    def test_an_average_moment_of_a_loud_song_is_not_a_drop(self):
        loud_song = [0.5 + (i % 10) * 0.01 for i in range(60)]
        kind, _ = c.classify_level(0.54, loud_song)
        self.assertIn(kind, ("verse", "build"))

    def test_silence_reads_as_quiet(self):
        song = [0.2 + (i % 7) * 0.02 for i in range(60)]
        kind, pct = c.classify_level(0.0, song)
        self.assertEqual(kind, "quiet")
        self.assertEqual(pct, 0.0)


class TestTrackProfile(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self._old = audio.PROFILE_DIR
        audio.PROFILE_DIR = self.dir.name
        self.addCleanup(lambda: setattr(audio, "PROFILE_DIR", self._old))

    def filled(self, key="tema"):
        p = c.TrackProfile(key, 120.0)
        for i in range(80):
            pos = i * c.PROFILE_STEP
            p.record(pos, 0.1 if i < 40 else 0.6, 0.4)
        return p

    def test_it_remembers_a_track_between_plays(self):
        self.assertTrue(self.filled().save())
        again = c.TrackProfile("tema", 120.0)
        self.assertTrue(again.load())
        self.assertTrue(again.known)
        self.assertEqual(len(again.rms), 80)

    def test_half_a_song_is_not_a_map(self):
        p = c.TrackProfile("corto", 10.0)
        p.record(0.0, 0.3, 0.5)
        self.assertFalse(p.save())

    def test_an_unknown_track_cannot_see_ahead(self):
        p = self.filled()          # grabado en vivo, no cargado del cache
        self.assertIsNone(p.coming(5.0))

    def test_a_known_track_sees_the_loud_part_coming(self):
        self.filled().save()
        p = c.TrackProfile("tema", 120.0)
        p.load()
        # a los 19 s todavía está en la parte floja y a los 21 arranca la fuerte:
        # lo que importa es que AVISE el cambio antes de que pase
        self.assertIn(p.coming(19.0, ahead=2.0), ("build", "drop"))
        self.assertIsNone(p.coming(5.0, ahead=2.0))   # dentro de la misma parte

    def test_a_change_needs_to_hold_before_it_counts(self):
        p = self.filled()
        p.section = "quiet"
        p.since = 100.0
        _, _, changed = p.update(0.0, 0.6, 100.5)      # medio segundo nomás
        self.assertFalse(changed)
        seen = False
        for i in range(1, 40):                          # sostenido en el tiempo
            _, _, changed = p.update(0.0, 0.6, 100.5 + i * c.SECTION_HOLD / 2)
            seen = seen or changed
        self.assertTrue(seen)


class TestUnheardParts(unittest.TestCase):
    """Un tema que se empezó a escuchar por la mitad tiene el principio en cero.
    Ese cero es "no lo escuché", no "acá el tema está callado": si cuenta como
    parte de la canción, todo lo que suene después parece un estribillo."""

    def test_unheard_zeros_do_not_count_as_quiet(self):
        song = [0.0] * 40 + [0.3 + (i % 5) * 0.01 for i in range(40)]
        kind, _ = c.classify_level(0.31, song)
        self.assertIn(kind, ("verse", "build"))

    def test_it_will_not_predict_a_part_it_never_heard(self):
        p = c.TrackProfile("x", 100.0)
        p.rms = [0.0] * 60
        p.known = True
        self.assertIsNone(p.coming(5.0))


class TestSectionSmoothing(unittest.TestCase):
    """Una sección dura una estrofa, no un compás: un golpe suelto no puede
    hacer que el tema entero cambie de parte."""

    def profile(self):
        p = c.TrackProfile("x", 100.0)
        for i in range(60):
            p.record(i * c.PROFILE_STEP, 0.2, 0.5)
        return p

    def test_one_loud_hit_does_not_change_the_section(self):
        p = self.profile()
        p.section = "verse"
        p.since = 0.0
        changed = False
        for i in range(1, 20):
            p.update(0.0, 0.2, i * 0.5)          # tema tranquilo
        _, _, changed = p.update(0.0, 3.0, 12.0)  # un solo bombo enorme
        self.assertFalse(changed)

    def test_a_sustained_change_does_get_through(self):
        p = self.profile()
        p.since = 0.0
        seen = set()
        for i in range(1, 80):
            kind, _, _ = p.update(0.0, 3.0, i * 0.5)
            seen.add(kind)
        self.assertIn("drop", seen)


class TestFlatSong(unittest.TestCase):
    def test_a_song_with_no_dynamics_is_not_one_long_drop(self):
        flat = [0.25] * 40
        kind, pct = c.classify_level(0.25, flat)
        self.assertEqual(kind, "verse")
        self.assertAlmostEqual(pct, 0.5, places=2)


class TestGameDetection(unittest.TestCase):
    """"Pantalla completa" solo no alcanza: un video a pantalla completa apagaba
    la letra justo cuando uno la quiere mirando algo."""

    def test_a_fullscreen_game_counts(self):
        self.assertTrue(c.is_game_window({"class": "cs2", "fullscreen": 2}))

    def test_a_window_that_is_not_fullscreen_never_counts(self):
        self.assertFalse(c.is_game_window({"class": "cs2", "fullscreen": 0,
                                           "fullscreenClient": 0}))

    def test_a_fullscreen_browser_is_not_a_game(self):
        self.assertFalse(c.is_game_window({"class": "google-chrome", "fullscreen": 1,
                                           "fullscreenClient": 1}))

    def test_a_fullscreen_video_player_is_not_a_game(self):
        self.assertFalse(c.is_game_window({"class": "mpv", "fullscreen": 2}))

    def test_it_also_looks_at_the_initial_class(self):
        self.assertFalse(c.is_game_window({"class": "", "initialClass": "firefox",
                                           "fullscreen": 1}))

    def test_nothing_focused_is_not_a_game(self):
        self.assertFalse(c.is_game_window({}))
        self.assertFalse(c.is_game_window(None))


class TestNotAGameConfigurable(unittest.TestCase):
    """not_a_game era una tupla fija en system.py; ahora es
    config.CFG["system"]["not_a_game"], configurable en config.toml. Un
    usuario que no toca la clave nueva tiene que ver exactamente el
    comportamiento de siempre."""

    def setUp(self):
        self.old = list(config.CFG["system"]["not_a_game"])
        self.addCleanup(lambda: config.CFG["system"].__setitem__("not_a_game", self.old))

    def test_default_matches_the_old_hardcoded_tuple(self):
        # el valor de fábrica que antes era la tupla NOT_A_GAME hardcodeada en
        # system.py tiene que seguir siendo exactamente el default de config,
        # para que nadie que no toque config.toml note ninguna diferencia
        for name in ("chrome", "chromium", "firefox", "zen", "brave", "vivaldi",
                     "librewolf", "waterfox", "epiphany", "mpv", "vlc", "celluloid",
                     "haruna", "totem", "spotify", "netflix", "youtube"):
            self.assertIn(name, config.CFG["system"]["not_a_game"])

    def test_untouched_config_behaves_exactly_like_before(self):
        self.assertFalse(c.is_game_window({"class": "google-chrome", "fullscreen": 1}))
        self.assertTrue(c.is_game_window({"class": "cs2", "fullscreen": 2}))

    def test_a_user_can_add_to_the_list_via_config(self):
        config.CFG["system"]["not_a_game"] = list(self.old) + ["obs"]
        self.assertFalse(c.is_game_window({"class": "obs-studio", "fullscreen": 1}))

    def test_a_user_can_shrink_the_list_via_config(self):
        # si lo saca de la lista, ahora SÍ cuenta como juego
        config.CFG["system"]["not_a_game"] = [n for n in self.old if n != "mpv"]
        self.assertTrue(c.is_game_window({"class": "mpv", "fullscreen": 2}))

    def test_the_list_round_trips_through_config_toml(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "config.toml")
            with open(path, "w") as f:
                f.write('[system]\nnot_a_game = ["obs", "discord"]\n')
            old_path = config.CONFIG_PATH
            config.CONFIG_PATH = path
            self.addCleanup(lambda: setattr(config, "CONFIG_PATH", old_path))
            cfg = c.read_config()
            self.assertEqual(cfg["system"]["not_a_game"], ["obs", "discord"])
            # el resto de las claves de [system] siguen ahí (merge sobre DEFAULTS)
            self.assertEqual(cfg["system"]["terminals"], config.DEFAULTS["system"]["terminals"])


class TestCompositorDetection(unittest.TestCase):
    """gaming() y la lista de monitores son Hyprland-only. En otro compositor
    tienen que apagarse solas y avisar UNA vez, no reventar por tick."""

    def setUp(self):
        self.env = dict(os.environ)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(self.env)))
        self.empty = tempfile.TemporaryDirectory()      # XDG_RUNTIME_DIR sin hypr/
        self.addCleanup(self.empty.cleanup)
        gp = config.CFG["behavior"]["game_pause"]
        self.addCleanup(lambda: config.CFG["behavior"].__setitem__("game_pause", gp))
        system._hypr_warned = False
        self.addCleanup(lambda: setattr(system, "_hypr_warned", False))
        # cualquier hyprctl que se escape del guard tiene que hacer ruido
        self.ran = []
        real_run = system.subprocess.run
        def spy(cmd, *a, **kw):
            self.ran.append(cmd)
            return real_run(cmd, *a, **kw)
        system.subprocess.run = spy
        self.addCleanup(lambda: setattr(system.subprocess, "run", real_run))
        self.which = system.shutil.which
        self.addCleanup(lambda: setattr(system.shutil, "which", self.which))
        self.logged = []
        real_log = system.log
        system.log = lambda *a: self.logged.append(" ".join(str(x) for x in a))
        self.addCleanup(lambda: setattr(system, "log", real_log))

    def blank_env(self):
        for k in ("HYPRLAND_INSTANCE_SIGNATURE", "XDG_CURRENT_DESKTOP"):
            os.environ.pop(k, None)
        os.environ["XDG_RUNTIME_DIR"] = self.empty.name

    def test_hyprland_is_detected_by_its_signature(self):
        self.blank_env()
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "whatever"
        system.shutil.which = lambda n: "/usr/bin/hyprctl"
        self.assertTrue(system._hyprland())
        self.assertEqual(self.logged, [])

    def test_a_scrubbed_env_still_finds_it_by_the_desktop_name(self):
        # arrancado como unit de systemd la firma puede no estar
        self.blank_env()
        os.environ["XDG_CURRENT_DESKTOP"] = "Hyprland"
        system.shutil.which = lambda n: "/usr/bin/hyprctl"
        self.assertTrue(system._hyprland())

    def test_or_by_the_runtime_socket_directory(self):
        self.blank_env()
        os.mkdir(os.path.join(self.empty.name, "hypr"))
        system.shutil.which = lambda n: "/usr/bin/hyprctl"
        self.assertTrue(system._hyprland())

    def test_without_any_signal_nothing_shells_out(self):
        self.blank_env()
        config.CFG["behavior"]["game_pause"] = True   # el guard, no el early-return
        self.assertFalse(system._hyprland())
        self.assertEqual(system._monitors(), [])
        self.assertEqual(system._monitors_lr(), [])
        self.assertFalse(system.gaming())
        self.assertEqual(self.ran, [])

    def test_the_signature_without_the_binary_is_not_enough(self):
        self.blank_env()
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "whatever"
        system.shutil.which = lambda n: None
        self.assertFalse(system._hyprland())

    def test_it_complains_once_and_then_shuts_up(self):
        self.blank_env()
        for _ in range(5):
            system._hyprland()
        self.assertEqual(len(self.logged), 1)
        self.assertIn("hyprctl", self.logged[0])


class TestSplitRepeats(unittest.TestCase):
    """Una línea de letra no siempre es una frase: muchas veces son golpes
    repetidos, y cada golpe va a una pantalla distinta. Esto tiene que aguantar
    todas las formas en que una letra escribe una repetición."""

    def test_hyphens_are_repetitions(self):
        # el caso que lo destapó: venía pegado con guiones y era UNA palabra
        self.assertEqual(c.split_repeats("Take-take-take me to the beach"),
                         ["Take", "take", "take", "me to the beach"])

    def test_commas_are_repetitions(self):
        self.assertEqual(c.split_repeats("take, take, take me"),
                         ["take,", "take,", "take", "me"])

    def test_plain_spaces_are_repetitions(self):
        self.assertEqual(c.split_repeats("down down down"), ["down", "down", "down"])

    def test_a_repeated_pair_counts_as_one_hit(self):
        self.assertEqual(c.split_repeats("Take me, take me, take me to the beach"),
                         ["Take me,", "take me,", "take me", "to the beach"])

    def test_a_repeated_trio_counts_too(self):
        self.assertEqual(c.split_repeats("to the beach, to the beach"),
                         ["to the beach,", "to the beach"])

    def test_the_smallest_group_wins(self):
        # cuatro golpes, no dos pares
        self.assertEqual(c.split_repeats("down, down, down, down"),
                         ["down,", "down,", "down,", "down"])

    def test_a_spelled_out_word_becomes_one_hit_per_letter(self):
        # se canta letra por letra, así que son cuatro golpes y no una palabra
        self.assertEqual(c.split_repeats("T-A-K-E, take me")[:4],
                         ["T", "A", "K", "E,"])
        self.assertEqual(c.split_repeats("R.E.S.P.E.C.T"),
                         list("RESPECT"))
        # y también deletreado con espacios
        self.assertEqual(c.split_repeats("T A K E me")[:4], ["T", "A", "K", "E"])

    def test_a_hyphen_with_one_letter_is_not_always_spelling(self):
        for word in ("e-mail", "T-shirt", "x-ray", "K-pop", "U-turn"):
            self.assertEqual(c.split_repeats("say " + word), ["say " + word], word)

    def test_a_stutter_opens_up(self):
        self.assertEqual(c.split_repeats("B-B-B-Baby you"),
                         ["B", "B", "B", "Baby you"])

    def test_a_compound_word_is_not_a_repetition(self):
        self.assertEqual(c.split_repeats("people-pleasing planet"),
                         ["people-pleasing planet"])

    def test_a_line_without_repeats_stays_whole(self):
        line = "just a normal line with no repeats"
        self.assertEqual(c.split_repeats(line), [line])

    def test_case_and_punctuation_do_not_hide_a_repetition(self):
        self.assertEqual(len(c.split_repeats("Ha! ha... HA?")), 3)

    def test_slashes_cut_too(self):
        self.assertEqual(c.split_repeats("I own / I own"), ["I own", "I own"])

    def test_it_does_not_only_work_in_latin(self):
        # con un filtro a–z, dos palabras japonesas distintas quedaban vacías y
        # parecían la misma repetición
        self.assertEqual(c.split_repeats("もっと もっと 欲しい"),
                         ["もっと", "もっと", "欲しい"])
        self.assertEqual(c.split_repeats("最後 まで"), ["最後 まで"])

    def test_too_many_hits_get_merged(self):
        # nadie lee doce pedazos en cuatro segundos: la cola se junta
        long_words = c.split_repeats("baby " * 12)
        self.assertLessEqual(len(long_words), c.SEG_MAX)
        # deletrear entra con más lugar, porque cada golpe es una letra sola
        letters = c.split_repeats("A-B-C-D-E-F-G-H-I-J-K-L")
        self.assertLessEqual(len(letters), c.SEG_MAX_SHORT)
        self.assertGreater(len(letters), c.SEG_MAX)

    def test_empty_and_whitespace_do_not_crash(self):
        self.assertEqual(c.split_repeats(""), [])
        self.assertEqual(c.split_repeats("   "), [])

    def test_the_event_carries_the_cuts(self):
        sent = []
        old = ipc.send
        ipc.send = lambda ev: sent.append(ev)
        self.addCleanup(lambda: setattr(ipc, "send", old))
        c.show("take, take, take me", "t", 1.0, 5.0)
        c.show("a plain line", "t", 5.0, 9.0)
        self.assertEqual(len(sent[0]["segs"]), 4)
        self.assertNotIn("segs", sent[1])


class TestTuneChannel(unittest.TestCase):
    """El panel de sliders es OTRO proceso escribiendo un archivo: no se le cree
    nada de lo que manda."""

    def test_a_normal_line_goes_through(self):
        self.assertEqual(c.parse_tune("flicker=0.250\n"), {"flicker": 0.25})

    def test_several_lines_at_once(self):
        got = c.parse_tune("flicker=0.1\nnoise=0.5\n")
        self.assertEqual(got, {"flicker": 0.1, "noise": 0.5})

    def test_a_key_that_is_not_a_setting_is_ignored(self):
        self.assertEqual(c.parse_tune("rm=1\nplayer=vlc\nflicker=0.3"), {"flicker": 0.3})

    def test_garbage_values_are_ignored(self):
        self.assertEqual(c.parse_tune("flicker=mucho\nnoise=\n"), {})

    def test_junk_does_not_crash(self):
        self.assertEqual(c.parse_tune(""), {})
        self.assertEqual(c.parse_tune("sin igual\n\n"), {})


class TestKnobsAreReachable(unittest.TestCase):
    """Una perilla nueva se agrega hoy en tres lugares: DEFAULTS (valor),
    CONFIG_EVENT_MAP (si el overlay la necesita) y, si tiene slider, tune.qml.
    El TOML de ejemplo (DEFAULT_CONFIG) ya NO es un cuarto lugar: se genera
    solo a partir de DEFAULTS + un dict de comentarios (_CONFIG_COMMENTS), así
    que sólo hace falta agregar el comentario ahí si se quiere prosa — la
    clave y el valor salen solos. Olvidarse de un lugar no rompe nada:
    simplemente la perilla no hace nada, que es peor — de ahí que estos tests
    verifiquen la sincronía en vez de sólo documentarla en prosa."""

    SHELL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shell")

    def test_the_sample_toml_declares_every_key_with_the_default_value(self):
        # `fatal edit` abre este archivo: lo que no está escrito no existe.
        # Se parsea el TOML generado y se compara contra DEFAULTS entero (no
        # sólo [crt]): así un DEFAULT_CONFIG desincronizado de DEFAULTS revienta
        # el test en vez de silenciosamente servir otro default al usuario.
        import tomllib
        parsed = tomllib.loads(c.DEFAULT_CONFIG)
        self.assertEqual(parsed, c.DEFAULTS,
                          "el TOML de ejemplo generado no coincide con DEFAULTS")

    def test_default_config_is_generated_from_defaults(self):
        # si alguien vuelve a escribir DEFAULT_CONFIG a mano en vez de generarlo,
        # este test lo detecta aunque el contenido coincida por casualidad
        self.assertEqual(c.DEFAULT_CONFIG, config._render_default_config(c.DEFAULTS))

    def test_every_crt_key_has_a_comment(self):
        # no es obligatorio, pero una perilla sin prosa en `fatal config` es
        # una perilla que nadie sabe que existe
        for key in c.DEFAULTS["crt"]:
            self.assertIn(key, config._CONFIG_COMMENTS["crt"],
                          f"crt.{key} no tiene comentario en _CONFIG_COMMENTS")

    def test_every_system_key_has_a_comment(self):
        for key in c.DEFAULTS["system"]:
            self.assertIn(key, config._CONFIG_COMMENTS["system"],
                          f"system.{key} no tiene comentario en _CONFIG_COMMENTS")

    def test_every_slider_is_a_numeric_crt_key(self):
        # el panel escribe `clave=valor` y parse_tune descarta lo que no es un
        # número de [crt]: un slider con otra clave mueve la barra y nada más
        with open(os.path.join(self.SHELL, "tune.qml"), encoding="utf-8") as f:
            qml = f.read()
        keys = re.findall(r'\{\s*key:\s*"([a-z_]+)"', qml)
        self.assertTrue(keys, "no se encontró ningún slider en tune.qml")
        for key in keys:
            self.assertIn(key, c.DEFAULTS["crt"], f"el slider {key} no es una opción de [crt]")
            self.assertIsInstance(c.DEFAULTS["crt"][key], (int, float))
            self.assertEqual(c.parse_tune(f"{key}=0.5"), {key: 0.5})

    def test_the_water_knobs_are_saved_in_their_own_section(self):
        # el agua tiene interruptor (bool) y cantidad (número): los dos van a [crt]
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "config.toml")
            with open(path, "w") as f:
                f.write("[display]\nscale = 1.0\n\n[crt]\nwater = true\nwater_amp = 0.55\n")
            old = config.CONFIG_PATH
            config.CONFIG_PATH = path
            self.addCleanup(lambda: setattr(config, "CONFIG_PATH", old))
            c._save_config({"water": ("crt", False), "water_amp": ("crt", 0.9)})
            with open(path) as f:
                body = f.read()
            self.assertIn("water = false", body)
            self.assertIn("water_amp = 0.9", body)

    def test_editing_a_multiline_commented_key_survives_on_the_generated_toml(self):
        # el camino real: `fatal edit` crea el config con DEFAULT_CONFIG (el
        # generado), y `fatal tune`/el menú despues reescriben una clave
        # puntual con _save_config. "flicker" y "palette" tienen los
        # comentarios más largos (varias líneas): si el regex de _save_config
        # se llevara puesto el comentario, sería acá donde se vería
        import tomllib
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "config.toml")
            with open(path, "w") as f:
                f.write(c.DEFAULT_CONFIG)
            old = config.CONFIG_PATH
            config.CONFIG_PATH = path
            self.addCleanup(lambda: setattr(config, "CONFIG_PATH", old))
            c._save_config({"flicker": ("crt", 0.9), "palette": ("crt", "dragons")})
            with open(path) as f:
                body = f.read()
            parsed = tomllib.loads(body)
            self.assertEqual(parsed["crt"]["flicker"], 0.9)
            self.assertEqual(parsed["crt"]["palette"], "dragons")
            # el resto del archivo (todas las demás claves y su prosa) no se tocó
            for key, value in c.DEFAULTS["crt"].items():
                if key in ("flicker", "palette"):
                    continue
                self.assertEqual(parsed["crt"][key], value)
            self.assertIn("kick drum", body)  # medio del comentario de flicker
            self.assertIn("ImageMagick", body)  # medio del comentario de palette

    def test_read_config_always_fills_every_default_key(self):
        # read_config mezcla el TOML del usuario SOBRE una copia de DEFAULTS
        # (nunca al revés), así que aunque el usuario haya borrado una clave
        # a mano, CFG (y por lo tanto _config_event) siempre las tiene todas
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "config.toml")
            with open(path, "w") as f:
                f.write("[display]\nscale = 2.0\n")  # el resto de las claves falta
            old = config.CONFIG_PATH
            config.CONFIG_PATH = path
            self.addCleanup(lambda: setattr(config, "CONFIG_PATH", old))
            cfg = c.read_config()
            self.assertEqual(cfg["display"]["scale"], 2.0)
            for section, values in c.DEFAULTS.items():
                for key in values:
                    self.assertIn(key, cfg[section], f"{section}.{key} no sobrevivió al merge")


class _FakeInput:
    """Cola de respuestas de teclado para el menú de `fatal config`. Cada
    llamada a input() saca la próxima; si se acaban, sigue devolviendo ''
    (como si el usuario apretara enter) — así un test no cuelga esperando
    una respuesta que se olvidó de poner en la cola."""

    def __init__(self, case, *answers):
        self._it = iter(answers)
        self._old = builtins.input
        case.addCleanup(lambda: setattr(builtins, "input", self._old))
        builtins.input = lambda *a, **k: next(self._it, "")


class TestPick(unittest.TestCase):
    """`_pick` es la base de casi todo el menú: si acepta un número fuera de
    rango o basura sin volver a preguntar, cualquier perilla queda mal."""

    OPTIONS = [("uno", "u"), ("dos", "d"), ("tres", "t")]

    def answer(self, *lines):
        _FakeInput(self, *lines)

    def test_valid_selection_returns_its_value(self):
        self.answer("2")
        self.assertEqual(c._pick("t", self.OPTIONS, "u"), "d")

    def test_empty_keeps_the_current_value(self):
        self.answer("")
        self.assertIsNone(c._pick("t", self.OPTIONS, "u"))

    def test_invalid_selection_retries_until_a_good_one(self):
        self.answer("nope", "0", "99", "1")
        self.assertEqual(c._pick("t", self.OPTIONS, "u"), "u")

    def test_out_of_range_number_is_rejected_not_accepted(self):
        # "0" y "99" no son índices válidos (1..len(options)): tienen que
        # volver a preguntar, no devolver cualquier cosa
        self.answer("0", "")
        self.assertIsNone(c._pick("t", self.OPTIONS, "u"))


class TestAskNum(unittest.TestCase):
    """`_ask_num` es el que más perillas de [crt] usa (scale, curvature,
    bloom...); un límite mal chequeado ahí se nota en pantalla."""

    def answer(self, *lines):
        _FakeInput(self, *lines)

    def test_valid_number_in_range(self):
        self.answer("1.5")
        self.assertEqual(c._ask_num("t", 1.0, 0.5, 3.0), 1.5)

    def test_comma_decimal_is_accepted(self):
        self.answer("1,5")
        self.assertEqual(c._ask_num("t", 1.0, 0.5, 3.0), 1.5)

    def test_empty_keeps_the_current_value(self):
        self.answer("")
        self.assertIsNone(c._ask_num("t", 1.0, 0.5, 3.0))

    def test_below_range_retries_then_accepts_a_good_value(self):
        self.answer("0.1", "1.0")
        self.assertEqual(c._ask_num("t", 1.0, 0.5, 3.0), 1.0)

    def test_above_range_retries_then_accepts_a_good_value(self):
        self.answer("99", "2.0")
        self.assertEqual(c._ask_num("t", 1.0, 0.5, 3.0), 2.0)

    def test_non_numeric_retries_instead_of_crashing(self):
        self.answer("abc", "1.0")
        self.assertEqual(c._ask_num("t", 1.0, 0.5, 3.0), 1.0)

    def test_boundaries_are_inclusive(self):
        self.answer("0.5")
        self.assertEqual(c._ask_num("t", 1.0, 0.5, 3.0), 0.5)
        self.answer("3.0")
        self.assertEqual(c._ask_num("t", 1.0, 0.5, 3.0), 3.0)

    def test_just_outside_the_boundary_is_rejected(self):
        self.answer("3.0000001", "")
        self.assertIsNone(c._ask_num("t", 1.0, 0.5, 3.0))


class TestAskInt(unittest.TestCase):
    def answer(self, *lines):
        _FakeInput(self, *lines)

    def test_valid_int_in_range(self):
        self.answer("5")
        self.assertEqual(c._ask_int("t", 0, 0, 50), 5)

    def test_empty_keeps_the_current_value(self):
        self.answer("")
        self.assertIsNone(c._ask_int("t", 0, 0, 50))

    def test_a_float_string_is_not_a_valid_int_and_retries(self):
        self.answer("1.5", "1")
        self.assertEqual(c._ask_int("t", 0, 0, 50), 1)

    def test_out_of_range_retries_then_accepts(self):
        self.answer("-1", "51", "25")
        self.assertEqual(c._ask_int("t", 0, 0, 50), 25)

    def test_boundaries_are_inclusive(self):
        self.answer("0")
        self.assertEqual(c._ask_int("t", 5, 0, 50), 0)
        self.answer("50")
        self.assertEqual(c._ask_int("t", 5, 0, 50), 50)


class TestAskText(unittest.TestCase):
    def answer(self, *lines):
        _FakeInput(self, *lines)

    def test_text_is_returned_stripped(self):
        self.answer("  hola  ")
        self.assertEqual(c._ask_text("t", "viejo"), "hola")

    def test_empty_keeps_the_current_value(self):
        self.answer("")
        self.assertIsNone(c._ask_text("t", "viejo"))


class TestAskScreens(unittest.TestCase):
    """`_ask_screens` arma sus propias opciones a partir de los monitores
    reales: si el mock no está bien encadenado, cualquier respuesta numérica
    apunta a la pantalla equivocada."""

    MONS = [("DP-4", "1920x1080 horizontal"), ("DP-5", "2560x1440 horizontal")]

    def setUp(self):
        self._old_monitors = system._monitors
        system._monitors = lambda: list(self.MONS)
        self.addCleanup(lambda: setattr(system, "_monitors", self._old_monitors))

    def answer(self, *lines):
        _FakeInput(self, *lines)

    def test_auto_is_the_first_option(self):
        self.answer("1")
        self.assertEqual(c._ask_screens("all"), "auto")

    def test_all_is_the_second_option(self):
        self.answer("2")
        self.assertEqual(c._ask_screens("auto"), "all")

    def test_a_single_named_screen(self):
        self.answer("3")
        self.assertEqual(c._ask_screens("auto"), "DP-4")

    def test_several_lets_you_pick_more_than_one(self):
        # con 2+ monitores aparece la opción "several" al final de la lista
        self.answer(str(len(self.MONS) + 3), "1,2")
        self.assertEqual(c._ask_screens("auto"), ["DP-4", "DP-5"])

    def test_several_with_garbage_numbers_returns_none(self):
        # los tokens que no son índices válidos se descartan en silencio;
        # si TODOS son basura no queda nada para elegir
        self.answer(str(len(self.MONS) + 3), "x,y")
        self.assertIsNone(c._ask_screens("auto"))

    def test_several_with_a_mix_of_good_and_bad_tokens_drops_the_bad_ones_silently(self):
        # a diferencia de `_ask_crt_order` (que valida TODOS los tokens con
        # `all(...)` y reintenta si alguno es basura), acá el filtro es por
        # token: "1,x" no es un error, es "me quedo con el 1 y listo". No es
        # un bug de validación (no cuela ningún valor fuera de rango), pero
        # el usuario que tipeó dos pantallas se queda con una sin aviso —
        # comportamiento real, pineado a propósito, no corregido.
        self.answer(str(len(self.MONS) + 3), "1,x")
        self.assertEqual(c._ask_screens("auto"), ["DP-4"])

    def test_with_a_single_monitor_there_is_no_several_option(self):
        system._monitors = lambda: [self.MONS[0]]
        # opciones: 1) auto, 2) all, 3) DP-4 -- "4" no existe, tiene que reintentar
        self.answer("4", "2")
        self.assertEqual(c._ask_screens("auto"), "all")


class TestAskPlayer(unittest.TestCase):
    def setUp(self):
        self._old_players = system._players
        self.addCleanup(lambda: setattr(system, "_players", self._old_players))

    def answer(self, *lines):
        _FakeInput(self, *lines)

    def test_no_players_falls_back_to_free_text(self):
        system._players = lambda: []
        self.answer("spotify")
        self.assertEqual(c._ask_player("old"), "spotify")

    def test_picks_a_detected_player_by_number(self):
        system._players = lambda: ["spotify", "firefox"]
        self.answer("2")
        self.assertEqual(c._ask_player("spotify"), "firefox")

    def test_other_falls_back_to_manual_text(self):
        system._players = lambda: ["spotify"]
        self.answer("2", "vlc")   # 2) other (type it in)
        self.assertEqual(c._ask_player("spotify"), "vlc")


def _row_for(settings, target_key):
    """Reproduce la numeración de `_menu`: sólo cuenta filas con sección
    (los separadores como "— screen —" no tienen número)."""
    n = 0
    for key, section, _, _ in settings:
        if section is None:
            continue
        n += 1
        if key == target_key:
            return n
    raise AssertionError(f"{target_key} no está en SETTINGS")


class TestSetupMenu(unittest.TestCase):
    """El loop de `setup()`: elegir una fila, editarla, cancelar sin tocar
    nada, deshacer. Usa un CONFIG_PATH temporal para no rozar el config real
    ni depender del resto de las perillas (pantallas, player MPRIS...)."""

    TEST_SETTINGS = [
        ("karaoke", "display", "Karaoke", lambda cur: c._pick("Karaoke", c.YESNO, cur)),
        ("scale", "display", "Dialog scale",
         lambda cur: c._ask_num("Dialog scale", cur, 0.5, 3.0)),
    ]

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = os.path.join(tmp.name, "config.toml")
        with open(self.path, "w") as f:
            f.write(c.DEFAULT_CONFIG)
        self._old_path = config.CONFIG_PATH
        config.CONFIG_PATH = self.path
        self.addCleanup(lambda: setattr(config, "CONFIG_PATH", self._old_path))

        self._old_settings = c.setup.SETTINGS
        c.setup.SETTINGS = self.TEST_SETTINGS
        self.addCleanup(lambda: setattr(c.setup, "SETTINGS", self._old_settings))

        # el menú imprime pantallas enteras a cada paso; silenciarlo evita
        # ensuciar la salida de `unittest discover` sin cambiar el chequeo.
        # Se guarda la referencia porque algunos tests necesitan confirmar
        # POR QUÉ se llegó a un resultado (ej: que el valor fue rechazado y
        # no que la fila nunca se seleccionó), no sólo el estado final.
        self.out = io.StringIO()
        patcher = mock.patch("sys.stdout", self.out)
        patcher.start()
        self.addCleanup(patcher.stop)

    def answer(self, *lines):
        _FakeInput(self, *lines)

    def _read_saved(self):
        import tomllib
        with open(self.path, "rb") as f:
            return tomllib.load(f)

    def test_quit_immediately_changes_nothing(self):
        self.answer("q")
        c.setup.setup()
        saved = self._read_saved()
        self.assertEqual(saved["display"]["karaoke"], False)   # default
        self.assertEqual(saved["display"]["scale"], 1.0)       # default

    def test_invalid_row_number_retries_instead_of_crashing(self):
        # "99" no es una fila válida (sólo hay 2 en TEST_SETTINGS): tiene que
        # volver al menú, no reventar ni aplicar nada
        self.answer("99", "q")
        c.setup.setup()
        saved = self._read_saved()
        self.assertEqual(saved["display"]["karaoke"], False)

    def test_a_valid_edit_is_saved_to_disk(self):
        # fila 1 = karaoke, opción 1 de YESNO = "yes" -> True (el default es
        # False, así que este edit sí mueve la aguja)
        self.answer("1", "1", "q")   # fila 1 (karaoke), opción 1 = "yes"
        c.setup.setup()
        saved = self._read_saved()
        self.assertEqual(saved["display"]["karaoke"], True)

    def test_out_of_range_number_during_an_edit_does_not_get_saved(self):
        # fila 2 = scale, 10 está fuera de [0.5, 3.0]: _ask_num tiene que
        # reintentar en vez de guardar un valor inválido; enter cancela.
        # Sin el assert de stdout esto pasaría igual aunque la fila nunca
        # se hubiera seleccionado (el "" final también cancela desde el
        # menú principal) — así que se confirma que SE LLEGÓ a _ask_num y
        # que rechazó el 10, no sólo que scale terminó en el default.
        self.answer("2", "10", "", "q")
        c.setup.setup()
        self.assertIn("a number between 0.5 and 3.0", self.out.getvalue())
        saved = self._read_saved()
        self.assertEqual(saved["display"]["scale"], 1.0)   # sigue en el default

    def test_undo_reverts_a_saved_change(self):
        self.answer("1", "1", "u", "q")   # editar karaoke a yes, después deshacer
        c.setup.setup()
        # sin este assert, si el edit nunca se hubiera guardado, "u" habría
        # impreso "nothing to undo" y el resultado final sería idéntico
        self.assertIn("1 setting(s) back to how you found them", self.out.getvalue())
        saved = self._read_saved()
        self.assertEqual(saved["display"]["karaoke"], False)

    def test_undo_with_nothing_changed_does_not_crash(self):
        self.answer("u", "q")
        c.setup.setup()   # no debe explotar ni escribir nada raro
        self.assertIn("nothing to undo", self.out.getvalue())
        saved = self._read_saved()
        self.assertEqual(saved["display"]["karaoke"], False)

    def test_ctrl_c_mid_edit_returns_to_the_menu_without_saving(self):
        # setup() envuelve la llamada al editor en
        # `except (KeyboardInterrupt, EOFError): continue` — es la otra
        # forma de "cancelación" además del enter vacío, y con su propio
        # modo de falla posible (guardar un valor a medio construir, o
        # que el Ctrl-C se lleve puesto todo el menú en vez de sólo el edit)
        settings = self.TEST_SETTINGS + [
            ("player", "behavior", "Player",
             lambda cur: (_ for _ in ()).throw(KeyboardInterrupt())),
        ]
        c.setup.SETTINGS = settings
        row = _row_for(settings, "player")
        self.answer(str(row), "q")
        c.setup.setup()   # no tiene que propagar el KeyboardInterrupt
        saved = self._read_saved()
        self.assertEqual(saved["behavior"]["player"], config.DEFAULTS["behavior"]["player"])

    def test_eof_mid_edit_also_returns_to_the_menu_without_saving(self):
        settings = self.TEST_SETTINGS + [
            ("player", "behavior", "Player",
             lambda cur: (_ for _ in ()).throw(EOFError())),
        ]
        c.setup.SETTINGS = settings
        row = _row_for(settings, "player")
        self.answer(str(row), "q")
        c.setup.setup()
        saved = self._read_saved()
        self.assertEqual(saved["behavior"]["player"], config.DEFAULTS["behavior"]["player"])


class TestSetupDeathAgeWarning(unittest.TestCase):
    """death_age_min > death_age_max es un estado válido para cada perilla
    por separado (1..50) pero sin sentido juntas: setup() tiene que avisar,
    no guardarlo en silencio."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = os.path.join(tmp.name, "config.toml")
        with open(self.path, "w") as f:
            f.write(c.DEFAULT_CONFIG)
        self._old_path = config.CONFIG_PATH
        config.CONFIG_PATH = self.path
        self.addCleanup(lambda: setattr(config, "CONFIG_PATH", self._old_path))

    def answer(self, *lines):
        _FakeInput(self, *lines)

    def test_pushing_min_above_max_warns_in_the_next_screen(self):
        row = _row_for(c.setup.SETTINGS, "death_age_min")
        # default: death_age_min=3, death_age_max=7 -> 8 lo deja arriba del máximo
        self.answer(str(row), "8", "q")
        out = io.StringIO()
        with mock.patch("sys.stdout", out):
            c.setup.setup()
        self.assertIn("heads up", out.getvalue())
        import tomllib
        with open(self.path, "rb") as f:
            saved = tomllib.load(f)
        self.assertEqual(saved["effects"]["death_age_min"], 8)


class TestLogRotation(unittest.TestCase):
    """El daemon corre semanas: sin tope el log llena el tmpfs (que es RAM)."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "daemon.log")

    def test_a_small_log_is_left_alone(self):
        with open(self.path, "w") as f:
            f.write("chico\n")
        self.assertFalse(util.rotate_log(self.path, limit=1024))
        with open(self.path) as f:
            self.assertEqual(f.read(), "chico\n")
        self.assertFalse(os.path.exists(self.path + ".1"))

    def test_over_the_limit_it_rotates_into_one_backup(self):
        with open(self.path, "w") as f:
            f.write("x" * 2048)
        self.assertTrue(util.rotate_log(self.path, limit=1024))
        self.assertEqual(os.path.getsize(self.path), 0)
        self.assertEqual(os.path.getsize(self.path + ".1"), 2048)

    def test_only_one_backup_is_kept(self):
        for body in ("viejo", "nuevo"):
            with open(self.path, "w") as f:
                f.write(body * 1024)
            util.rotate_log(self.path, limit=1024)
        self.assertEqual(sorted(os.listdir(self.dir.name)),
                         ["daemon.log", "daemon.log.1"])
        with open(self.path + ".1") as f:
            self.assertTrue(f.read().startswith("nuevo"))

    def test_the_inode_survives_the_rotation(self):
        # se trunca el mismo archivo, no se renombra: el redirect de bin/fatal ya
        # lo tiene abierto y con un rename seguiría escribiendo en el backup
        with open(self.path, "w") as f:
            f.write("x" * 2048)
        before = os.stat(self.path).st_ino
        util.rotate_log(self.path, limit=1024)
        self.assertEqual(os.stat(self.path).st_ino, before)

    def test_an_open_append_writer_keeps_writing_to_the_live_log(self):
        # bin/fatal redirige con `>>` justamente por esto
        with open(self.path, "a") as writer:
            writer.write("x" * 2048)
            writer.flush()
            util.rotate_log(self.path, limit=1024)
            writer.write("después\n")
            writer.flush()
        with open(self.path) as f:
            self.assertEqual(f.read(), "después\n")

    def test_a_log_that_is_not_there_is_not_an_error(self):
        self.assertFalse(util.rotate_log(os.path.join(self.dir.name, "nope.log")))

    def test_nothing_rotates_when_stdout_is_not_a_file(self):
        # corriendo el daemon a mano, stdout es la terminal: nada que rotar
        old_stdout, old_target = sys.stdout, util._log_target
        util._log_target = False
        sys.stdout = io.StringIO()
        try:
            self.assertIsNone(util._stdout_log())
            util.log("sin archivo detrás")     # no tiene que explotar
        finally:
            sys.stdout, util._log_target = old_stdout, old_target

    def test_log_rotates_the_file_behind_stdout(self):
        old_stdout, old_target = sys.stdout, util._log_target
        util._log_target = False
        sys.stdout = open(self.path, "a")
        try:
            sys.stdout.write("x" * 2048)
            self.assertEqual(util._stdout_log(), self.path)
            util.log("la línea que dispara la rotación", )
        finally:
            sys.stdout.close()
            sys.stdout, util._log_target = old_stdout, old_target
        util.rotate_log(self.path, limit=1024)
        self.assertTrue(os.path.exists(self.path + ".1"))


class TestRuntimePaths(unittest.TestCase):
    """PID y logs viven en $XDG_RUNTIME_DIR/cartelitos/, no en /tmp: /tmp lo
    comparten todas las sesiones y no se limpia al salir."""

    def test_every_runtime_path_hangs_off_the_runtime_dir(self):
        for path in (util.DAEMON_PID_PATH, util.QS_PID_PATH,
                     util.LOG_PATH, util.QS_LOG_PATH):
            self.assertTrue(path.startswith(util.RUN_DIR + os.sep), path)
        self.assertTrue(util.RUN_DIR.endswith(os.sep + "cartelitos"))

    def test_nothing_points_at_slash_tmp_when_the_runtime_dir_exists(self):
        if os.environ.get("XDG_RUNTIME_DIR"):
            self.assertFalse(util.RUN_DIR.startswith("/tmp/"))


class TestDaemonPid(unittest.TestCase):
    """_daemon_pid() confirma el cmdline: el sistema recicla PIDs y un SIGUSR1
    al número equivocado le pega a un proceso ajeno."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.pidfile = os.path.join(self.dir.name, "daemon.pid")
        old = util.DAEMON_PID_PATH
        util.DAEMON_PID_PATH = self.pidfile
        self.addCleanup(lambda: setattr(util, "DAEMON_PID_PATH", old))

    def _write(self, body):
        with open(self.pidfile, "w") as f:
            f.write(body)

    def test_no_pidfile_is_none(self):
        self.assertIsNone(c._daemon_pid())

    def test_garbage_is_none_not_a_crash(self):
        self._write("no soy un pid\n")
        self.assertIsNone(c._daemon_pid())

    def test_a_pid_that_is_not_cartelitos_is_rejected(self):
        # nuestro propio proceso: vivo, pero su cmdline no es el del daemon
        self._write(str(os.getpid()))
        with open(f"/proc/{os.getpid()}/cmdline", "rb") as f:
            if b"cartelitos" in f.read():
                self.skipTest("el runner se llama cartelitos")
        self.assertIsNone(c._daemon_pid())

    def test_a_dead_pid_is_none(self):
        self._write("999999999")
        self.assertIsNone(c._daemon_pid())

    def test_it_reads_the_runtime_pidfile(self):
        proc = subprocess.Popen([sys.executable, "-c",
                                 "import time; time.sleep(30)  # cartelitos"])
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        _wait_cmdline(proc.pid)
        self._write(str(proc.pid))
        self.assertEqual(c._daemon_pid(), proc.pid)


class TestOptionalTools(unittest.TestCase):
    """`fatal status` tiene que decir qué falta y qué se pierde: media app
    apagada por un paquete que no está parecía un bug."""

    def test_nothing_missing_prints_nothing(self):
        old = system.OPTIONAL_TOOLS
        system.OPTIONAL_TOOLS = []
        self.addCleanup(lambda: setattr(system, "OPTIONAL_TOOLS", old))
        with _patched_tray(True):
            self.assertEqual(system.health_lines(), [])

    def test_a_missing_tool_names_the_feature_it_costs(self):
        old_which = system.shutil.which
        system.shutil.which = lambda n: None if n in ("pw-record", "parec") else "/usr/bin/" + n
        self.addCleanup(lambda: setattr(system.shutil, "which", old_which))
        with _patched_tray(True):
            lines = system.health_lines()
        self.assertEqual(len(lines), 1)
        self.assertIn("pw-record/parec not found", lines[0])
        self.assertIn("→", lines[0])
        self.assertTrue(len(lines[0].split("→")[1].strip()) > 5)

    def test_an_alternative_that_is_there_is_enough(self):
        # magick O convert: con uno de los dos alcanza
        old_which = system.shutil.which
        system.shutil.which = lambda n: None if n == "magick" else "/usr/bin/" + n
        self.addCleanup(lambda: setattr(system.shutil, "which", old_which))
        with _patched_tray(True):
            self.assertEqual(system.health_lines(), [])

    def test_the_tray_is_reported_too(self):
        old_which = system.shutil.which
        system.shutil.which = lambda n: "/usr/bin/" + n
        self.addCleanup(lambda: setattr(system.shutil, "which", old_which))
        with _patched_tray(False):
            lines = system.health_lines()
        self.assertEqual(len(lines), 1)
        self.assertIn("AyatanaAppIndicator3", lines[0])

    def test_every_entry_says_what_breaks(self):
        for names, consequence in system.OPTIONAL_TOOLS:
            self.assertTrue(names and all(names))
            self.assertTrue(len(consequence) > 10, names)

    def test_the_check_flag_prints_the_same_lines(self):
        out = subprocess.run(
            [sys.executable, os.path.join(REPO, "cartelitos.py"), "--check"],
            capture_output=True, text=True, timeout=30)
        self.assertEqual(out.returncode, 0)
        printed = [l for l in out.stdout.splitlines() if l.strip()]
        for line in printed:
            self.assertIn("not found →", line)


class TestTrayFallback(unittest.TestCase):
    """start_tray() es opcional: sin gi/AyatanaAppIndicator3 el daemon tiene
    que seguir vivo igual, dejando claro en el log qué falta. La detección de
    "¿está gi?" es la misma que usa `fatal status` (system._tray_available),
    no una copia: si una cambia y la otra no, este test lo agarra."""

    def setUp(self):
        # sacamos cualquier `gi` real que haya quedado cacheado en sys.modules
        # (o el gi.repository de un test anterior) para que cada test arranque
        # desde un import limpio.
        self._removed = {}
        for name in ("gi", "gi.repository"):
            if name in sys.modules:
                self._removed[name] = sys.modules.pop(name)
        self.addCleanup(self._restore)

    def _restore(self):
        for name in ("gi", "gi.repository"):
            sys.modules.pop(name, None)
        sys.modules.update(self._removed)

    def test_gi_missing_logs_clearly_and_does_not_crash(self):
        sys.modules["gi"] = None  # cualquier `import gi` levanta ImportError
        out = io.StringIO()
        threads_before = {t.ident for t in threading.enumerate()}
        with mock.patch("sys.stdout", out):
            result = tray.start_tray()  # no debe tirar excepción
        self.assertIsNone(result)
        self.assertIn("tray not available", out.getvalue())
        self.assertIn("continuing without an icon", out.getvalue())
        # sin gi no hay bandeja que levantar: no se lanzó el hilo "tray"
        new_threads = [t for t in threading.enumerate()
                       if t.ident not in threads_before]
        self.assertFalse(any(t.name == "tray" for t in new_threads))

    def test_uses_the_same_detection_as_fatal_status(self):
        # misma pregunta ("¿puedo importar gi + Ayatana?") que hace
        # system._tray_available() para `fatal status`; no se duplica la
        # lógica, se comparte el resultado.
        sys.modules["gi"] = None
        self.assertFalse(system._tray_available())
        out = io.StringIO()
        with mock.patch("sys.stdout", out):
            tray.start_tray()
        self.assertIn("tray not available", out.getvalue())

    def test_start_tray_does_not_crash_when_gi_is_available(self):
        # gi real puede estar instalado o no en la máquina que corre los
        # tests; lo que importa acá no es que dibuje nada de GTK de verdad
        # (eso levantaría un ícono real en la bandeja de quien corra la
        # suite) sino que el código de armado del menú no reviente. Se
        # simula gi con mocks que satisfacen la API que tray.py usa.
        fake_gi = mock.MagicMock()
        fake_repo = mock.MagicMock()
        sys.modules["gi"] = fake_gi
        sys.modules["gi.repository"] = fake_repo

        # con Gtk.main() mockeado el hilo termina casi al instante, así que
        # enumerarlo desde afuera es una carrera: interceptamos el propio
        # threading.Thread que arma start_tray() para quedarnos con el
        # objeto y poder esperarlo (join) de forma determinística.
        created = []
        real_thread = threading.Thread

        def spy_thread(*args, **kwargs):
            t = real_thread(*args, **kwargs)
            created.append(t)
            return t

        with mock.patch("cartelitos.tray.threading.Thread", side_effect=spy_thread):
            result = tray.start_tray()
        self.assertIsNone(result)  # start_tray() no bloquea: lanza un hilo

        self.assertEqual(len(created), 1)
        self.assertEqual(created[0].name, "tray")
        created[0].join(timeout=5)
        self.assertFalse(created[0].is_alive(),
                          "el hilo de la bandeja se quedó colgado")


class TestTerminalPreference(unittest.TestCase):
    """La lista de terminals que prueba _terminal() (después de $TERMINAL) era
    fija en system.py; ahora sale de config.CFG["system"]["terminals"]. Sin
    tocar la config nueva, el orden de preferencia tiene que ser el de
    siempre."""

    OLD_ORDER = ["kitty", "alacritty", "foot", "wezterm", "ghostty", "konsole",
                 "gnome-terminal", "xterm"]

    def setUp(self):
        self.env = dict(os.environ)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(self.env)))
        os.environ.pop("TERMINAL", None)
        self.old_terminals = list(config.CFG["system"]["terminals"])
        self.addCleanup(lambda: config.CFG["system"].__setitem__("terminals", self.old_terminals))
        self.old_which = system.shutil.which
        self.addCleanup(lambda: setattr(system.shutil, "which", self.old_which))

    def test_default_order_matches_the_old_hardcoded_list(self):
        self.assertEqual(config.DEFAULTS["system"]["terminals"], self.OLD_ORDER)

    def test_untouched_config_picks_the_same_terminal_as_before(self):
        # sólo "foot" existe: con la lista de siempre, gana igual que antes
        system.shutil.which = lambda n: "/usr/bin/foot" if n == "foot" else None
        self.assertEqual(system._terminal(), "/usr/bin/foot")

    def test_terminal_env_var_still_wins_over_the_config_list(self):
        os.environ["TERMINAL"] = "myterm"
        system.shutil.which = lambda n: "/usr/bin/" + n
        self.assertEqual(system._terminal(), "/usr/bin/myterm")

    def test_a_user_can_reorder_the_preference_via_config(self):
        config.CFG["system"]["terminals"] = ["xterm", "kitty"]
        system.shutil.which = lambda n: "/usr/bin/" + n if n in ("xterm", "kitty") else None
        self.assertEqual(system._terminal(), "/usr/bin/xterm")

    def test_nothing_found_returns_none(self):
        config.CFG["system"]["terminals"] = ["madeup-term"]
        system.shutil.which = lambda n: None
        self.assertIsNone(system._terminal())


class _patched_tray:
    def __init__(self, available):
        self.available = available

    def __enter__(self):
        self._old = system._tray_available
        system._tray_available = lambda: self.available

    def __exit__(self, *exc):
        system._tray_available = self._old
        return False


class TestFatalRunningGuard(unittest.TestCase):
    """running() en bin/fatal: `kill -0` solo daba ON con un PID reciclado de
    otra sesión, y stop le mandaba la señal a un proceso ajeno."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(REPO, "bin", "fatal"), encoding="utf-8") as f:
            body = f.read()
        start = body.index("running() {")
        cls.fn = body[start:body.index("\n}\n", start) + 3]

    def _run(self, pidfile, want):
        script = f'{self.fn}\nrunning "{pidfile}" "{want}" && echo YES || echo NO\n'
        out = subprocess.run(["bash", "-c", script], capture_output=True,
                             text=True, timeout=30)
        return out.stdout.strip()

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.pidfile = os.path.join(self.dir.name, "daemon.pid")

    def _spawn(self, marker):
        proc = subprocess.Popen([sys.executable, "-c",
                                 f"import time; time.sleep(30)  # {marker}"])
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        _wait_cmdline(proc.pid)
        with open(self.pidfile, "w") as f:
            f.write(str(proc.pid))
        return proc

    def test_a_live_process_with_the_right_cmdline_is_running(self):
        self._spawn("cartelitos.py")
        self.assertEqual(self._run(self.pidfile, "cartelitos.py"), "YES")

    def test_a_recycled_pid_is_not_running(self):
        self._spawn("otra-cosa")
        self.assertEqual(self._run(self.pidfile, "cartelitos.py"), "NO")

    def test_no_pidfile_is_not_running(self):
        self.assertEqual(self._run(self.pidfile, "cartelitos.py"), "NO")

    def test_garbage_in_the_pidfile_is_not_running(self):
        with open(self.pidfile, "w") as f:
            f.write("not a pid\n")
        self.assertEqual(self._run(self.pidfile, "cartelitos.py"), "NO")

    def test_an_empty_pidfile_is_not_running(self):
        open(self.pidfile, "w").close()
        self.assertEqual(self._run(self.pidfile, "cartelitos.py"), "NO")

    def test_a_dead_pid_is_not_running(self):
        with open(self.pidfile, "w") as f:
            f.write("999999999")
        self.assertEqual(self._run(self.pidfile, "cartelitos.py"), "NO")

    def test_an_empty_cmdline_falls_back_to_kill_minus_zero(self):
        # entre el fork y el exec (y en un zombie) el cmdline está vacío: exigirlo
        # ahí haría que `fatal on; fatal status` dijera OFF con todo arrancando bien
        proc = subprocess.Popen([sys.executable, "-c", ""])
        self.addCleanup(proc.wait)
        # sin poll()/wait(): eso lo reapea y el PID desaparece. Se espera al
        # estado Z leyendo /proc, que es lo que ve running()
        end = time.monotonic() + 5
        while time.monotonic() < end:
            with open(f"/proc/{proc.pid}/stat") as f:
                if f.read().rsplit(") ", 1)[1].split()[0] == "Z":
                    break
            time.sleep(0.01)
        with open(f"/proc/{proc.pid}/cmdline", "rb") as f:   # zombie sin reapear
            self.assertEqual(f.read(), b"")
        with open(self.pidfile, "w") as f:
            f.write(str(proc.pid))
        self.assertEqual(self._run(self.pidfile, "cartelitos.py"), "YES")


class TestFatalRuntimeLayout(unittest.TestCase):
    """bin/fatal y el paquete tienen que apuntar a los MISMOS archivos."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(REPO, "bin", "fatal"), encoding="utf-8") as f:
            cls.body = f.read()

    def test_no_pidfile_or_log_lives_in_tmp(self):
        for line in self.body.splitlines():
            if line.startswith("OLD_"):   # los viejos, sólo para poder matarlos
                continue
            self.assertNotIn("/tmp/cartelitos", line)

    def test_the_daemon_pidfile_matches_the_python_side(self):
        self.assertIn('D_PID="$RUN/daemon.pid"', self.body)
        self.assertTrue(util.DAEMON_PID_PATH.endswith("/cartelitos/daemon.pid"))

    def test_the_logs_are_opened_in_append_mode(self):
        # con `>` el truncado de la rotación dejaría un agujero del tamaño del log
        self.assertIn('>>"$LOGFILE"', self.body)

    def test_status_asks_the_package_what_is_missing(self):
        self.assertIn("--check", self.body)
