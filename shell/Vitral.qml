// fatal-lyrics — motivo `vitral` (2026-10-22; en el sorteo, grupo `calm` de `motifGroups`).
//
// Un vitral de Voronoi: teselas de vidrio facetado con plomo oscuro entre ellas. Qué hace con
// cada señal:
//   · tiempo (`beatN`) — se enciende una tanda de teselas por tiempo (se apagan con una cola
//     de ~3 tiempos); cuáles, sale de un hash del contador: no se repite entre temas (`seed`).
//   · bombo (`thump`)  — una onda de choque sale de un punto (`hitS`) y empuja los centros de las
//     teselas hacia afuera con el resorte de `Thump.js` (se pasa, vuelve, se apaga): los plomos
//     se doblan al paso del frente, que además brilla.
//   · agudos (`fizz`)  — titila el reborde de las teselas.
//   · densidad (`dens`) — se prenden más teselas por tiempo.
//   · carácter (`temper`) — viene de `phys`: calmo, onda ancha y suave; agitado, seca.
// Los centros pasean solos (`drift`, acumulada): los plomos nunca quedan quietos.
//
// Costo: UN ShaderEffect de pantalla completa: 9 sitios de Voronoi por píxel, 4 ondas por sitio.
import QtQuick
import "Ease.js" as E
import "Thump.js" as T

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
        property variant res: Qt.vector2d(width, height)
        property real drift: m.drift
        property real dens: m.dens
        property real fizz: m.fizz
        property real bn: m.beatN
        property real since: Math.min(m.sinceTick, m.beatS * 1.5)
        property real beatS: m.beatS
        property real seed: E.hash(m.seed * 3.17 + 0.3)
        property real dropAmt: m.dropAmt
        property real cells: 6
        fragmentShader: Qt.resolvedUrl("vitral.frag.qsb")
    }
}
