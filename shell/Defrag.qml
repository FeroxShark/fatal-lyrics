// defrag — el Desfragmentador de disco de Windows 95 ("Mostrar detalles").
//
// Una grilla de bloques del disco: libres, datos sueltos, datos ya ordenados y
// unos pocos que no se pueden mover. En cada tiempo el desfragmentador LEE un
// tramo del final del disco (parpadea en `hot`) y lo ESCRIBE en el primer
// hueco libre (se llena de izquierda a derecha con el snap de Motion). En 30
// tiempos el disco queda ordenado arriba; en el tiempo 31 se vuelve a
// fragmentar (cada bloque vuelve a su lugar con un destello, escalonado al
// azar) y el loop arranca igual que empezó. Abajo, el renglón de estado del
// programa con el porcentaje. Lo que suena:
//   · `tick`: un movimiento por tiempo — el disco se ordena a tempo, y los
//     bloques VUELAN del final al hueco (se ve el viaje, no sólo el destino)
//   · `low`: en cada tiempo sale una onda desde el cabezal de escritura que
//     recorre el disco; el bajo le da la fuerza
//   · `level`: el brillo de los datos
//   · `high`: los bloques libres titilan con los platillos
//   · `drop`: la onda va en `hot` y llega más lejos
//
// El plan entero (estado inicial y los 30 movimientos) sale de `seed` una vez;
// cada cuadro sólo pinta.
//
// Costo en el overlay: un `MShape` con ~1300 rectángulos en ~47 tandas por
// cuadro, más un renglón de Text/Rectangle.
import QtQuick
import "Ease.js" as E

MotifBase {
    id: m

    readonly property int cols: portrait ? 26 : 60
    readonly property int rows: portrait ? 44 : 22
    readonly property int moves: 30
    readonly property real q: E.wrap(beatN, 32) + bp

    // FREE 0, DATA 1, OPT 2, FIXED 3
    readonly property var plan: makePlan(seed, cols * rows)
    function makePlan(sd, n) {
        let r = Math.floor(sd * 1e6) + 3;
        const rnd = () => { r = (r * 1103515245 + 12345) % 2147483648; return r / 2147483648; };
        const g = new Array(n).fill(0);
        let i = 0;
        while (i < n) {
            const run = 1 + Math.floor(rnd() * 8);
            const used = rnd() < 0.52;
            for (let k = 0; k < run && i < n; k++, i++)
                g[i] = used ? 1 : 0;
        }
        for (let k = 0; k < n * 0.015; k++) g[Math.floor(rnd() * n)] = 3;
        const settle = s => { for (let j = 0; j < n; j++) { if (s[j] === 1) s[j] = 2; else if (s[j] !== 2 && s[j] !== 3) break; } };
        const start = g.slice();
        // cuántos bloques mueve cada tiempo: el menor que termina en 30. Se
        // simula porque muchos bloques quedan en su lugar solos al cerrarse
        // los huecos de adelante (contar los sueltos daba 100 % en el tiempo 12)
        const sim = L => {
            const h = start.slice();
            settle(h);
            const snaps = [h.slice()], mv = [];
            for (let k = 0; k < moves; k++) {
                const src = [], dst = [];
                // los últimos L bloques sueltos del disco (los fragmentos de un
                // archivo, aunque no estén pegados)
                for (let e = n - 1; e >= 0 && src.length < L; e--)
                    if (h[e] === 1) src.push(e);
                let f = h.indexOf(0);
                for (let s = 0; s < src.length; s++) {
                    while (f >= 0 && f < n && h[f] !== 0) f++;
                    if (f < 0 || f >= n || f > src[s]) break;
                    dst.push(f);
                    h[f] = 2;
                    h[src[s]] = 0;
                    f++;
                }
                settle(h);
                mv.push({ src: src.slice(0, dst.length), dst: dst });
                snaps.push(h.slice());
            }
            return { snaps: snaps, moves: mv, done: h.indexOf(1) < 0 };
        };
        let run = null;
        for (let L = 1; L < n; L++) { run = sim(L); if (run.done) break; }
        const snaps = run.snaps, mv = run.moves;
        let used = 0, opt0 = [];
        for (let j = 0; j < n; j++) if (start[j] === 1 || start[j] === 2) used++;
        for (const s of snaps) { let o = 0; for (let j = 0; j < n; j++) if (s[j] === 2) o++; opt0.push(o); }
        // el cabezal: el primer bloque que todavía no está ordenado
        const front = snaps.map(s => { let j = 0; while (j < n && (s[j] === 2 || s[j] === 3)) j++; return j; });
        return { start: start, snaps: snaps, moves: mv, used: used, opt: opt0, front: front };
    }

    readonly property real cell: Math.min(width * 0.88 / cols, height * (portrait ? 0.8 : 0.74) / rows)
    readonly property real gx: (width - cols * cell) / 2
    readonly property real gy: (height - (rows + 3.6) * cell) / 2

    // Por `MShape` (placa de video): el Canvas costaba ~50 ms por cuadro. Los
    // ~1300 bloques van en tandas por color y opacidad (cuantizada a 1/20);
    // el renglón de estado son Text y Rectangle comunes.
    function rectPts(x, y, w, h) {
        return [Qt.point(x, y), Qt.point(x + w, y), Qt.point(x + w, y + h), Qt.point(x, y + h), Qt.point(x, y)];
    }
    // los bloques no se mueven: su rectángulo (y el del punto) se arma una vez
    property var cellRects: []
    property var dotRects: []
    property string rectsFor: ""
    function ensureRects() {
        const key = [cols, rows, cell, gx, gy].join("|");
        if (key === rectsFor) return;
        const c = cell, pad = Math.max(1, c * 0.14), R = [], Dt = [];
        for (let i = 0; i < cols * rows; i++) {
            const x = gx + (i % cols) * c, y = gy + Math.floor(i / cols) * c;
            R.push(rectPts(x + pad, y + pad, c - 2 * pad, c - 2 * pad));
            Dt.push(rectPts(x + c * 0.4, y + c * 0.4, c * 0.2, c * 0.2));
        }
        cellRects = R;
        dotRects = Dt;
        rectsFor = key;
    }
    property real pct: 0
    property bool regragging: false
    MShape { id: sh }
    // tandas: 0..20 color, 21..41 hot (opacidad k/20), 42 los puntos, 43..46 los
    // que vuelan (estela 3..1, cabeza)
    function build() {
        const P = plan, n = cols * rows, c = cell, pad = Math.max(1, c * 0.14);
        const k = Math.floor(q), u = q - k;
        let state, mv = null;
        if (k < moves) {
            state = P.snaps[k];
            mv = P.moves[k];
            pct = E.mix(P.opt[k], P.opt[k + 1], E.outExpo(E.prog(u, 0.35, 0.5))) / P.used;
        } else {
            state = P.snaps[moves];
            pct = P.opt[moves] / P.used;
        }
        regragging = k >= 31;
        // qué pasa con cada bloque que se mueve en este tiempo: se lee
        // (parpadea), VUELA escalonado hasta su hueco y aterriza
        const src = {}, dst = {};
        const fly = [];
        if (mv) {
            const nm = mv.dst.length;
            for (let i = 0; i < mv.src.length; i++) src[mv.src[i]] = true;
            for (let i = 0; i < nm; i++) {
                const st = 0.18 + 0.22 * (nm > 1 ? i / (nm - 1) : 0);
                const f = E.prog(u, st, 0.3);
                dst[mv.dst[i]] = f >= 1;
                if (f > 0 && f < 1) fly.push({ a: mv.src[i], b: mv.dst[i], f: f });
            }
        }
        // la onda del tiempo: sale del cabezal y recorre el disco
        const fr = P.front[Math.min(k, moves)];
        const hx = fr % cols, hy = Math.floor(fr / cols);
        const reach = (drop ? 1.6 : 1.0) * Math.max(cols, rows);
        const waveR = E.outQuad(bp) * reach;
        const waveA = (1 - E.inQuad(bp)) * (0.45 + 0.9 * low) * (drop ? 1.4 : 1.0);
        const bright = 0.7 + 0.4 * level;
        const regrag = k >= 31 ? u : -1;        // el tiempo 31: se desordena de nuevo
        const dropBeat = drop ? 1 - E.outQuad(bp) : 0;
        const readBlink = u < 0.35 && Math.floor(u * 12) % 2 === 0;
        ensureRects();
        const geo = [];
        for (let t = 0; t < 47; t++) geo.push([]);
        const put = (isHot, a, i) => {
            const key = (isHot ? 21 : 0) + Math.round(Math.min(1, Math.max(0, a)) * 20);
            if (key % 21 > 0) geo[key].push(cellRects[i]);
        };
        for (let i = 0; i < n; i++) {
            let s = state[i], flash = 0;
            if (regrag >= 0) {
                const at = E.hash(i * 1.37 + seed) * 0.8;
                if (regrag >= at) {
                    s = P.start[i];
                    flash = Math.exp(-(regrag - at) * beatS / 0.08);
                }
            }
            let col, a, hotC = false;
            if (mv && src[i] && u < 0.18) { col = hot; hotC = true; a = readBlink ? 1 : 0.55; }
            else if (mv && src[i]) { s = 0; col = null; }
            if (mv && dst[i] !== undefined) {
                if (dst[i]) { col = u < 0.75 ? hot : colour; hotC = u < 0.75; a = 1; }
                else { col = null; s = 0; }
            }
            const cx = i % cols, cy = Math.floor(i / cols);
            const d = Math.hypot(cx - hx, (cy - hy) * 1.6);
            const wave = waveA * Math.exp(-Math.abs(d - waveR) / 2.6);
            if (!col) {
                if (s === 0) {
                    const tw = high * E.hash2(i, Math.floor(lt * 20 + 1e-6) % 300);
                    put(false, 0.06 + 0.22 * tw * tw + 0.35 * wave, i);
                    continue;
                }
                hotC = s === 3;
                a = (s === 1 ? 0.38 : s === 2 ? 0.8 + 0.12 * dropBeat : 0.7) * bright;
            }
            const hotWave = drop && wave > 0.35;
            put(flash > 0.02 || hotWave || hotC, Math.max(a + wave, flash), i);
            // no se puede mover: un punto adentro
            if (s === 3)
                geo[42].push(dotRects[i]);
        }
        for (const f of fly) {
            const ax = f.a % cols, ay = Math.floor(f.a / cols);
            const bx = f.b % cols, by2 = Math.floor(f.b / cols);
            for (let tr = 3; tr >= 0; tr--) {
                const e = E.outExpo(Math.max(0, f.f - tr * 0.05));
                // un arco: sube un poco en el medio del viaje
                const lift = Math.sin(Math.PI * e) * c * 1.5;
                const x = gx + E.mix(ax, bx, e) * c, y = gy + E.mix(ay, by2, e) * c - lift;
                geo[46 - tr].push(rectPts(x + pad, y + pad, c - 2 * pad, c - 2 * pad));
            }
        }
        if (sh.styles.length === 0 || stylesFor !== "" + colour + hot + bg) {
            const st = [];
            for (let t = 0; t < 21; t++) st.push({ w: 0, f: E.col(colour, t / 20) });
            for (let t = 0; t < 21; t++) st.push({ w: 0, f: E.col(hot, t / 20) });
            st.push({ w: 0, f: E.col(bg, 1) });
            for (let tr = 3; tr >= 0; tr--) st.push({ w: 0, f: E.col(hot, tr === 0 ? 1 : 0.35 * (1 - tr / 4)) });
            sh.styles = st;
            stylesFor = "" + colour + hot + bg;
        }
        sh.geo = geo;
    }
    property string stylesFor: ""
    onFrame: build()

    // el renglón de estado, como el del programa
    readonly property real barY: gy + rows * cell + cell * 1.2
    readonly property int pctN: Math.floor(E.clamp01(pct) * 100)
    Text {
        x: m.gx; y: m.barY
        text: m.regragging ? "Fragmentando la unidad C..." : "Desfragmentando la unidad C"
        font.family: m.fontFamily; font.pixelSize: Math.max(1, Math.round(m.cell * 1.25))
        color: E.col(m.colour, 0.9)
    }
    Text {
        x: m.gx + m.cols * m.cell - width; y: m.barY
        text: m.pctN + "% completado"
        font.family: m.fontFamily; font.pixelSize: Math.max(1, Math.round(m.cell * 1.25))
        color: E.col(m.colour, 0.9)
    }
    Rectangle {
        id: bar
        x: m.gx; y: m.barY + m.cell * 1.6
        width: m.cols * m.cell; height: m.cell * 0.9
        color: "transparent"
        border.color: E.col(m.colour, 0.6)
        border.width: Math.max(1, m.cell * 0.1)
        // la barra de a bloques, como la de Win95
        Repeater {
            model: 40
            Rectangle {
                required property int index
                readonly property real bw: bar.width / 40
                visible: index < Math.floor(E.clamp01(m.pct) * 40)
                x: index * bw + bw * 0.12; y: m.cell * 0.15
                width: bw * 0.76; height: m.cell * 0.6
                color: E.col(m.colour, 0.95)
            }
        }
    }
}
