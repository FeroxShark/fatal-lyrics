// pipes — el salvapantallas "Tuberías 3D" de Windows 95, al compás.
//
// Ocho caños crecen por una grilla 3D sin chocarse: dos nuevos en cada frase
// de dos compases (el segundo, más corto) (tiempos 0, 8, 16 y 24 del loop), cuatro tramos por tiempo
// (semicorcheas), y en cada codo una bocha. La cámara orbita despacio (±14°,
// una ida y vuelta por loop): la deriva uniforme de Motion. En el último
// tiempo del loop la pantalla se LIMPIA como la del salvapantallas: fogonazo y
// apagado, y el loop arranca vacío. Lo que suena:
//   · `tick`: el largo de los caños es el compás (tramos por semicorchea); el
//     tramo que nace en el tiempo prende su bocha en `hot`
//   · `drop`: el caño del drop entra con una bocha grande y todos los codos
//     laten en cada tiempo
//   · `low`: el brillo del caño (el bombo lo levanta)
//
// Los caños salen de `seed` (un recorrido distinto por aparición), calculados
// una vez; cada cuadro sólo proyecta y dibuja los tramos que ya nacieron.
//
// Cada tramo es un cilindro (tres trazos apilados corridos hacia la luz,
// arriba a la izquierda, como el de Win95) y los codos esferas con los mismos
// tonos. Se ordena por capas de profundidad TRAMO a tramo, no por recta entera:
// una recta larga promediaba su profundidad y los caños de atrás tapaban a los
// de adelante. La niebla lleva lo lejano hacia el fondo.
//
// Costo en el overlay: un `MShape` con 5 capas × (8 caños × 3 tonos + 3), sólo
// cambia la geometría por cuadro.
import QtQuick
import "../Ease.js" as E

MotifBase {
    id: m

    readonly property int steps: 4            // tramos por tiempo
    readonly property int beatsPerPipe: 8
    readonly property var dims: portrait ? [7, 12, 6] : [12, 7, 6]
    // la posición dentro del loop, en tiempos (0..32)
    readonly property real q: E.wrap(beatN, 32) + bp

    // ---- el recorrido, una vez por semilla ----------------------------------
    readonly property var pipes: build(seed, dims)
    function build(sd, d) {
        let r = Math.floor(sd * 1e6) + 11;
        const rnd = () => { r = (r * 1103515245 + 12345) % 2147483648; return r / 2147483648; };
        const used = {};
        const key = p => p[0] + "," + p[1] + "," + p[2];
        const inside = p => p[0] >= 0 && p[1] >= 0 && p[2] >= 0 && p[0] < d[0] && p[1] < d[1] && p[2] < d[2];
        const dirs = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
        const out = [];
        const n = 32 / beatsPerPipe * 2;
        for (let k = 0; k < n; k++) {
            let p;
            for (let tries = 0; tries < 50; tries++) {
                p = [Math.floor(rnd() * d[0]), Math.floor(rnd() * d[1]), Math.floor(rnd() * d[2])];
                if (!used[key(p)]) break;
            }
            used[key(p)] = true;
            let dir = dirs[Math.floor(rnd() * 6)];
            const pts = [p];
            // el último caño deja libre el último tiempo: es el de la limpieza
            // el segundo de cada frase es la mitad de largo: la pantalla no se
            // tapa entera antes de la limpieza
            const len = (k % 2 ? beatsPerPipe * steps / 2 : beatsPerPipe * steps) - (k >= n - 2 ? steps : 0);
            for (let s = 0; s < len; s++) {
                const opts = [];
                for (const dd of dirs) {
                    const np = [p[0] + dd[0], p[1] + dd[1], p[2] + dd[2]];
                    if (inside(np) && !used[key(np)])
                        opts.push({ d: dd, w: dd === dir ? 5 : 1 });
                }
                if (opts.length === 0) break;       // encerrado: el caño termina ahí
                let tot = 0;
                for (const o of opts) tot += o.w;
                let pick = rnd() * tot;
                for (const o of opts) { pick -= o.w; if (pick <= 0) { dir = o.d; break; } }
                p = [p[0] + dir[0], p[1] + dir[1], p[2] + dir[2]];
                used[key(p)] = true;
                pts.push(p);
            }
            // de a dos por frase; el segundo sale medio tiempo después
            out.push({ pts: pts, born: Math.floor(k / 2) * beatsPerPipe + (k % 2) * 0.5,
                       shade: [0.0, 0.55, -1, 0.3, -0.5, 0.8, 0.15, -1.3][k % 8] });
        }
        return out;
    }

    function mixc(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    // ---- el dibujo: `MShape` (placa de video) --------------------------------
    //
    // El Canvas con un degradé por tramo costaba ~40 ms por cuadro. Acá el
    // cilindro son TRES trazos apilados de la misma polilínea, cada uno más
    // fino y corrido hacia la luz (arriba a la izquierda): borde oscuro, cuerpo
    // y brillo. Como la luz es fija en pantalla, sirve para cualquier dirección
    // del caño, y visto de punta el trazo redondo es la tapa. Las bochas son
    // anillos chiquitos con el mismo trazo grueso (sin relleno: un relleno
    // taparía el codo de un caño que dobla), que el grosor cierra en disco.
    //
    // El orden: la profundidad se corta en `slabs` capas y se dibuja de atrás
    // hacia adelante; adentro de una capa, caño por caño. Lo de adelante tapa a
    // lo de atrás tramo a tramo, como en el Canvas ordenado. La niebla va por capa.
    // cada aparición: caños más finos o más gordos y la cámara más o menos inquieta
    readonly property real thick: 0.3 + 0.1 * E.hash(seed * 4.3 + 0.9)
    readonly property real orbit: 0.14 + 0.18 * E.hash(seed * 6.7 + 0.5)
    readonly property int slabs: 5
    readonly property int nPipes: 8
    // [grosor relativo, corrimiento x, y (en diámetros)] de cada tono
    readonly property var layers: [[1, 0, 0], [0.72, -0.08, -0.1], [0.26, -0.16, -0.2]]
    property string styleKey: ""
    property real clearFlash: 0
    property real pipesAlpha: 1

    MShape { id: sh; opacity: m.pipesAlpha }
    Rectangle {
        anchors.fill: parent
        color: m.hot
        opacity: 0.35 * m.clearFlash
        visible: m.clearFlash > 0
    }

    function disc(x, y, r) {
        const o = [];
        r = Math.max(0.5, r);
        for (let k = 0; k <= 12; k++)
            o.push(Qt.point(x + r * Math.cos(k * Math.PI / 6), y + r * Math.sin(k * Math.PI / 6)));
        return o;
    }

    function draw() {
        const d = dims;
        // la limpieza: fogonazo en el tiempo 31 y apagado hasta el 32
        const clearP = q >= 31 ? q - 31 : 0;
        pipesAlpha = q >= 31 ? 1 - E.inQuad(clearP) : 1;
        const flash = q >= 31 ? 1 - E.outQuad(Math.min(1, clearP * 3)) : 0;
        clearFlash = flash;
        // cámara: órbita de ±14° en yaw y ±6° en pitch, una vuelta por loop
        const yaw = orbit * Math.sin(2 * Math.PI * lt / loopS);
        const pitch = 0.1 * Math.sin(2 * Math.PI * lt / loopS * 2 + 1);
        const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
        const D = Math.max(d[0], d[1]) * 2.2;
        const f = Math.min(width / d[0], height / d[1]) * D * 0.8;
        const proj = p => {
            let x = p[0] - (d[0] - 1) / 2, y = p[1] - (d[1] - 1) / 2, z = p[2] - (d[2] - 1) / 2;
            let x2 = x * cy + z * sy, z2 = -x * sy + z * cy;
            let y2 = y * cp - z2 * sp, z3 = y * sp + z2 * cp;
            const zz = z3 + D;
            return [width / 2 + f * x2 / zz, height / 2 + f * y2 / zz, zz];
        };
        const zNear = D - d[2] * 0.7, zFar = D + d[2] * 0.7;
        // capa 0 = la más lejana (se dibuja primero)
        const slabOf = z => slabs - 1 - Math.min(slabs - 1, Math.max(0, Math.floor((z - zNear) / (zFar - zNear) * slabs)));
        const zOf = L => zNear + (slabs - 1 - L + 0.5) / slabs * (zFar - zNear);
        const R = thick;
        const bright = 0.8 + 0.25 * low;
        const white = Qt.rgba(1, 1, 1, 1);
        const beatHot = drop ? 1 - E.outQuad(bp) : 0;
        const per = nPipes * 3 + 3;           // tandas por capa: 3 por caño + 3 de bochas calientes
        const geo = [];
        for (let t = 0; t < slabs * per; t++) geo.push([]);
        // un tono de una capa: la polilínea corrida hacia la luz
        const W = L => 2 * f * R / zOf(L);
        const tube = (L, pi, pts) => {
            const w = W(L);
            for (let j = 0; j < 3; j++) {
                const ox = layers[j][1] * w, oy = layers[j][2] * w;
                geo[L * per + pi * 3 + j].push(pts.map(p => Qt.point(p[0] + ox, p[1] + oy)));
            }
        };
        const ball = (L, pi, p, rMul, isHot) => {
            const w = W(L), rb = f * R * rMul / p[2];
            for (let j = 0; j < 3; j++) {
                const k = rb / (w / 2);
                const ox = layers[j][1] * w * k, oy = layers[j][2] * w * k;
                const r = rb * [1, 0.78, 0.34][j] - layers[j][0] * w / 2;
                geo[L * per + (isHot ? nPipes * 3 + j : pi * 3 + j)].push(disc(p[0] + ox, p[1] + oy, r));
            }
        };
        for (let pi = 0; pi < pipes.length && pi < nPipes; pi++) {
            const pp = pipes[pi];
            const grown = (q - pp.born) * steps;
            if (grown <= 0) continue;
            const P = pp.pts.map(proj);
            const bornAgo = (q - pp.born) * beatS;
            const h0 = Math.exp(-bornAgo / 0.25);
            ball(slabOf(P[0][2]), pi, P[0], 1.15 * (1 + (drop ? 0.5 : 0.25) * Math.exp(-bornAgo / 0.18)), h0 > 0.3);
            const n = Math.min(pp.pts.length - 1, Math.ceil(grown));
            // los tramos seguidos de la misma capa van en una sola polilínea
            let run = null, runL = -1;
            const flush = () => { if (run && run.length > 1) tube(runL, pi, run); run = null; };
            for (let s = 0; s < n; s++) {
                const k = Math.min(1, grown - s);
                const a = P[s], b0 = P[s + 1];
                const b = k >= 1 ? b0 : [E.mix(a[0], b0[0], k), E.mix(a[1], b0[1], k), E.mix(a[2], b0[2], k)];
                const L = slabOf((a[2] + b[2]) / 2);
                if (L !== runL) { flush(); run = [a]; runL = L; }
                run.push(b);
                if (k < 1) {
                    // la punta que crece: una bocha que brilla
                    ball(slabOf(b[2]), pi, b, 1.0, true);
                    continue;
                }
                if (s + 2 < pp.pts.length && s + 1 < grown) {
                    const u = pp.pts[s], v = pp.pts[s + 1], w = pp.pts[s + 2];
                    const turn = (v[0] - u[0]) !== (w[0] - v[0]) || (v[1] - u[1]) !== (w[1] - v[1]) || (v[2] - u[2]) !== (w[2] - v[2]);
                    if (turn) {
                        // el codo que cae en un tiempo late
                        const onBeat = (s + 1) % steps === 0;
                        const ago = (q - pp.born - (s + 1) / steps) * beatS;
                        const h = (onBeat ? Math.exp(-ago / 0.2) : 0) + 0.8 * beatHot;
                        ball(slabOf(b0[2]), pi, b0, 1.08, h > 0.3);
                    }
                }
            }
            flush();
        }
        // los estilos sólo cambian con el color, el brillo o la limpieza
        const key = [colour, hot, bg, Math.round(bright * 20), Math.round(flash * 10), width, height].join("|");
        if (key !== styleKey) {
            const st = [];
            for (let L = 0; L < slabs; L++) {
                const fog = 0.5 * E.clamp01((zOf(L) - zNear) / (zFar - zNear));
                const tone = (c, j) => {
                    c = mixc(flash > 0 ? Qt.tint(c, Qt.rgba(hot.r, hot.g, hot.b, flash)) : c, bg, fog);
                    return j === 0 ? Qt.darker(c, 2.6) : j === 1 ? Qt.lighter(c, 1.05 * bright) : mixc(c, white, 0.55 * bright);
                };
                const w = W(L);
                for (let pi = 0; pi < nPipes; pi++) {
                    const sh0 = pipes.length > pi ? pipes[pi].shade : 0;
                    const base = sh0 < 0 ? Qt.darker(colour, 1 - sh0)
                        : Qt.tint(colour, Qt.rgba(hot.r, hot.g, hot.b, sh0));
                    for (let j = 0; j < 3; j++) {
                        const c = tone(base, j);
                        st.push({ w: layers[j][0] * w, c: c });
                    }
                }
                const hb = Qt.tint(colour, Qt.rgba(hot.r, hot.g, hot.b, 0.85));
                for (let j = 0; j < 3; j++) {
                    const c = tone(hb, j);
                    st.push({ w: layers[j][0] * w, c: c });
                }
            }
            sh.styles = st;
            styleKey = key;
        }
        sh.geo = geo;
    }
    onFrame: draw()
}
