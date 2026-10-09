"""Tanda 8 / slice "colores": paletas de tres caras y reparto que sigue la parte del
tema. Ver docs/tanda8-estado/colores.md.

Se testean las funciones puras de `shell/Faces.js` (con node, si está): contraste de
la letra en las tres caras (fijas y de la tapa), qué parte del tema es, el portero,
el reparto por modo con 1-4 pantallas y el orden del escalonado; y el cableado de la
perilla `crt.face_mode` (config → ipc → Ajustes → shell.qml).
"""
import json
import os
import re
import shutil
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "shell")
NODE = shutil.which("node")
# la letra se lee (WCAG AA texto normal); `hot` es la palabra que suena, grande
INK_MIN = 4.5
HOT_MIN = 3.0
# los tres fondos se distinguen entre sí: bloodline tiene la prendida roja de
# luz media (#ff2f14), y su frambuesa queda en 1.77 — el piso es ése
BG_MIN = 1.7


def read(name):
    with open(os.path.join(SHELL, name), encoding="utf-8") as f:
        return f.read()


def fixed_schemes():
    """Las 6 paletas de `shell.qml` como dicts {key: {a|b|c: {bg, ink, hot, dim}}}."""
    block = re.search(r"readonly property var schemes: \[(.*?)\n    \]", read("shell.qml"),
                      re.S).group(1)
    out = {}
    for key, body in re.findall(r'\{ key: "(\w+)",(.*?)\} \},', block + ",", re.S):
        faces = {}
        for name, face in re.findall(r"\b([abc]): \{([^{}]*)\}", body + "}"):
            faces[name] = dict(re.findall(r'\b(bg|ink|hot|dim): "(#[0-9a-f]{6})"', face))
        out[key] = faces
    return out


@unittest.skipUnless(NODE, "node no está instalado")
class TestFacesJs(unittest.TestCase):
    # `.pragma library` no es JS válido para node: se saca y se evalúa el resto
    def js(self, expr):
        src = read("Faces.js").replace(".pragma library", "")
        out = subprocess.run([NODE, "-e", src + "\nconsole.log(JSON.stringify(" + expr + "));"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    # ---- las caras
    def test_the_six_fixed_palettes_have_three_readable_faces(self):
        schemes = fixed_schemes()
        self.assertEqual(sorted(schemes), sorted(["dragons", "ado", "poison", "bloodline",
                                                  "vapor", "bone"]))
        for key, sc in schemes.items():
            self.assertEqual(sorted(sc), ["a", "b", "c"], key)
            v = self.js("checkScheme(%s)" % json.dumps(sc))
            self.assertGreaterEqual(v["inkMin"], INK_MIN, key)
            self.assertGreaterEqual(v["bgMin"], BG_MIN, key)
            # la `hot` de la prendida de bloodline es de la tanda 2 (3.67): el
            # piso es el de texto grande
            self.assertGreaterEqual(v["hotMin"], HOT_MIN, key)

    def test_the_middle_face_sits_between_lit_and_dark_in_light(self):
        # las tres se separan por LUZ: la media nunca queda más clara que la
        # prendida ni más oscura que el tubo apagado
        for key, sc in fixed_schemes().items():
            y = self.js("[luminance(%r), luminance(%r), luminance(%r)]"
                        % (sc["a"]["bg"], sc["c"]["bg"], sc["b"]["bg"]))
            self.assertGreater(y[0], y[1], key)
            self.assertGreater(y[1], y[2], key)

    def test_the_cover_palette_is_readable_for_every_hue(self):
        # la tapa puede ser de cualquier tono: con L fija, un azul dejaba la letra
        # ilegible. Barrido de tono × saturación, una tapa de un solo color (el
        # caso que más deriva)
        v = self.js("(() => { let w = {inkMin: 99, hotMin: 99, bgMin: 99};"
                    " for (let h = 0; h < 1; h += 0.02) for (const s of [0.25, 0.6, 1]) {"
                    "  const r = checkScheme(albumFaces([hslToHex(h, s, 0.5)]));"
                    "  for (const k in w) w[k] = Math.min(w[k], r[k]); } return w; })()")
        self.assertGreaterEqual(v["inkMin"], INK_MIN)
        self.assertGreaterEqual(v["hotMin"], HOT_MIN)
        self.assertGreaterEqual(v["bgMin"], BG_MIN)

    def test_a_grey_cover_gives_no_palette(self):
        self.assertIsNone(self.js('albumFaces(["#808080", "#1a1a1a", "#f0f0f0"])'))
        self.assertIsNone(self.js("albumFaces([])"))

    def test_the_cover_uses_its_own_third_colour_when_it_has_one(self):
        # rojo, rojo casi igual, azul, verde: el segundo no cuenta como otro color
        v = self.js('(() => { const f = albumFaces(["#d02020", "#d83018", "#2040d0", "#20a040"]);'
                    ' return [f.a.bg, f.b.ink, f.c.bg].map(x => rgbToHsl(hexToRgb(x))[0]); })()')
        self.assertLess(min(v[0], 1 - v[0]), 0.03)          # rojo
        self.assertAlmostEqual(v[1], 0.64, delta=0.03)      # azul
        self.assertAlmostEqual(v[2], 0.40, delta=0.03)      # verde

    def test_a_cover_of_near_identical_hues_is_opened_up(self):
        # tres naranjas: no son tres colores. La oscura va al otro lado de la
        # rueda (lo de siempre) y la media al medio del arco más grande
        v = self.js('(() => { const f = albumFaces(["#e07020", "#e07828", "#d86818"]);'
                    ' return [f.a.bg, f.b.ink, f.c.bg].map(x => rgbToHsl(hexToRgb(x))[0]); })()')
        gaps = self.js("[hueGap(%f, %f), hueGap(%f, %f), hueGap(%f, %f)]"
                       % (v[0], v[1], v[0], v[2], v[1], v[2]))
        for g in gaps:
            self.assertGreater(g, 0.15)

    # ---- qué parte del tema es
    def test_face_mode_follows_the_section(self):
        v = self.js('[faceMode("verse", false, false), faceMode("drop", false, false),'
                    ' faceMode("build", false, false), faceMode("quiet", false, false),'
                    ' faceMode("quiet", false, true), faceMode("verse", true, false),'
                    ' faceMode("drop", true, true)]')
        self.assertEqual(v, ["verse", "chorus", "wild", "verse", "wild", "wild", "wild"])

    def test_a_long_verse_rotates_the_wall_instead_of_staying_two_one(self):
        # Vivaldi / un tema sin build ni drop detectable: la parte es `verse`
        # todo el rato y la pared se quedaba en 2-1 para siempre
        after = self.js("VARIETY_AFTER_MS")
        v = self.js('[varietyMode("verse", %d, 0), varietyMode("verse", %d, 1),'
                    ' varietyMode("verse", %d, 2), varietyMode("verse", 1000, 0),'
                    ' varietyMode("chorus", %d, 0), varietyMode("wild", %d, 0)]'
                    % (after, after, after, after * 3, after * 3))
        self.assertEqual(v, ["wild", "chorus", "wild", "verse", "chorus", "wild"])

    def test_overlay_wires_the_variety_and_logs_section_and_pattern(self):
        qml = read("shell.qml")
        self.assertIn("Faces.varietyMode(", qml)
        self.assertRegex(qml, r'console\.log\("crt: faces [^\n]*audSection')

    def test_the_gate_lets_events_in_and_makes_the_verse_wait(self):
        hold = 10000
        v = self.js('[gateOk(1e6, 1e6 - 3000, %d, "verse", "chorus"),'
                    ' gateOk(1e6, 1e6 - 3000, %d, "verse", "wild"),'
                    ' gateOk(1e6, 1e6 - 3000, %d, "chorus", "verse"),'
                    ' gateOk(1e6, 1e6 - 10000, %d, "chorus", "verse"),'
                    ' gateOk(1e6, 1e6 - 1000, %d, "verse", "chorus"),'
                    ' gateOk(1e6, 0, %d, "verse", "verse")]' % ((hold,) * 6))
        self.assertEqual(v, [True, True, False, True, False, False])

    # ---- el reparto
    def pattern(self, mode, n, prev, focus, r=0.3):
        return self.js("facePattern(%s, %d, %s, %d, %f)" % (json.dumps(mode), n,
                                                           json.dumps(prev), focus, r))

    def test_three_screens_verse_is_two_one_chorus_one_wild_three(self):
        for r in (0.0, 0.2, 0.5, 0.8, 0.99):
            for prev in ([0, 1, 0], [1, 1, 0], [2, 0, 1], []):
                for focus in (0, 1, 2):
                    verse = self.pattern("verse", 3, prev, focus, r)
                    self.assertEqual(sorted(set(verse)), [0, 1], (prev, focus, r))
                    chorus = self.pattern("chorus", 3, prev, focus, r)
                    self.assertEqual(len(set(chorus)), 1, (prev, focus, r))
                    wild = self.pattern("wild", 3, prev, focus, r)
                    self.assertEqual(sorted(wild), [0, 1, 2], (prev, focus, r))

    def test_the_screen_with_the_line_keeps_its_face(self):
        for r in (0.1, 0.6, 0.9):
            for prev in ([0, 1, 1], [1, 0, 0], [2, 1, 0], [0, 0, 0]):
                for focus in (0, 1, 2):
                    for mode in ("chorus", "wild"):
                        out = self.pattern(mode, 3, prev, focus, r)
                        self.assertEqual(out[focus], prev[focus], (mode, prev, focus, r))
                    if prev[focus] < 2:
                        out = self.pattern("verse", 3, prev, focus, r)
                        self.assertEqual(out[focus], prev[focus], ("verse", prev, focus, r))

    def test_one_screen_degrades_to_the_face_itself(self):
        self.assertEqual(self.pattern("verse", 1, [2], 0), [0])
        self.assertEqual(self.pattern("chorus", 1, [0], 0), [0])
        self.assertEqual(self.pattern("wild", 1, [0], 0), [2])

    def test_two_screens_degrade_with_criterion(self):
        for r in (0.1, 0.7):
            for focus in (0, 1):
                self.assertEqual(sorted(self.pattern("verse", 2, [0, 0], focus, r)), [0, 1])
                ch = self.pattern("chorus", 2, [1, 0], focus, r)
                self.assertEqual(ch[0], ch[1])
                # el foco conserva la suya y entra la media
                wild = self.pattern("wild", 2, [0, 1], focus, r)
                self.assertEqual(wild[focus], [0, 1][focus])
                self.assertEqual(wild[1 - focus], 2)
                # si el foco ya tenía la media, la otra es una de a/b
                wild = self.pattern("wild", 2, [2, 2], focus, r)
                self.assertEqual(wild[focus], 2)
                self.assertIn(wild[1 - focus], (0, 1))

    def test_four_screens_wild_shows_all_three_and_no_equal_neighbours(self):
        for focus in range(4):
            for r in (0.2, 0.8):
                out = self.pattern("wild", 4, [0, 1, 0, 1], focus, r)
                self.assertEqual(sorted(set(out)), [0, 1, 2])
                for i in range(3):
                    self.assertNotEqual(out[i], out[i + 1], out)
                verse = self.pattern("verse", 4, [0, 1, 0, 1], focus, r)
                self.assertEqual(sorted(set(verse)), [0, 1])

    def test_classic_two_tone_never_paints_all_screens_the_same(self):
        for n in (2, 3, 4):
            for i in range(40):
                out = self.js("twoTone(%d, %f)" % (n, i / 40))
                self.assertEqual(sorted(set(out)), [0, 1], (n, i))

    def test_infection_swaps_keep_the_mode(self):
        # la infección MUDA la cara (swap donante↔receptora): el multiconjunto
        # no cambia, así que el drop sigue todo igual y el puente sigue con las
        # tres distintas. Se simula el swap sobre cada reparto.
        for mode in ("verse", "chorus", "wild"):
            out = self.pattern(mode, 3, [0, 1, 0], 1, 0.4)
            for d, rcv in ((0, 1), (1, 2), (2, 0)):
                sw = list(out)
                sw[d], sw[rcv] = sw[rcv], sw[d]
                self.assertEqual(sorted(sw), sorted(out), mode)

    def test_steps_go_from_the_line_outwards_and_only_the_ones_that_change(self):
        self.assertEqual(self.js("stepOrder([0,1,0], [1,1,1], 1)"), [0, 2])
        self.assertEqual(self.js("stepOrder([0,1,0,1], [2,2,2,2], 0)"), [0, 1, 2, 3])
        self.assertEqual(self.js("stepOrder([0,1,0,1], [0,2,2,2], 3)"), [3, 2, 1])
        self.assertEqual(self.js("stepOrder([1,1,1], [1,1,1], 1)"), [])


class TestFaceModeKnob(unittest.TestCase):
    # por fuente y no importando `cartelitos.config`: importarlo lee (y crea)
    # la config de verdad de ~/.config
    def src(self, name):
        with open(os.path.join(ROOT, "cartelitos", name), encoding="utf-8") as f:
            return f.read()

    def test_default_is_song_and_documented(self):
        conf = self.src("config.py")
        self.assertIn('"face_mode": "song",', conf)
        self.assertIn('"face_mode": "how the faces are spread', conf)

    def test_it_travels_to_the_overlay(self):
        self.assertIn('("crt_face_mode", "crt", "face_mode")', self.src("ipc.py"))
        qml = read("shell.qml")
        self.assertIn('crt_face_mode: "crtFaceMode"', qml)
        self.assertIn('property string crtFaceMode: "song"', qml)

    def test_the_settings_window_offers_both(self):
        from cartelitos import settings
        self.assertEqual(sorted(o["value"] for o in settings.ROWS["crt.face_mode"]["options"]),
                         ["classic", "song"])

    def test_shell_imports_faces_and_steps_the_change(self):
        qml = read("shell.qml")
        self.assertIn('import "Faces.js" as Faces', qml)
        # la infección espera al escalonado, y el Timer corre los dos en orden
        infect = re.search(r"function updateInfection\(\) \{.*?\n    \}\n", qml, re.S).group(0)
        self.assertIn("faceSteps.length > 0", infect)
        self.assertRegex(qml, r"root\.crtFaceTick\(\);\s*root\.updateInfection\(\);")
        # el pico en `song` re-reparte dentro de la parte, nunca en el drop
        peak = re.search(r"function resetFacesOnPeak\(\) \{.*?\n    \}\n", qml, re.S).group(0)
        self.assertIn('crtFaceModeNow === "chorus"', peak)
        # crtFace indexa las tres caras
        self.assertIn("[sc.a, sc.b, sc.c || sc.b][idx]", qml)


if __name__ == "__main__":
    unittest.main()
