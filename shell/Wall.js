// fatal-lyrics — la cámara de PARED (tanda "música y momentos", r14.1).
//
// Cada tubo escalaba la cámara (golpe, zoom de foco, latido) sobre SU centro: con 2 % de
// golpe, DP-2 se comía 11 px de su borde derecho y HDMI-A-1 19 px del izquierdo (unos 30 px de
// la costura, que se partía justo en el bombo). Acá todas las pantallas escalan sobre UN
// pivote de pared, y la costura entre dos tubos que se tocan queda quieta: el punto de la
// costura no se mueve, sea cual sea el factor de cada lado (el zoom de foco sí difiere por
// pantalla).
//
// El pivote es el centro de la unión de las pantallas del tubo, pegado a la costura más
// cercana a ese centro: el centro de DP-2 + HDMI-A-1 cae a 420 px de la costura, y con el
// pivote ahí la pantalla de la izquierda se achicaría 8 px hacia adentro al 2 % y dejaría
// asomar el fondo. Una pantalla sola, o sin vecinas, queda sobre su propio centro (como
// antes). `local` ata el pivote al rectángulo de cada pantalla: una pantalla que no toca la
// costura (un tercer monitor) escala sobre su borde más cercano al pivote, así su borde no
// se mete hacia adentro y nunca asoma el fondo.
//
// Las rects son {x, y, w, h} en coordenadas globales del compositor. Puro: lo usan
// `shell.qml`, `Crt.qml` y `tests/test_musica_momentos.py` (con node).
.pragma library

var EPS = 1;     // px: dos bordes que difieren menos que esto son el mismo

function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }

// Las costuras del conjunto: {axis: "x"|"y", at, mid} — `at` es la coordenada del borde
// compartido y `mid` el centro del tramo que comparten las dos pantallas (en el otro eje).
function seams(rects) {
    const out = [];
    for (let i = 0; i < rects.length; i++) {
        for (let j = 0; j < rects.length; j++) {
            if (i === j) continue;
            const a = rects[i], b = rects[j];
            if (Math.abs(a.x + a.w - b.x) < EPS) {
                const y0 = Math.max(a.y, b.y), y1 = Math.min(a.y + a.h, b.y + b.h);
                if (y1 - y0 > EPS) out.push({ axis: "x", at: b.x, mid: (y0 + y1) / 2 });
            }
            if (Math.abs(a.y + a.h - b.y) < EPS) {
                const x0 = Math.max(a.x, b.x), x1 = Math.min(a.x + a.w, b.x + b.w);
                if (x1 - x0 > EPS) out.push({ axis: "y", at: b.y, mid: (x0 + x1) / 2 });
            }
        }
    }
    return out;
}

// El pivote de pared, en coordenadas globales.
function pivot(rects) {
    if (!rects || rects.length === 0)
        return { x: 0, y: 0 };
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (let i = 0; i < rects.length; i++) {
        x0 = Math.min(x0, rects[i].x);
        y0 = Math.min(y0, rects[i].y);
        x1 = Math.max(x1, rects[i].x + rects[i].w);
        y1 = Math.max(y1, rects[i].y + rects[i].h);
    }
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    const ss = seams(rects);
    let best = null, bd = Infinity;
    for (let i = 0; i < ss.length; i++) {
        const d = Math.abs(ss[i].at - (ss[i].axis === "x" ? cx : cy));
        if (d < bd) { bd = d; best = ss[i]; }
    }
    if (!best)
        return { x: cx, y: cy };
    return best.axis === "x" ? { x: best.at, y: best.mid } : { x: best.mid, y: best.at };
}

// El pivote en coordenadas de UNA pantalla (el `origin` del Scale de su cámara), atado a su
// rectángulo.
function local(rect, pv) {
    return { x: clamp(pv.x - rect.x, 0, rect.w), y: clamp(pv.y - rect.y, 0, rect.h) };
}

// Dónde cae un punto de la pantalla (px locales) tras escalar `s` sobre `origin`.
function scaleAbout(p, origin, s) { return origin + s * (p - origin); }
