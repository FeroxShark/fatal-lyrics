// mystify — el salvapantallas "Mystify Your Mind" de Windows 95, en fósforo.
//
// Dos polígonos de cuatro vértices rebotan contra el borde de la pantalla con
// su estela de ecos. Cada vértice rebota con un número ENTERO de idas y
// vueltas cada 15 s, así la figura entera vuelve a su lugar al cerrar el loop.
// Lo que suena:
//   · el tiempo (`tick`): el polígono de adelante se enciende en `hot` y se
//     apaga en el tiempo; en el drop los dos se pasan el color de golpe en golpe
//   · el golpe del tubo (`surge`): los ecos se ABREN (más separación entre
//     copias) y vuelven a juntarse — se ve el golpe como un latido de la estela
//   · `energy`: cuántos ecos (10 en la estrofa, 22 en el drop)
//   · `drop`: entra un tercer polígono desde el centro, con el snap de Motion
//
// Costo en el overlay: un `MShape` (placa de video) con 15 tandas, 3 × 22
// polilíneas de 4 puntos; ~2 ms de CPU por cuadro.
import QtQuick
import "Ease.js" as E

MotifBase {
    id: m

    readonly property real margin: span * 0.06
    readonly property int echoes: Math.round(E.clamp(8 + 9 * (energy - 0.9) / 0.7 + 4, 10, 22) * quality)
    readonly property real gap: 0.045 * gapMul * (1 + 1.6 * surge)
    readonly property int polys: drop || dropAmt > 0 ? 3 : 2
    // cada aparición es otra: de 3 a 6 vértices y la estela más o menos abierta
    readonly property int nv: 3 + Math.floor(E.hash(seed * 5.13 + 0.7) * 4)
    readonly property real gapMul: 0.7 + 0.8 * E.hash(seed * 2.71 + 0.3)

    // rebotes por loop de cada vértice [x, y], y su arranque
    function rate(p, v, axis) { return 2 + Math.floor(E.hash(p * 13.1 + v * 3.7 + axis * 1.9 + seed) * 4); }
    function start(p, v, axis) { return E.hash(p * 7.3 + v * 11.9 + axis * 5.1 + seed * 3); }

    function vertex(p, v, tt) {
        const x = margin + E.tri(tt / loopS * rate(p, v, 0) + start(p, v, 0)) * (width - 2 * margin);
        const y = margin + E.tri(tt / loopS * rate(p, v, 1) + start(p, v, 1)) * (height - 2 * margin);
        if (p < 2)
            return [x, y];
        // el tercero crece desde el centro con el drop
        const k = dropAmt;
        return [width / 2 + (x - width / 2) * k, height / 2 + (y - height / 2) * k];
    }

    // Las líneas van por Qt Quick Shapes (`MShape`, la placa de video), no por
    // un Canvas: el Canvas rasterizaba cada trazo ancho y translúcido en el
    // procesador y costaba ~90 ms por cuadro (banco 2026-09-27). Acá el JS sólo
    // calcula puntos, y cada tanda junta los ecos de un mismo brillo.
    readonly property real beatHot: 1 - E.outQuad(bp)
    function lead(p) { return drop ? (beatN + p) % 2 === 0 : p === 0; }
    // brillo de cada cubeta de ecos (fuerte, medio, tenue)
    readonly property var echoA: [0.62, 0.36, 0.14]

    MShape {
        id: sh
    }
    // estilos: por polígono [eco fuerte, medio, tenue], después [halo, frente]
    function build() {
        const styles = [], geo = [];
        for (let p = 0; p < 3; p++) {
            const base = lead(p) ? hot : colour;
            for (let k = 0; k < 3; k++) {
                styles.push({ w: span * 0.003, c: E.col(base, echoA[k] * 0.75) });
                geo.push([]);
            }
        }
        for (let p = 0; p < 3; p++) {
            const ld = lead(p), base = ld ? hot : colour;
            styles.push({ w: span * (0.014 + 0.01 * beatHot), c: E.col(base, 0.16 + 0.2 * beatHot) });
            styles.push({ w: span * 0.0045,
                          c: ld ? E.col(Qt.rgba(1, 1, 1, 1), 0.55 + 0.45 * beatHot) : E.col(base, 1) });
            geo.push([]); geo.push([]);
        }
        for (let p = 0; p < polys; p++) {
            for (let e = echoes; e >= 0; e--) {
                const tt = lt - e * gap;
                const poly = [];
                for (let v = 0; v <= nv; v++) {
                    const q = vertex(p, v % nv, tt);
                    poly.push(Qt.point(q[0], q[1]));
                }
                if (e === 0) {
                    geo[9 + p * 2].push(poly);
                    geo[10 + p * 2].push(poly);
                    continue;
                }
                const a = Math.pow(1 - e / (echoes + 1), 1.6);
                geo[p * 3 + (a > 0.5 ? 0 : a > 0.22 ? 1 : 2)].push(poly);
            }
        }
        sh.styles = styles;
        sh.geo = geo;
    }
    onFrame: build()
}
