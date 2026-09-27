// 06 RESOLVE — 13.594–15.000
// El impacto final: todo lo anterior queda como siluetas quemadas que se
// apagan, y entra el lockup "FATAL LYRICS" en un cartel (snap con overshoot,
// onda de choque). El nombre se DESCIFRA letra por letra. Hold quieto (lo
// fluido son los holds largos), el cursor entra y aprieta "Aceptar": el
// error se acepta, puente de glitch y el tubo se apaga (raya → punto → negro,
// en post.frag). El último cuadro es negro como el primero: loop limpio.
//
// Integrable: el descifrado por letra sirve para el título del tema en la
// funda / la tarjeta de intro del CRT (`crt.intro_card`).
import QtQuick
import ".."
import "../Ease.js" as E
import "../Timeline.js" as TL

Item {
    id: m
    property real t: 0
    property QtObject audio
    property string mono: "monospace"
    property string pixel: "monospace"

    readonly property var seg: TL.segment("resolve")
    readonly property real t0: seg.t0
    readonly property real clickAt: 14.34
    readonly property real releaseAt: 14.44
    readonly property string logo: "FATAL LYRICS"

    Rectangle { anchors.fill: parent; color: "#000000" }

    // siluetas quemadas de todo lo que pasó
    Repeater {
        model: 14
        Rectangle {
            required property int index
            readonly property real fade: 1 - E.prog(m.t, m.t0, 0.7 + E.hash(index) * 0.4)
            x: E.hash(index * 3.3) * (m.width - width)
            y: E.hash(index * 5.9) * (m.height - height)
            width: 260 + E.hash(index * 1.7) * 420
            height: width * 0.3
            color: "transparent"
            border.color: "#6a7f86"
            border.width: 2
            opacity: 0.45 * fade
            Rectangle { width: parent.width; height: parent.height * 0.2; color: "#6a7f86"; opacity: 0.5 }
        }
    }

    // onda de choque con forma de ventana
    Rectangle {
        readonly property real p: E.prog(m.t, m.t0, 0.6)
        readonly property real s: 0.6 + E.outExpo(p) * 1.6
        visible: p < 1
        width: dlg.width * s; height: dlg.height * s
        x: (m.width - width) / 2; y: (m.height - height) / 2
        color: "transparent"
        border.color: "#ffffff"
        border.width: 14 * (1 - p)
        opacity: 1 - p
    }

    Win95Dialog {
        id: dlg
        readonly property real inE: E.outBack(E.prog(m.t, m.t0, 0.38), 2.2)
        readonly property real drift: 1 + 0.025 * E.prog(m.t, m.t0 + 0.3, 1.2)
        k: 2.1 * drift
        baseW: 520
        bodyH: 118
        title: "fatal-lyrics.exe"
        icon: "none"
        buttons: ["Aceptar", "Cancelar"]
        pressedIndex: m.t >= m.clickAt && m.t < m.releaseAt ? 0 : -1
        x: (m.width - width) / 2
        y: (m.height - height) / 2
        shadow: 14
        flash: 1 - E.prog(m.t, m.t0, 0.1)
        sweep: E.prog(m.t, m.t0 + 0.12, 0.3)
        transform: Scale {
            origin.x: dlg.width / 2; origin.y: dlg.height / 2
            xScale: E.mix(0.55, 1, dlg.inE); yScale: xScale
        }

        Column {
            anchors.centerIn: parent
            spacing: 14 * dlg.k
            // el nombre se descifra de izquierda a derecha
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: m.logo.length
                    Text {
                        required property int index
                        readonly property real lockAt: m.t0 + 0.06 + index * 0.028
                        text: E.scramble(m.logo.charAt(index), m.t, index * 7 + 3, m.t >= lockAt ? 1 : 0)
                        font.family: m.pixel
                        font.pixelSize: 32 * dlg.k
                        color: m.t >= lockAt ? "#000080" : "#808080"
                        width: 32 * dlg.k
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: E.prog(m.t, m.t0 + 0.42, 0.2)
                text: "letras que no responden"
                font.family: m.mono
                font.pixelSize: 26 * dlg.k
                color: "#404040"
            }
        }
    }

    // el cursor aprieta "Aceptar"
    Cursor95 {
        k: 2.4
        readonly property rect b: dlg.buttonRect(0)
        readonly property real tx: dlg.x + b.x + b.width * 0.55
        readonly property real ty: dlg.y + b.y + b.height * 0.5
        readonly property real e: E.inOutCubic(E.prog(m.t, 13.95, m.clickAt - 13.95 - 0.03))
        visible: m.t >= 13.95
        x: E.mix(m.width * 0.92, tx, e)
        y: E.mix(m.height + 40, ty, e)
    }
}
