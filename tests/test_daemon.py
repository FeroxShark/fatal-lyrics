"""Tests de la máquina de estados del loop principal (cartelitos.daemon.DaemonLoop).

No corre threads, sockets ni playerctl real: todas las dependencias van
inyectadas como mocks al constructor, así que sólo se ejercita la lógica de
transición (pausa/resume por juego, limpieza al cambiar de track, etc.)."""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))  # noqa: E402

from cartelitos import daemon  # noqa: E402


def make_config(**behavior_overrides):
    """Un stub de `config` con el CFG mínimo que usa DaemonLoop."""
    cfg = mock.MagicMock()
    cfg.CFG = {
        "behavior": {
            "pause_clear": 15,
            "now_playing": True,
            "offset": 0.0,
            "sing": False,
            **behavior_overrides,
        },
        "display": {"karaoke": False},
    }
    cfg.crt_on.return_value = False
    return cfg


def make_ipc():
    ipc_mock = mock.MagicMock()
    ipc_mock._song_where = {"pos": 0.0, "at": 0.0, "playing": False}
    return ipc_mock


def make_lyr():
    lyr_mock = mock.MagicMock()
    lyr_mock._fetch = {"id": None, "lyrics": None, "done": False}
    return lyr_mock


def make_offsets():
    offsets_mock = mock.MagicMock()
    offsets_mock.get.return_value = 0.0
    offsets_mock.track_get.return_value = 0.0
    # devuelven float y no un MagicMock: el daemon los usa como número
    # (`session_offset`) y un mock ahí revienta el `round()` recién dos
    # llamadas después, lejos de donde estaba el problema
    offsets_mock.effective.return_value = 0.0
    offsets_mock.record.return_value = 0.0
    return offsets_mock


def make_loop(**overrides):
    kwargs = dict(
        gaming=mock.Mock(return_value=False),
        playerctl_state=mock.Mock(return_value=None),
        ipc=make_ipc(),
        config=make_config(),
        audio=mock.MagicMock(),
        art=mock.MagicMock(),
        lyr=make_lyr(),
        offsets=make_offsets(),
        tray=mock.MagicMock(),
        log=mock.Mock(),
        sleep=mock.Mock(),
        monotonic=mock.Mock(return_value=0.0),
    )
    kwargs.update(overrides)
    return daemon.DaemonLoop(**kwargs)


def track(id="t1", status="Playing", title="Song", artist="Artist", album="Album",
          art="art.png", pos=1.0, length=100.0):
    return {"id": id, "status": status, "title": title, "artist": artist,
            "album": album, "art": art, "pos": pos, "length": length}


class TestGamePause(unittest.TestCase):
    def test_first_check_pauses_when_gaming_starts(self):
        loop = make_loop(gaming=mock.Mock(return_value=True))
        self.assertTrue(loop.check_game(10.0))
        self.assertTrue(loop.paused_by_game)
        loop._log.assert_any_call("game detected: pausing")

    def test_pausing_clears_in_flight_track_state(self):
        loop = make_loop(gaming=mock.Mock(return_value=True))
        loop.track_id = "abc"
        loop.lyrics = [(0.0, "hola")]
        loop.idx = 3
        loop.check_game(10.0)
        self.assertIsNone(loop.track_id)
        self.assertIsNone(loop.lyrics)
        self.assertEqual(loop.idx, -1)
        loop._ipc.clear.assert_called_once()

    def test_pausing_turns_off_a_running_crt(self):
        cfg = make_config()
        cfg.crt_on.return_value = True
        loop = make_loop(gaming=mock.Mock(return_value=True), config=cfg)
        loop.check_game(10.0)
        self.assertTrue(loop.crt_paused_by_game)
        cfg.set_crt.assert_called_once_with(False)

    def test_resumes_once_gaming_goes_back_to_false(self):
        gaming = mock.Mock(side_effect=[True, False])
        loop = make_loop(gaming=gaming)
        loop.check_game(10.0)      # entra en pausa (t=0, primer chequeo)
        self.assertTrue(loop.paused_by_game)
        result = loop.check_game(20.0)   # pasaron >5s: vuelve a chequear
        self.assertFalse(result)
        self.assertFalse(loop.paused_by_game)
        loop._log.assert_any_call("game closed: resuming")

    def test_resuming_restores_a_crt_it_had_turned_off(self):
        cfg = make_config()
        cfg.crt_on.return_value = True
        gaming = mock.Mock(side_effect=[True, False])
        loop = make_loop(gaming=gaming, config=cfg)
        loop.check_game(10.0)
        loop.check_game(20.0)
        cfg.set_crt.assert_any_call(True)
        self.assertFalse(loop.crt_paused_by_game)

    def test_does_not_re_check_before_five_seconds_pass(self):
        gaming = mock.Mock(return_value=True)
        loop = make_loop(gaming=gaming)
        loop.check_game(10.0)
        loop.check_game(10.5)   # < 5s: no debería volver a llamar a gaming()
        self.assertEqual(gaming.call_count, 1)

    def test_tick_sleeps_two_seconds_while_paused_by_game(self):
        loop = make_loop(gaming=mock.Mock(return_value=True), monotonic=mock.Mock(return_value=10.0))
        loop.tick()
        loop._sleep.assert_called_once_with(2)
        loop._playerctl_state.assert_not_called()


class TestTrackChangeCleanup(unittest.TestCase):
    def test_new_track_id_resets_lyrics_and_index_and_clears_overlay(self):
        loop = make_loop()
        loop.track_id = "old"
        loop.lyrics = [(0.0, "algo")]
        loop.idx = 2

        loop.handle_track(track(id="new"), now=0.0)

        self.assertEqual(loop.track_id, "new")
        self.assertIsNone(loop.lyrics)
        self.assertEqual(loop.idx, -1)
        loop._ipc.clear.assert_called_once()

    def test_new_track_kicks_off_a_lyrics_fetch(self):
        loop = make_loop()
        loop.handle_track(track(id="new", title="Song"), now=0.0)
        loop._lyr.fetch_lyrics_async.assert_called_once()

    def test_new_track_without_title_skips_fetch_and_resets_fetch_state(self):
        loop = make_loop()
        loop.handle_track(track(id="new", title=""), now=0.0)
        loop._lyr.fetch_lyrics_async.assert_not_called()
        self.assertEqual(loop._lyr._fetch, {"id": None, "lyrics": None, "status": None, "done": False})

    def test_new_track_sends_now_playing_when_enabled(self):
        loop = make_loop()
        loop.handle_track(track(id="new"), now=0.0)
        sent = [c.args[0] for c in loop._ipc.send.call_args_list]
        self.assertTrue(any(e.get("cmd") == "np" for e in sent))

    def test_new_track_sends_now_playing_for_the_crt_with_the_sleeve_off(self):
        # la funda apagada, pero el tubo prendido: el evento sale igual porque
        # el modo instrumental del CRT lo necesita para decir qué suena
        cfg = make_config(now_playing=False)
        cfg.crt_on.return_value = True
        loop = make_loop(config=cfg)
        loop.handle_track(track(id="new"), now=0.0)
        sent = [c.args[0] for c in loop._ipc.send.call_args_list]
        self.assertTrue(any(e.get("cmd") == "np" for e in sent))

    def test_new_track_skips_now_playing_with_the_sleeve_and_the_crt_off(self):
        cfg = make_config(now_playing=False)
        cfg.crt_on.return_value = False
        loop = make_loop(config=cfg)
        loop.handle_track(track(id="new"), now=0.0)
        sent = [c.args[0] for c in loop._ipc.send.call_args_list]
        self.assertFalse(any(e.get("cmd") == "np" for e in sent))

    def test_turning_the_crt_on_mid_track_resends_now_playing(self):
        cfg = make_config(now_playing=False)
        cfg.crt_on.return_value = False
        loop = make_loop(config=cfg)
        loop.handle_track(track(id="same"), now=0.0)
        loop._ipc.send.reset_mock()
        cfg.crt_on.return_value = True          # `fatal crt on` a mitad del tema
        loop.handle_track(track(id="same"), now=1.0)
        sent = [c.args[0] for c in loop._ipc.send.call_args_list]
        self.assertTrue(any(e.get("cmd") == "np" for e in sent))
        # y no lo repite en cada vuelta
        loop._ipc.send.reset_mock()
        loop.handle_track(track(id="same"), now=2.0)
        sent = [c.args[0] for c in loop._ipc.send.call_args_list]
        self.assertFalse(any(e.get("cmd") == "np" for e in sent))

    def test_new_track_sets_the_audio_profile(self):
        loop = make_loop()
        t = track(id="new")
        loop.handle_track(t, now=0.0)
        loop._audio.set_profile.assert_called_once()

    def test_same_track_id_does_not_re_trigger_the_cleanup(self):
        loop = make_loop()
        loop.track_id = "same"
        loop.handle_track(track(id="same"), now=0.0)
        loop._ipc.clear.assert_not_called()
        loop._audio.set_profile.assert_not_called()

    def test_player_going_away_clears_state_via_tick(self):
        loop = make_loop(playerctl_state=mock.Mock(return_value=None))
        loop.track_id = "old"
        loop.lyrics = [(0.0, "algo")]
        loop.idx = 5

        loop.tick()

        self.assertIsNone(loop.track_id)
        self.assertIsNone(loop.lyrics)
        self.assertEqual(loop.idx, -1)
        loop._ipc.clear.assert_called_once()
        loop._sleep.assert_called_once_with(1.5)

    def test_player_stopped_status_also_clears_state(self):
        loop = make_loop(playerctl_state=mock.Mock(return_value=track(status="Stopped")))
        loop.track_id = "old"
        loop.tick()
        self.assertIsNone(loop.track_id)
        loop._ipc.clear.assert_called_once()

    def test_no_active_track_ever_is_a_noop(self):
        loop = make_loop(playerctl_state=mock.Mock(return_value=None))
        loop.tick()
        loop._ipc.clear.assert_not_called()


class TestSeekBack(unittest.TestCase):
    def test_seek_back_resets_and_reshows_current_line(self):
        loop = make_loop()
        loop._lyr.current_line_index.side_effect = [2, 0]
        loop.lyrics = [(0.0, "a"), (10.0, "b"), (20.0, "c")]
        loop.track_id = "t1"

        loop.handle_track(track(id="t1", pos=60.0), now=0.0)
        loop._ipc.reset_mock()

        loop.handle_track(track(id="t1", pos=20.0), now=1.0)

        loop._ipc.clear.assert_called_once()
        loop._log.assert_any_call("seek back: reset")
        loop._ipc.show.assert_called_with("a", "Song", 0.0, 10.0, None,
                                          nxt=loop._ipc.next_line.return_value)

    def test_small_backward_jitter_does_not_reset(self):
        loop = make_loop()
        loop._lyr.current_line_index.return_value = 1
        loop.lyrics = [(0.0, "a"), (10.0, "b")]
        loop.track_id = "t1"

        loop.handle_track(track(id="t1", pos=30.0), now=0.0)
        loop._ipc.reset_mock()
        loop.handle_track(track(id="t1", pos=29.0), now=1.0)

        loop._ipc.clear.assert_not_called()

    def test_new_track_is_not_treated_as_a_seek_back(self):
        loop = make_loop()
        loop._lyr.current_line_index.return_value = -1
        loop.lyrics = [(0.0, "a")]
        loop.track_id = "t1"

        loop.handle_track(track(id="t1", pos=60.0), now=0.0)
        loop._ipc.reset_mock()

        loop.handle_track(track(id="t2", pos=0.0), now=1.0)

        # se llama una vez (por el cambio de track), no dos (track-change + seek-back)
        loop._ipc.clear.assert_called_once()
        for call in loop._log.call_args_list:
            self.assertNotEqual(call.args[0], "seek back: reset")


class TestWordTimes(unittest.TestCase):
    """T1.1: si la línea trae tiempos por palabra (LRC "enhanced"), viajan con
    el evento; una línea vieja de dos campos no rompe nada."""

    def test_word_times_go_out_with_the_line(self):
        loop = make_loop()
        loop._lyr.current_line_index.return_value = 0
        loop.lyrics = [(0.0, "one two", [(0.0, "one"), (0.5, "two")]), (10.0, "b", None)]
        loop.track_id = "t1"

        loop.handle_track(track(id="t1", pos=1.0), now=0.0)

        loop._ipc.show.assert_called_with("one two", "Song", 0.0, 10.0,
                                          [(0.0, "one"), (0.5, "two")],
                                          nxt=loop._ipc.next_line.return_value)

    def test_a_two_field_line_still_works(self):
        loop = make_loop()
        loop._lyr.current_line_index.return_value = 0
        loop.lyrics = [(0.0, "a")]
        loop.track_id = "t1"

        loop.handle_track(track(id="t1", pos=1.0), now=0.0)

        loop._ipc.show.assert_called_with("a", "Song", 0.0, 5.0, None,
                                          nxt=loop._ipc.next_line.return_value)


class TestNextLineIsWired(unittest.TestCase):
    """El overlay anticipa dónde cae la línea que viene, así que el `show`
    tiene que llevar la SIGUIENTE a la que se está mostrando — con la letra
    entera y el índice de la actual, no con otra cosa."""

    def test_the_show_carries_the_line_after_the_current_one(self):
        loop = make_loop()
        loop._lyr.current_line_index.return_value = 1
        loop.lyrics = [(0.0, "a"), (10.0, "b"), (20.0, "c")]
        loop.track_id = "t1"

        loop.handle_track(track(id="t1", pos=11.0), now=0.0)

        loop._ipc.next_line.assert_called_once_with(loop.lyrics, 1)


class TestLyricsListIsSent(unittest.TestCase):
    """La letra entera sale UNA vez, cuando la búsqueda vuelve con ella."""

    def _loop_with_fetch(self, lyrics, status):
        loop = make_loop()
        loop.track_id = "t1"
        loop._lyr._fetch = {"id": "t1", "lyrics": lyrics, "done": True,
                            "status": status}
        loop._lyr.current_line_index.return_value = -1
        return loop

    def test_it_goes_out_when_the_lyric_arrives(self):
        loop = self._loop_with_fetch([(0.0, "a"), (10.0, "b")], "ok")
        loop.handle_track(track(id="t1"), now=0.0)
        loop._ipc.lyrics_list.assert_called_once_with([(0.0, "a"), (10.0, "b")])

    def test_only_once_per_track(self):
        loop = self._loop_with_fetch([(0.0, "a")], "ok")
        loop.handle_track(track(id="t1"), now=0.0)
        loop.handle_track(track(id="t1", pos=2.0), now=1.0)
        loop._ipc.lyrics_list.assert_called_once()

    def test_unsynced_lyrics_go_out_without_times(self):
        loop = self._loop_with_fetch([(0.0, "todo el texto junto")], "plain")
        loop.handle_track(track(id="t1"), now=0.0)
        loop._ipc.lyrics_list.assert_not_called()
        loop._ipc.lyrics_plain.assert_called_once_with("todo el texto junto")

    def test_a_track_without_lyrics_sends_no_plain_either(self):
        loop = self._loop_with_fetch(None, "none")
        loop.handle_track(track(id="t1"), now=0.0)
        loop._ipc.lyrics_plain.assert_not_called()

    def test_a_track_without_lyrics_sends_nothing(self):
        loop = self._loop_with_fetch(None, "none")
        loop.handle_track(track(id="t1"), now=0.0)
        loop._ipc.lyrics_list.assert_not_called()


class TestPauseNearEnd(unittest.TestCase):
    def test_paused_near_end_clears_immediately(self):
        loop = make_loop()
        loop.track_id = "t1"
        loop.handle_track(track(id="t1", status="Paused", pos=99.0, length=100.0), now=0.0)
        self.assertTrue(loop.pause_cleared)
        loop._ipc.clear.assert_called_once()
        loop._log.assert_any_call("track ending: dialogs cleared")

    def test_paused_far_from_end_does_not_clear_immediately(self):
        loop = make_loop()
        loop.track_id = "t1"
        loop.handle_track(track(id="t1", status="Paused", pos=10.0, length=100.0), now=0.0)
        self.assertFalse(loop.pause_cleared)
        loop._ipc.clear.assert_not_called()


class TestPlainLyrics(unittest.TestCase):
    def test_shows_a_single_dialog_with_the_first_six_lines(self):
        loop = make_loop()
        loop.track_id = "t1"
        loop.lyrics = [(0.0, "\n".join(f"line {i}" for i in range(10)))]
        loop.lyrics_kind = "plain"

        loop.handle_track(track(id="t1", status="Playing"), now=0.0)

        loop._ipc.show.assert_called_once_with(
            "\n".join(f"line {i}" for i in range(6)), "unsynced lyrics")
        self.assertTrue(loop.plain_shown)

    def test_only_shows_it_once_per_track(self):
        loop = make_loop()
        loop.track_id = "t1"
        loop.lyrics = [(0.0, "line one")]
        loop.lyrics_kind = "plain"

        loop.handle_track(track(id="t1", status="Playing"), now=0.0)
        loop.handle_track(track(id="t1", status="Playing", pos=5.0), now=1.0)

        loop._ipc.show.assert_called_once()

    def test_a_new_track_resets_plain_shown(self):
        loop = make_loop()
        loop.track_id = "t1"
        loop.lyrics = [(0.0, "line one")]
        loop.lyrics_kind = "plain"
        loop.plain_shown = True

        loop.handle_track(track(id="t2", status="Playing"), now=0.0)

        self.assertFalse(loop.plain_shown)


class TestHangDialog(unittest.TestCase):
    """T4.5: silencio largo con la letra cargada. Que el programa se cuelgue a
    propósito es mejor que una pantalla vacía que parece un programa muerto."""

    def loop_with_lyrics(self, line=0):
        loop = make_loop()
        loop.track_id = "t1"
        loop._lyr.current_line_index.return_value = line
        loop.lyrics = [(0.0, "primera"), (120.0, "la que viene mucho después")]
        loop.lyrics_kind = "synced"
        loop.idx = line          # la línea ya se mostró: nada nuevo por mostrar
        loop.last_show_at = 0.0
        return loop

    def test_thirty_seconds_of_silence_hang_the_program(self):
        loop = self.loop_with_lyrics()
        loop.handle_track(track(id="t1", pos=1.0), now=0.0)
        loop._ipc.hang.assert_not_called()
        loop.handle_track(track(id="t1", pos=36.0), now=35.0)
        loop._ipc.hang.assert_called_once_with()

    def test_it_only_hangs_once_per_track(self):
        loop = self.loop_with_lyrics()
        loop.handle_track(track(id="t1", pos=36.0), now=35.0)
        loop.handle_track(track(id="t1", pos=50.0), now=50.0)
        loop._ipc.hang.assert_called_once()

    def test_a_line_that_just_showed_up_resets_the_clock(self):
        # la línea entra en el primer tick (idx pasa de -1 a 0): el reloj del
        # colgado arranca ahí, no cuando se cargó la letra
        loop = self.loop_with_lyrics()
        loop.idx = -1
        loop.handle_track(track(id="t1", pos=1.0), now=20.0)
        loop._ipc.show.assert_called_once()
        loop.handle_track(track(id="t1", pos=30.0), now=45.0)
        loop._ipc.hang.assert_not_called()

    def test_a_new_track_gets_its_own_hang(self):
        loop = self.loop_with_lyrics()
        loop.hang_sent = True
        loop.handle_track(track(id="t2", pos=1.0), now=10.0)
        self.assertFalse(loop.hang_sent)
        self.assertEqual(loop.last_show_at, 10.0)

    def test_unsynced_lyrics_never_hang(self):
        # con la letra sin sincronizar no viene ninguna línea más POR DISEÑO:
        # eso no es un silencio del tema, es todo lo que había
        loop = self.loop_with_lyrics()
        loop.lyrics_kind = "plain"
        loop.lyrics = [(0.0, "todo el texto junto")]
        loop.handle_track(track(id="t1", pos=1.0), now=0.0)
        loop.handle_track(track(id="t1", pos=40.0), now=40.0)
        loop._ipc.hang.assert_not_called()

    def test_a_paused_track_does_not_hang(self):
        loop = self.loop_with_lyrics()
        loop._config.CFG["behavior"]["pause_clear"] = 0
        loop.handle_track(track(id="t1", status="Paused", pos=10.0), now=40.0)
        loop._ipc.hang.assert_not_called()

    def test_the_lyrics_search_does_not_count_as_silence(self):
        # la búsqueda va en otro hilo y puede tardar veinte segundos: esa espera
        # no es el tema quedándose callado
        loop = make_loop()
        loop.track_id = "t1"
        loop.lyrics_kind = None
        loop._lyr.current_line_index.return_value = 0
        loop._lyr._fetch = {"id": "t1", "lyrics": [(0.0, "primera")],
                            "status": "ok", "done": True}
        loop.handle_track(track(id="t1", pos=1.0), now=40.0)
        self.assertEqual(loop.last_show_at, 40.0)
        loop._ipc.hang.assert_not_called()


class TestSync(unittest.TestCase):
    """El gesto de ajuste fino. La cuenta la lleva offsets.record(): el daemon
    aplica lo que ese le devuelve y no acumula nada por su lado, porque
    persistir para el artista REBAJA lo que el tema pide (ver offsets.py) y
    sumar el delta encima lo contaría dos veces."""

    def test_applies_what_offsets_says_the_track_needs(self):
        loop = make_loop()
        loop.current_artist = "Artist"
        loop.track_id = "t1"
        loop.session_offset = 0.15
        loop._offsets.record.return_value = 0.25

        loop.sync(0.1)

        self.assertAlmostEqual(loop.session_offset, 0.25)
        self.assertEqual(loop.idx, -1)

    def test_the_hint_travels_as_its_own_event_not_as_a_dialog(self):
        # un `show` con el tubo prendido PASA A SER la línea de la letra: el
        # aviso borraba el verso que se estaba tratando de sincronizar
        loop = make_loop()
        loop.current_artist = "Artist"
        loop.track_id = "t1"
        loop._offsets.record.return_value = 0.25

        loop.sync(0.1)

        loop._ipc.show.assert_not_called()
        loop._ipc.sync_hint.assert_called_once_with(0.1, 0.25, "Artist")

    def test_a_negative_delta(self):
        loop = make_loop()
        loop.current_artist = "Artist"
        loop.track_id = "t1"
        loop._offsets.record.return_value = -0.1

        loop.sync(-0.1)

        self.assertAlmostEqual(loop.session_offset, -0.1)
        loop._ipc.sync_hint.assert_called_once_with(-0.1, -0.1, "Artist")

    def test_records_the_correction_for_the_current_artist_and_track(self):
        loop = make_loop()
        loop.current_artist = "Artist"
        loop.track_id = "t1"

        loop.sync(0.1)

        loop._offsets.record.assert_called_once_with("Artist", 0.1, "t1")

    def test_without_a_known_artist_does_not_touch_offsets(self):
        loop = make_loop()
        loop.current_artist = None
        loop.track_id = "t1"

        loop.sync(0.1)

        loop._offsets.record.assert_not_called()
        self.assertAlmostEqual(loop.session_offset, 0.1)

    def test_without_a_track_id_does_not_touch_offsets(self):
        # no hay a qué tema anotárselo: se aplica a la sesión y nada más
        loop = make_loop()
        loop.current_artist = "Artist"
        loop.track_id = None

        loop.sync(0.1)

        loop._offsets.record.assert_not_called()
        self.assertAlmostEqual(loop.session_offset, 0.1)

    def test_a_new_track_seeds_the_session_offset_from_artist_plus_track(self):
        loop = make_loop(offsets=make_offsets())
        loop._offsets.effective.return_value = 0.3

        loop.handle_track(track(id="new", artist="Artist"), now=0.0)

        self.assertEqual(loop.current_artist, "Artist")
        self.assertEqual(loop.session_offset, 0.3)
        loop._offsets.effective.assert_called_once_with("Artist", "new")


class TestLongPauseClear(unittest.TestCase):
    def test_clears_after_the_configured_pause_window(self):
        loop = make_loop(config=make_config(pause_clear=15))
        loop.handle_track(track(status="Paused"), now=0.0)
        self.assertFalse(loop.pause_cleared)

        loop._ipc.reset_mock()
        loop.handle_track(track(status="Paused"), now=16.0)
        self.assertTrue(loop.pause_cleared)
        loop._ipc.clear.assert_called_once()

    def test_zero_disables_the_long_pause_clear(self):
        loop = make_loop(config=make_config(pause_clear=0))
        loop.handle_track(track(status="Paused"), now=0.0)
        loop._ipc.reset_mock()
        loop.handle_track(track(status="Paused"), now=1000.0)
        self.assertFalse(loop.pause_cleared)
        loop._ipc.clear.assert_not_called()

    def test_resuming_playback_resends_now_playing_after_a_clear(self):
        loop = make_loop(config=make_config(pause_clear=15))
        loop.handle_track(track(status="Paused"), now=0.0)
        loop.handle_track(track(status="Paused"), now=16.0)
        self.assertTrue(loop.resend_np)

        loop._ipc.reset_mock()
        loop.handle_track(track(status="Playing"), now=17.0)
        self.assertFalse(loop.resend_np)
        sent = [c.args[0] for c in loop._ipc.send.call_args_list]
        self.assertTrue(any(e.get("cmd") == "np" for e in sent))


class TestFastPollDecision(unittest.TestCase):
    def test_playing_with_lyrics_wants_the_fast_poll(self):
        loop = make_loop()
        loop._lyr.current_line_index.return_value = -1
        loop.track_id = "t1"          # mismo id que track(): no dispara track-change
        loop.lyrics = [(0.0, "linea")]
        fast = loop.handle_track(track(status="Playing"), now=0.0)
        self.assertTrue(fast)

    def test_paused_never_wants_the_fast_poll(self):
        loop = make_loop()
        loop.track_id = "t1"
        loop.lyrics = [(0.0, "linea")]
        fast = loop.handle_track(track(status="Paused"), now=0.0)
        self.assertFalse(fast)

    def test_playing_without_lyrics_wants_the_idle_poll(self):
        loop = make_loop()
        fast = loop.handle_track(track(status="Playing", title=""), now=0.0)
        self.assertFalse(fast)


if __name__ == "__main__":
    unittest.main()


class TestSingGate(unittest.TestCase):
    """T5.2: ¿está cantando? El umbral sale de la sala, no de un número fijo."""

    def quiet(self, gate, level=0.004, seconds=20.0, t=0.0):
        """Llena la ventana del cuarto con ruido de fondo. Devuelve el reloj."""
        for _ in range(int(seconds * 10)):
            t += 0.1
            gate.feed(level, t)
        return t

    def test_a_quiet_room_is_not_singing(self):
        gate = daemon.SingGate()
        self.quiet(gate)
        self.assertFalse(gate.singing)

    def test_nothing_is_decided_before_there_is_a_room_to_compare_with(self):
        gate = daemon.SingGate()
        t = 0.0
        for _ in range(5):     # medio segundo de mic: todavía no alcanza
            t += 0.1
            self.assertFalse(gate.feed(0.5, t))
        self.assertIsNone(gate.threshold())

    def test_a_voice_over_the_room_turns_it_on(self):
        gate = daemon.SingGate()
        t = self.quiet(gate)
        changed = False
        for _ in range(20):
            t += 0.1
            changed = gate.feed(0.2, t) or changed
        self.assertTrue(changed)
        self.assertTrue(gate.singing)

    def test_it_stays_on_through_a_whole_chorus(self):
        # el que se comería un umbral que se alimenta con la propia voz: a los
        # veinte segundos el percentil 60 SERÍA la voz y el modo se apagaría
        # solo en la mitad del estribillo
        gate = daemon.SingGate()
        t = self.quiet(gate)
        for _ in range(300):        # 30 s cantando sin parar
            t += 0.1
            gate.feed(0.2, t)
        self.assertTrue(gate.singing)

    def test_going_quiet_again_turns_it_off(self):
        gate = daemon.SingGate()
        t = self.quiet(gate)
        for _ in range(100):
            t += 0.1
            gate.feed(0.2, t)
        for _ in range(60):         # seis segundos callado
            t += 0.1
            gate.feed(0.004, t)
        self.assertFalse(gate.singing)

    def test_a_breath_in_the_middle_does_not_lose_the_room(self):
        # la memoria del cuarto es de MUESTRAS calladas, no de reloj: con un
        # filtro por tiempo, un estribillo de más de 20 s la deja toda vencida
        # y el primer respiro la borra — el umbral se rearmaba con la voz que
        # venía enseguida y el modo no volvía a prender nunca más
        gate = daemon.SingGate()
        t = self.quiet(gate)
        for _ in range(300):        # 30 s cantando
            t += 0.1
            gate.feed(0.2, t)
        for _ in range(20):         # dos segundos de respiro
            t += 0.1
            gate.feed(0.004, t)
        self.assertFalse(gate.singing)
        self.assertIsNotNone(gate.threshold())   # el cuarto sigue ahí
        for _ in range(10):         # y se vuelve a cantar
            t += 0.1
            gate.feed(0.2, t)
        self.assertTrue(gate.singing)

    def test_the_room_only_remembers_its_own_size(self):
        gate = daemon.SingGate()
        self.quiet(gate, seconds=120.0)
        self.assertEqual(len(gate.room), int(daemon.SING_HISTORY * 10))

    def test_a_steady_fan_never_turns_it_on(self):
        # ruido de fondo parejo y fuerte: el umbral ES ese ruido, así que no
        # puede superarse a sí mismo (por eso los dos multiplicadores son > 1)
        gate = daemon.SingGate()
        self.quiet(gate, level=0.05, seconds=40.0)
        self.assertFalse(gate.singing)

    def test_absolute_silence_never_turns_it_on(self):
        gate = daemon.SingGate()
        self.quiet(gate, level=0.0, seconds=30.0)
        self.assertFalse(gate.singing)

    def test_without_a_line_playing_it_never_turns_on(self):
        # hablar al lado del micrófono sin música no es cantar
        gate = daemon.SingGate()
        t = self.quiet(gate)
        for _ in range(50):
            t += 0.1
            gate.feed(0.3, t, active=False)
        self.assertFalse(gate.singing)

    def test_the_line_going_away_turns_it_off(self):
        gate = daemon.SingGate()
        t = self.quiet(gate)
        for _ in range(30):
            t += 0.1
            gate.feed(0.2, t)
        self.assertTrue(gate.singing)
        t += 0.1
        self.assertTrue(gate.feed(0.2, t, active=False))
        self.assertFalse(gate.singing)


class TestVoiceEvents(unittest.TestCase):
    """El daemon es el único que sabe si hay letra sonando: la decisión se toma
    acá y al overlay le llega el resultado, no el nivel del micrófono."""

    def loop_singing(self):
        loop = make_loop(config=make_config(sing=True))
        loop.voice_active = True
        t = 0.0
        for _ in range(200):
            t += 0.1
            loop.voice(0.004, t)
        return loop, t

    def sing_events(self, loop):
        return [call.args[0] for call in loop._ipc.send.call_args_list
                if call.args and call.args[0].get("cmd") == "sing"]

    def test_it_tells_the_overlay_when_the_singing_starts(self):
        loop, t = self.loop_singing()
        for _ in range(20):
            t += 0.1
            loop.voice(0.2, t)
        self.assertEqual(self.sing_events(loop), [{"cmd": "sing", "on": True}])

    def test_only_the_changes_travel(self):
        # 10 bloques por segundo: mandar cada uno sería un chorro por el socket
        loop, t = self.loop_singing()
        for _ in range(100):
            t += 0.1
            loop.voice(0.2, t)
        for _ in range(60):
            t += 0.1
            loop.voice(0.004, t)
        self.assertEqual(self.sing_events(loop),
                         [{"cmd": "sing", "on": True}, {"cmd": "sing", "on": False}])

    def test_with_the_mode_off_the_mic_decides_nothing(self):
        loop = make_loop()      # sing = False
        loop.voice_active = True
        t = 0.0
        for _ in range(300):
            t += 0.1
            loop.voice(0.5, t)
        self.assertFalse(loop.sing.singing)
        self.assertEqual(self.sing_events(loop), [])

    def test_turning_the_mode_off_puts_the_screen_back(self):
        # sin esto el overlay se queda esperando un "dejó de cantar" que ya
        # nadie va a mandar: con el modo apagado no hay captura
        loop = make_loop(config=make_config(sing=True))
        loop.voice_active = True
        t = 0.0
        for _ in range(220):
            t += 0.1
            loop.voice(0.004 if _ < 200 else 0.2, t)
        self.assertTrue(loop.sing.singing)
        loop._config.CFG["behavior"]["sing"] = False
        loop.voice(0.2, t + 0.1)
        self.assertFalse(loop.sing.singing)
        self.assertEqual(self.sing_events(loop)[-1], {"cmd": "sing", "on": False})


class TestVoiceActive(unittest.TestCase):
    """`voice_active` es la mitad de la decisión: cantar necesita una canción."""

    def playing(self, **kw):
        """Un loop con el tema ya en curso (mismo id que track(): no dispara
        el camino de track nuevo, que borraría la letra)."""
        loop = make_loop(**kw)
        loop._lyr.current_line_index.return_value = -1
        loop.track_id = "t1"
        loop.lyrics = [(0.0, "line")]
        return loop

    def test_playing_with_lyrics_is_active(self):
        loop = self.playing()
        loop.handle_track(track(pos=1.0), 1.0)
        self.assertTrue(loop.voice_active)

    def test_paused_is_not_active(self):
        loop = self.playing()
        loop.handle_track(track(status="Paused", pos=1.0), 1.0)
        self.assertFalse(loop.voice_active)

    def test_without_lyrics_it_is_not_active(self):
        # un instrumental no se canta: la pantalla no tiene que prenderse
        loop = self.playing()
        loop.lyrics = None
        loop.handle_track(track(pos=1.0), 1.0)
        self.assertFalse(loop.voice_active)

    def test_the_player_going_away_is_not_active(self):
        loop = self.playing()
        loop.handle_track(track(pos=1.0), 1.0)
        loop.clear_track_state()
        self.assertFalse(loop.voice_active)

    def test_a_game_pause_is_not_active(self):
        loop = self.playing(gaming=mock.Mock(return_value=True))
        loop.handle_track(track(pos=1.0), 1.0)
        loop.check_game(100.0)
        self.assertFalse(loop.voice_active)
