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

// ---- El LIENZO de pared (los motivos extendidos, `docs/PARED.md`). Un motivo "de pared" no
// dibuja su pantalla: dibuja UN mundo del tamaño de la caja que envuelve todas las pantallas
// del tubo, y cada pantalla muestra su recorte. Los huecos entre monitores (DP-2 asoma 370 px
// por arriba de HDMI-A-1) son mundo que nadie ve, igual que la pantalla que tiene la letra.

// La caja de todas las pantallas, en coordenadas del compositor, y `span`: el lado corto de la
// pantalla más chica, la medida de los trazos (un trazo de pared mide lo mismo que en una
// pantalla sola, y lo mismo en todas).
function canvas(rects) {
    if (!rects || rects.length === 0)
        return { x: 0, y: 0, w: 1, h: 1, span: 1 };
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity, sp = Infinity;
    for (let i = 0; i < rects.length; i++) {
        const r = rects[i];
        x0 = Math.min(x0, r.x);
        y0 = Math.min(y0, r.y);
        x1 = Math.max(x1, r.x + r.w);
        y1 = Math.max(y1, r.y + r.h);
        sp = Math.min(sp, r.w, r.h);
    }
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0, span: Math.max(sp, 1) };
}

// Qué recorte del lienzo dibuja una pantalla: {x, y, w, h} en px de lienzo.
//   off — la esquina de la pantalla en el lienzo; size — {w, h} de la pantalla
//   pv  — el pivote de pared en px de lienzo (`pivot` menos la esquina del lienzo)
//   o   — el origen de SU cámara (`local`, px de la pantalla); s — el factor de su cámara
//   z   — el tirón propio del dibujo (el golpe), que en pared no puede ir por el Scale del
//         item: sobre su centro partiría la costura, y sobre el pivote dejaría asomar el fondo
// Lo que se ve queda como si TODA la pared escalara `s·z` sobre el pivote verdadero: `local`
// ata el origen de la cámara al rectángulo (una pantalla que no toca el pivote escala sobre su
// borde), y `d` corre el recorte lo que esa diferencia de origen desplaza.
function view(off, size, pv, o, s, z) {
    const sz = Math.max(s, 0.05), zz = Math.max(z, 0.05);
    const dx = (o.x - (pv.x - off.x)) * (1 - 1 / sz);
    const dy = (o.y - (pv.y - off.y)) * (1 - 1 / sz);
    return { x: pv.x + (off.x - dx - pv.x) / zz, y: pv.y + (off.y - dy - pv.y) / zz,
             w: size.w / zz, h: size.h / zz };
}
