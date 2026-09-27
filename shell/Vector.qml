// vector — un teseracto (el cubo de cuatro dimensiones) en monitor vectorial.
//
// Como una Vectrex o el osciloscopio de un laboratorio: sólo líneas, con
// halo de fósforo y la estela corta del haz. Gira despacio en dos planos a la
// vez (XW e YZ, un número entero de vueltas por loop) y en cada golpe del tubo
// pega un OCTAVO DE VUELTA con el snap de Motion — ocho golpes = una vuelta
// entera, así que el giro cierra el loop aunque avance a los saltos. Al
// girar en XW el cubo de adentro sale y el de afuera entra: se da vuelta como
// un guante. Lo que suena:
//   · `kick`: el octavo de vuelta
//   · `tick`: el tamaño pega un tirón en cada tiempo y los vértices se prenden
//   · `drop`: aparecen dos ecos girados (tres teseractos entrelazados) y las
//     aristas van en `hot` en cada tiempo
//   · `low`: el grosor del haz
//
// Costo en el overlay: un `MShape` con 32 aristas × (1 + 5 de estela) × hasta
// 3 copias; ~6 ms de CPU por cuadro en el drop (el Canvas eran ~95).
import QtQuick
import "Ease.js" as E

MotifBase {
    id: m

    readonly property var verts: {
        const v = [];
        for (let i = 0; i < 16; i++)
            v.push([(i & 1) ? 1 : -1, (i & 2) ? 1 : -1, (i & 4) ? 1 : -1, (i & 8) ? 1 : -1]);
        return v;
    }
    readonly property var edges: {
        const e = [];
        for (let i = 0; i < 16; i++)
            for (let b = 0; b < 4; b++) {
                const j = i ^ (1 << b);
                if (j > i) e.push([i, j]);
            }
        return e;
    }
    // el octavo de vuelta de cada golpe, con el snap (0..8 → 0..2π)
    readonly property real jolt: (E.wrap(kick, 8) - 1 + E.outExpo(E.prog(sinceKick, 0, 0.34))) * Math.PI / 4
    readonly property real punch: 1 + 0.07 * Math.exp(-sinceTick / 0.13)
    // cada aparición gira distinto: vueltas enteras por loop en cada plano
    // (el loop sigue cerrando) y un tamaño propio
    readonly property int ra: 1 + Math.floor(E.hash(seed * 3.3 + 0.1) * 2)
    readonly property int rb: 1 + Math.floor(E.hash(seed * 4.7 + 0.2) * 3)
    readonly property int rc: Math.floor(E.hash(seed * 6.1 + 0.3) * 2)
    readonly property real sz: 0.85 + 0.3 * E.hash(seed * 7.9 + 0.4)

    function project(tt, extra) {
        const a = 2 * Math.PI * tt / loopS * ra + jolt + extra;   // XW: 1–2 vueltas por loop + saltos
        const b = 2 * Math.PI * tt / loopS * rb + extra * 0.5;    // YZ: 1–3 vueltas
        const c = 2 * Math.PI * tt / loopS * rc + 0.6 + seed;     // XZ: 0–1, para que no quede de frente
        const ca = Math.cos(a), sa = Math.sin(a), cb = Math.cos(b), sb = Math.sin(b);
        const cc = Math.cos(c), sc = Math.sin(c);
        const s = span * 0.19 * punch * sz;
        const out = [];
        for (const p of verts) {
            let x = p[0] * ca - p[3] * sa, w = p[0] * sa + p[3] * ca;
            let y = p[1] * cb - p[2] * sb, z = p[1] * sb + p[2] * cb;
            const x2 = x * cc - z * sc, z2 = x * sc + z * cc;
            // 4D → 3D → 2D, las dos con perspectiva
            const k4 = 1 / (2.6 - w);
            const X = x2 * k4, Y = y * k4, Z = z2 * k4;
            const k3 = 2.4 / (3.2 - Z);
            out.push([width / 2 + X * k3 * s * 2.2, height / 2 + Y * k3 * s * 2.2, w]);
        }
        return out;
    }

    // Por `MShape` (placa de video): el Canvas costaba ~95 ms por cuadro.
    // Tandas por copia: 6 de estela × 2 de profundidad en W (adentro/afuera),
    // 2 de halo y 1 de vértices (octógonos rellenos).
    MShape { id: sh }
    function build() {
        const styles = [], geo = [];
        const beatHot = 1 - E.outQuad(bp);
        const copies = dropAmt > 0.01 ? 3 : 1;
        const lw = span * (0.0035 + 0.002 * low);
        const r = lw * (1.2 + 1.6 * beatHot);
        for (let cI = 0; cI < 3; cI++) {
            const on = cI < copies;
            const extra = cI * 2 * Math.PI / 3;
            const amt = cI === 0 ? 1 : dropAmt;
            const hotEdge = drop && cI === 0 ? beatHot : 0;
            for (let tr = 5; tr >= 0; tr--) {
                const P = on ? project(lt - tr * 0.022, extra) : null;
                const a = (tr === 0 ? 1 : 0.22 * (1 - tr / 6)) * amt;
                for (let bucket = 0; bucket < 2; bucket++) {
                    const depth = bucket === 0 ? 0.3 : 0.85;
                    const segs = [];
                    if (on)
                        for (const e of edges) {
                            const p = P[e[0]], q = P[e[1]];
                            if (((p[2] + q[2]) > 0 ? 1 : 0) !== bucket) continue;
                            segs.push([Qt.point(p[0], p[1]), Qt.point(q[0], q[1])]);
                        }
                    if (tr === 0) {
                        styles.push({ w: lw * 5, c: E.col(colour, 0.18 * a * depth) });
                        geo.push(segs);
                    }
                    styles.push({ w: tr === 0 ? lw : lw * 0.7,
                                  c: E.col(hotEdge > 0.3 ? hot : colour, a * (0.45 + 0.55 * depth)) });
                    geo.push(segs);
                }
                if (tr === 0) {
                    const dots = [];
                    if (on)
                        for (const p of P) {
                            const o = [];
                            for (let k = 0; k < 8; k++)
                                o.push(Qt.point(p[0] + r * Math.cos(k * Math.PI / 4), p[1] + r * Math.sin(k * Math.PI / 4)));
                            dots.push(o);
                        }
                    styles.push({ w: 0, f: E.col(hot, (0.5 + 0.5 * beatHot) * amt) });
                    geo.push(dots);
                }
            }
        }
        sh.styles = styles;
        sh.geo = geo;
    }
    onFrame: build()
}
