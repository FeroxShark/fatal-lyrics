// mystify — el salvapantallas "Mystify Your Mind" de Windows 95, en fósforo.
//
// Dos polígonos de 3 a 6 vértices rebotan contra el borde de la pantalla con
// su estela de ecos. Cada vértice rebota con un número ENTERO de idas y
// vueltas cada 15 s, así la figura entera vuelve a su lugar al cerrar el loop.
// Lo que suena:
//   · el ritmo (`rate` → `movOff` → `lt`): los vértices corren más rápido con la
//     música, con la fase INTEGRADA (nunca `clock × velocidad`)
//   · el tiempo (`tick`): el polígono de adelante se enciende en `hot` y se
//     apaga en el tiempo; en el drop los dos se pasan el color de golpe en golpe
//   · el golpe del tubo (`surge`): los ecos se ABREN y la estela se estira
//   · `energy`: cuántos ecos (10 en la estrofa, 22 en el drop)
//   · `hf` (flujo de agudos, con la curva `React.fizz` del tubo): el color se corre hacia
//     `hot` y el resplandor prende; `high` (nivel de agudos) sólo ensancha el resplandor
//   · corte seco (`cut`): el dibujo se AGARRA — los vértices se quedan quietos (hasta 0,6 s
//     de fase) y la estela se estira hacia atrás; al volver la música los vértices dan el
//     salto atrasado con el snap de Motion y la estela se recoge. Nada de exponenciales:
//     todo llega a 0 exacto (Mystify.js), así el loop del banco cierra
//   · `drop`: entra un tercer polígono desde el centro, con el snap de Motion
//
// El dibujo vive en `mystify.frag` (por píxel, analítico); acá sólo se reparten
// los vértices y los números del cuadro.
// Costo en el overlay: UN ShaderEffect de pantalla completa. Cero geometría por
// cuadro (antes: 15 tandas de Shapes, 3 × 22 polilíneas reconstruidas en JS).
import QtQuick
import "../Ease.js" as E
import "../Mystify.js" as Hold
import "../React.js" as React

MotifBase {
    id: m

    readonly property real margin: span * 0.07
    readonly property int echoes: Math.round(E.clamp(8 + 9 * (energy - 0.9) / 0.7 + 4, 10, 22) * quality)
    readonly property real gap: 0.045 * gapMul * (1 + 1.6 * surge + 1.3 * cutK)
    // cada aparición es otra: de 3 a 6 vértices y la estela más o menos abierta
    readonly property int nv: 3 + Math.floor(E.hash(seed * 5.13 + 0.7) * 4)
    readonly property real gapMul: 0.7 + 0.8 * E.hash(seed * 2.71 + 0.3)

    // rebotes por loop de cada vértice [x, y], y su arranque
    // (no se llama `rate`: esa es la propiedad del ritmo que hereda de MotifBase, y un
    // método del hijo la PISA — `base.rate` leería la función y el ritmo daría NaN)
    function bounces(p, v, axis) { return 2 + Math.floor(E.hash(p * 13.1 + v * 3.7 + axis * 1.9 + seed) * 4); }
    function start(p, v, axis) { return E.hash(p * 7.3 + v * 11.9 + axis * 5.1 + seed * 3); }

    // Las 4 columnas de una matriz = 4 vértices; fila = (rebotes x, rebotes y, arranque x,
    // arranque y). `Qt.matrix4x4` recibe las filas, y el shader lee columnas.
    function verts(p, v0) {
        const f = (r, v) => r === 0 ? bounces(p, v, 0) : r === 1 ? bounces(p, v, 1)
                          : r === 2 ? start(p, v, 0) : start(p, v, 1);
        const a = [];
        for (let r = 0; r < 4; r++)
            for (let c = 0; c < 4; c++)
                a.push(v0 + c < 6 ? f(r, v0 + c) : 0);
        return Qt.matrix4x4(...a);
    }

    // ---- corte seco -----------------------------------------------------------
    // Estampas, no historia: `cutAt`/`backAt` en `clock`, `freezeAt`/`thawAt` en la fase
    // monótona `clock + movOff` (la de `lt` sin envolver a los 15 s). Mientras el corte dura
    // `backAt`/`thawAt` valen 1e9. Nada se llama `lt`/`rate`/`movOff` (TRAMPAS: pisan MotifBase).
    property bool started: false
    property real cutAt: -1e6
    property real backAt: 1e9
    property real freezeAt: 0
    property real thawAt: 1e9
    function markCut() {
        cutAt = clock;
        backAt = 1e9;
        freezeAt = clock + movOff;
        thawAt = 1e9;
    }
    onCutChanged: {
        if (!started) return;
        if (cut) {
            markCut();
        } else {
            backAt = clock;
            thawAt = clock + movOff;
        }
    }
    // un corte ya en curso al aparecer el motivo cuenta desde ahora
    Component.onCompleted: {
        started = true;
        if (cut) markCut();
    }
    // agarre 0..1: entra rápido (0,12 s), suelta con el snap de Motion (`enterMs`, 320 ms)
    readonly property real cutK: Hold.hold(clock, cutAt, backAt, 0.12, 0.32)
    // atraso de fase: hasta 0,6 s con los vértices quietos; al soltar, el salto atrasado
    readonly property real cutLag: Hold.lag(clock + movOff, freezeAt, thawAt, 0.6)
    // la fase que va al shader: `lt` (viva) menos lo que se quedó quieta
    readonly property real ltShow: E.wrap(lt - cutK * cutLag, loopS)

    readonly property real beatHot: 1 - E.outQuad(bp)
    function lead(p) { return drop ? (beatN + p) % 2 === 0 : p === 0; }
    function leadK(p) { return lead(p) ? 0.55 + 0.45 * beatHot : 0; }

    ShaderEffect {
        anchors.fill: parent
        property variant a0: m.verts(0, 0)
        property variant a1: m.verts(0, 4)
        property variant b0: m.verts(1, 0)
        property variant b1: m.verts(1, 4)
        property variant c0: m.verts(2, 0)
        property variant c1: m.verts(2, 4)
        property color ink: m.colour
        property color hot: m.hot
        property variant res: Qt.vector2d(width, height)
        property real lt: m.ltShow
        property real gap: m.gap
        property real echoes: m.echoes
        property real nv: m.nv
        property real margin: m.margin
        property real dropAmt: m.dropAmt
        property real pulse: m.beatHot
        property real high: m.high
        property real hf: React.fizz(m.hf, 1)
        property real wpx: m.span * (0.0034 + 0.0016 * m.beatHot)
        property real lead0: m.leadK(0)
        property real lead1: m.leadK(1)
        property real lead2: m.leadK(2)
        fragmentShader: Qt.resolvedUrl("mystify.frag.qsb")
    }
}
