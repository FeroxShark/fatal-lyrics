"""Ritmo: una sola grilla de tiempos (`BeatGrid`), con la latencia del análisis restada, enganchada
con un PLL y re-sincronizada en seek/pausa. Ver docs/TRAMPAS.md "Todo al ritmo".

La parte del daemon se mide con golpes sintéticos (la fase que sale por el evento `bpm` contra
el tiempo VERDADERO del bombo); la del overlay, por texto, como los demás tests de shell/."""
import math
import os
import random
import re
import statistics
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from cartelitos import audio as c  # noqa: E402

SHELL = os.path.join(ROOT, "shell")


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


def wrap(x, p):
    """x en (-p/2, p/2]: el error de fase más corto."""
    return (x + p / 2) % p - p / 2


def simulate(bpm=123.4, seconds=120.0, jitter=0.015, extras=True, seed=3, t0=1000.0,
             shift=None, tracker=None):
    """Un tema a `bpm` con bombos que caen con jitter, algún golpe perdido y contratiempos
    (palmas/hi-hats que sobresalen) — como sale de la vida real. Devuelve la lista de
    (now, evento bpm, tiempo verdadero del último tiempo) cada vez que el daemon habla.

    `shift=(t, delta)`: a los `t` s el tema salta `delta` s de fase (un seek)."""
    rnd = random.Random(seed)
    P = 60.0 / bpm
    tr = tracker or c.BpmTracker()
    out = []
    k = 0
    phase_shift = 0.0
    while k * P < seconds:
        true = t0 + k * P + phase_shift
        if shift and k * P >= shift[0] and not phase_shift:
            phase_shift = shift[1]
            true += phase_shift
            tr.grid.unlock()                       # el daemon lo detecta por la posición
        events = []
        if rnd.random() > 0.08:                    # 8 % de bombos perdidos
            events.append(true + rnd.uniform(-jitter, jitter))
        if extras and rnd.random() < 0.4:          # contratiempo a la corchea (palma / hi-hat)
            events.append(true + P * 0.5 + rnd.uniform(-jitter, jitter))
        if extras and rnd.random() < 0.06:         # y alguno suelto, donde cae
            events.append(true + P * rnd.uniform(0.2, 0.8))
        for t in events:
            now = t + c.BEAT_LATENCY_S             # el análisis se entera tarde
            tr.beat(now)
            ev = tr.event(now)
            if ev:
                out.append((now, ev, true, t))
        k += 1
    return tr, out


def grid_error(tr, truths):
    """Error (s) de la grilla contra los tiempos verdaderos en `truths`."""
    P = 60.0 / tr.bpm
    errs = []
    for t_true in truths:
        # la grilla dice que hubo un tiempo en anchor + n*P; el verdadero está en t_true
        n = round((t_true - tr.grid.anchor) / tr.grid.period)
        errs.append(tr.grid.anchor + n * tr.grid.period - t_true)
    return errs


class TestBeatGrid(unittest.TestCase):
    def test_the_grid_lands_on_the_real_beat_with_noise(self):
        # el evento ancla al overlay en `now - phase`: contra el tiempo verdadero del bombo,
        # con bombos perdidos, contratiempos a la corchea y algún golpe suelto
        P = 60.0 / 123.4
        for seed in range(1, 11):
            tr, out = simulate(seed=seed)
            errs = [wrap(now - ev["phase"] - true, P) for now, ev, true, _ in out if now > 1010.0]
            self.assertTrue(errs)
            self.assertLess(statistics.pstdev(errs), 0.010, seed)
            self.assertLess(max(abs(e) for e in errs), 0.045, seed)
            self.assertLess(abs(statistics.mean(errs)), 0.008, seed)   # sin sesgo: latencia compensada

    def test_the_old_anchor_to_the_last_onset_was_worse(self):
        # antes: phase = edad del ÚLTIMO golpe detectado (contratiempos incluidos)
        P = 60.0 / 123.4
        tr, out = simulate()
        old = [wrap(t + c.BEAT_LATENCY_S - true, P) for now, ev, true, t in out if now > 1010.0]
        new = [wrap(now - ev["phase"] - true, P) for now, ev, true, _ in out if now > 1010.0]
        self.assertGreater(statistics.pstdev(old), 5 * statistics.pstdev(new))

    def test_it_locks_in_a_few_seconds_even_when_the_first_onsets_are_offbeats(self):
        P = 60.0 / 123.4
        for seed in range(1, 21):
            tr, out = simulate(seed=seed, seconds=60.0)
            bad = [now - 1000.0 for now, ev, true, _ in out
                   if abs(wrap(now - ev["phase"] - true, P)) > 0.045]
            self.assertLess(max(bad, default=0.0), 12.0, seed)

    def test_no_drift_over_two_and_a_half_minutes(self):
        # el período que mide el tracker se mueve (121..124 BPM en la corrida): la grilla no
        # se va con él, el PLL la mantiene sobre el bombo
        P = 60.0 / 123.4
        tr, out = simulate(seconds=150.0, seed=11)
        errs = [(now, wrap(now - ev["phase"] - true, P)) for now, ev, true, _ in out if now > 1010.0]
        third = len(errs) // 3
        first = [e for _, e in errs[:third]]
        last = [e for _, e in errs[-third:]]
        self.assertLess(abs(statistics.mean(last) - statistics.mean(first)), 0.012)
        self.assertLess(max(abs(e) for _, e in errs), 0.040)

    def test_a_real_tempo_change_is_followed(self):
        # 123 -> 100 BPM: el tracker lo tarda en ver y la grilla lo reemplaza sólo si se sostiene
        tr, _ = simulate(bpm=123.4, seconds=40.0, seed=2)
        tr, out = simulate(bpm=100.0, seconds=60.0, seed=4, t0=1040.0, tracker=tr)
        P = 0.6
        late = [wrap(now - ev["phase"] - true, P) for now, ev, true, _ in out if now > 1040.0 + 35.0]
        self.assertTrue(late)
        self.assertLess(statistics.pstdev(late), 0.015)
        self.assertAlmostEqual(tr.grid.period, 0.6, delta=0.012)

    def test_a_seek_relocks_within_a_few_beats(self):
        P = 60.0 / 123.4
        tr, out = simulate(seconds=60.0, shift=(30.0, 0.21), seed=5)
        after = [(now, wrap(now - ev["phase"] - true, P)) for now, ev, true, _ in out if now > 1030.0]
        settled = [e for now, e in after if now > 1030.0 + 8 * P]
        self.assertTrue(settled)
        self.assertLess(max(abs(e) for e in settled), 0.040)

    def test_pause_and_seek_unlock_the_grid(self):
        g = c.BeatGrid()
        g.onset(10.0, 0.5)
        self.assertIsNotNone(g.age(10.2))
        g.unlock()
        self.assertIsNone(g.age(10.2))

    def test_offbeat_onsets_do_not_move_the_grid(self):
        g = c.BeatGrid()
        for k in range(8):
            g.onset(10.0 + 0.5 * k, 0.5)
        before = g.anchor
        g.onset(14.25, 0.5)             # contratiempo exacto: a media corchea... fuera de GRID_TOL
        self.assertAlmostEqual(g.anchor % 0.5, before % 0.5, places=6)

    def test_changing_the_period_does_not_jump_the_current_beat(self):
        g = c.BeatGrid()
        for k in range(10):
            g.onset(10.0 + 0.5 * k, 0.5)
        age = g.age(14.9)
        g.onset(15.0, 0.4999)           # el compás se afinó un pelo
        self.assertAlmostEqual(g.age(15.0), 0.0, delta=0.02)
        self.assertLess(age, 0.5)

    def test_the_analysis_latency_is_subtracted_from_the_anchor(self):
        tr = c.BpmTracker()
        t = 100.0
        for _ in range(14):
            tr.beat(t)
            t += 0.5
        t -= 0.5
        ev = tr.event(t + 0.2)
        self.assertAlmostEqual(ev["phase"], 0.2 + c.BEAT_LATENCY_S, delta=0.01)

    def test_the_latency_estimate_is_the_half_hop_plus_the_capture_quantum(self):
        self.assertAlmostEqual(c.BEAT_LATENCY_S, c.AUDIO_HOP / c.AUDIO_RATE / 2 + 0.010)
        self.assertLess(c.BEAT_LATENCY_S, 0.05)

    def test_the_capture_loop_relocks_on_pause_and_on_position_jumps(self):
        with open(os.path.join(ROOT, "cartelitos", "audio.py"), encoding="utf-8") as f:
            src = f.read()
        loop = src.split("def _capture_loop", 1)[1]
        self.assertIn("bpm.grid.unlock()", loop)
        self.assertIn("SEEK_JUMP_S", loop)


class TestUnaSolaFuenteDeTiempo(unittest.TestCase):
    """El overlay: lo que va al ritmo cuelga de `lastBeatAt`/`beatMs` (shell.qml) y de las
    funciones de ahí, no de relojes propios."""

    def test_the_beat_tick_is_aimed_at_the_grid_not_polled(self):
        qml = read("shell.qml")
        self.assertIn("function msToNextBeat(", qml)
        self.assertIn("function beatStepAim(", qml)
        self.assertIn("beatLateMs", qml)
        self.assertNotRegex(qml, r"Timer \{\s*interval: 25\s*repeat: true\s*running: root\.crtOn && root\.bpmLive")

    def test_the_grid_stops_when_the_music_is_paused(self):
        qml = read("shell.qml")
        m = re.search(r"readonly property bool bpmLive:(.*?)\n    // Cuantizar", qml, re.S)
        self.assertIn("posPlaying", m.group(1))

    def test_the_offset_knob_exists_in_every_layer(self):
        for rel, needle in (("cartelitos/config.py", "beat_offset"),
                            ("cartelitos/ipc.py", "crt_beat_offset"),
                            ("cartelitos/settings.py", "beat_offset"),
                            ("shell/shell.qml", "crtBeatOffset")):
            with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
                self.assertIn(needle, f.read(), rel)

    def test_hit_and_the_tick_ask_the_same_function(self):
        crt = read("Crt.qml")
        body = crt.split("function hit(", 1)[1].split("function beatStep", 1)[0]
        self.assertIn("ctl.msToNextBeat(", body)

    def test_the_timer_clock_of_the_tube_counts_real_time(self):
        crt = read("Crt.qml")
        m = re.search(r"interval: crt\.deepSleep \|\| crt\.tubeIdle \? 200.*?\n    \}\n", crt, re.S)
        body = m.group(0)
        self.assertNotIn("tubeTime += interval / 1000", body)
        self.assertIn("Date.now()", body)


if __name__ == "__main__":
    unittest.main()
