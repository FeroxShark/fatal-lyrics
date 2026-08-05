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


def make_loop(**overrides):
    kwargs = dict(
        gaming=mock.Mock(return_value=False),
        playerctl_state=mock.Mock(return_value=None),
        ipc=make_ipc(),
        config=make_config(),
        audio=mock.MagicMock(),
        art=mock.MagicMock(),
        lyr=make_lyr(),
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
        self.assertEqual(loop._lyr._fetch, {"id": None, "lyrics": None, "done": False})

    def test_new_track_sends_now_playing_when_enabled(self):
        loop = make_loop()
        loop.handle_track(track(id="new"), now=0.0)
        sent = [c.args[0] for c in loop._ipc.send.call_args_list]
        self.assertTrue(any(e.get("cmd") == "np" for e in sent))

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
