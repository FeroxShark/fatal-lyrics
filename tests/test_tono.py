"""El color sigue a la canción: `cartelitos/tone.py` mide, `shell/Faces.js` aplica.

Señales sintéticas pasadas por el `AudioAnalyzer` de verdad (no eventos
inventados): un agudo brillante tiene que dar `warm` positivo, un grave hondo
negativo, un cambio SOSTENIDO de sección mueve `shift` y un ruido corto no.
Del lado de JS (con node): el tono cálido cae en ámbar y no en violeta, el frío
en azul hondo y más oscuro, y la letra se lee en toda la rueda y todo el rango.
"""
import json
import math
import os
import random
import re
import shutil
import struct
import subprocess
import unittest

from cartelitos import audio, tone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")
NODE = shutil.which("node")
R = audio.AUDIO_RATE
HOP = audio.AUDIO_HOP
DT = HOP / R


def block(kind, i, amp=1.0, rng=None):
    """Un bloque de PCM (s16 mono) del tipo pedido."""
    out = []
    for k in range(HOP):
        t = (i * HOP + k) / R
        if kind == "deep":      # bajo + armónico, nada arriba de 200 Hz
            v = 0.5 * math.sin(2 * math.pi * 70 * t) + 0.2 * math.sin(2 * math.pi * 140 * t)
        elif kind == "mid":     # voz media
            v = 0.3 * math.sin(2 * math.pi * 220 * t) + 0.2 * math.sin(2 * math.pi * 660 * t)
        elif kind == "bright":  # voz alta, platillos
            v = (0.25 * math.sin(2 * math.pi * 1800 * t) + 0.2 * math.sin(2 * math.pi * 3000 * t)
                 + 0.2 * math.sin(2 * math.pi * 4200 * t) + 0.1 * rng.uniform(-1, 1))
        else:
            raise ValueError(kind)
        out.append(int(max(-1.0, min(1.0, v * amp)) * 32767))
    return struct.pack(f"<{HOP}h", *out)


class Run:
    """Pasa señal por el analizador y el tracker, con reloj propio."""

    def __init__(self):
        self.an = audio.AudioAnalyzer()
        self.tr = tone.ToneTracker()
        self.now = 100.0
        self.i = 0
        self.rng = random.Random(7)
        self.msgs = []

    def play(self, kind, seconds, amp=1.0):
        for _ in range(int(seconds / DT)):
            self.now += DT
            self.i += 1
            ev = self.an.feed(block(kind, self.i, amp, self.rng), self.now)
            msg = self.tr.feed(ev, self.now, self.an.peak)
            if msg:
                self.msgs.append(msg)
        return self.tr.warm, self.tr.shift


class TestRegister(unittest.TestCase):
    def test_bright_high_sound_leans_warm(self):
        warm, _ = Run().play("bright", 30)
        self.assertGreater(warm, 0.5)

    def test_deep_low_sound_leans_cold(self):
        warm, _ = Run().play("deep", 30)
        self.assertLess(warm, -0.5)

    def test_it_moves_with_the_register_both_ways(self):
        r = Run()
        r.play("deep", 20)
        low = r.tr.warm
        r.play("bright", 25)
        high = r.tr.warm
        r.play("deep", 25)
        self.assertLess(low, -0.3)
        self.assertGreater(high, 0.3)
        self.assertLess(r.tr.warm, high - 0.5)

    def test_it_takes_seconds_not_frames(self):
        r = Run()
        r.play("deep", 20)
        before = r.tr.warm
        r.play("bright", 0.5)           # medio segundo de agudos no lo mueve
        self.assertLess(abs(r.tr.warm - before), 0.15)

    def test_silence_goes_back_to_neutral(self):
        r = Run()
        r.play("bright", 20)
        r.play("deep", 1.0, amp=0.0)    # nivel 0: pausa
        self.assertGreater(r.tr.warm, 0.3)      # una pausa corta no pinta nada
        r.play("deep", 15.0, amp=0.0)
        self.assertLess(abs(r.tr.warm), 0.1)

    def test_events_are_rate_limited_and_stay_alive(self):
        r = Run()
        r.play("mid", 20)
        gaps = [b["cmd"] for b in r.msgs]
        self.assertTrue(all(g == "tone" for g in gaps))
        self.assertLessEqual(len(r.msgs), 20 / tone.SEND_MIN_GAP_S + 1)
        self.assertGreaterEqual(len(r.msgs), 20 / tone.SEND_BEAT_S - 1)


class TestMood(unittest.TestCase):
    def verse_then(self, kind, amp, seconds):
        r = Run()
        r.play("mid", 25, amp=0.15)             # una estrofa floja
        r.play(kind, seconds, amp=amp)
        return r

    def test_sustained_change_moves_the_hue(self):
        r = self.verse_then("bright", 1.0, 14)  # estribillo: fuerte y brillante
        self.assertGreater(r.tr.shift, 0.4)

    def test_sustained_drop_moves_it_the_other_way(self):
        r = Run()
        r.play("bright", 25, amp=1.0)
        r.play("deep", 14, amp=0.12)
        self.assertLess(r.tr.shift, -0.3)

    def test_a_short_burst_does_not(self):
        r = Run()
        r.play("mid", 25, amp=0.15)
        peak = 0.0
        r.play("bright", 2.5, amp=1.0)          # un golpe de 2,5 s
        peak = max(peak, abs(r.tr.shift))
        r.play("mid", 20, amp=0.15)
        peak = max(peak, abs(r.tr.shift))
        self.assertLess(peak, 0.05)
        self.assertLess(abs(r.tr.shift), 0.05)

    def test_hysteresis_releases_only_when_it_settles(self):
        r = self.verse_then("bright", 1.0, 14)
        self.assertGreater(r.tr.target, 0.0)
        # el mood se mantiene arriba un rato más: el pestillo no se suelta de golpe
        r.play("bright", 5, amp=1.0)
        self.assertGreater(r.tr.target, 0.0)
        # y a la larga, con la base alcanzándolo, vuelve a 0
        r.play("bright", 180, amp=1.0)
        self.assertEqual(r.tr.target, 0.0)
        self.assertLess(abs(r.tr.shift), 0.1)

    def test_new_track_keeps_what_is_on_screen(self):
        r = self.verse_then("bright", 1.0, 14)
        shown = (r.tr.warm, r.tr.shift)
        r.tr.reset()
        self.assertEqual((r.tr.warm, r.tr.shift), shown)


@unittest.skipUnless(NODE, "node no está instalado")
class TestFacesTone(unittest.TestCase):
    def js(self, expr):
        with open(os.path.join(SHELL, "Faces.js"), encoding="utf-8") as f:
            src = f.read().replace(".pragma library", "")
        out = subprocess.run([NODE, "-e", src + "\nconsole.log(JSON.stringify(" + expr + "));"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def test_warm_lands_on_amber_and_never_violet(self):
        v = self.js("(() => { let out = []; for (let h = 0; h < 1; h += 0.05)"
                    " out.push([h, toneHue(h, 1, 0), toneHue(h, 0.5, 0)]); return out; })()")
        for h, full, half in v:
            gap_before = min(abs(h - 0.105), 1 - abs(h - 0.105))
            gap_full = min(abs(full - 0.105), 1 - abs(full - 0.105))
            self.assertLess(gap_full, gap_before * 0.5 + 1e-9, h)       # se acerca al ámbar
            self.assertFalse(0.7 <= full <= 0.88, f"{h} -> {full} es violeta")
            self.assertTrue(full <= 0.2 or full >= 0.9 or h > 0.2, (h, full))
            gap_half = min(abs(half - 0.105), 1 - abs(half - 0.105))
            self.assertLessEqual(gap_full, gap_half + 1e-9)             # más tono, más cerca

    def test_cold_lands_on_deep_blue(self):
        v = self.js("(() => { let out = []; for (let h = 0; h < 1; h += 0.05)"
                    " out.push([h, toneHue(h, -1, 0)]); return out; })()")
        for h, cold in v:
            gap_before = min(abs(h - 0.58), 1 - abs(h - 0.58))
            gap_cold = min(abs(cold - 0.58), 1 - abs(cold - 0.58))
            self.assertLess(gap_cold, gap_before * 0.5 + 1e-9, h)

    def test_neutral_changes_nothing(self):
        v = self.js('(() => { const c = ["#c03020", "#2040d0", "#20a040"];'
                    ' return [JSON.stringify(albumFaces(c, 0.5)) === JSON.stringify(albumFaces(c, 0.5,'
                    ' {warm: 0, shift: 0})), toneHex("#000080", 0, 0), toneHex("#1084d0", 0, 0)]; })()')
        self.assertEqual(v, [True, "#000080", "#1084d0"])

    def test_warm_faces_are_brighter_and_cold_ones_darker(self):
        # MISMO tono en las tres: acá se mide la luz, no el corrimiento de tono
        v = self.js('(() => { let out = []; for (let h = 0; h < 1; h += 0.1) for (const s of [0.5, 0.9]) {'
                    ' const f = (t) => [faceLit(h, s, t), faceDark(h, s, t), faceMid(h, s, t)];'
                    ' out.push([f(1), f(0), f(-1)].map(x => [luminance(x[0].bg), luminance(x[1].ink),'
                    ' luminance(x[2].bg), luminance(x[1].bg)])); } return out; })()')
        for warm, mid, cold in v:
            for i in range(4):
                self.assertGreaterEqual(warm[i], mid[i] - 1e-9, i)
                self.assertGreaterEqual(mid[i], cold[i] - 1e-9, i)
            self.assertGreater(mid[0], cold[0] + 0.04)      # la prendida se nota más oscura
            self.assertGreater(warm[1], cold[1] - 1e-9)

    def test_text_stays_readable_across_the_wheel_and_the_whole_range(self):
        v = self.js("(() => { let w = {inkMin: 99, hotMin: 99, bgMin: 99, at: null};"
                    " for (let h = 0; h < 1; h += 0.025) for (const s of [0.4, 0.7, 1])"
                    " for (const t of [-1, -0.5, 0, 0.5, 1]) for (const sh of [-1, 0, 1]) {"
                    "  const f = albumFaces([hslToHex(h, s, 0.5)], 0.6, {warm: t, shift: sh});"
                    "  const r = checkScheme(f);"
                    "  if (r.inkMin < w.inkMin) { w.inkMin = r.inkMin; w.at = [h, s, t, sh]; }"
                    "  w.hotMin = Math.min(w.hotMin, r.hotMin); w.bgMin = Math.min(w.bgMin, r.bgMin); }"
                    " return w; })()")
        self.assertGreaterEqual(v["inkMin"], 4.5, v["at"])
        self.assertGreaterEqual(v["hotMin"], 3.0)
        self.assertGreaterEqual(v["bgMin"], 1.7)

    def test_dialog_title_bar_keeps_white_text_readable(self):
        v = self.js("(() => { let w = 99; let k = 99;"
                    " for (const t of [-1, -0.5, 0.5, 1]) for (const sh of [-1, 0, 1]) {"
                    "  w = Math.min(w, contrast('#ffffff', toneHex('#000080', t, sh)),"
                    "               contrast('#ffffff', toneHex('#1084d0', t, sh)));"
                    "  k = Math.min(k, contrast('#c0c0c0', toneHex('#000080', t, sh, 3))); }"
                    " return [w, k]; })()")
        self.assertGreaterEqual(v[0], 3.8)      # el celeste de fábrica ya está en 3.9
        self.assertGreaterEqual(v[1], 4.5)      # el karaoke sobre el gris del cartel


class TestWiring(unittest.TestCase):
    def read(self, *p):
        with open(os.path.join(ROOT, *p), encoding="utf-8") as f:
            return f.read()

    def test_the_knob_travels_config_to_overlay_and_settings(self):
        from cartelitos import config, ipc, settings
        self.assertTrue(config.DEFAULTS["display"]["song_color"])
        self.assertIn(("song_color", "display", "song_color"), ipc.CONFIG_EVENT_MAP)
        self.assertIn('song_color: "songColorOn"', self.read("shell", "shell.qml"))
        rows = [r for g in settings.GROUPS for r in g["rows"]]
        self.assertTrue(any(r["id"] == "display.song_color" for r in rows))

    def test_the_overlay_applies_the_tone_to_cover_and_dialogs(self):
        qml = self.read("shell", "shell.qml")
        self.assertIn('ev.cmd === "tone"', qml)
        self.assertIn("Faces.albumFaces(hex, (crtMoodLocked || crtMood).energy,", qml)
        self.assertIn("{ warm: songWarm, shift: songShift }", qml)
        self.assertIn("root.barColorA", qml)
        self.assertIn("root.karaokeColor", qml)

    def test_the_capture_loop_feeds_the_tracker_and_resets_per_track(self):
        src = self.read("cartelitos", "audio.py")
        self.assertIn("tone.feed(ev, now, an.peak)", src)
        self.assertIn("tone.reset()", src)
        self.assertIn('"cmd": "tone", "warm": 0.0, "shift": 0.0', src)


if __name__ == "__main__":
    unittest.main()
