#!/usr/bin/env python3
"""fatal-lyrics motivos CRT — banco de la PARED (`docs/PARED.md`), offscreen.

Cada pantalla corre SU instancia del motivo (como un Crt.qml por pantalla) sobre el lienzo
común; `--ref` dibuja el lienzo entero con una sola. La costura está bien si cada pantalla es
el recorte de la referencia: `--check` renderiza las dos y mide la diferencia por pantalla.

    ./pared.py 3 truchet --stills 2,6.5          # out/pared/3-truchet-t02.000.png
    ./pared.py 3 pipes --stills 6.5 --ref        # la referencia (lienzo entero)
    ./pared.py --check                           # todos los layouts × motivos de pared
    ./pared.py --check --cam 1.06 --zoom 1.04    # con la cámara y el tirón puestos

Layouts (px lógicos, como `hyprctl monitors`):
    2   DP-2 vertical + HDMI-A-1, instrumental
    3   el equipo de Ferox (DP-2 vertical, HDMI-A-1, DP-1 corrido 247 px), letra en el medio
    3i  el mismo, instrumental
    3h  tres 1920×1080 en fila, letra en el medio
    2t  DP-2 vertical + HDMI-A-1, letra en HDMI-A-1 (borde)
    3e  el equipo de Ferox, letra en DP-2 (borde)
    3v  tres 1920×1080 apiladas, letra en el medio (espejo vertical)

La pantalla de la letra no lleva la pared; las demás la reparten como declara el motivo
(`wallFit` en shell/<Kind>.qml: "behind" o "mirror", `Wall.fit`). Una espejada se mide contra
el recorte reflejado de la referencia (con la cámara puesta, contra `--ref --ref-mirror`: la
referencia escalando sobre el pivote reflejado).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["QT_QPA_PLATFORM"] = "offscreen:configfile=" + os.path.join(HERE, "offscreen.json")
os.environ["QT_QUICK_BACKEND"] = "rhi"
os.environ["QSG_RHI_BACKEND"] = "opengl"

FPS = 60
OUT = os.path.join(HERE, "out", "pared")
DP2 = {"x": 0, "y": -370, "w": 1080, "h": 1920}
HDMI = {"x": 1080, "y": 0, "w": 1920, "h": 1080}
DP1 = {"x": 3000, "y": 247, "w": 1920, "h": 1080}
LAYOUTS = {
    "2": ([DP2, HDMI], -1),
    "3": ([DP2, HDMI, DP1], 1),
    "3i": ([DP2, HDMI, DP1], -1),
    "3h": ([{"x": 0, "y": 0, "w": 1920, "h": 1080}, {"x": 1920, "y": 0, "w": 1920, "h": 1080},
            {"x": 3840, "y": 0, "w": 1920, "h": 1080}], 1),
    "2t": ([DP2, HDMI], 1),
    "3e": ([DP2, HDMI, DP1], 0),
    "3v": ([{"x": 0, "y": 0, "w": 1920, "h": 1080}, {"x": 0, "y": 1080, "w": 1920, "h": 1080},
            {"x": 0, "y": 2160, "w": 1920, "h": 1080}], 1),
}
KINDS = {"truchet": "ado", "mystify": "bloodline", "pipes": "poison",
         "dunes": "bloodline", "ocean": "ado", "pond": "poison",
         "stars": "ado", "tunnel": "dragons"}
SC = 0.4
SHELL = os.path.join(HERE, "..", "..", "shell")


def wall_fit(kind):
    """Lo que declara el motivo para la pantalla de la letra (`wallFit`, default "behind")."""
    with open(os.path.join(SHELL, kind.capitalize() + ".qml"), encoding="utf-8") as f:
        m = re.search(r'^\s+wallFit:\s*"(\w+)"', f.read(), re.M)
    return m.group(1) if m else "behind"


def fits(rects, text, mode):
    """`Wall.fit` (el de shell/, con node): por pantalla, la esquina que dibuja y si se espeja."""
    with open(os.path.join(HERE, "Wall.js"), encoding="utf-8") as f:
        src = f.read().replace(".pragma library", "")
    out = subprocess.run([shutil.which("node"), "-e", src + "\nconsole.log(JSON.stringify(fit(%s, %d, %s)));"
                          % (json.dumps(rects), text, json.dumps(mode))],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def render(layout, kind, times, ref, cam, zoom, refm=False, fit=None):
    from PyQt6.QtCore import QUrl, qInstallMessageHandler
    from PyQt6.QtGui import QGuiApplication
    from PyQt6.QtQuick import QQuickView
    qInstallMessageHandler(lambda m, c, s: print(f"qml: {s}", file=sys.stderr))
    rects, text = LAYOUTS[layout]
    app = QGuiApplication(sys.argv[:1])
    view = QQuickView()
    view.setResizeMode(QQuickView.ResizeMode.SizeViewToRootObject)
    view.setInitialProperties({"rects": rects, "textIdx": text, "ref": ref, "sc": SC,
                               "camS": cam, "zoom": zoom, "kind": kind, "scheme": KINDS[kind],
                               "fitMode": fit or wall_fit(kind), "refMirror": refm})
    view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "Pared.qml")))
    if view.status() != QQuickView.Status.Ready:
        for e in view.errors():
            print(e.toString(), file=sys.stderr)
        sys.exit(1)
    view.show()
    root = view.rootObject()
    os.makedirs(OUT, exist_ok=True)
    tag = f"{layout}-{kind}" + ("-refm" if ref and refm else "-ref" if ref else "")
    # los relojes y el estado (golpes, deriva) se arman cuadro a cuadro desde -2 s, igual
    # en las dos corridas: la referencia y la pared ven la misma historia
    f, paths = -2 * FPS, []
    for t in sorted(times):
        while f < round(t * FPS):
            root.setProperty("t", f / FPS)
            app.processEvents()
            f += 1
        root.setProperty("t", t)
        for _ in range(2):
            app.processEvents()
            img = view.grabWindow()
        p = os.path.join(OUT, f"{tag}-t{t:06.3f}.png")
        img.save(p)
        paths.append(p)
    print("\n".join(paths))


def check(times, cam, zoom):
    import numpy as np
    from PIL import Image
    worst = 0.0
    for layout, (rects, text) in LAYOUTS.items():
        cvx = min(r["x"] for r in rects)
        cvy = min(r["y"] for r in rects)
        for kind in KINDS:
            fit = fits(rects, text, wall_fit(kind))
            camd = cam != 1 or zoom != 1
            runs = [[], ["--ref"]] + ([["--ref", "--ref-mirror"]] if fit["ax"] and camd else [])
            for extra in runs:
                cmd = [sys.executable, __file__, layout, kind, "--stills", ",".join(map(str, times)),
                       "--cam", str(cam), "--zoom", str(zoom)] + extra
                r = subprocess.run(cmd, capture_output=True, text=True, env=dict(os.environ, LC_ALL="C"))
                errs = [ln for ln in r.stderr.splitlines() if ("qml:" in ln or "Error" in ln) and "locale" not in ln]
                if r.returncode != 0 or errs:
                    print(f"{layout} {kind} {extra}: rc={r.returncode}\n  " + "\n  ".join(errs[:8]))
            for t in times:
                a = np.asarray(Image.open(os.path.join(OUT, f"{layout}-{kind}-t{t:06.3f}.png")).convert("RGB"), np.int16)
                b = np.asarray(Image.open(os.path.join(OUT, f"{layout}-{kind}-ref-t{t:06.3f}.png")).convert("RGB"), np.int16)
                bm = b
                if fit["ax"] and camd:
                    bm = np.asarray(Image.open(os.path.join(OUT, f"{layout}-{kind}-refm-t{t:06.3f}.png")).convert("RGB"), np.int16)
                row = []
                for i, s in enumerate(rects):
                    if i == text:
                        row.append("letra")
                        continue
                    m = fit["s"][i]
                    x0, y0 = round((s["x"] - cvx) * SC), round((s["y"] - cvy) * SC)
                    x1, y1 = x0 + round(s["w"] * SC), y0 + round(s["h"] * SC)
                    # la espejada: el recorte reflejado de la referencia, dado vuelta
                    u0, v0 = round((m["x"] - cvx) * SC), round((m["y"] - cvy) * SC)
                    u1, v1 = u0 + (x1 - x0), v0 + (y1 - y0)
                    want = (bm if m["fx"] or m["fy"] else b)[v0:v1, u0:u1]
                    if m["fx"]:
                        want = want[:, ::-1]
                    if m["fy"]:
                        want = want[::-1]
                    # 2 px de margen: el borde del recorte cae en medio píxel
                    d = np.abs(a[y0 + 2:y1 - 2, x0 + 2:x1 - 2] - want[2:-2, 2:-2])
                    mean = float(d.mean())
                    worst = max(worst, mean)
                    row.append(f"{mean:5.2f}/{int(np.percentile(d, 99.5)):3d}")
                print(f"{layout:3s} {kind:8s} {wall_fit(kind)[:3]} t={t:5.2f}  " + "  ".join(row))
    print(f"peor media por pantalla: {worst:.2f} (0..255; media/percentil 99,5)")
    return worst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("layout", nargs="?", choices=list(LAYOUTS))
    ap.add_argument("kind", nargs="?", choices=list(KINDS))
    ap.add_argument("--stills", default="2,6.5")
    ap.add_argument("--ref", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--cam", type=float, default=1.0)
    ap.add_argument("--zoom", type=float, default=1.0)
    ap.add_argument("--ref-mirror", action="store_true", help="referencia sobre el pivote reflejado")
    ap.add_argument("--fit", choices=("behind", "mirror"), help="pisa el wallFit del motivo")
    a = ap.parse_args()
    times = [float(x) for x in a.stills.split(",")]
    if a.check:
        check(times, a.cam, a.zoom)
    elif a.layout and a.kind:
        render(a.layout, a.kind, times, a.ref, a.cam, a.zoom, a.ref_mirror, a.fit)
    else:
        ap.error("layout y motivo, o --check")


if __name__ == "__main__":
    main()
