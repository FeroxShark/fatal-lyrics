"""Tests for the parts that are easy to break without noticing: the LRC parser,
the TOML writer that has to preserve your comments, config reloading, and the
three-way lyrics result that the cache and the retry both depend on.

Run with:  python3 -m unittest discover -s tests
"""
import atexit
import builtins
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
atexit.register(_TMP.cleanup)  # si no, el finalizer avisa que quedó sin limpiar
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


class TestCrtSwitch(unittest.TestCase):
    """El interruptor del modo CRT es un archivo, no el socket: el overlay lo
    vigila él mismo, así que apagarlo tiene que funcionar con el daemon muerto."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self._old = c.CRT_PATH
        c.CRT_PATH = os.path.join(self.dir.name, "cartelitos-crt")
        self.addCleanup(lambda: setattr(c, "CRT_PATH", self._old))

    def test_off_when_the_file_is_not_there(self):
        self.assertFalse(c.crt_on())

    def test_on_and_off_round_trip(self):
        self.assertTrue(c.set_crt(True))
        self.assertTrue(c.crt_on())
        self.assertTrue(c.set_crt(False))
        self.assertFalse(c.crt_on())

    def test_the_file_holds_a_single_flag(self):
        c.set_crt(True)
        with open(c.CRT_PATH) as f:
            self.assertEqual(f.read(), "1")

    def test_garbage_reads_as_off(self):
        with open(c.CRT_PATH, "w") as f:
            f.write("whatever")
        self.assertFalse(c.crt_on())

    def test_no_leftover_temp_file(self):
        # se escribe con rename atómico: el overlay nunca lee un archivo a medias
        c.set_crt(True)
        self.assertEqual(sorted(os.listdir(self.dir.name)), ["cartelitos-crt"])

    def test_a_directory_that_does_not_exist_does_not_raise(self):
        c.CRT_PATH = os.path.join(self.dir.name, "nope", "cartelitos-crt")
        self.assertFalse(c.set_crt(True))
        self.assertFalse(c.crt_on())


class TestConfigEvent(unittest.TestCase):
    """El evento de config se arma a mano: una clave nueva en DEFAULTS que no se
    agregue acá nunca llega al overlay, y no falla nada — simplemente no anda."""

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


class TestCrtOrder(unittest.TestCase):
    """El orden de las pantallas decide dónde cae cada pedazo de una línea
    partida, así que una entrada mal escrita no puede pasar como buena."""

    MONS = [("DP-4", "vertical, at x=0"), ("HDMI-A-2", "at x=1080"),
            ("DP-5", "at x=3000")]

    def setUp(self):
        self._mons = c._monitors_lr
        c._monitors_lr = lambda: list(self.MONS)
        self.addCleanup(lambda: setattr(c, "_monitors_lr", self._mons))
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
        c._monitors_lr = lambda: [("DP-4", "at x=0")]
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
        self._old = c.PROFILE_DIR
        c.PROFILE_DIR = self.dir.name
        self.addCleanup(lambda: setattr(c, "PROFILE_DIR", self._old))

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
        old = c.send
        c.send = lambda ev: sent.append(ev)
        self.addCleanup(lambda: setattr(c, "send", old))
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
