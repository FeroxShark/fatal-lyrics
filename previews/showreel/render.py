#!/usr/bin/env python3
"""fatal-lyrics showreel — render offscreen, determinista, cuadro a cuadro.

Nunca abre nada en pantalla: Qt corre con la plataforma `offscreen` y RHI
OpenGL. Avanza `t` de Reel.qml, agarra el cuadro y lo manda crudo a ffmpeg.

    ./render.py                              # out/showreel.mp4 (15 s, 1080p60, con audio)
    ./render.py --from 11 --to 13.6 -o out/drop.mp4
    ./render.py --stills 0.3,2.1,5.5 --dir out/stills
    ./render.py --segments                   # un mp4 por módulo + gif + contact sheet

La pista de audio es la MISMA partitura que SyntheticAudio (Timeline.js,
leída del QML): sirve para ver que la reactividad cae en el golpe.
"""
import argparse
import json
import os
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
# ASIGNADO, no setdefault: la sesión de Ferox exporta QT_QPA_PLATFORM=wayland y
# con setdefault la ventana se abría en su pantalla. La pantalla virtual es de
# 4K porque la default del offscreen es chica y recorta la ventana.
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

import numpy as np  # noqa: E402
from PyQt6.QtCore import QUrl, qInstallMessageHandler  # noqa: E402
from PyQt6.QtGui import QGuiApplication, QImage  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

W, H, FPS = 1920, 1080, 60


# los errores de QML (un Loader que no carga) no salían por ningún lado
def _qt_log(mode, ctx, msg):
    print(f"qml: {msg}", file=sys.stderr)


qInstallMessageHandler(_qt_log)


class Stage:
    def __init__(self, solo="", hud=True):
        self.app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
        self.view = QQuickView()
        self.view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
        self.view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Reel.qml")))
        if self.view.status() != QQuickView.Status.Ready:
            for e in self.view.errors():
                print(e.toString(), file=sys.stderr)
            sys.exit(1)
        self.view.resize(W, H)
        self.view.show()
        self.root = self.view.rootObject()
        self.root.setProperty("solo", solo)
        self.root.setProperty("hud", hud)

    def events(self):
        return json.loads(self.root.property("eventsJson"))

    def segments(self):
        return json.loads(self.root.property("segmentsJson"))

    def frame(self, t):
        self.root.setProperty("t", float(t))
        # dos vueltas: la primera carga Loaders / pide los paint() de los Canvas,
        # la segunda los dibuja. Sin eso, un Canvas nuevo sale vacío un cuadro.
        for _ in range(2):
            self.app.processEvents()
            img = self.view.grabWindow()
        return img.convertToFormat(QImage.Format.Format_RGBA8888)


# ---- audio: la partitura de Timeline.js, sintetizada ----------------------

SR = 48000


def synth(ev, length):
    n = int(length * SR)
    out = np.zeros(n)
    rng = np.random.default_rng(7)

    def place(t0, sig, gain=1.0):
        i = int(t0 * SR)
        if i >= n:
            return
        m = min(len(sig), n - i)
        out[i:i + m] += sig[:m] * gain

    def env(dur, tau):
        tt = np.arange(int(dur * SR)) / SR
        return tt, np.exp(-tt / tau)

    # bombo: seno con caída de tono (808 corto) + click
    tt, e = env(0.5, 0.16)
    f = 45 + 110 * np.exp(-tt / 0.03)
    kick = np.sin(2 * np.pi * np.cumsum(f) / SR) * e
    kick[:96] += rng.uniform(-1, 1, 96) * 0.5
    for t0 in ev["kicks"]:
        place(t0, kick, 0.9)
    # tambor: ruido + tono
    tt, e = env(0.25, 0.07)
    sn = rng.uniform(-1, 1, len(tt)) * e * 0.7 + np.sin(2 * np.pi * 190 * tt) * np.exp(-tt / 0.05) * 0.5
    sn = np.diff(sn, prepend=0) * 0.8 + sn * 0.4
    for t0 in ev["snares"]:
        g = 0.55 if ev["rollAt"] <= t0 < ev["gapAt"] else 0.7
        if ev["rollAt"] <= t0 < ev["gapAt"]:
            g *= 0.5 + 0.5 * (t0 - ev["rollAt"]) / (ev["gapAt"] - ev["rollAt"])
        place(t0, sn, g)
    # hats
    tt, e = env(0.06, 0.012)
    hat = np.diff(rng.uniform(-1, 1, len(tt)), prepend=0) * e
    for t0 in ev["hats"]:
        place(t0, hat, 0.25)
    # teclas del prompt
    tt, e = env(0.02, 0.003)
    key = rng.uniform(-1, 1, len(tt)) * e
    for t0 in ev["keys"]:
        place(t0, key, 0.35)
    place(ev["enter"], key, 0.6)
    # impactos: crash + sub
    tt, e = env(2.0, 0.55)
    crash = np.diff(rng.uniform(-1, 1, len(tt)), prepend=0) * e * 0.35 + np.sin(2 * np.pi * 42 * tt) * np.exp(-tt / 0.6) * 0.8
    for t0 in ev["impacts"]:
        place(t0, crash, 0.7)
    # riser del redoble: ruido que sube + barrido
    r0, r1 = ev["rollAt"], ev["gapAt"]
    tt = np.arange(int((r1 - r0) * SR)) / SR
    k = tt / (r1 - r0)
    sweep = np.sin(2 * np.pi * np.cumsum(200 + 1800 * k ** 2) / SR) * 0.15 + rng.uniform(-1, 1, len(tt)) * 0.12
    place(r0, sweep * k ** 2)
    # bajo del drop, con sidechain del bombo
    d0, d1 = ev["dropAt"], ev["impacts"][-1]
    tt = np.arange(int((d1 - d0) * SR)) / SR
    saw = ((tt * 55) % 1.0) * 2 - 1
    duck = np.ones_like(tt)
    for kt in ev["kicks"]:
        if d0 <= kt < d1:
            i = int((kt - d0) * SR)
            m = min(len(tt) - i, int(0.3 * SR))
            duck[i:i + m] = np.minimum(duck[i:i + m], 1 - np.exp(-np.arange(m) / SR / 0.09))
    place(d0, saw * duck * 0.22)
    # cama: acorde suave del stack al build
    c0, c1 = ev["kicks"][0], ev["gapAt"]
    tt = np.arange(int((c1 - c0) * SR)) / SR
    pad = sum(np.sin(2 * np.pi * fq * tt) for fq in (220, 261.6, 329.6)) / 3
    place(c0, pad * 0.08 * np.minimum(1, tt / 0.3))
    # prendido del tubo: golpe seco + zumbido que baja
    tt, e = env(0.6, 0.15)
    place(0.0, np.sin(2 * np.pi * (60 + 40 * np.exp(-tt / 0.05)) * tt) * e * 0.5)

    out = np.tanh(out * 1.2)
    out /= max(1e-9, np.abs(out).max()) / 0.9
    return out


def write_wav(path, mono):
    st = np.stack([mono, mono], axis=1)
    pcm = (st * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ---- salidas ---------------------------------------------------------------

def render_video(stage, t0, t1, out, audio=True, crf=16):
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    f0 = int(round(t0 * FPS))
    f1 = int(round(t1 * FPS))
    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-"]
    if audio:
        wav = os.path.join(HERE, "out", "track.wav")
        if not os.path.exists(wav):
            write_wav(wav, synth(stage.events(), 15.0))
        cmd += ["-ss", f"{f0 / FPS:.6f}", "-t", f"{(f1 - f0) / FPS:.6f}", "-i", wav,
                "-c:a", "aac", "-b:a", "192k"]
    cmd += ["-c:v", "libx264", "-preset", "slow", "-crf", str(crf), "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", "-shortest", out]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for f in range(f0, f1):
        img = stage.frame(f / FPS)
        p.stdin.write(img.constBits().asstring(img.sizeInBytes()))
        if f % 60 == 0:
            print(f"  {out}: {f / FPS:5.2f}s", file=sys.stderr, flush=True)
    p.stdin.close()
    if p.wait() != 0:
        sys.exit("ffmpeg falló")


def render_stills(stage, times, outdir):
    os.makedirs(outdir, exist_ok=True)
    paths = []
    for t in times:
        img = stage.frame(t)
        p = os.path.join(outdir, f"t{t:06.3f}.png")
        img.save(p)
        paths.append(p)
    return paths


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="t0", type=float, default=0.0)
    ap.add_argument("--to", dest="t1", type=float, default=15.0)
    ap.add_argument("-o", "--out", default=os.path.join(HERE, "out", "showreel.mp4"))
    ap.add_argument("--stills", help="lista de tiempos separados por coma")
    ap.add_argument("--dir", default=os.path.join(HERE, "out", "stills"))
    ap.add_argument("--solo", default="")
    ap.add_argument("--no-hud", action="store_true")
    ap.add_argument("--no-audio", action="store_true")
    ap.add_argument("--segments", action="store_true", help="reel + un mp4 por módulo + gif + contact sheet")
    a = ap.parse_args()

    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    stage = Stage(solo=a.solo, hud=not a.no_hud)
    wav = os.path.join(HERE, "out", "track.wav")
    write_wav(wav, synth(stage.events(), 15.0))

    if a.stills:
        for p in render_stills(stage, [float(x) for x in a.stills.split(",")], a.dir):
            print(p)
        return

    render_video(stage, a.t0, a.t1, a.out, audio=not a.no_audio)
    print(a.out)
    if not a.segments:
        return

    out = os.path.join(HERE, "out")
    for i, s in enumerate(stage.segments()):
        clip = os.path.join(out, f"{i + 1:02d}-{s['key']}.mp4")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{s['t0']:.6f}", "-i", a.out,
                        "-t", f"{s['t1'] - s['t0']:.6f}", "-c:v", "libx264", "-crf", "16",
                        "-pix_fmt", "yuv420p", "-c:a", "aac", clip], check=True)
        print(clip)
    gif = os.path.join(out, "showreel-preview.gif")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", a.out, "-vf",
                    "fps=15,scale=560:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
                    gif], check=True)
    print(gif)
    keys = [0.3, 1.2, 1.7, 2.6, 3.4, 4.2, 5.0, 5.8, 6.7, 7.9, 9.6, 10.9,
            11.3, 11.8, 12.7, 13.7, 14.2, 14.7]
    sheet = os.path.join(out, "contact.png")
    sel = "+".join(f"eq(n\\,{int(round(k * FPS))})" for k in keys)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", a.out, "-vf",
                    f"select='{sel}',scale=480:-1,tile=6x3:padding=6:color=black", "-frames:v", "1",
                    "-fps_mode", "passthrough", sheet], check=True)
    print(sheet)


if __name__ == "__main__":
    main()
