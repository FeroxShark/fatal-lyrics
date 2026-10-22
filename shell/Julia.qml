// fatal-lyrics — motivo `julia` (2026-10-22; en el sorteo, grupo `calm` de `motifGroups`).
//
// El conjunto de Julia con líneas de nivel: un `c` camina por el borde de la cardioide de
// Mandelbrot y la pantalla muestra cómo escapa z² + c. Qué hace con cada señal:
//   · bombo (`thump`)  — empuja `c` hacia afuera y acerca la cámara: el conjunto se astilla y
//     vuelve (la envolvente del resorte de `Thump.js`, con una masa más pesada que el motivo).
//   · tiempo (`beatN`) — las líneas de nivel dan un paso hacia el conjunto con el snap de
//     Motion (OutExpo 320 ms) y se quedan quietas hasta el próximo.
//   · agudos (`fizz`)  — chispas sobre las líneas.
//   · densidad (`dens`) — más líneas de nivel; el interior se enciende.
//   · carácter (`temper`) — calmo: golpe ancho y lento; agitado: seco (viene de `phys`).
// La deriva (`drift`, acumulada) camina `c` por el borde aunque no suene nada.
//
// Costo: UN ShaderEffect de pantalla completa (≤ 56 iteraciones por píxel, sin texturas);
// `quality` baja el tope de iteraciones.
import QtQuick
import "Ease.js" as E
import "Thump.js" as T

ThumpBase {
    id: m

    readonly property var camPhys: T.heavy(phys, 2)
    readonly property real pulse: E.clamp01(T.envSum(camPhys, clock, hitT, hitA))

    ShaderEffect {
        anchors.fill: parent
        property color ink: m.colour
        property color hot: m.hot
        property color bg: m.bg
        property variant res: Qt.vector2d(width, height)
        property real drift: m.drift
        property real dens: m.dens
        property real fizz: m.fizz
        property real pulse: m.pulse
        property real bn: m.beatN
        property real since: Math.min(m.sinceTick, m.beatS * 1.5)
        property real seed: E.hash(m.seed * 3.17 + 0.3)
        property real dropAmt: m.dropAmt
        property real quality: Math.max(0.5, Math.min(1, m.quality))
        fragmentShader: Qt.resolvedUrl("julia.frag.qsb")
    }
}
