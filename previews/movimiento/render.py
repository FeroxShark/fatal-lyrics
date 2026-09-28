#!/usr/bin/env python3
"""fatal-lyrics — banco del ritmo de los dibujos (tanda 8, slice movimiento-visual).

    ./render.py sheet            # docs/tanda8-estado/movimiento-ritmo.png + out/metrics.json
    ./render.py cpu [--frames N] # CPU y pared por cuadro: perilla en 0 vs ritmo andando
    ./render.py sheet --pace wild
    ./render.py sheet --score fast   # ronda 3: pasaje nervioso con golpes → movimiento-ritmo-golpes.png

Nunca abre nada en pantalla (plataforma `offscreen` ASIGNADA). El dibujo es el
`Mystify` de `shell/`; el ritmo, `shell/Speed.js`; la fila de `crtPaceTable`, la de
`shell/shell.qml`. La partitura es `mov` subiendo y bajando a los 240 s de tema (con
`t` grande, el producto `t · rate` salta; el integrado no). Hay dos: `slow` (rampas de 4 s,
sin golpes: la de la ronda 1) y `fast` (ronda 3: sube en 0.4 s, golpes cada 0.5 s y una
caída de 1 s — lo que hace `mov` con el suavizado nuevo del daemon).
"""
import argparse
import json
import os
import re
import resource
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402
from PyQt6.QtCore import QMetaObject, QUrl, qInstallMessageHandler  # noqa: E402
from PyQt6.QtGui import QGuiApplication, QImage  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

OUT = os.path.join(HERE, "out")
DOCS = os.path.join(ROOT, "docs", "tanda8-estado")
FPS = 60
T0 = 240.0          # a qué altura del tema arranca la partitura
DUR = 12.0


def _qt_log(mode, ctx, msg):
    print(f"qml: {msg}", file=sys.stderr)


qInstallMessageHandler(_qt_log)


def pace_row(name):
    with open(os.path.join(ROOT, "shell", "shell.qml"), encoding="utf-8") as f:
        qml = f.read()
    table = re.search(r"crtPaceTable:\s*\(\{(.*?)\n    \}\)", qml, re.S).group(1)
    table = re.sub(r"//[^\n]*", "", table)
    for row, body in re.findall(r"^\s{8}(\w+):\s*\{(.*?)\n\s{8}\},", table, re.S | re.M):
        if row == name:
            return {k: float(v) for k, v in re.findall(r"(\w+):\s*([\d.]+)\b", body)}
    raise SystemExit(f"no hay fila {name} en crtPaceTable")


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def mov_at(tau):
    """La partitura: quieto 1 s, sube en 4 s, arriba 2 s, baja en 4 s, quieto 1 s."""
    if tau < 1:
        return 0.0
    if tau < 5:
        return smooth((tau - 1) / 4)
    if tau < 7:
        return 1.0
    return 1.0 - smooth((tau - 7) / 4)


def mov_fast(tau):
    """Ronda 3: quieto (0.15) 1 s, sube en 0.4 s a 0.72, nervioso 4.6 s, cae en 1 s a 0.2."""
    if tau < 1:
        return 0.15
    if tau < 1.4:
        return 0.15 + 0.57 * smooth((tau - 1) / 0.4)
    if tau < 6:
        return 0.72
    if tau < 7:
        return 0.72 - 0.52 * smooth((tau - 6) / 1.0)
    return 0.2


# golpes de la partitura `fast`: (tau, fuerte?). Uno cada 0.5 s en el pasaje nervioso, el
# cuarto fuerte; y uno suelto en el calmo.
HITS_FAST = [(1.4 + 0.5 * i, i % 4 == 0) for i in range(10)] + [(9.0, False)]
SCORES = {"slow": (mov_at, []), "fast": (mov_fast, HITS_FAST)}


class Bench:
    def __init__(self):
        self.app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
        self.view = QQuickView()
        self.view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
        self.view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Bench.qml")))
        if self.view.status() != QQuickView.Status.Ready:
            for e in self.view.errors():
                print(e.toString(), file=sys.stderr)
            sys.exit(1)
        self.view.resize(1280, 720)
        self.view.show()
        self.root = self.view.rootObject()
        self.score = "slow"
        self.fired = 0

    def set(self, **kw):
        for k, v in kw.items():
            self.root.setProperty(k, v)

    def start(self, mode):
        self.set(mode=mode)
        QMetaObject.invokeMethod(self.root, "reset")
        self.fired = 0

    def step(self, t, grab=True):
        mov_fn, hits = SCORES[self.score]
        # los golpes van ANTES de `t`: el `rate` de este cuadro ya lo lleva
        while self.fired < len(hits) and hits[self.fired][0] <= t - T0 + 1e-9:
            tau, hard = hits[self.fired]
            self.root.setProperty("hitT", float(T0 + tau))
            self.root.setProperty("hitStrength", 1.0 if hard else 0.4)
            self.root.setProperty("hitN", self.root.property("hitN") + 1)
            self.fired += 1
        self.root.setProperty("mov", float(mov_fn(t - T0)))
        self.root.setProperty("t", float(t))
        self.app.processEvents()
        if not grab:
            return None
        img = self.view.grabWindow().convertToFormat(QImage.Format.Format_RGBA8888)
        a = np.frombuffer(img.constBits().asstring(img.sizeInBytes()), np.uint8)
        return a.reshape(img.height(), img.width(), 4)[:, :, :3].copy()


def lum(rgb):
    return rgb.astype(np.float64) @ np.array([0.299, 0.587, 0.114])


# ---- dibujo de la hoja (mismo estilo que previews/reaccion) ---------------------

def font(size):
    for p in ("/usr/share/fonts/TTF/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans.ttf",
              "/usr/share/fonts/noto/NotoSans-Regular.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def thumb(rgb, w):
    im = Image.fromarray(rgb)
    return im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)


def plot(series, t0, t1, w, h, title, lo=None, hi=None, marks=()):
    """series: [(nombre, color, [(t, v)])]. Lo que pasa de [lo, hi] se recorta."""
    im = Image.new("RGB", (w, h), (24, 24, 28))
    d = ImageDraw.Draw(im)
    fs = font(16)
    vals = [v for _, _, pts in series for _, v in pts]
    lo = min(vals) if lo is None else lo
    hi = max(vals) if hi is None else hi
    pad = 44

    def xy(t, v):
        v = min(max(v, lo), hi)
        return (pad + (t - t0) / (t1 - t0) * (w - 2 * pad),
                h - pad - (v - lo) / (hi - lo) * (h - 2 * pad))
    for v in (lo, hi) + tuple(m for m in marks):
        _, y = xy(t0, v)
        d.line([(pad, y), (w - pad, y)], fill=(60, 60, 70))
        d.text((4, y - 9), f"{v:g}", fill=(150, 150, 160), font=fs)
    for k, (name, col, pts) in enumerate(series):
        d.line([xy(t, v) for t, v in pts], fill=col, width=3)
        d.text((pad + 10 + 300 * k, h - pad + 14), name, fill=col, font=fs)
    d.text((pad, 8), title, fill=(230, 230, 230), font=font(18))
    return im


def run(b, mode, grab_at=(), mad=True):
    """Una pasada de la partitura: velocidad de dibujo, MAD, cuadros y el `rate` que
    calculó el QML (`Speed.rate`, no una copia en Python)."""
    b.start(mode)
    n = int(DUR * FPS)
    prev_d, prev_l = None, None
    speed, diff, shots, rates, bases = [], [], {}, {}, {}
    want = {round(T0 + g, 4): g for g in grab_at}
    for k in range(n + 1):
        t = T0 + k / FPS
        img = b.step(t, grab=mad or round(t, 4) in want)
        d_t = b.root.property("drawT")
        rates[round(t - T0, 4)] = b.root.property("rate")
        bases[round(t - T0, 4)] = b.root.property("baseRate")
        if prev_d is not None:
            speed.append((t - T0, (d_t - prev_d) * FPS))
        prev_d = d_t
        if img is not None:
            if round(t, 4) in want:
                shots[want[round(t, 4)]] = img
            if mad:
                l_ = lum(img[::2, ::2])
                if prev_l is not None:
                    diff.append((t - T0, float(np.abs(l_ - prev_l).mean())))
                prev_l = l_
    return speed, diff, shots, rates, bases


def sheet(args):
    pace = pace_row(args.pace)
    b = Bench()
    b.score = args.score
    mov_fn = SCORES[args.score][0]
    b.set(pace={"movMin": pace["movMin"], "movMax": pace["movMax"], "movKick": pace["movKick"]})
    os.makedirs(OUT, exist_ok=True)

    if args.score == "fast":
        grabs = [0.5, 1.2, 1.6, 2.5, 5.0, 6.5, 8.0, 10.0]
    else:
        grabs = [0.5, 2.5, 3.5, 4.5, 6.0, 8.0, 9.5, 11.5]
    res = {mode: run(b, mode, grabs) for mode in ("off", "int", "prod")}
    rates = res["int"][3]
    bases = res["int"][4]

    def rate_at(tau):
        return rates[round(tau, 4)]

    taus = [k / FPS for k in range(int(DUR * FPS) + 1)]
    metrics = {"pace": args.pace, "score": args.score, "movMin": pace["movMin"],
               "movMax": pace["movMax"], "movKick": pace["movKick"], "t0_s": T0, "fps": FPS}
    for mode, (speed, diff, _, rr, _bb) in res.items():
        sp = [v for _, v in speed]
        dev = [abs(v - rr[round(t, 4)]) for t, v in speed]
        metrics[mode] = {
            "vel_dibujo_max": round(max(sp), 4),
            "vel_dibujo_min": round(min(sp), 4),
            "desvio_max_vs_rate": round(max(dev), 4),
            "mad_cuadro_a_cuadro_media": round(float(np.mean([v for _, v in diff])), 3),
            "mad_cuadro_a_cuadro_max": round(float(max(v for _, v in diff)), 3),
        }
    if args.score == "fast":
        # cuánto tarda el ritmo BASE (sin el empujón) en llegar al 90 % del pasaje nervioso al
        # subir y del calmo al bajar, y cuánto pega el golpe encima
        base_hi = bases[round(3.0, 4)]
        base_lo = bases[round(10.0, 4)]
        base_start = bases[round(0.5, 4)]
        up = next(t for t in taus if t >= 1.0 and bases[round(t, 4)] >= base_start + 0.9 * (base_hi - base_start))
        dn = next(t for t in taus if t >= 6.0 and bases[round(t, 4)] <= base_hi - 0.9 * (base_hi - base_lo))
        pk = max(rates[round(t, 4)] / bases[round(t, 4)] for t in taus if 1.4 <= t < 6.0)
        metrics["ritmo_base"] = {"quieto": round(base_start, 3), "nervioso": round(base_hi, 3),
                                 "calmo_final": round(base_lo, 3),
                                 "sube_al_90pct_s": round(up - 1.0, 2), "baja_al_90pct_s": round(dn - 6.0, 2),
                                 "empujon_max_sobre_base": round(pk, 3),
                                 "ritmo_max_con_golpes": round(max(rates.values()), 3)}
    with open(os.path.join(OUT, "metrics.json"), "w") as f:
        json.dump(metrics, f, indent=2)
    print(json.dumps(metrics, indent=2))

    cw = 300
    rows = [("integrado", res["int"][2]), ("t · rate", res["prod"][2])]
    ch = round(720 * cw / 1280)
    lw = 150
    W = lw + len(grabs) * (cw + 8) + 8
    top = 98
    strip = Image.new("RGB", (W, top + len(rows) * (ch + 8) + 8), (18, 18, 20))
    d = ImageDraw.Draw(strip)
    d.text((12, 14), f"Ritmo de los dibujos con mov subiendo y bajando — Mystify, pace {args.pace}, "
                     f"a los {T0:.0f} s de tema", fill=(235, 235, 235), font=font(28))
    for j, g in enumerate(grabs):
        d.text((lw + j * (cw + 8) + 4, 72), f"+{g:.1f}s mov={mov_fn(g):.2f} ×{rate_at(g):.2f}",
               fill=(200, 200, 200), font=font(16))
    for i, (lab, shots) in enumerate(rows):
        y = top + i * (ch + 8)
        d.text((10, y + ch // 2 - 12), lab, fill=(235, 235, 235), font=font(22))
        for j, g in enumerate(grabs):
            strip.paste(thumb(shots[g], cw), (lw + j * (cw + 8), y))

    hi1 = max(1.7, max(rates.values()) + 0.1)
    p1 = plot([("mov", (140, 200, 255), [(t, mov_fn(t)) for t in taus]),
               ("ritmo base", (255, 180, 90), [(t, bases[round(t, 4)]) for t in taus]),
               ("ritmo con el golpe", (255, 90, 160), [(t, rate_at(t)) for t in taus])],
              0, DUR, W, 260, f"la partitura {args.score}: mov y el ritmo (fila {args.pace}: "
              f"{pace['movMin']:g}–{pace['movMax']:g}, golpe {pace['movKick']:g}, pivote 0.45, mov crudo)",
              lo=0, hi=hi1, marks=(1.0,))
    p2 = plot([("integrado", (255, 180, 90), res["int"][0]),
               ("t · rate (control)", (255, 90, 90), res["prod"][0]),
               ("perilla en 0", (140, 140, 150), res["off"][0])],
              0, DUR, W, 300, "velocidad del reloj de dibujo (s de dibujo por s real) — recortada a "
              f"[-2, 3]; el producto llega a {metrics['prod']['vel_dibujo_max']:.0f}× y "
              f"{metrics['prod']['vel_dibujo_min']:.0f}×", lo=-2, hi=3, marks=(0.0, 1.0))
    p3 = plot([("integrado", (255, 180, 90), res["int"][1]),
               ("t · rate (control)", (255, 90, 90), res["prod"][1]),
               ("perilla en 0", (140, 140, 150), res["off"][1])],
              0, DUR, W, 300, "cambio de imagen cuadro a cuadro (luminancia media absoluta, 0-255)",
              lo=0)
    out = Image.new("RGB", (W, strip.height + p1.height + p2.height + p3.height), (18, 18, 20))
    y = 0
    for im in (strip, p1, p2, p3):
        out.paste(im, (0, y))
        y += im.height
    suffix = "" if args.pace == "normal" else "-" + args.pace
    if args.score == "fast":
        suffix = "-golpes" + suffix
    path = os.path.join(DOCS, f"movimiento-ritmo{suffix}.png")
    out.save(path, optimize=True)
    print(path)


def cpu(args):
    pace = pace_row(args.pace)
    b = Bench()
    b.set(pace={"movMin": pace["movMin"], "movMax": pace["movMax"], "movKick": pace["movKick"]})
    res = {}
    for mode in ("off", "int") * 2:
        b.start(mode)
        b.step(T0)
        r0, w0 = resource.getrusage(resource.RUSAGE_SELF), time.perf_counter()
        for k in range(args.frames):
            b.step(T0 + (k + 1) / FPS)
        r1, w1 = resource.getrusage(resource.RUSAGE_SELF), time.perf_counter()
        cpu_ms = ((r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime)) * 1000 / args.frames
        res[mode] = {"cpu_ms_por_cuadro": round(cpu_ms, 3),
                     "pared_ms_por_cuadro": round((w1 - w0) * 1000 / args.frames, 3)}
    print(json.dumps(res, indent=2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["sheet", "cpu"])
    ap.add_argument("--pace", default="normal")
    ap.add_argument("--score", choices=sorted(SCORES), default="slow")
    ap.add_argument("--frames", type=int, default=600)
    args = ap.parse_args()
    {"sheet": sheet, "cpu": cpu}[args.cmd](args)


if __name__ == "__main__":
    main()
