#!/usr/bin/env python3
"""fatal-lyrics — banco de la reacción fina del vidrio (tanda 8), fuera de pantalla.

    ./render.py sheet            # docs/tanda8-estado/reaccion-*.png + out/metrics.json
    ./render.py cpu [--frames N] # CPU y pared por cuadro, .qsb de antes vs de ahora
    ./render.py sheet --pace wild

Nunca abre nada en pantalla (plataforma `offscreen` ASIGNADA). El "antes" son los
`.qsb` de la tanda 7 (`git show <rev>:shell/crt.frag.qsb`, rev por defecto el
commit anterior al slice) con los uniforms nuevos en 0; el "ahora", `shell/`.
La partitura es `Score.js`; los uniforms nuevos los calcula `shell/React.js`.
"""
import argparse
import json
import os
import re
import resource
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402
from PyQt6.QtCore import QUrl, qInstallMessageHandler  # noqa: E402
from PyQt6.QtGui import QGuiApplication, QImage  # noqa: E402
from PyQt6.QtQuick import QQuickView  # noqa: E402

BEFORE_REV = "521e66a"      # el vidrio de la tanda 7, antes de este slice
OUT = os.path.join(HERE, "out")
DOCS = os.path.join(ROOT, "docs", "tanda8-estado")
FPS = 60


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


def motion():
    with open(os.path.join(ROOT, "shell", "Motion.qml"), encoding="utf-8") as f:
        src = f.read()
    return {k: int(v) for k, v in re.findall(r"readonly property int (\w+):\s*(\d+)", src)}


def before_dir():
    d = os.path.join(OUT, "antes-qsb")
    os.makedirs(d, exist_ok=True)
    blob = subprocess.run(["git", "-C", ROOT, "show", f"{BEFORE_REV}:shell/crt.frag.qsb"],
                          capture_output=True, check=True).stdout
    with open(os.path.join(d, "crt.frag.qsb"), "wb") as f:
        f.write(blob)
    return d


class Bench:
    def __init__(self, w=1920, h=1080):
        self.app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])
        self.view = QQuickView()
        self.view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
        self.view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Bench.qml")))
        if self.view.status() != QQuickView.Status.Ready:
            for e in self.view.errors():
                print(e.toString(), file=sys.stderr)
            sys.exit(1)
        self.view.resize(w, h)
        self.view.show()
        self.root = self.view.rootObject()

    def set(self, **kw):
        for k, v in kw.items():
            self.root.setProperty(k, v)

    def frame(self, t):
        self.root.setProperty("t", float(t))
        for _ in range(2):
            self.app.processEvents()
            img = self.view.grabWindow()
        img = img.convertToFormat(QImage.Format.Format_RGBA8888)
        a = np.frombuffer(img.constBits().asstring(img.sizeInBytes()), np.uint8)
        return a.reshape(img.height(), img.width(), 4)[:, :, :3].copy()


def lum(rgb):
    return rgb.astype(np.float64) @ np.array([0.299, 0.587, 0.114])


# ---- dibujo de la hoja ---------------------------------------------------------

def font(size):
    for p in ("/usr/share/fonts/TTF/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans.ttf",
              "/usr/share/fonts/noto/NotoSans-Regular.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def thumb(rgb, w):
    im = Image.fromarray(rgb)
    return im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)


def grid(rows, labels_left, labels_top, title, cell_w, notes=()):
    """rows: lista de filas de imágenes PIL del mismo tamaño."""
    f, fs = font(22), font(18)
    hs = [row[0].height for row in rows]
    lw = 150
    top = 70 + (28 if labels_top else 0)
    W = lw + len(rows[0]) * (cell_w + 8) + 8
    H = top + sum(h + 8 for h in hs) + 16 + 24 * len(notes)
    sheet = Image.new("RGB", (W, H), (18, 18, 20))
    d = ImageDraw.Draw(sheet)
    d.text((12, 14), title, fill=(235, 235, 235), font=font(28))
    for j, lab in enumerate(labels_top):
        d.text((lw + j * (cell_w + 8) + 4, 72), lab, fill=(200, 200, 200), font=fs)
    y = top
    for i, row in enumerate(rows):
        d.text((10, y + hs[i] // 2 - 12), labels_left[i], fill=(235, 235, 235), font=f)
        for j, im in enumerate(row):
            sheet.paste(im, (lw + j * (cell_w + 8), y))
        y += hs[i] + 8
    for k, n in enumerate(notes):
        d.text((12, y + 6 + 24 * k), n, fill=(190, 190, 190), font=fs)
    return sheet


def plot(series, t0, t1, w, h, title, marks=()):
    """series: [(nombre, color, [(t, v)])]; v en 0..~1.2."""
    im = Image.new("RGB", (w, h), (24, 24, 28))
    d = ImageDraw.Draw(im)
    fs = font(16)
    vals = [v for _, _, pts in series for _, v in pts]
    lo, hi = min(vals + [0]), max(vals + [1])
    pad = 40

    def xy(t, v):
        return (pad + (t - t0) / (t1 - t0) * (w - 2 * pad),
                h - pad - (v - lo) / (hi - lo) * (h - 2 * pad))
    for tm, lab in marks:
        x, _ = xy(tm, lo)
        d.line([(x, pad), (x, h - pad)], fill=(70, 70, 80))
        d.text((x + 3, pad - 18), lab, fill=(160, 160, 170), font=fs)
    for k, (name, col, pts) in enumerate(series):
        d.line([xy(t, v) for t, v in pts], fill=col, width=3)
        d.text((pad + 10 + 220 * k, h - pad + 12), name, fill=col, font=fs)
    d.text((pad, 8), title, fill=(230, 230, 230), font=font(18))
    return im


# ---- las tres hojas ------------------------------------------------------------

def sheet(args):
    pace = pace_row(args.pace)
    mo = motion()
    old = before_dir()
    b = Bench()
    b.set(pace=pace, motion=mo)
    os.makedirs(OUT, exist_ok=True)
    metrics = {"pace": args.pace}

    def both(t, **kw):
        b.set(mode="before", dir=old, **kw)
        a = b.frame(t)
        b.set(mode="after", dir=os.path.join(ROOT, "shell"), **kw)
        return a, b.frame(t)

    # 1) el corte: tira de cuadros y la curva de brillo medio
    times = [3.28, 3.44, 3.52, 3.70, 3.76, 3.82, 3.95, 4.10]
    before_row, after_row = [], []
    for t in times:
        a, n = both(t, screen="text", tube="trinitron")
        before_row.append(thumb(a, 300))
        after_row.append(thumb(n, 300))
    curve_a, curve_n = [], []
    for k in range(int(3.1 * FPS), int(4.3 * FPS)):
        t = k / FPS
        a, n = both(t, screen="text", tube="trinitron")
        curve_a.append((t, lum(a).mean()))
        curve_n.append((t, lum(n).mean()))
    ref = np.mean([v for t, v in curve_a if t < 3.3])
    curve_a = [(t, v / ref) for t, v in curve_a]
    curve_n = [(t, v / ref) for t, v in curve_n]
    metrics["corte"] = {
        "brillo_medio_en_corte_antes": round(float(np.mean([v for t, v in curve_a if 3.6 <= t < 3.75])), 3),
        "brillo_medio_en_corte_ahora": round(float(np.mean([v for t, v in curve_n if 3.6 <= t < 3.75])), 3),
        "pico_vuelta_antes": round(float(max(v for t, v in curve_a if 3.75 <= t < 4.1)), 3),
        "pico_vuelta_ahora": round(float(max(v for t, v in curve_n if 3.75 <= t < 4.1)), 3),
    }
    g = grid([before_row, after_row], ["antes", "ahora"], [f"t={t:.2f}" for t in times],
             f"Corte seco (cut 3.40–3.75, vuelve con cutf=0.9) — pace {args.pace}", 300,
             notes=["silencio real desde 3.30; el daemon marca cut=1 a los 100 ms. Antes: el tubo "
                    "ni se entera. Ahora: la luz baja (exitMs) y vuelve de golpe (enterMs)."])
    p = plot([("antes", (140, 140, 150), curve_a), ("ahora", (255, 180, 90), curve_n)],
             3.1, 4.3, g.width, 300, "brillo medio relativo al de antes del corte",
             marks=[(3.30, "silencio"), (3.40, "cut=1"), (3.75, "vuelve")])
    out = Image.new("RGB", (g.width, g.height + p.height), (18, 18, 20))
    out.paste(g, (0, 0))
    out.paste(p, (0, g.height))
    out.save(os.path.join(DOCS, f"reaccion-corte{args.suffix}.png"), optimize=True)

    # 2) bajo vs agudos: el mismo cuadro con el golpe, con los agudos y quieto. Sin
    # ruido ni barra, para que la diferencia sea SÓLO el canal.
    quiet = dict(screen="text", tube="trinitron", clean=True)
    b.set(**quiet)
    shots = {"quieto (1.00)": 1.00, "golpe de bajo (0.25)": 0.25, "agudos (2.16)": 2.16}
    cells_a, cells_n, crops_a, crops_n = [], [], [], []
    frames = {}
    for lab, t in shots.items():
        a, n = both(t, **quiet)
        frames[lab] = (a, n)
        cells_a.append(thumb(a, 420))
        cells_n.append(thumb(n, 420))
        cy, cx = 470, 560     # un pedazo del borde de la letra, 2×
        crops_a.append(Image.fromarray(a[cy:cy + 150, cx:cx + 210]).resize((420, 300), Image.NEAREST))
        crops_n.append(Image.fromarray(n[cy:cy + 150, cx:cx + 210]).resize((420, 300), Image.NEAREST))
    # Cada canal se mide contra el MISMO cuadro sin ese canal (mismo `t`: el titileo de
    # 60 Hz del shader depende del reloj y ensucia cualquier comparación entre cuadros).
    #   bajo:   t=0.25 con el golpe vs t=0.25 con `pulseOff`
    #   agudos: t=2.16 ahora vs t=2.16 antes (antes = sin los uniforms nuevos)
    def channel(with_, without):
        lw, lo_ = lum(with_), lum(without)
        hl = lo_ > 110
        return {
            "brillo_medio_%": round(float((lw.mean() / lo_.mean() - 1) * 100), 2),
            "cambio_local_rms": round(float(np.sqrt(np.mean((lw - lo_) ** 2))), 2),
            "azul_menos_rojo_en_claros": round(float(
                (with_[..., 2].astype(float) - with_[..., 0])[hl].mean()
                - (without[..., 2].astype(float) - without[..., 0])[hl].mean()), 2),
        }
    ch = {}
    b.set(pulseOff=True)
    _, n0 = both(0.25, **quiet)
    b.set(pulseOff=False)
    ch["golpe de bajo (0.25)"] = channel(frames["golpe de bajo (0.25)"][1], n0)
    a, n = frames["agudos (2.16)"]
    ch["agudos (2.16)"] = channel(n, a)
    # identidad: los .qsb nuevos con los cuatro uniforms en 0 contra los viejos
    b.set(mode="before", dir=old)
    a = b.frame(5.3)
    b.set(dir=os.path.join(ROOT, "shell"))
    n = b.frame(5.3)
    metrics["identidad_uniforms_en_0_max_abs"] = int(np.abs(a.astype(int) - n.astype(int)).max())
    metrics["bajo_vs_agudos_ahora"] = ch
    g = grid([cells_a, cells_n, crops_a, crops_n], ["antes", "ahora", "antes 2×", "ahora 2×"],
             list(shots), f"El bajo sube la LUZ; los agudos mueven las FILAS y enfrían los claros — pace {args.pace}",
             420, notes=["golpe (ahora): brillo %+.1f %%, cambio local %.1f; agudos: brillo %+.1f %%, cambio local %.1f, "
                         "azul−rojo en claros %+.1f" % (ch["golpe de bajo (0.25)"]["brillo_medio_%"],
                                                         ch["golpe de bajo (0.25)"]["cambio_local_rms"],
                                                         ch["agudos (2.16)"]["brillo_medio_%"],
                                                         ch["agudos (2.16)"]["cambio_local_rms"],
                                                         ch["agudos (2.16)"]["azul_menos_rojo_en_claros"]),
                         "(el golpe se dibuja al valor de flicker=1 para comparar a la misma escala)"])
    g.save(os.path.join(DOCS, f"reaccion-agudos{args.suffix}.png"), optimize=True)

    # 3) el grano: seis cuadros seguidos (60 fps) sucio, antes/ahora, y el quimógrafo:
    # la amplitud del ruido por fila (eje y) a lo largo del tiempo (eje x). Quieto =
    # gris parejo; con movimiento = franjas en diagonal.
    gz = dict(screen="motif", tube="arcade", clean=False)
    b.set(**gz)
    seq = [6.5 + k / FPS for k in range(6)]
    ra_, rn_ = [], []
    for t in seq:
        a, n = both(t, **gz)
        ra_.append(Image.fromarray(a[380:620, 820:1140]).resize((320, 240), Image.NEAREST))
        rn_.append(Image.fromarray(n[380:620, 820:1140]).resize((320, 240), Image.NEAREST))
    kym = {}
    for mode_, d in (("before", old), ("after", os.path.join(ROOT, "shell"))):
        b.set(mode=mode_, dir=d)
        cols = []
        for k in range(0, int(3.0 * FPS)):
            t = 4.5 + k / FPS
            y = lum(b.frame(t))[:, 200:1720]
            hp = y - (np.roll(y, 1, 1) + np.roll(y, -1, 1) + 2 * y) / 4      # pasaaltos horizontal
            cols.append(np.abs(hp).mean(axis=1))
        kym[mode_] = np.array(cols).T                                         # filas × tiempo
    lo_, hi_ = np.percentile(np.concatenate([kym["before"], kym["after"]]), [2, 98])
    kims = []
    for mode_ in ("before", "after"):
        k = np.clip((kym[mode_] - lo_) / (hi_ - lo_ + 1e-6), 0, 1)
        kims.append(Image.fromarray((k * 255).astype(np.uint8)).resize((900, 300), Image.BILINEAR).convert("RGB"))
    # cuánto se mueve: la varianza por fila de la amplitud (bandas) y la correlación
    # entre cuadros vecinos (deriva)
    for mode_ in ("before", "after"):
        k = kym[mode_][150:930]
        metrics.setdefault("grano", {})[mode_] = {
            "contraste_de_bandas": round(float(k.std(axis=0).mean() / k.mean()), 3),
        }
    g = grid([ra_, rn_], ["antes", "ahora"], [f"t={t:.3f}" for t in seq],
             f"El grano sucio (dirt 0.9, sin letra, tubo arcade): seis cuadros seguidos — pace {args.pace}", 320)
    d_ = ImageDraw.Draw(g)
    W = max(g.width, 900 + 170)
    kimg = Image.new("RGB", (W, 2 * 316 + 60), (18, 18, 20))
    dk = ImageDraw.Draw(kimg)
    dk.text((12, 8), "Amplitud del ruido por fila (vertical) en el tiempo (horizontal, 4.5→7.5 s; dirt sube de 0.15 a 0.9)",
            fill=(230, 230, 230), font=font(18))
    for i, (lab, im) in enumerate(zip(("antes", "ahora"), kims)):
        dk.text((12, 50 + i * 316 + 140), lab, fill=(235, 235, 235), font=font(22))
        kimg.paste(im, (150, 40 + i * 316))
    out = Image.new("RGB", (max(g.width, W), g.height + kimg.height), (18, 18, 20))
    out.paste(g, (0, 0))
    out.paste(kimg, (0, g.height))
    out.save(os.path.join(DOCS, f"reaccion-grano{args.suffix}.png"), optimize=True)

    with open(os.path.join(OUT, f"metrics{args.suffix}.json"), "w") as f:
        json.dump(metrics, f, indent=2, ensure_ascii=False)
    print(json.dumps(metrics, indent=2, ensure_ascii=False))


def cpu(args):
    pace = pace_row(args.pace)
    b = Bench()
    b.set(pace=pace, motion=motion(), screen="motif", tube="arcade")
    res = {}
    for mode_, d in (("before", before_dir()), ("after", os.path.join(ROOT, "shell"))) * 2:
        b.set(mode=mode_, dir=d)
        b.frame(0)
        r0, w0 = resource.getrusage(resource.RUSAGE_SELF), time.perf_counter()
        for k in range(args.frames):
            b.frame(4.0 + k / FPS)
        r1, w1 = resource.getrusage(resource.RUSAGE_SELF), time.perf_counter()
        cpu_ms = ((r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime)) * 1000 / args.frames
        res[mode_] = {"cpu_ms_por_cuadro": round(cpu_ms, 3),
                      "pared_ms_por_cuadro": round((w1 - w0) * 1000 / args.frames, 3)}
    print(json.dumps(res, indent=2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["sheet", "cpu"])
    ap.add_argument("--pace", default="normal")
    ap.add_argument("--suffix", default="")
    ap.add_argument("--frames", type=int, default=300)
    args = ap.parse_args()
    {"sheet": sheet, "cpu": cpu}[args.cmd](args)


if __name__ == "__main__":
    main()
