// fatal-lyrics — motivo `truchet` (2026-10-22; en el sorteo, grupo `neutral` de `motifGroups`).
//
// Azulejos de Truchet: una red de cables hecha de arcos, sin principio ni fin, en la que cada
// casilla gira un cuarto de vuelta de tanto en tanto. Qué hace con cada señal:
//   · tiempo (`beatN`) — las casillas giran SIEMPRE en un tiempo (cada una con su período de
//     1, 2, 4 u 8 tiempos): snap OutExpo 320 ms de Motion y quieta hasta el próximo giro.
//   · bombo (`thump`)  — una onda sale de un punto (`hitS`) y viaja por la red con el resorte
//     de `Thump.js`: los cables engordan y los empalmes se encienden a su paso.
//   · agudos (`fizz`)  — titilan los empalmes de los bordes.
//   · densidad (`dens`) — giran más casillas por tiempo.
// La red se desliza sola (`drift`, acumulada): nunca queda quieta.
//
// PARED (`docs/PARED.md`): con lienzo común la red es UNA sola que cruza las pantallas (`wallView`)
// y las ondas del bombo salen del foco de la pared.
//
// Costo: UN ShaderEffect de pantalla completa, UNA casilla por píxel (sin vecinos, sin texturas).
import QtQuick
import "../Ease.js" as E
import "../Thump.js" as T

ThumpBase {
    id: m

    ShaderEffect {
        anchors.fill: parent
        property color ink: m.colour
        property color hot: m.hot
        property color bg: m.bg
        property vector4d hitAge: m.hitAge
        property vector4d hitAmp: m.hitAmp
        property vector4d hitSeed: m.hitSeed
        property vector4d phys: m.physV
        property real physN: m.physN
        property real drift: m.drift
        property real dens: m.dens
        property real fizz: m.fizz
        property real bn: m.beatN
        property real since: Math.min(m.sinceTick, m.beatS * 1.5)
        property real beatS: m.beatS
        property real seed: E.hash(m.seed * 3.17 + 0.3)
        property real dropAmt: m.dropAmt
        // fija: cambiarla en vivo desplazaría toda la red
        property real cells: 8
        property vector4d view: m.wallView
        property variant foc: Qt.vector2d((m.wallFocus.x - m.wallArea.x / 2) / m.span,
                                            (m.wallFocus.y - m.wallArea.y / 2) / m.span)
        property real wallK: m.walled ? 1 : 0
        fragmentShader: Qt.resolvedUrl("truchet.frag.qsb")
    }
}
