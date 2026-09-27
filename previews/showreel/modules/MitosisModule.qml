// 04 MITOSIS BUILD — 7.500–11.250
// Un cartel "Copiando letra..." entra en el bombo y se DIVIDE a tempo: 2, 4,
// 8, 16, 32 en negras, 64 y 128 cuando el redoble acelera. Cada hijo nace de
// la celda de su padre (se ve la división, no un corte). Las barras de
// progreso corren cada vez más rápido; una ola en diagonal los va colgando
// ("(No responde)", barra gris). El glitch del vidrio crece con el redoble.
// En 11.016 todo se congela y se apaga: el vacío antes del drop.
//
// Integrable: la división es la versión con presupuesto del `max_dialogs=0`
// (Ferox deja carteles sin límite): en un drop con compás confiable, UN
// cartel se multiplica en vez de apilar N sueltos. Lo colgado ya existe
// (`hung` en shell.qml): acá se dispara por ola en vez de por edad.
import QtQuick
import ".."
import "../Ease.js" as E
import "../Timeline.js" as TL

Item {
    id: m
    property real t: 0
    property QtObject audio
    property string mono: "monospace"

    readonly property var seg: TL.segment("build")
    // [momento de la división, columnas, filas]. Parte primero en FILAS: la
    // celda alterna entre 3.8:1 y 1.9:1 y el cartel (≈3.2:1) siempre la llena.
    readonly property var levels: [
        [TL.b(16), 1, 1], [TL.b(17), 1, 2], [TL.b(18), 2, 2], [TL.b(19), 2, 4],
        [TL.b(20), 4, 4], [TL.b(21), 4, 8], [TL.b(21.5), 8, 8], [TL.b(22), 8, 16]
    ]
    readonly property int lv: {
        let l = 0;
        for (let i = 0; i < levels.length; i++) if (t >= levels[i][0]) l = i;
        return l;
    }
    readonly property real margin: 70
    readonly property bool gap: t >= TL.GAP_AT
    readonly property real hungAt: TL.b(22.25)

    function cellRect(level, c, r) {
        const cols = levels[level][1], rows = levels[level][2];
        const w = (width - 2 * margin) / cols, h = (height - 2 * margin) / rows;
        return Qt.rect(margin + c * w, margin + r * h, w, h);
    }
    // de qué celda del nivel anterior viene (c, r)
    function parentOf(level, c, r) {
        if (level === 0) return Qt.point(c, r);
        const doubledCols = levels[level][1] === 2 * levels[level - 1][1];
        return doubledCols ? Qt.point(c >> 1, r) : Qt.point(c, r >> 1);
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.08 * (1 - E.prog(m.t, m.seg.t0, 3)), 0.1 * (1 - E.prog(m.t, m.seg.t0, 3)), 1)
    }

    Item {
        anchors.fill: parent
        visible: !m.gap

        Repeater {
            model: 128
            Win95Dialog {
                id: cell
                required property int index
                readonly property int cols: m.levels[m.lv][1]
                readonly property int rows: m.levels[m.lv][2]
                readonly property int c: index % cols
                readonly property int r: Math.floor(index / cols)
                readonly property real t0: m.levels[m.lv][0]
                readonly property real interval: m.lv + 1 < m.levels.length ? m.levels[m.lv + 1][0] - t0 : 0.4
                readonly property real e: E.outExpo(E.prog(m.t, t0, Math.min(0.3, interval * 0.8)))
                readonly property point par: m.parentOf(m.lv, c, r)
                readonly property rect from: m.lv === 0 ? m.cellRect(0, 0, 0) : m.cellRect(m.lv - 1, par.x, par.y)
                readonly property rect to: m.cellRect(m.lv, c, r)
                readonly property real cw: E.mix(from.width, to.width, e)
                readonly property real chh: E.mix(from.height, to.height, e)
                readonly property real ccx: E.mix(from.x + from.width / 2, to.x + to.width / 2, e)
                readonly property real ccy: E.mix(from.y + from.height / 2, to.y + to.height / 2, e)
                readonly property real seed: E.hash(index * 3.7 + 1)
                readonly property real diag: (c / cols + r / rows) / 2
                readonly property real roll: m.audio ? m.audio.riser : 0
                // el primero entra con el snap; después sólo se divide
                readonly property real spawn: E.outExpo(E.prog(m.t, m.seg.t0, 0.32))
                readonly property real prog: E.clamp01(E.inCubic(E.prog(m.t, m.seg.t0, TL.GAP_AT - m.seg.t0)) * (0.55 + seed * 0.7) + 0.04)

                visible: index < cols * rows
                baseW: 420
                // el cuerpo estira el cartel hasta la forma de su celda
                bodyH: E.clamp(420 * chh / cw * 0.97 - 66, 40, 170)
                k: Math.min(cw * 0.9 / baseW, chh * 0.84 / baseH) * (m.lv === 0 ? E.mix(0.7, 1, spawn) : 1)
                x: ccx - width / 2 + (seed - 0.5) * roll * cw * 0.12 * (m.audio ? 0.3 + m.audio.audHi * 2 : 0)
                y: ccy - height / 2
                title: "copiando.exe"
                text: "Copiando letra... " + Math.floor(prog * 100) + "%"
                icon: "warning"
                buttons: ["Cancelar"]
                progress: prog
                hung: m.t >= m.hungAt && diag < E.prog(m.t, m.hungAt, TL.GAP_AT - m.hungAt - 0.1) * 1.05
                flash: m.lv === 0 ? 1 - E.prog(m.t, m.seg.t0, 0.08)
                       : (1 - e) * 0.6 + (m.audio && seed < 0.12 * roll ? Math.exp(-(m.t - m.audio.lastBeatAt) / 0.05) : 0)
                shadow: 6
            }
        }
    }

    // el vacío: todo se apaga, queda un cursor que parpadea en el tiempo
    Text {
        visible: m.gap && Math.floor((m.t - TL.GAP_AT) / (TL.BEAT / 4)) % 2 === 0
        anchors.centerIn: parent
        text: "_"
        color: "#ffffff"
        font.family: m.mono
        font.pixelSize: 64
    }
}
