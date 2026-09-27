// swarm — una bandada de punteros de Windows 95 que ARMA la palabra que viene.
//
// Tres bandadas de flechitas viajan cada una en formación (un centro que
// pasea, las flechas en un óvalo que respira alrededor, todo periódico en
// 15 s), con profundidad (las chicas van atrás y más tenues) y una estela
// corta. En el primer tiempo de cada
// compás las que hacen falta se clavan en su lugar y escriben `nextWord` en
// matriz de puntos 5×7 (Dots.js): snap OutExpo de 320 ms con un escalonado
// chico, así se lee la bandada llegando, no una palabra que aparece. Tres
// tiempos quietas (el hold largo de Motion) y en el cuarto revientan hacia
// afuera y vuelven a la bandada. Lo que suena:
//   · `tick`: el compás entero es la frase — formar, sostener, soltar
//   · `nextWord`: lo que escriben (la primera palabra de la línea que viene;
//     sin ella, la palabra más larga del verso que suena, y si no, FATAL)
//   · `tick`: en cada tiempo un puñado de la bandada hace CLIC (un anillo que
//     se abre en la punta); `level` decide cuántas
//   · `high` en la subida: la palabra tiembla, cada puntero por su lado
//   · `drop`: la palabra late en cada tiempo (se abre desde su centro y se
//     prende en `hot`) y la bandada de fondo se enciende
//
// Costo en el overlay: un `MShape` con hasta 260 flechas de 7 puntos (+ 2 de
// estela las del fondo), ~8 ms de CPU por cuadro; baja la cuenta con `quality`.
import QtQuick
import "../Ease.js" as E
import "../Dots.js" as D

MotifBase {
    id: m

    readonly property int count: Math.round(260 * quality)
    // la palabra: la que viene; si no hay, la más larga del verso que suena
    readonly property string wordText: {
        if (D.clean(nextWord).length > 0)
            return nextWord;
        const ln = lines && lines.length > 0 && lineNo >= 0 ? D.clean(lines[lineNo % lines.length]) : "";
        let best = "";
        for (const w of ln.split(" "))
            if (w.length > best.length && w.length <= 8) best = w;
        return best.length > 0 ? best : "FATAL";
    }
    readonly property var word: D.cells(wordText, 8)
    readonly property int need: word.pts.length
    // cuántas flechas escriben: dos por punto, así la letra sale gorda
    readonly property int writers: Math.min(count, need * 2)
    readonly property real cell: Math.min(width * 0.84 / word.cols, height * 0.40 / 7)
    readonly property real ox: (width - word.cols * cell) / 2
    readonly property real oy: (height - 7 * cell) / 2
    // dónde va del compás, en tiempos (0..4)
    readonly property real q: E.wrap(beatN, 4) + bp
    readonly property real arrow: Math.max(span * 0.0016, cell * 0.042)

    // la profundidad de cada flecha (0 atrás .. 1 adelante), fija
    function depth(i) { return E.hash(i * 3.17 + 0.5); }
    // de 2 a 4 bandadas (según la aparición); cada flecha en su lugar de un
    // óvalo que respira
    readonly property int flocks: 2 + Math.floor(E.hash(seed * 3.9 + 0.6) * 3)
    readonly property real spread: 0.8 + 0.45 * E.hash(seed * 8.3 + 0.2)
    function wander(i, tt) {
        const P = 3, Q = 5;
        const fl = i % flocks;
        const u = tt / loopS;
        const cx = width / 2 + width * 0.34 * E.pnoise(u * P + fl * 0.31, P, 1 + seed + fl * 5);
        const cy = height / 2 + height * 0.3 * E.pnoise(u * P + 0.5 + fl * 0.17, P, 2 + seed + fl * 7);
        const ang = E.hash(i * 1.7) * 2 * Math.PI + 2 * Math.PI * u * (fl % 2 === 1 ? -1 : 1);
        const rad = span * spread * (0.05 + 0.17 * Math.sqrt(E.hash(i * 2.3 + 1)))
            * (1 + 0.25 * Math.sin(2 * Math.PI * u * 2 + fl));
        return [cx + Math.cos(ang) * rad * 1.35 + span * 0.03 * E.pnoise(u * Q + i * 0.37, Q, i * 1.3),
                cy + Math.sin(ang) * rad + span * 0.03 * E.pnoise(u * Q + i * 0.61, Q, i * 2.1 + 7)];
    }
    function target(i) {
        const p = word.pts[i % need];
        // la segunda flecha del punto va corrida medio casillero
        const k = Math.floor(i / need);
        return [ox + (p.x + 0.12 + 0.34 * k) * cell, oy + (p.y + 0.08 + 0.3 * k) * cell];
    }

    // Por `MShape` (placa de video): el Canvas costaba ~45 ms por cuadro.
    // la flecha de Win95, en su grilla de 12×19, como polilínea cerrada
    function arrowPts(x, y, s) {
        return [Qt.point(x, y), Qt.point(x, y + 16 * s), Qt.point(x + 4 * s, y + 12 * s),
                Qt.point(x + 7 * s, y + 18 * s), Qt.point(x + 9.4 * s, y + 17 * s),
                Qt.point(x + 6.4 * s, y + 11 * s), Qt.point(x + 11.4 * s, y + 11 * s),
                Qt.point(x, y)];
    }
    function ring(x, y, r) {
        const o = [];
        for (let k = 0; k <= 16; k++)
            o.push(Qt.point(x + r * Math.cos(k * Math.PI / 8), y + r * Math.sin(k * Math.PI / 8)));
        return o;
    }
    MShape { id: sh }
    // tandas: por profundidad (4, de atrás para adelante) [estela 2, estela 1,
    // flechas, clics]; después las que escriben (5, según cuánto llegaron)
    function build() {
        const styles = [], geo = [];
        const bs = beatS;
        const wcx = ox + word.cols * cell / 2, wcy = oy + 3.5 * cell;
        const beatHot = drop ? 1 - E.outQuad(bp) : 0;
        const swell = drop && q >= 1 && q < 3 ? 0.07 * (1 - E.outExpo(bp)) : 0;
        const dark = Qt.darker(bg, 1.4);
        const clickN = Math.round((0.04 + 0.12 * level + (drop ? 0.1 : 0)) * count);
        const clickSeed = beatN % 97;
        const NB = 4;
        const byDepth = [];
        for (let b = 0; b < NB; b++) byDepth.push([]);
        for (let i = writers; i < count; i++)
            byDepth[Math.min(NB - 1, Math.floor(depth(i) * NB))].push(i);
        for (let b = 0; b < NB; b++) {
            const list = byDepth[b];
            const dp = (b + 0.5) / NB;
            const sc = arrow * (0.55 + 0.7 * dp);
            const a0 = Math.min(1, 0.22 + 0.5 * dp + 0.2 * dropAmt + 0.15 * beatHot);
            // la estela: la misma bandada unos cuadros antes
            for (let tr = 2; tr >= 1; tr--) {
                const g = [];
                for (const i of list) {
                    const w = wander(i, lt - tr * 0.045);
                    g.push(arrowPts(w[0], w[1], sc));
                }
                styles.push({ w: 0, f: E.col(colour, a0 * 0.18 / tr) });
                geo.push(g);
            }
            const g = [], clicks = [];
            for (const i of list) {
                const w = wander(i, lt);
                g.push(arrowPts(w[0], w[1], sc));
                if (E.hash2(i, clickSeed) * count < clickN) clicks.push(w);
            }
            styles.push({ w: Math.max(1, sc * 0.7), c: E.col(dp > 0.6 ? hot : dark, dp > 0.6 ? 0.5 * a0 : 0.8),
                          f: E.col(colour, a0) });
            geo.push(g);
            // el clic del tiempo
            const cr = sc * (4 + 22 * E.outExpo(bp));
            const rings = [];
            if (bp < 1)
                for (const w of clicks) rings.push(ring(w[0], w[1], cr));
            styles.push({ w: Math.max(1, sc * 1.1), c: E.col(drop ? hot : colour, 0.7 * (1 - bp) * (0.5 + 0.5 * dp)) });
            geo.push(rings);
        }
        // las que escriben, en 5 tandas según cuánto llegaron
        const NL = 5;
        const byLit = [];
        for (let b = 0; b < NL; b++) byLit.push([]);
        for (let i = 0; i < writers && need > 0; i++) {
            const w = wander(i, lt);
            const g = target(i);
            // escalonado: las de la izquierda llegan primero (lectura)
            const stag = (word.pts[i % need].x / Math.max(1, word.cols)) * 0.12;
            let f, burst = 0;
            if (q < 3) {
                f = E.outExpo(E.prog(q * bs, stag, 0.32));
            } else {
                const e = E.outExpo(E.prog((q - 3) * bs, stag * 0.5, 0.42));
                f = 1 - e;
                burst = Math.sin(Math.PI * e) * span * 0.16;
            }
            let tx = g[0] + (g[0] - wcx) * swell, ty = g[1] + (g[1] - wcy) * swell;
            // la subida: cada una tiembla por su lado
            const shake = cell * 0.45 * high * (section === "build" ? 1 : 0.15);
            tx += (E.hash2(i, Math.floor(lt * 30 + 1e-6) % 450) - 0.5) * shake;
            ty += (E.hash2(i + 91, Math.floor(lt * 30 + 1e-6) % 450) - 0.5) * shake;
            const dx = g[0] - wcx, dy = g[1] - wcy, dl = Math.max(1, Math.hypot(dx, dy));
            const lit = f > 0.9 ? 1 : f;
            byLit[Math.min(NL - 1, Math.round(lit * (NL - 1)))].push(
                arrowPts(E.mix(w[0], tx, f) + dx / dl * burst, E.mix(w[1], ty, f) + dy / dl * burst, arrow));
        }
        for (let b = 0; b < NL; b++) {
            const lit = b / (NL - 1);
            styles.push({ w: Math.max(1, arrow * 0.8), c: E.col(lit > 0.9 ? hot : dark, 0.5 + 0.5 * lit),
                          f: E.col(beatHot > 0.3 ? hot : colour, 0.35 + 0.65 * lit) });
            geo.push(byLit[b]);
        }
        sh.styles = styles;
        sh.geo = geo;
    }
    onFrame: build()
}
