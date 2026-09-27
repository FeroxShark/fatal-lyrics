// harmonograph — el péndulo que dibuja: una pluma que traza la canción.
//
// Un harmonógrafo de laboratorio: dos péndulos por eje que se van frenando,
// y la pluma deja una roseta que se cierra en espiral hacia el centro. Una
// figura por frase de dos compases (cuatro por loop), cada una con su
// relación de frecuencias: la estrofa en 2:3 y 3:4, la subida desafinada (no
// cierra), el drop en 1:2. La pluma avanza al ritmo del tiempo, y lo que la
// hace de esta canción: **el trazo es más grueso donde cayó un golpe**, así la
// figura terminada queda con el compás anotado como nudos. Al cerrar la frase
// la figura se quema y se apaga mientras arranca la siguiente. Lo que suena:
//   · `tick`: por dónde va la pluma y dónde quedan los nudos
//   · `section`: la relación de la figura (la misma idea del scope)
//   · `drop`: la figura de la frase del drop se dibuja en `hot`
//
// Costo en el overlay: un `MShape` con ~520 tramos cortos por figura (dos
// mientras se cruzan); los puntos de cada figura se calculan una sola vez.
import QtQuick
import "Ease.js" as E

MotifBase {
    id: m

    readonly property real q: E.wrap(beatN, 32) + bp
    readonly property int phrase: Math.floor(q / 8)
    readonly property real u: (q - phrase * 8) / 8
    // cada frase: [f1, f2, f3, f4] (x = f1 + f2, y = f3 + f4) y los desfases.
    // Casi enteros: la figura se cierra despacio y gira, que es lo que hace
    // que un harmonógrafo se vea vivo y no como una curva de libro.
    // Cada aparición saca sus cuatro figuras de un repertorio de ocho (la
    // tercera frase, la de la subida, siempre desafinada) y su propio
    // número de vueltas. Ojo al sumar una: x e y comparten frecuencias, así
    // que el desfase entre las componentes iguales (p0↔p3, p1↔p2) tiene que
    // andar por 1.2–2 rad; cerca de 0 o de π la roseta se aplasta en una diagonal.
    readonly property var repertoire: [
        { f: [2, 3.006, 3, 2.004], p: [0, 0.3, 1.57, 1.9] },
        { f: [3, 4.008, 4, 3.004], p: [0.2, 0, 1.77, 1.0] },
        { f: [1, 2.006, 2.004, 1], p: [0, 0.8, 1.57, 2.4] },
        { f: [2, 5.01, 5.004, 2], p: [0.6, 0.1, 1.6, 2.1] },
        { f: [3, 2.005, 2, 3.004], p: [1.1, 0.5, 1.8, 2.6] },
        { f: [4, 5.006, 5, 4.004], p: [0.3, 1.4, 2.9, 1.6] },
        { f: [1, 3.004, 3.006, 1], p: [0.9, 0.2, 1.5, 2.5] },
        { f: [5, 3.007, 3, 5.003], p: [0.1, 2.0, 0.8, 1.6] }
    ]
    readonly property var ratios: {
        const out = [];
        for (let ph = 0; ph < 4; ph++) {
            const r = repertoire[Math.floor(E.hash(seed * 9.1 + ph * 1.7 + 0.3) * repertoire.length)];
            // la subida: se corre de la afinación para que no cierre
            out.push(ph === 2 ? { f: [r.f[0], r.f[1] + 0.06, r.f[2] + 0.03, r.f[3]], p: r.p } : r);
        }
        return out;
    }
    readonly property int segs: Math.round(2600 * quality)
    readonly property real turns: 13 + Math.floor(E.hash(seed * 2.3 + 0.8) * 7)   // vueltas por figura

    function pt(ph, s) {
        const r = ratios[ph];
        const T = 2 * Math.PI * turns * s;
        const d1 = Math.exp(-1.9 * s), d2 = Math.exp(-2.5 * s);
        const R = span * 0.44;
        return [width / 2 + R * (0.5 * d1 * Math.sin(r.f[0] * T + r.p[0]) + 0.5 * d2 * Math.sin(r.f[1] * T + r.p[1])),
                height / 2 + R * (0.5 * d2 * Math.sin(r.f[2] * T + r.p[2]) + 0.5 * d1 * Math.sin(r.f[3] * T + r.p[3]))];
    }

    // Por `MShape` (placa de video): el Canvas costaba ~50 ms por cuadro. La
    // figura entera de cada frase no depende del cuadro (sólo cuánto se ve),
    // así que sus puntos se calculan una vez y se cortan.
    property var ptsCache: ({})
    onWidthChanged: ptsCache = {}
    onHeightChanged: ptsCache = {}
    onSegsChanged: ptsCache = {}
    onRatiosChanged: ptsCache = {}
    onTurnsChanged: ptsCache = {}
    function figurePts(ph) {
        let c = ptsCache[ph];
        if (!c) {
            c = [];
            for (let i = 0; i <= segs; i++) {
                const q = pt(ph, i / segs);
                c.push(Qt.point(q[0], q[1]));
            }
            ptsCache[ph] = c;
        }
        return c;
    }
    // 4 tandas de grosor según qué tan cerca de un golpe cayó cada tramo
    readonly property int nk: 4
    function figure(styles, geo, ph, upTo, alpha, hotLine) {
        const P = figurePts(ph);
        const n = Math.max(2, Math.floor(segs * upTo));
        const lw = span * 0.0022;
        const chunk = 5;
        const paths = [];
        for (let b = 0; b < nk; b++) paths.push([]);
        for (let i0 = 0; i0 < n; i0 += chunk) {
            // en qué tiempo de la frase cayó este tramo → nudo si fue un golpe
            const beatPos = (i0 + chunk / 2) / segs * 8;
            const knot = Math.exp(-(beatPos - Math.floor(beatPos)) * beatS / 0.045);
            paths[Math.min(nk - 1, Math.round(knot * (nk - 1)))].push(P.slice(i0, Math.min(n, i0 + chunk) + 1));
        }
        for (let b = 0; b < nk; b++) {
            const knot = b / (nk - 1);
            styles.push({ w: lw * (1 + 3.2 * knot), c: E.col(hotLine ? hot : colour, alpha * (0.55 + 0.45 * knot)) });
            geo.push(paths[b]);
        }
        return P[n];
    }
    function disc(x, y, r) {
        const o = [];
        for (let k = 0; k < 16; k++)
            o.push(Qt.point(x + r * Math.cos(k * Math.PI / 8), y + r * Math.sin(k * Math.PI / 8)));
        return o;
    }
    MShape { id: sh }
    function build() {
        const styles = [], geo = [];
        // la figura anterior se apaga en el primer tiempo de la nueva
        const fade = 1 - E.inQuad(E.clamp01(u * 8));
        if (fade > 0.001)
            figure(styles, geo, (phrase + 3) % 4, 1, 0.8 * fade, false);
        else
            for (let b = 0; b < nk; b++) { styles.push({ w: 0 }); geo.push([]); }
        const head = figure(styles, geo, phrase, u, 1, phrase === 3 && drop);
        // la pluma
        const beatHot = 1 - E.outQuad(bp);
        styles.push({ w: 0, f: E.col(colour, 0.18) });
        geo.push([disc(head.x, head.y, span * (0.02 + 0.02 * beatHot))]);
        styles.push({ w: 0, f: E.col(hot, 0.9) });
        geo.push([disc(head.x, head.y, span * (0.007 + 0.008 * beatHot))]);
        sh.styles = styles;
        sh.geo = geo;
    }
    onFrame: build()
}
