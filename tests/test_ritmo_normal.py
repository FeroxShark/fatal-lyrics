"""Ritmo en el modo NORMAL (cartelitos, sin tubo): la captura de audio y la grilla de tiempos
(`BeatGrid`) también corren con carteles + música, y los glitches espontáneos caen sobre la grilla
(`shell/BeatBurst.qml`, con la misma `msToNextBeat` que el CRT). Ver docs/TRAMPAS.md "Todo al
ritmo". Los glitches se miden de verdad: un harness de QML corre `BeatBurst` con una grilla de
120 BPM y se mide en qué punto del compás cae cada disparo."""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from cartelitos import audio  # noqa: E402

SHELL = os.path.join(ROOT, "shell")
QML = shutil.which("qml6") or shutil.which("qml")

HARNESS = """
import QtQuick
import "file://%(shell)s"

Item {
    id: top
    property double anchor: Date.now() - 137      // la grilla: un tiempo cada %(beat)d ms
    property real beatMs: %(beat)d
    property bool lockedNow: %(locked)s
    property var fired: []
    function msToNextBeat(now) {
        const b = beatMs;
        return b - (((now - anchor) %% b) + b) %% b;
    }
    function beatStepAim(left) {
        return Math.max(1, Math.round(left > 40 ? left * 0.85 : left));
    }
    BeatBurst {
        active: true
        locked: top.lockedNow
        beatMs: top.beatMs
        msToNext: top.msToNextBeat
        stepAim: top.beatStepAim
        glitchiness: 1
        gProb: 10                                  // todos los intentos disparan
        onBurst: {
            const b = top.beatMs;
            let late = ((Date.now() - top.anchor) %% b + b) %% b;
            if (late > b / 2)
                late -= b;
            top.fired.push(Math.round(late));
        }
    }
    Timer {
        interval: %(run)d
        running: true
        onTriggered: { console.log("FIRED " + JSON.stringify(top.fired)); Qt.quit(); }
    }
}
"""


def run_harness(locked, run_ms=5200, beat=500):
    d = tempfile.mkdtemp(prefix="bbtest-")
    try:
        path = os.path.join(d, "h.qml")
        with open(path, "w") as f:
            f.write(HARNESS % {"shell": SHELL, "beat": beat, "run": run_ms,
                               "locked": "true" if locked else "false"})
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1")
        out = subprocess.run([QML, path], capture_output=True, text=True, timeout=60, env=env)
        m = re.search(r"FIRED (\[.*?\])", out.stdout + out.stderr)
        if not m:
            raise AssertionError("harness sin salida:\n" + out.stdout + out.stderr)
        return eval(m.group(1))
    finally:
        shutil.rmtree(d, ignore_errors=True)


@unittest.skipUnless(QML, "falta el binario `qml`")
class TestLosGlitchesCaenSobreElTiempo(unittest.TestCase):
    def test_with_a_beat_grid_every_glitch_lands_on_the_beat(self):
        fired = run_harness(locked=True)
        self.assertGreaterEqual(len(fired), 5, fired)       # ~un intento por tiempo, 5,2 s a 120 BPM
        # qué tan cerca de la marca: el Timer de QML es grueso, pero el último paso es corto
        for late in fired:
            self.assertLess(abs(late), 25, fired)
        # y no se apilan: un disparo por tiempo como mucho
        self.assertLessEqual(len(fired), 11, fired)

    def test_without_a_beat_grid_they_fall_back_to_random(self):
        fired = run_harness(locked=False)
        self.assertGreaterEqual(len(fired), 5, fired)
        # al azar: si TODOS cayeran a menos de 40 ms del compás, sería una grilla
        self.assertTrue(any(abs(late) > 60 for late in fired), fired)


class TestLaGrillaEnModoNormal(unittest.TestCase):
    CFG = {"display": {"dialogs": True}, "effects": {"glitch": "normal"},
           "crt": {"audio": True, "beat_lock": True}}

    def patch(self, cfg=None, crt=False, playing=True):
        cfg = cfg or self.CFG
        return (mock.patch.object(audio.config, "CFG", cfg),
                mock.patch.object(audio.config, "crt_on", return_value=crt),
                mock.patch.object(audio.ipc, "_song_pos", return_value=10.0 if playing else None))

    def run_with(self, **kw):
        a, b, c = self.patch(**kw)
        with a, b, c:
            return audio.capture_wanted()

    def setUp(self):
        audio._light["playing_at"] = 0.0

    def test_music_with_dialogs_turns_the_capture_on_without_the_tube(self):
        self.assertTrue(self.run_with())

    def test_no_music_means_no_capture(self):
        self.assertFalse(self.run_with(playing=False))

    def test_a_short_pause_keeps_the_grid_and_a_long_one_drops_it(self):
        self.assertTrue(self.run_with())
        self.assertTrue(self.run_with(playing=False))              # recién pausada
        audio._light["playing_at"] -= audio.LIGHT_GRACE_S + 1
        self.assertFalse(self.run_with(playing=False))

    def test_every_switch_that_makes_it_pointless_turns_it_off(self):
        for section, key, val in (("display", "dialogs", False), ("effects", "glitch", "off"),
                                  ("crt", "beat_lock", False), ("crt", "audio", False)):
            cfg = {k: dict(v) for k, v in self.CFG.items()}
            cfg[section][key] = val
            self.assertFalse(self.run_with(cfg=cfg), (section, key))

    def test_the_tube_still_captures_with_no_dialogs(self):
        cfg = {k: dict(v) for k, v in self.CFG.items()}
        cfg["display"]["dialogs"] = False
        self.assertTrue(self.run_with(cfg=cfg, crt=True, playing=False))


class TestElCableado(unittest.TestCase):
    def read(self, *p):
        with open(os.path.join(ROOT, *p), encoding="utf-8") as f:
            return f.read()

    def test_the_overlay_burst_clock_is_the_beat_clock(self):
        qml = self.read("shell", "shell.qml")
        self.assertIn("BeatBurst {", qml)
        self.assertIn("msToNext: root.msToNextBeat", qml)
        self.assertIn("locked: root.crtBeatLock && root.bpmLive", qml)
        m = re.search(r"readonly property bool bpmLive:(.*?)\n    // Cuantizar", qml, re.S)
        self.assertNotIn("crtOn", m.group(1))        # la grilla vive también sin tubo

    def test_there_is_no_random_burst_timer_left_in_the_dialog(self):
        qml = self.read("shell", "shell.qml")
        self.assertNotIn("interval = 160 + Math.random()", qml)

    def test_the_light_capture_skips_what_only_the_tube_draws(self):
        src = self.read("cartelitos", "audio.py").split("def _capture_loop", 1)[1]
        self.assertIn("light = not config.crt_on()", src)
        for needle in ("not light and now - last_wave", "not light and gate.hit",
                       "if light:\n                    continue"):
            self.assertIn(needle, src)


if __name__ == "__main__":
    unittest.main()
