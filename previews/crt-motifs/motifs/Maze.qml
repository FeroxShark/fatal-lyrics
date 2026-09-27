// maze — el "Laberinto 3D" de Windows 95: la cámara camina un pasillo en anillo.
//
// Un paso por tiempo: 8 adelante, doblar, 6 adelante, doblar… 32 acciones = 32
// tiempos = la vuelta entera, y el loop cierra en la celda de partida. Cada
// paso es el snap de Motion (OutExpo, 340 ms) y después quieta hasta el tiempo
// siguiente: se camina AL PASO de la canción, no deslizando. Al doblar gira 90°
// con la misma curva. Una deriva lenta de la mirada (±1.4°, periódica) hace que
// ni el hold sea un cuadro congelado. Lo que suena:
//   · `tick`: los pasos y los giros; en cada tiempo las aristas se prenden
//   · `drop`: la niebla se abre (se ve el fondo del pasillo) y la cuadrícula
//     del piso se enciende y late
//   · `high` en la subida: la niebla respira con los platillos
//
// El dibujo vive en `maze.frag` (raycaster por píxel); acá sólo la cámara.
// Costo en el overlay: un ShaderEffect de pantalla completa, ≤ 40 pasos de DDA
// por píxel. Lo más caro de estos ocho en GPU, lo más barato en CPU.
import QtQuick
import "../Ease.js" as E

MotifBase {
    id: m

    // las 33 posiciones de la vuelta: [x, y, ángulo]
    readonly property var states: {
        const acts = [];
        const legs = [8, 6, 8, 6];
        for (const n of legs) {
            for (let i = 0; i < n; i++) acts.push("F");
            acts.push("R");
        }
        let x = 1.5, y = 1.5, a = 0;
        const out = [[x, y, a]];
        for (const c of acts) {
            if (c === "F") { x += Math.round(Math.cos(a)); y += Math.round(Math.sin(a)); }
            else a += Math.PI / 2;
            out.push([x, y, a]);
        }
        return out;
    }
    readonly property int step: E.wrap(beatN, 32)
    readonly property real e: E.outExpo(E.prog(sinceTick, 0, 0.34))
    readonly property var s0: states[step]
    readonly property var s1: states[step + 1]
    readonly property bool walking: s0[2] === s1[2]

    ShaderEffect {
        anchors.fill: parent
        property variant res: Qt.vector2d(width, height)
        property variant cam: Qt.vector3d(E.mix(m.s0[0], m.s1[0], m.e), E.mix(m.s0[1], m.s1[1], m.e),
            E.mix(m.s0[2], m.s1[2], m.e) + 0.025 * Math.sin(2 * Math.PI * m.lt / m.loopS * 2))
        property real bob: m.walking ? -0.012 * Math.sin(Math.PI * E.prog(m.sinceTick, 0, 0.3)) : 0
        property real pulse: E.clamp01(Math.exp(-m.sinceTick / 0.12) * (0.45 + 0.55 * m.dropAmt) + 0.3 * m.surge)
        property real dropAmt: m.dropAmt
        property real fogK: 0.17 + (m.section === "build" ? 0.12 * m.high : 0)
        property real seed: m.seed
        property real lt: m.lt
        property color ink: m.colour
        property color hot: m.hot
        property color bg: m.bg
        fragmentShader: Qt.resolvedUrl("maze.frag.qsb")
    }
}
