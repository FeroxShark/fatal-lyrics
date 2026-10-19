// fatal-lyrics — motivo `membrana` (testeo 2026-10-19; ya está en el sorteo, grupo `hot` de `motifGroups`).
//
// El parche de un bombo en perspectiva, malla de fósforo. Qué hace con cada señal:
//   · bombo (`thump`)  — le pega al parche en un punto: la onda baja, se pasa, vuelve
//     y se apaga viajando hacia afuera (resorte de `Thump.js`, los golpes se suman).
//     La CÁMARA es una masa más pesada colgada del mismo golpe: se hunde un poco
//     más tarde y vuelve con follow-through (nunca a la vez que el parche).
//   · agudos (`fizz`)  — un temblor fino corre por encima y los nudos de la malla
//     titilan; no mueve nada grande.
//   · densidad (`dens`) — más filas, malla más cerrada, la deriva de fondo más alta
//     y el parche gira un poco más rápido.
//   · carácter (`temper`) — calmo: ondas largas, ataque blando, cámara que flota;
//     agitado: ondulitas cortas y secas, golpe instantáneo, cámara que pega.
// La deriva (`drift`, acumulada) no para nunca: sin música el parche respira.
//
// Costo: UN ShaderEffect de pantalla completa (≤ 72 filas por píxel, corta en la
// primera que lo tapa). CPU: las cuentas de cámara de abajo, ~20 números por cuadro.
import QtQuick
import "Ease.js" as E
import "Thump.js" as T

ThumpBase {
    id: m

    // la cámara: el mismo golpe en una masa 4× más pesada (más lenta, más tarde)
    readonly property var camPhys: T.heavy(phys, 4)
    readonly property real camK: T.sum(camPhys, clock, hitT, hitA, 0.04)

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
        property real temper: m.temper
        property real camH: 1.75 - 0.16 * m.camK * E.mix(0.6, 1.0, m.temper)
        property real pitch: 0.50 + 0.045 * m.camK + 0.03 * Math.sin(m.drift * 0.37)
        property real roll: 0.05 * Math.sin(m.drift * 0.23) + 0.012 * m.camK * (m.hitS[3] > 0.5 ? 1 : -1)
        property real yaw: m.drift * 0.16
        // calmo: la onda viaja lenta y ancha; agitado: rápida
        property real waveC: E.mix(1.6, 3.4, m.temper)
        property real rows: Math.round(E.mix(34, 66, m.dens) * (m.portrait ? 1.3 : 1))
        property real depth: 0.55
        fragmentShader: Qt.resolvedUrl("membrana.frag.qsb")
    }
}
