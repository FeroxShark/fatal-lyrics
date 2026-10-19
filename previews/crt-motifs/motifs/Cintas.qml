// fatal-lyrics — motivo `cintas` (testeo 2026-10-19, NO está en el sorteo).
//
// Cintas de fósforo tendidas a distintas profundidades (cuerdas de un bajo vistas
// de costado). Qué hace con cada señal:
//   · bombo (`thump`)  — PULSA las cintas: se comban (modo 1 + algo del 2) y se
//     retuercen sobre su eje. Las de atrás pesan más: responden más tarde y más
//     lento, así la ola baja por la pila (overlap). La cámara es otra masa, más
//     pesada todavía: cabecea después del golpe y vuelve (follow-through).
//   · agudos (`fizz`)  — aparecen fibras finas que corren por adentro de las cintas.
//   · densidad (`dens`) — entran cintas (3 → 8, de a una, de atrás) y la deriva
//     de fondo crece.
//   · carácter (`temper`) — calmo: cintas anchas, combadura larga y blanda, torsión
//     lenta; agitado: finas, latigazo seco, más vueltas.
// La deriva (`drift`, acumulada) no para: sin música las cintas ondulan y giran.
//
// Costo: UN ShaderEffect de pantalla completa, ≤ 8 capas × 4 golpes por píxel.
import QtQuick
import "../Ease.js" as E
import "../Thump.js" as T

ThumpBase {
    id: m

    readonly property var camPhys: T.heavy(phys, 6)
    readonly property real camK: T.sum(camPhys, clock, hitT, hitA, 0.06)

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
        property real camX: 0.35 * Math.sin(m.drift * 0.21)
        property real camY: 0.05 * Math.sin(m.drift * 0.33) - 0.045 * m.camK
        property real layers: E.mix(3.2, 8, m.dens)
        property real bend: E.mix(0.30, 0.22, m.temper)
        property real twist: E.mix(0.9, 2.2, m.temper)
        property real seed: m.seed
        fragmentShader: Qt.resolvedUrl("cintas.frag.qsb")
    }
}
