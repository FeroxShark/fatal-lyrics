// fatal-lyrics — motivo `giroscopio` (testeo 2026-10-19; ya está en el sorteo, grupo `neutral` de `motifGroups`).
//
// Un giróscopo de aros anidados (cardán) en 3D, raymarch. Qué hace con cada señal:
//   · bombo (`thump`)  — cada golpe es un impulso de giro: el aro de ADENTRO (liviano)
//     salta primero y se pasa; los de afuera (más pesados) arrancan más tarde, giran
//     menos y se asientan después (overlap y follow-through: el mecanismo "hace tic").
//     El núcleo late con la envolvente del golpe y la cámara se acerca un poco, con
//     una masa más pesada todavía.
//   · agudos (`fizz`)  — marcas finas a lo largo de los aros que se prenden y corren,
//     y el polvo del fondo titila. No mueven nada grande.
//   · densidad (`dens`) — entran aros de adentro (3 → 6), cuentas que orbitan el aro
//     de afuera (0 → 10), más polvo en el fondo y la deriva más rápida.
//   · carácter (`temper`) — calmo: giros chicos, resortes blandos y lentos, brillo
//     ancho; agitado: tics grandes y secos, resortes duros, brillo puntual.
// Los aros también giran solos con la deriva (`drift`, acumulada): nunca se para.
//
// Física: un resorte de segundo orden por aro, integrado acá (semi-implícito, pasos
// ≤ 1/240 s: no depende de los cuadros). El golpe mueve el OBJETIVO del resorte
// (el giro queda hecho, no vuelve atrás); el resorte llega con su sobrepaso.
// Costo: un ShaderEffect de pantalla completa (≤ 72 pasos, sólo dentro de la esfera
// que envuelve al giróscopo). CPU: 6 resortes, ~40 números por cuadro.
import QtQuick
import "Ease.js" as E
import "Thump.js" as T

ThumpBase {
    id: m

    // aro 0 = el de afuera (masa 6) .. aro 5 = el de adentro (masa 1)
    readonly property var masses: [6.0, 4.6, 3.4, 2.4, 1.6, 1.0]
    // cada aro gira para su lado (un mecanismo, no un trompo)
    readonly property var dirs: [1, -1, 1, -1, 1, -1]
    readonly property var rates: [0.10, 0.16, 0.22, 0.30, 0.38, 0.47]
    property var tgt: [0, 0, 0, 0, 0, 0]
    property var pos: [0, 0, 0, 0, 0, 0]
    property var vel: [0, 0, 0, 0, 0, 0]
    property real gLast: -1e9

    onHitNChanged: {
        const k = hitA[3] * E.mix(0.35, 0.75, temper);
        const t = tgt.slice();
        for (let i = 0; i < 6; i++)
            t[i] += dirs[i] * k * Math.pow(masses[i], -0.35);
        tgt = t;
    }
    Connections {
        target: m
        function onClockChanged() {
            const dt = m.clock - m.gLast;
            m.gLast = m.clock;
            if (!(dt > 0) || dt > 0.5)
                return;
            const n = Math.ceil(dt * 240), h = dt / n;
            const p = m.pos.slice(), v = m.vel.slice();
            for (let i = 0; i < 6; i++) {
                const w = m.phys.w / Math.sqrt(m.masses[i]), z = m.phys.zeta;
                for (let s = 0; s < n; s++) {
                    v[i] += (-w * w * (p[i] - m.tgt[i]) - 2 * z * w * v[i]) * h;
                    p[i] += v[i] * h;
                }
            }
            m.pos = p;
            m.vel = v;
        }
    }
    function ang(i) { return pos[i] + dirs[i] * rates[i] * drift + 0.6 * i; }

    readonly property var camPhys: T.heavy(phys, 5)
    readonly property real camK: T.sum(camPhys, clock, hitT, hitA, 0.05)

    ShaderEffect {
        anchors.fill: parent
        property color ink: m.colour
        property color hot: m.hot
        property color bg: m.bg
        property vector4d angA: Qt.vector4d(m.ang(0), m.ang(1), m.ang(2), m.ang(3))
        property vector4d angB: Qt.vector4d(m.ang(4), m.ang(5), E.mix(3, 6, m.dens), Math.round(E.mix(0, 10, m.dens)))
        property variant res: Qt.vector2d(width, height)
        property real camD: (m.portrait ? 4.2 : 3.35) - 0.22 * m.camK
        property real camYaw: m.drift * 0.12
        property real camPitch: 0.32 + 0.14 * Math.sin(m.drift * 0.19) + 0.035 * m.camK
        property real core: E.clamp01(T.envSum(m.phys, m.clock, m.hitT, m.hitA))
        property real glow: E.clamp01(T.envSum(m.camPhys, m.clock, m.hitT, m.hitA))
        property real fizz: m.fizz
        property real dens: m.dens
        property real drift: m.drift
        property real temper: m.temper
        fragmentShader: Qt.resolvedUrl("giroscopio.frag.qsb")
    }
}
