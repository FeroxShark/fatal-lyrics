// pipes — el salvapantallas "Tuberías 3D" de Windows 95, al compás.
//
// Ocho caños crecen por una grilla 3D sin chocarse: dos nuevos en cada frase
// de dos compases (el segundo, más corto) (tiempos 0, 8, 16 y 24 del loop), cuatro tramos por tiempo
// (semicorcheas), y en cada codo una bocha. La cámara orbita despacio (±14°,
// una ida y vuelta por loop) y se acerca y se aleja una vez por loop: la deriva
// uniforme de Motion. En el último tiempo del loop la pantalla se LIMPIA como la
// del salvapantallas: fogonazo y apagado, y el loop arranca vacío. Qué hace con
// cada señal (es un `ThumpBase`: el mismo feed de ritmo que membrana o cascada):
//   · tiempo (`beatN` + `bp`) — el largo de los caños es el compás (tramos por
//     semicorchea); el tramo que nace en el tiempo prende su bocha en `hot`; los
//     codos de los tiempos laten al pasar; un collar de cromo cada tiempo
//   · bombo (`thump`) — el tubo ENGORDA con el resorte de `Thump.js` (calmo:
//     blando y largo, agitado: seco), la imagen rebota, y cada golpe lanza desde
//     la raíz de cada caño un PAQUETE de luz que corre hasta la punta (velocidad
//     fija: el audio mueve amplitud, nunca velocidad); en el piso sale un aro
//   · agudos (`fizz`) — destellos en cruz que centellean en los codos
//   · `drop` — todos los codos laten en cada tiempo y el cromo se enciende
//   · `low` — el brillo del caño
//
// Los caños salen de `seed` (un recorrido distinto por aparición), calculados
// una vez; cada cuadro sólo proyecta y dibuja los tramos que ya nacieron.
//
// Cada tramo es un cilindro: CINCO trazos apilados de la misma polilínea, cada
// uno más fino y corrido hacia la luz (arriba a la izquierda): rebote de luz en
// el borde, sombra, cuerpo, luz y brillo. Los corrimientos son
// proporcionales a lo que sobra de grosor, así ningún trazo interior se sale
// del exterior. Los codos son esferas con los mismos tonos. Se ordena por capas
// de profundidad TRAMO a tramo, no por recta entera: una recta larga promediaba
// su profundidad y los caños de atrás tapaban a los de adelante. La niebla lleva
// lo lejano hacia el fondo. Abajo, una grilla de piso (muy tenue) da la
// profundidad que le faltaba al negro.
//
// PARED (`docs/PARED.md`): con lienzo común la grilla toma la forma del lienzo (7 casillas por
// lado corto de pantalla, como sola), nacen más caños por frase, todo se proyecta en px de
// lienzo y cada pantalla corta su ventana (`wallWin`): lo que cae afuera no se arma. El aro del
// piso sale debajo del foco.
//
// Costo en el overlay: un `MShape` con 5 capas × (4 paletas × 5 tonos + 11) +
// el piso; sólo cambia la geometría por cuadro. Dos caños comparten paleta
// (k y k+4): el estilo es de la paleta, no del caño.
import QtQuick
import "../Ease.js" as E
import "../Thump.js" as T

ThumpBase {
    id: m
    // pared con la letra en una pantalla: movimiento con dirección: el mundo sigue por detrás de la letra (`Wall.fit`)
    wallFit: "behind"

    readonly property int steps: 4            // tramos por tiempo
    readonly property int beatsPerPipe: 8
    readonly property var dims: walled
        ? [E.clamp(Math.round(7 * wallArea.x / span), 5, 30), E.clamp(Math.round(7 * wallArea.y / span), 5, 30), 6]
        : portrait ? [7, 12, 6] : [12, 7, 6]
    // caños que nacen por frase: 2 en una pantalla, más en una grilla de pared más grande
    readonly property int perPhrase: walled ? E.clamp(Math.round(dims[0] * dims[1] / 42), 2, 6) : 2
    // la posición dentro del loop, en tiempos (0..32)
    readonly property real q: E.wrap(beatN, 32) + bp

    // ---- el recorrido, una vez por semilla ----------------------------------
    readonly property var pipes: build(seed, dims, perPhrase)
    function build(sd, d, per) {
        let r = Math.floor(sd * 1e6) + 11;
        const rnd = () => { r = (r * 1103515245 + 12345) % 2147483648; return r / 2147483648; };
        const used = {};
        const key = p => p[0] + "," + p[1] + "," + p[2];
        const inside = p => p[0] >= 0 && p[1] >= 0 && p[2] >= 0 && p[0] < d[0] && p[1] < d[1] && p[2] < d[2];
        const dirs = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
        const out = [];
        const n = 32 / beatsPerPipe * per;
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
            const len = (k % 2 ? beatsPerPipe * steps / 2 : beatsPerPipe * steps) - (k >= n - per ? steps : 0);
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
            // de a `per` por frase (dos en una pantalla), cada uno medio tiempo después del anterior
            out.push({ pts: pts, born: Math.floor(k / per) * beatsPerPipe + (k % per) * 0.5, grp: k % nGrp });
        }
        return out;
    }

    function mixc(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    // ---- el dibujo: `MShape` (placa de video) --------------------------------
    //
    // El Canvas con un degradé por tramo costaba ~40 ms por cuadro. Acá el
    // cilindro son CINCO trazos apilados de la misma polilínea (`tones`): como la
    // luz es fija en pantalla, sirve para cualquier dirección del caño, y visto
    // de punta el trazo redondo es la tapa. Las bochas son anillos chiquitos con
    // el mismo trazo grueso (sin relleno: un relleno taparía el codo de un caño
    // que dobla), que el grosor cierra en disco.
    //
    // El orden: la profundidad se corta en `slabs` capas y se dibuja de atrás
    // hacia adelante; adentro de una capa, paleta por paleta. Lo de adelante tapa
    // a lo de atrás tramo a tramo, como en el Canvas ordenado. La niebla va por capa.
    // cada aparición: caños más finos o más gordos y la cámara más o menos inquieta
    readonly property real thick: 0.3 + 0.1 * E.hash(seed * 4.3 + 0.9)
    readonly property real orbit: 0.14 + 0.18 * E.hash(seed * 6.7 + 0.5)
    readonly property int slabs: 5
    readonly property int nPipes: 32 / beatsPerPipe * perPhrase
    readonly property int nGrp: 4                       // paletas de caño
    // grosor relativo de cada tono y cuánto se corre hacia la luz (en diámetros)
    readonly property var tones: [1, 0.88, 0.64, 0.36, 0.13]
    readonly property int nT: 5
    readonly property real litX: -0.5                   // la luz: arriba a la izquierda
    readonly property real litY: -0.86
    readonly property real litK: 0.6
    // cuántos estilos tiene cada capa: nGrp paletas + collares + bochas calientes + destello
    readonly property int perSlab: (nGrp + 2) * nT + 1
    readonly property int fx: 6                         // estilos del piso (2 de grilla, 4 de aro) van ANTES
    // el matiz de cada paleta (<0: oscurece; >0: tira al `hot`)
    readonly property var shades: [0.0, 0.55, -1.0, 0.3]
    property string styleKey: ""
    property string colCacheKey: ""
    property var colCache: null
    property real clearFlash: 0
    property real pipesAlpha: 1

    // el golpe: envolvente del bombo (engorda el tubo) y rebote (la imagen)
    readonly property real kAmp: 0.5 + 0.7 * temper
    readonly property real kenv: E.clamp01(T.envSum(phys, clock, hitT, hitA) * phys.norm) * kAmp

    MShape { id: sh; opacity: m.pipesAlpha }
    Rectangle {
        anchors.fill: parent
        color: m.hot
        opacity: 0.35 * m.clearFlash
        visible: m.clearFlash > 0
    }

    readonly property var circ: [10, 16, 26].map(n => {
        const c = [];
        for (let k = 0; k <= n; k++) c.push([Math.cos(k * 2 * Math.PI / n), Math.sin(k * 2 * Math.PI / n)]);
        return c;
    })
    function disc(x, y, r) {
        r = Math.max(0.5, r);
        const c = circ[r < 6 ? 0 : r < 16 ? 1 : 2];
        const o = [];
        for (let k = 0; k < c.length; k++)
            o.push(Qt.point(x + r * c[k][0], y + r * c[k][1]));
        return o;
    }

    function draw() {
        const d = dims;
        // la limpieza: fogonazo en el tiempo 31 y apagado hasta el 32
        const clearP = q >= 31 ? q - 31 : 0;
        pipesAlpha = q >= 31 ? 1 - E.inQuad(clearP) : 1;
        const flash = q >= 31 ? 1 - E.outQuad(Math.min(1, clearP * 3)) : 0;
        clearFlash = flash;
        // cámara: órbita de ±14° en yaw, cabeceo que deja ver el piso, y un
        // acercarse y alejarse por loop (el zoom se cuantiza: ancha los trazos)
        const ph = 2 * Math.PI * lt / loopS;
        const yaw = orbit * Math.sin(ph);
        const pitch = 0.13 + 0.06 * Math.sin(ph * 2 + 1);
        const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
        const D = Math.max(d[0], d[1]) * 2.2;
        const zoomC = 1 + 0.05 * Math.sin(ph + 2.1);
        const zoom = Math.round(zoomC * 50) / 50;
        // en px de lienzo y pasado a esta pantalla: p = (p_lienzo - ventana) · kz (sin pared,
        // ventana = la pantalla y kz = 1). `kz` es el tirón del motivo, que en pared va acá.
        const win = wallWin, kz = win.w > 0 ? width / win.w : 1;
        const kzq = walled ? Math.round(kz * 50) / 50 : 1;     // para los grosores: se cuantiza como `zoom`
        const f = Math.min(wallArea.x / d[0], wallArea.y / d[1]) * D * 0.8 * zoomC * kz;
        // el rebote del bombo: el resorte (sube, se pasa, vuelve) empuja la imagen para abajo
        const kpos = T.sum(phys, clock, hitT, hitA, 0) * kAmp;
        const bounce = span * 0.012 * kpos;
        const cxS = (wallArea.x / 2 - win.x) * kz, cyS = (wallArea.y * 0.47 + bounce - win.y) * kz;
        const proj = (x, y, z) => {
            const x2 = x * cy + z * sy, z2 = -x * sy + z * cy;
            const y2 = y * cp - z2 * sp, z3 = y * sp + z2 * cp;
            const zz = z3 + D;
            return [cxS + f * x2 / zz, cyS + f * y2 / zz, zz];
        };
        const cx0 = (d[0] - 1) / 2, cy0 = (d[1] - 1) / 2, cz0 = (d[2] - 1) / 2;
        const node = p => proj(p[0] - cx0, p[1] - cy0, p[2] - cz0);
        const zNear = D - d[2] * 0.7, zFar = D + d[2] * 0.7;
        // capa 0 = la más lejana (se dibuja primero)
        const slabOf = z => slabs - 1 - Math.min(slabs - 1, Math.max(0, Math.floor((z - zNear) / (zFar - zNear) * slabs)));
        const zOf = L => zNear + (slabs - 1 - L + 0.5) / slabs * (zFar - zNear);
        const kq = Math.round(kenv * 6) / 6;
        const R = thick * (1 + 0.16 * kq);
        const bright = 0.8 + 0.22 * low + 0.1 * kq + 0.12 * dropAmt;
        const beatHot = dropAmt * (1 - E.outQuad(bp));
        const geo = [];
        for (let t = 0; t < fx + slabs * perSlab; t++) geo.push([]);
        const base0 = L => fx + L * perSlab;
        const fW = f / zoomC * zoom / kz * kzq;
        // pared: lo que cae fuera de esta pantalla no se arma (los codos sí se anotan: los
        // destellos los sortean igual en todas las pantallas)
        const cullM = 3 * f * R / zNear;
        const off = pts => {
            if (!walled) return false;
            let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
            for (const p of pts) {
                x0 = Math.min(x0, p[0]); x1 = Math.max(x1, p[0]);
                y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]);
            }
            return x1 < -cullM || y1 < -cullM || x0 > width + cullM || y0 > height + cullM;
        };
        const W = L => 2 * fW * R / zOf(L);
        // un tono de una capa: la polilínea corrida hacia la luz. `wm` = grosor extra (collares)
        const put = (idx, w, pts, wm) => {
            if (off(pts)) return;
            for (let j = 0; j < nT; j++) {
                const sh0 = (1 - tones[j]) * 0.5 * litK * w * wm;
                const ox = litX * sh0, oy = litY * sh0;
                geo[idx + j].push(pts.map(p => Qt.point(p[0] + ox, p[1] + oy)));
            }
        };
        const tube = (L, g, pts) => put(base0(L) + g * nT, W(L), pts, 1);
        const COLLAR = nGrp * nT, HOT = (nGrp + 1) * nT, GLINT = (nGrp + 2) * nT;
        // una bocha de radio relativo `rMul` (1 = el del caño): círculos concéntricos corridos hacia la luz
        const ball = (L, g, p, rMul, isHot) => {
            if (off([p])) return;
            const w = W(L), rb = f * R * rMul / p[2];
            const idx = base0(L) + (isHot ? HOT : g * nT);
            for (let j = 0; j < nT; j++) {
                const wj = tones[j] * w;
                const sh0 = (1 - tones[j]) * rb * litK;
                const r = rb * tones[j] - wj / 2;
                geo[idx + j].push(disc(p[0] + litX * sh0, p[1] + litY * sh0, r));
            }
        };
        // ---- el piso: grilla tenue y los aros del bombo ----
        const fy = cy0 + 0.95;
        const gx0 = -cx0 - 2, gx1 = cx0 + 2, gz0 = -cz0 - 2.5, gz1 = cz0 + 2.5;
        // el aro sale debajo del foco (sin pared, el foco es el medio: x = 0)
        const rx = E.clamp((wallFocus.x - wallArea.x / 2) * kz * D / f, gx0, gx1);
        for (let x = Math.ceil(gx0 - 0.5); x <= gx1 + 0.5; x++)
            geo[1].push([proj(x, fy, gz0), proj(x, fy, gz1)].map(p => Qt.point(p[0], p[1])));
        for (let z = Math.ceil(gz0 - 0.5); z <= gz1 + 0.5; z++)
            geo[0].push([proj(gx0, fy, z), proj(gx1, fy, z)].map(p => Qt.point(p[0], p[1])));
        for (let i = 0; i < hitT.length; i++) {
            const age = clock - hitT[i];
            if (age < 0 || age > 1.1 || hitA[i] < 0.12) continue;
            const rr = 0.8 + age * 7;
            const ring = [];
            for (let k = 0; k <= 48; k++) {
                const a = k * Math.PI / 24;
                const p = proj(rx + rr * Math.cos(a) * 1.3, fy, rr * Math.sin(a));
                ring.push(Qt.point(p[0], p[1]));
            }
            geo[2 + Math.min(3, Math.floor(age / 0.28))].push(ring);
        }
        // ---- los caños ----
        const elbows = [];                // [pos, capa] de los codos ya crecidos: los destellos eligen entre ellos
        for (let pi = 0; pi < pipes.length && pi < nPipes; pi++) {
            const pp = pipes[pi];
            const g = pp.grp;
            const grown = (q - pp.born) * steps;
            if (grown <= 0) continue;
            const P = pp.pts.map(node);
            const bornAgo = (q - pp.born) * beatS;
            const h0 = Math.exp(-bornAgo / 0.25);
            ball(slabOf(P[0][2]), g, P[0], 1.25 * (1 + (drop ? 0.5 : 0.25) * Math.exp(-bornAgo / 0.18)), h0 > 0.3);
            const n = Math.min(pp.pts.length - 1, Math.ceil(grown));
            // los tramos seguidos de la misma capa van en una sola polilínea
            let run = null, runL = -1;
            const flush = () => { if (run && run.length > 1) tube(runL, g, run); run = null; };
            for (let s = 0; s < n; s++) {
                const k = Math.min(1, grown - s);
                const a = P[s], b0 = P[s + 1];
                const b = k >= 1 ? b0 : [E.mix(a[0], b0[0], k), E.mix(a[1], b0[1], k), E.mix(a[2], b0[2], k)];
                const L = slabOf((a[2] + b[2]) / 2);
                if (L !== runL) { flush(); run = [a]; runL = L; }
                run.push(b);
                if (k < 1) {
                    // la punta que crece: una bocha que brilla
                    ball(slabOf(b[2]), g, b, 1.15, true);
                    continue;
                }
                if (s + 2 < pp.pts.length && s + 1 < grown) {
                    const u = pp.pts[s], v = pp.pts[s + 1], w = pp.pts[s + 2];
                    const turn = (v[0] - u[0]) !== (w[0] - v[0]) || (v[1] - u[1]) !== (w[1] - v[1]) || (v[2] - u[2]) !== (w[2] - v[2]);
                    const nb = slabOf(b0[2]);
                    if (turn) {
                        // el codo que cae en un tiempo late
                        const onBeat = (s + 1) % steps === 0;
                        const ago = (q - pp.born - (s + 1) / steps) * beatS;
                        const h = (onBeat ? Math.exp(-ago / 0.2) : 0) + 0.8 * beatHot;
                        ball(nb, g, b0, 1.12 * (1 + 0.1 * kq), h > 0.3);
                        elbows.push([b0, nb]);
                    } else if ((s + 1) % steps === 0) {
                        // el collar de cromo: un tramito más gordo, a lo largo del caño, una vez por tiempo
                        const c = P[s + 2];
                        const len = Math.hypot(c[0] - a[0], c[1] - a[1]) || 1;
                        const hl = W(nb) * 0.26 / len;
                        const dx = (c[0] - a[0]) * hl, dy = (c[1] - a[1]) * hl;
                        put(base0(nb) + COLLAR, W(nb), [[b0[0] - dx, b0[1] - dy], [b0[0] + dx, b0[1] + dy]], 1.2);
                    }
                }
            }
            flush();
            // los paquetes de luz del bombo: salen de la raíz y corren hasta la punta
            const last = pp.pts.length - 1;
            for (let i = 0; i < hitT.length; i++) {
                const age = clock - hitT[i];
                if (age < 0 || age > 1.8 || hitA[i] < 0.12) continue;
                const pos = age * 11;
                if (pos > Math.min(last, grown - 1)) continue;
                const s = Math.floor(pos), k = pos - s;
                const a = P[s], b = P[s + 1];
                const pt = [E.mix(a[0], b[0], k), E.mix(a[1], b[1], k), E.mix(a[2], b[2], k)];
                ball(slabOf(pt[2]), g, pt, (1.05 + 0.3 * hitA[i]) * (1 - 0.5 * age / 1.8), true);
            }
        }
        // los agudos: destellos en cruz sobre codos que cambian ~9 veces por segundo
        if (elbows.length > 0 && fizz > 0.05) {
            const nG = Math.min(4, Math.round(1 + 4 * fizz));
            const stepK = Math.floor(clock * 9);
            for (let i = 0; i < nG; i++) {
                const e = elbows[Math.floor(E.hash(stepK * 13.7 + i * 3.1 + seed) * elbows.length)];
                const gl = f * R / e[0][2] * (0.9 + 1.1 * fizz);
                const x = e[0][0] + litX * f * R / e[0][2] * 0.5, y = e[0][1] + litY * f * R / e[0][2] * 0.5;
                const idx = base0(e[1]) + GLINT;
                geo[idx].push([Qt.point(x - gl, y), Qt.point(x + gl, y)]);
                geo[idx].push([Qt.point(x, y - gl), Qt.point(x, y + gl)]);
                geo[idx].push([Qt.point(x - gl * 0.45, y - gl * 0.45), Qt.point(x + gl * 0.45, y + gl * 0.45)]);
                geo[idx].push([Qt.point(x - gl * 0.45, y + gl * 0.45), Qt.point(x + gl * 0.45, y - gl * 0.45)]);
            }
        }
        // Los estilos son dos cosas: los colores (cambian con el esquema, el brillo, la
        // limpieza o el drop; los llamados a Qt.darker/lighter son lo caro) y los grosores
        // (cambian con el engorde del bombo y el zoom). Los colores se cachean aparte.
        const colKey = [colour, hot, bg, Math.round(bright * 20), Math.round(flash * 10), Math.round(dropAmt * 10)].join("|");
        if (colKey !== colCacheKey) {
            const cc = [], fr = [], ly = [], mn = [];
            const add = (c, f, L, m0) => { cc.push(c); fr.push(f); ly.push(L); mn.push(m0 || 0); };
            // el piso: grilla tenue (las líneas en z un poco más) y cuatro brillos para el aro
            add(mixc(bg, colour, 0.26), 1.2, -1);
            add(mixc(bg, colour, 0.17), 1.2, -1);
            for (let k = 0; k < 4; k++)
                add(mixc(bg, hot, [0.55, 0.38, 0.24, 0.12][k]), 2.2, -1);
            const white = Qt.rgba(1, 1, 1, 1);
            for (let L = 0; L < slabs; L++) {
                const fog = 0.5 * E.clamp01((zOf(L) - zNear) / (zFar - zNear));
                // los cinco tonos de una paleta: rebote, sombra, cuerpo, luz, brillo
                const toneHot = (c0, j) => {
                    const c = mixc(flash > 0 ? Qt.tint(c0, Qt.rgba(hot.r, hot.g, hot.b, flash)) : c0, bg, fog * 0.5);
                    switch (j) {
                    case 0: return mixc(Qt.darker(c, 1.5), hot, 0.2);
                    case 1: return Qt.darker(c, 2.0);
                    case 2: return Qt.lighter(c, 1.2 * bright);
                    case 3: return mixc(c, white, 0.55);
                    default: return white;
                    }
                };
                const tone = (c0, j) => {
                    const c = mixc(flash > 0 ? Qt.tint(c0, Qt.rgba(hot.r, hot.g, hot.b, flash)) : c0, bg, fog);
                    switch (j) {
                    case 0: return mixc(Qt.darker(c, 1.6), hot, 0.16);
                    case 1: return Qt.darker(c, 2.4);
                    case 2: return Qt.lighter(c, 1.05 * bright);
                    case 3: return Qt.lighter(c, 1.45 * bright);
                    default: return mixc(c, white, 0.72 * bright);
                    }
                };
                const push = (c0, wm, glow) => {
                    for (let j = 0; j < nT; j++)
                        add(glow ? toneHot(c0, j) : tone(c0, j), tones[j] * wm, L);
                };
                for (let g = 0; g < nGrp; g++) {
                    const s0 = shades[g];
                    push(s0 < 0 ? Qt.darker(colour, 1 - s0) : Qt.tint(colour, Qt.rgba(hot.r, hot.g, hot.b, s0)), 1);
                }
                // el cromo: más claro y tirando al `hot`, y se enciende en el drop
                push(Qt.tint(colour, Qt.rgba(hot.r, hot.g, hot.b, 0.2 + 0.5 * dropAmt)), 1.3);
                push(Qt.tint(colour, Qt.rgba(hot.r, hot.g, hot.b, 0.7)), 1, true);
                add(mixc(hot, white, 0.6), 0.09, L, 1.4);
            }
            colCache = { cc: cc, fr: fr, ly: ly, mn: mn };
            colCacheKey = colKey;
            styleKey = "";
        }
        const wKey = [kq, zoom, kzq, width, height].join("|");
        if (wKey !== styleKey) {
            const cs = colCache, st = [];
            const wL = [];
            for (let L = 0; L < slabs; L++) wL.push(W(L));
            for (let i = 0; i < cs.cc.length; i++)
                st.push({ w: cs.ly[i] < 0 ? cs.fr[i] : Math.max(cs.mn[i], cs.fr[i] * wL[cs.ly[i]]), c: cs.cc[i] });
            sh.styles = st;
            styleKey = wKey;
        }
        sh.geo = geo;
    }
    onFrame: draw()
}
