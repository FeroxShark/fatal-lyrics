#!/usr/bin/env python3
"""fatal-lyrics motivos CRT — render offscreen de loops de 15 s.

Cada motivo es un loop exacto: 8 compases a 128 BPM = 15 s = 900 cuadros, y el
cuadro 900 es el cuadro 0. Pasa por el vidrio REAL (signal.frag + crt.frag de
shell/). Nunca abre nada en pantalla.

    ./render.py mystify                     # out/mystify.mp4 (loop, 1080p60, con audio)
    ./render.py mystify --stills 1,6,12.5   # cuadros sueltos a out/stills/
    ./render.py mystify --portrait          # la pantalla vertical (1080x1920)
    ./render.py --all                       # todos + costura + contact sheet + mosaico
    ./render.py mystify --tube arcade --scheme vapor

Chequeo de costura: se renderiza el cuadro de t=15 después del loop y se
compara con el de t=0 (tienen que ser el mismo cuadro).
"""
import argparse
import os
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
# ASIGNADO, no setdefault: la sesión de Ferox exporta QT_QPA_PLATFORM=wayland y
# con setdefault la ventana se abre en su pantalla (docs/TRAMPAS.md).
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

import numpy as np  # noqa: E402
from PyQt6.QtCore import QUrl, qInstallMessageHandler  # noqa: E402
from PyQt6.QtGui import QGuiApplication, QImage  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

FPS = 60
BPM = 128
BEAT = 60 / BPM
LOOP = 32 * BEAT
FRAMES = int(round(LOOP * FPS))
OUT = os.path.join(HERE, "out")

# kind → (tubo, paleta) con que se ve mejor; el orden es el del contact sheet
MOTIFS = {
    "swarm": ("trinitron", "bone"),
    "splitflap": ("trinitron", "dragons"),
    "maze": ("trinitron", "ado"),
    "pipes": ("arcade", "poison"),
    "defrag": ("trinitron", "vapor"),
    "mystify": ("arcade", "bloodline"),
    "vector": ("green", "poison"),
    "harmonograph": ("amber", "bone"),
}


def _qt_log(mode, ctx, msg):
    print(f"qml: {msg}", file=sys.stderr)


qInstallMessageHandler(_qt_log)


class Stage:
    def __init__(self, kind, tube, scheme, portrait=False, glass=True):
        self.w, self.h = (1080, 1920) if portrait else (1920, 1080)
        self.app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
        self.view = QQuickView()
        self.view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
        self.view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Stage.qml")))
        if self.view.status() != QQuickView.Status.Ready:
            for e in self.view.errors():
                print(e.toString(), file=sys.stderr)
            sys.exit(1)
        self.view.resize(self.w, self.h)
        self.view.show()
        self.root = self.view.rootObject()
        self.root.setProperty("tube", tube)
        self.root.setProperty("scheme", scheme)
        self.root.setProperty("glassOn", glass)
        self.root.setProperty("kind", kind)
        # precalentamiento: los relojes capturados (último tiempo, drop) se
        # arman con el loop anterior, como si el tema viniera sonando
        for f in range(-FPS * 2, 0):
            self.frame(f / FPS)

    def frame(self, t):
        self.root.setProperty("t", float(t))
        # dos vueltas: la primera pide el paint() del Canvas, la segunda lo dibuja
        for _ in range(2):
            self.app.processEvents()
            img = self.view.grabWindow()
        return img.convertToFormat(QImage.Format.Format_RGBA8888)


# ---- audio: la partitura de Loop.js, sintetizada con la cola que da la vuelta

SR = 48000


def score():
    b = lambda n: n * BEAT  # noqa: E731
    snares = [b(i) for i in range(4, 16) if i % 2 == 1]
    snares += [b(16 + i * 0.5) for i in range(8)]
    snares += [b(20 + i * 0.25) for i in range(12)]
    snares += [b(23 + i * 0.125) for i in range(8)]
    snares += [b(i) for i in range(24, 32) if i % 2 == 1]
    hats = [b(i + 0.5) for i in range(24)] + [b(24 + i * 0.25) for i in range(32) if i % 4]
    return {"kicks": [b(i) for i in range(32)], "snares": snares, "hats": hats,
            "crashes": [b(0), b(24)], "riser": (b(16), b(24)), "drop": (b(24), LOOP)}


def synth():
    """Dos vueltas del loop; se queda con la segunda, así las colas del final
    suenan encima del principio y el loop de audio también cierra."""
    ev = score()
    n1 = int(LOOP * SR)
    out = np.zeros(2 * n1 + SR)
    rng = np.random.default_rng(7)

    def place(t0, sig, gain=1.0):
        i = int(round(t0 * SR))
        m = min(len(sig), len(out) - i)
        out[i:i + m] += sig[:m] * gain

    def env(dur, tau):
        tt = np.arange(int(dur * SR)) / SR
        return tt, np.exp(-tt / tau)

    tt, e = env(0.5, 0.16)
    kick = np.sin(2 * np.pi * np.cumsum(45 + 110 * np.exp(-tt / 0.03)) / SR) * e
    kick[:96] += rng.uniform(-1, 1, 96) * 0.4
    tt, e = env(0.25, 0.07)
    sn = rng.uniform(-1, 1, len(tt)) * e * 0.7 + np.sin(2 * np.pi * 190 * tt) * np.exp(-tt / 0.05) * 0.5
    sn = np.diff(sn, prepend=0) * 0.8 + sn * 0.4
    tt, e = env(0.06, 0.012)
    hat = np.diff(rng.uniform(-1, 1, len(tt)), prepend=0) * e
    tt, e = env(2.0, 0.6)
    crash = np.diff(rng.uniform(-1, 1, len(tt)), prepend=0) * e * 0.3
    for lap in range(2):
        o = lap * LOOP
        for t0 in ev["kicks"]:
            place(o + t0, kick, 0.9)
        for t0 in ev["snares"]:
            g = 0.7
            if ev["riser"][0] <= t0 < ev["riser"][1]:
                g = 0.3 + 0.4 * (t0 - ev["riser"][0]) / (ev["riser"][1] - ev["riser"][0])
            place(o + t0, sn, g)
        for t0 in ev["hats"]:
            place(o + t0, hat, 0.22)
        for t0 in ev["crashes"]:
            place(o + t0, crash, 0.6)
        r0, r1 = ev["riser"]
        tt = np.arange(int((r1 - r0) * SR)) / SR
        k = tt / (r1 - r0)
        sweep = np.sin(2 * np.pi * np.cumsum(200 + 1800 * k ** 2) / SR) * 0.14 + rng.uniform(-1, 1, len(tt)) * 0.1
        place(o + r0, sweep * k ** 2)
        # bajo: una nota por compás en la estrofa, sierra con sidechain en el drop
        for bar in range(8):
            t0 = bar * 4 * BEAT
            tt = np.arange(int(4 * BEAT * SR)) / SR
            root = [55, 55, 65.4, 49, 55, 55, 65.4, 49][bar]
            if bar < 6:
                sig = np.sin(2 * np.pi * root * tt) * 0.16 * np.minimum(1, tt / 0.02) * np.exp(-tt / 1.2)
            else:
                saw = ((tt * root) % 1.0) * 2 - 1
                duck = 1 - np.exp(-((tt % BEAT) / 0.09))
                sig = saw * duck * 0.2
            place(o + t0, sig)
        # colchón
        tt = np.arange(n1) / SR
        pad = sum(np.sin(2 * np.pi * fq * tt) for fq in (220, 261.6, 329.6)) / 3
        place(o, pad * 0.05)
    x = out[n1:2 * n1]
    x = np.tanh(x * 1.2)
    return x / (np.abs(x).max() / 0.9)


def write_wav(path, mono):
    pcm = (np.stack([mono, mono], axis=1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ---- salidas -----------------------------------------------------------------

def render_loop(stage, out, wav, crf=20):
    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{stage.w}x{stage.h}", "-r", str(FPS), "-i", "-",
           "-i", wav, "-c:a", "aac", "-b:a", "192k",
           "-c:v", "libx264", "-preset", "slow", "-crf", str(crf), "-pix_fmt", "yuv420p",
           "-movflags", "+faststart", "-shortest", out]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    first = None
    for f in range(FRAMES):
        img = stage.frame(f / FPS)
        if f == 0:
            first = img.copy()
        p.stdin.write(img.constBits().asstring(img.sizeInBytes()))
        if f % 150 == 0:
            print(f"  {os.path.basename(out)}: {f / FPS:5.2f}s", file=sys.stderr, flush=True)
    p.stdin.close()
    if p.wait() != 0:
        sys.exit("ffmpeg falló")
    # la costura: el cuadro de t=15 tiene que ser el de t=0
    last = stage.frame(LOOP)
    return seam_diff(first, last)


def seam_diff(a, b):
    def arr(img):
        return np.frombuffer(img.constBits().asstring(img.sizeInBytes()), np.uint8).astype(np.int16)
    d = np.abs(arr(a) - arr(b))
    return float(d.mean()), int(d.max())


def render_stills(stage, times, outdir, tag):
    os.makedirs(outdir, exist_ok=True)
    paths = []
    for t in times:
        p = os.path.join(outdir, f"{tag}-t{t:06.3f}.png")
        # medio segundo de cuadros seguidos antes: los relojes capturados
        # (último tiempo, drop) necesitan ver pasar el golpe, no saltar a él
        for f in range(-30, 0):
            stage.frame(t + f / FPS)
        stage.frame(t).save(p)
        paths.append(p)
    return paths


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", nargs="?")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--tube")
    ap.add_argument("--scheme")
    ap.add_argument("--portrait", action="store_true")
    ap.add_argument("--flat", action="store_true", help="sin vidrio (el motivo pelado)")
    ap.add_argument("--stills", help="tiempos separados por coma")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, "loop.wav")
    if not os.path.exists(wav):
        write_wav(wav, synth())

    if a.all:
        # Un proceso por motivo: dos QQuickView en el mismo proceso rompen las
        # pasadas del vidrio de la segunda (sale la cara pelada sobre blanco).
        report = []
        for kind in MOTIFS:
            r = subprocess.run([sys.executable, __file__, kind], capture_output=True, text=True)
            sys.stderr.write(r.stderr[-2000:] if r.returncode else "")
            line = next((ln for ln in r.stdout.splitlines() if "costura" in ln), f"{kind}: FALLÓ")
            print(line, flush=True)
            report.append(line)
            subprocess.run([sys.executable, __file__, kind, "--portrait", "--stills", "4.2,13.1"],
                           capture_output=True, text=True)
        gallery(list(MOTIFS))
        print("\n".join(report))
        return
    if not a.kind:
        ap.error("falta el kind (o --all)")
    kind = a.kind
    tube, scheme = MOTIFS.get(kind, ("trinitron", "ado"))
    tube, scheme = a.tube or tube, a.scheme or scheme
    st = Stage(kind, tube, scheme, a.portrait, not a.flat)
    if a.stills:
        tag = kind + ("-portrait" if a.portrait else "") + ("-flat" if a.flat else "")
        for p in render_stills(st, [float(x) for x in a.stills.split(",")], os.path.join(OUT, "stills"), tag):
            print(p)
        return
    out = os.path.join(OUT, f"{kind}{'-portrait' if a.portrait else ''}.mp4")
    mean, mx = render_loop(st, out, wav)
    print(f"{out}  costura: media {mean:.3f} máx {mx}")


def gallery(kinds):
    """contact sheet (4 momentos por motivo: estrofa, subida, drop, drop) y un
    mosaico con todos los loops a la vez."""
    times = [3.3, 9.6, 11.9, 13.4]
    rows = []
    for k in kinds:
        src = os.path.join(OUT, f"{k}.mp4")
        sel = "+".join(f"eq(n\\,{int(round(t * FPS))})" for t in times)
        row = os.path.join(OUT, f".row-{k}.png")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-vf",
                        f"select='{sel}',scale=480:-1,tile=4x1:padding=6:color=black",
                        "-frames:v", "1", "-fps_mode", "passthrough", row], check=True)
        rows.append(row)
    sheet = os.path.join(OUT, "contact.png")
    inputs = sum((["-i", r] for r in rows), [])
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex",
                    f"vstack=inputs={len(rows)}" if len(rows) > 1 else "null", sheet], check=True)
    for r in rows:
        os.remove(r)
    print(sheet)
    if len(kinds) < 2:
        return
    # mosaico: grilla de 4 columnas, cada loop a 480x270
    cols = 4
    n = len(kinds)
    inputs = sum((["-i", os.path.join(OUT, f"{k}.mp4")] for k in kinds), [])
    scaled = "".join(f"[{i}:v]scale=480:270[v{i}];" for i in range(n))
    layout = "|".join(f"{(i % cols) * 480}_{(i // cols) * 270}" for i in range(n))
    mosaic = os.path.join(OUT, "all-loops.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex",
                    scaled + "".join(f"[v{i}]" for i in range(n)) + f"xstack=inputs={n}:layout={layout}:fill=black[v]",
                    "-map", "[v]", "-map", "0:a", "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", mosaic], check=True)
    print(mosaic)


if __name__ == "__main__":
    main()
