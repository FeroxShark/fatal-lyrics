#!/usr/bin/env python3
"""fatal-lyrics — banco de las paletas de tres caras (tanda 8, slice "colores").

    ./render.py            # docs/tanda8-estado/colores-paletas.png + colores-tira.png

Fuera de pantalla y sin Qt: las paletas fijas salen de `shell/shell.qml` (regex,
como `pace_row` del banco de reacción), las de la tapa y el reparto de
`shell/Faces.js` corrido con node — la hoja muestra lo que corre en el overlay, no
una copia. Dibuja sólo el FONDO y la letra (sin vidrio ni shader): lo que se mira
acá es que las tres caras armen y que el texto se lea; el número de contraste
(WCAG) va impreso en cada tile.
"""
import json
import os
import re
import subprocess

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SHELL = os.path.join(ROOT, "shell")
DOCS = os.path.join(ROOT, "docs", "tanda8-estado")
FONT = os.path.join(SHELL, "fonts", "IBMPlexMono-Bold.ttf")
FONT_SMALL = os.path.join(SHELL, "fonts", "ShareTechMono-Regular.ttf")

# tapas de ejemplo: lo que manda el daemon en el evento `art` (hasta 4 colores)
COVERS = [
    ("tapa: rojo+azul+verde", ["#d02020", "#d83018", "#2040d0", "#20a040"]),
    ("tapa: tres naranjas", ["#e07020", "#e07828", "#d86818"]),
    ("tapa: un solo azul", ["#1c2f8f"]),
    ("tapa: teal+rosa+ocre", ["#1f8a8a", "#e0508a", "#c8a030"]),
    # apagadas (poca saturación): la energía del tema decide cuánto neón se les da
    ("tapa apagada: sepia", ["#8a7660", "#6e5e4c", "#a08c70"]),
    ("tapa apagada: gris azulado", ["#5c6878", "#48546a", "#7c8898"]),
]
# energía del tema (0..1): quieto, medio, de golpe
ENERGIES = (0.0, 0.5, 1.0)
LINE = ("no me", "ESCUCHÁS", "cuando grito")


def js(expr):
    src = open(os.path.join(SHELL, "Faces.js"), encoding="utf-8").read()
    src = src.replace(".pragma library", "")
    out = subprocess.run(["node", "-e", src + "\nconsole.log(JSON.stringify(" + expr + "));"],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def fixed_schemes():
    qml = open(os.path.join(SHELL, "shell.qml"), encoding="utf-8").read()
    block = re.search(r"readonly property var schemes: \[(.*?)\n    \]", qml, re.S).group(1)
    out = []
    for key, body in re.findall(r'\{ key: "(\w+)",(.*?)\} \},', block + ",", re.S):
        faces = {}
        for name, face in re.findall(r"\b([abc]): \{([^{}]*)\}", body + "}"):
            faces[name] = dict(re.findall(r'\b(bg|ink|hot|dim): "(#[0-9a-f]{6})"', face))
        out.append((key, faces))
    return out


def font(path, size):
    return ImageFont.truetype(path, size)


def tile(draw, x, y, w, h, face, label=None, text=True, contrast=None):
    draw.rectangle([x, y, x + w - 1, y + h - 1], fill=face["bg"])
    if text:
        parts = [(LINE[0] + " ", face["ink"]), (LINE[1], face["hot"]), (" " + LINE[2], face["ink"])]
        size = int(h * 0.16)
        while True:
            f = font(FONT, size)
            total = sum(draw.textlength(p, font=f) for p, _ in parts)
            if total <= w * 0.9 or size <= 10:
                break
            size -= 1
        cx = x + (w - total) / 2
        cy = y + h * 0.40
        for p, col in parts:
            draw.text((cx, cy), p, font=f, fill=col, anchor="lm")
            cx += draw.textlength(p, font=f)
        # la barra de progreso: `dim` + `ink`, como el "now playing" del tubo
        bw = w * 0.6
        bx = x + (w - bw) / 2
        by = y + h * 0.66
        draw.rectangle([bx, by, bx + bw, by + h * 0.035], fill=face["dim"])
        draw.rectangle([bx, by, bx + bw * 0.42, by + h * 0.035], fill=face["ink"])
    s = font(FONT_SMALL, max(12, int(h * 0.075)))
    if label:
        draw.text((x + 8, y + 6), label, font=s, fill=face["ink"])
    if contrast is not None:
        draw.text((x + w - 8, y + h - 6), contrast, font=s, fill=face["ink"], anchor="rd")


def contrast_label(face):
    v = js("[contrast(%r, %r), contrast(%r, %r)]" % (face["ink"], face["bg"],
                                                     face["hot"], face["bg"]))
    return "letra %.1f  hot %.1f" % (v[0], v[1])


def sheet():
    rows = fixed_schemes()
    for name, colors in COVERS:
        for e in ENERGIES:
            f = js("albumFaces(%s, %s)" % (json.dumps(colors), e))
            rows.append(("%s  e=%.1f" % (name, e), f, colors))
    tw, th, lw, gap = 480, 200, 300, 8
    W = lw + 3 * (tw + gap) + gap
    H = 70 + len(rows) * (th + gap) + gap
    img = Image.new("RGB", (W, H), "#101010")
    d = ImageDraw.Draw(img)
    d.text((gap, 18), "Paletas de tres caras — a (prendida)  b (tubo apagado)  c (media)",
           font=font(FONT, 26), fill="#e8e8e8")
    y = 70
    for row in rows:
        key, faces = row[0], row[1]
        d.text((gap, y + 10), key, font=font(FONT, 19), fill="#e8e8e8")
        if len(row) > 2:
            # los colores que mandó la tapa
            for i, col in enumerate(row[2]):
                d.rectangle([gap + i * 34, y + 50, gap + i * 34 + 28, y + 78], fill=col)
        chk = js("checkScheme(%s)" % json.dumps(faces))
        d.text((gap, y + th - 60), "fondos entre sí ≥ %.2f" % chk["bgMin"],
               font=font(FONT_SMALL, 16), fill="#b0b0b0")
        for i, k in enumerate("abc"):
            x = lw + gap + i * (tw + gap)
            tile(d, x, y, tw, th, faces[k], label=k, contrast=contrast_label(faces[k]))
        y += th + gap
    out = os.path.join(DOCS, "colores-paletas.png")
    img.save(out, optimize=True)
    return out


def simulate(faces, n, sections, r0=0.37):
    """El reparto que haría `crtFaceTick`: por cada parte, el patrón y sus pasos
    (una pantalla por paso, desde la de la letra). Devuelve cuadros
    [(etiqueta, reparto, foco)]."""
    frames = []
    prev = js("twoTone(%d, %f)" % (n, r0))
    focus = (n - 1) // 2
    mode_now = "verse"
    drop_seen = False
    for i, (sec, rare, focus) in enumerate(sections):
        focus = min(focus, n - 1)
        drop_seen = drop_seen or sec == "drop"
        want = js("faceMode(%r, %s, %s)" % (sec, "true" if rare else "false",
                                           "true" if drop_seen else "false"))
        tag = sec + (" + raro" if rare else "")
        if want == mode_now and i > 0:
            frames.append((tag + " (" + want + ", sigue)", list(prev), focus))
            continue
        nxt = js("facePattern(%r, %d, %s, %d, %f)" % (want, n, json.dumps(prev), focus,
                                                     (r0 + 0.29 * i) % 1))
        order = js("stepOrder(%s, %s, %d)" % (json.dumps(prev), json.dumps(nxt), focus))
        cur = list(prev)
        if i > 0:
            for k, scr in enumerate(order[:-1]):
                cur[scr] = nxt[scr]
                frames.append(("%s: %s -> %s, paso %d" % (tag, mode_now, want, k + 1), list(cur), focus))
        frames.append(("%s (%s)" % (tag, want), list(nxt), focus))
        prev = nxt
        mode_now = want
    return frames


def strip():
    fixed = dict(fixed_schemes())
    album = js("albumFaces(%s)" % json.dumps(COVERS[3][1]))
    song = [("verse", False, 1), ("drop", False, 1), ("verse", False, 2),
            ("build", False, 0), ("verse", False, 1), ("quiet", False, 1),
            ("verse", True, 2)]
    blocks = [
        ("dragons, 3 monitores", fixed["dragons"], 3),
        ("tapa teal+rosa+ocre, 3 monitores", album, 3),
        ("vapor, 2 monitores", fixed["vapor"], 2),
        ("ado, 1 monitor", fixed["ado"], 1),
    ]
    mw, mh, gap, lw = 190, 84, 6, 330
    # cada bloque: una fila por cuadro de la simulación
    sims = [(title, faces, n, simulate(faces, n, song)) for title, faces, n in blocks]
    W = lw + 4 * (mw + gap) + gap
    H = 60 + sum(40 + len(fr) * (mh + gap) for _, _, _, fr in sims) + gap
    img = Image.new("RGB", (W, H), "#101010")
    d = ImageDraw.Draw(img)
    d.text((gap, 14), "Reparto por parte del tema (face_mode = song) — 'letra' = pantalla con la letra",
           font=font(FONT, 22), fill="#e8e8e8")
    y = 60
    for title, faces, n, frames in sims:
        d.text((gap, y + 8), title, font=font(FONT, 20), fill="#ffd060")
        y += 40
        for label, rep, focus in frames:
            d.text((gap, y + mh / 2), label, font=font(FONT_SMALL, 17), fill="#d0d0d0",
                   anchor="lm")
            for i in range(n):
                face = faces["abc"[rep[i]]]
                x = lw + gap + i * (mw + gap)
                tile(d, x, y, mw, mh, face, label="abc"[rep[i]], text=False)
                if i == focus:
                    f = font(FONT, 24)
                    d.text((x + mw / 2, y + mh / 2), "letra", font=f, fill=face["ink"],
                           anchor="mm")
            y += mh + gap
    out = os.path.join(DOCS, "colores-tira.png")
    img.save(out, optimize=True)
    return out


if __name__ == "__main__":
    print(sheet())
    print(strip())
