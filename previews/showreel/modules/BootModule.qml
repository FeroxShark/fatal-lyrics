// 01 BOOT — 0.000–1.875
// Prompt DOS tipeado en fusas, Enter, y el primer cartel naciendo de un
// pixel: primero raya (como el haz del tubo), después abre en alto con
// resorte y llega asentado JUSTO en el primer bombo (1.875).
//
// Integrable: la entrada "raya → cartel" sirve de spawn alternativo para
// los carteles de shell.qml (reemplaza scale/opacity de spawnAnim).
import QtQuick
import ".."
import "../Ease.js" as E
import "../Timeline.js" as TL

Item {
    id: m
    property real t: 0
    property QtObject audio
    property string mono: "monospace"

    readonly property var seg: TL.segment("boot")
    readonly property real enter: TL.ENTER_AT
    readonly property var keys: TL.keystrokes()

    Rectangle { anchors.fill: parent; color: "#000000" }

    // ---- BIOS + prompt ---------------------------------------------------
    Item {
        id: dos
        x: 150; y: 170
        readonly property real kOut: E.outExpo(E.prog(m.t, m.enter, 0.28))
        opacity: 1 - E.prog(m.t, m.enter + 0.05, 0.2)
        transform: [
            Translate { y: -dos.kOut * 260 },
            Scale { origin.y: 0; yScale: 1 + dos.kOut * 2.2 }
        ]

        Repeater {
            model: [
                { at: 0.26, s: "FATAL LYRICS BIOS v9.5   (C) 1995-2026" },
                { at: 0.32, s: "Memoria de letras ........ 640K  OK" },
                { at: 0.38, s: "Sincronizando voz ........ 128 BPM  OK" }
            ]
            Text {
                required property var modelData
                required property int index
                y: index * 54
                visible: m.t >= modelData.at
                // los dos primeros cuadros de cada línea llegan como basura
                readonly property bool fresh: m.t < modelData.at + 2 / 60
                text: {
                    if (!fresh) return modelData.s;
                    let o = "";
                    for (let i = 0; i < modelData.s.length; i++)
                        o += E.scramble(modelData.s[i], m.t, i + index * 31, 0);
                    return o;
                }
                color: index === 0 ? "#ffffff" : "#9a9a9a"
                font.family: m.mono
                font.pixelSize: 46
            }
        }

        // el prompt: una tecla por golpe de fusa
        Text {
            id: prompt
            y: 4 * 54
            readonly property int typed: {
                let n = 0;
                for (let i = 0; i < m.keys.length; i++) if (m.keys[i] <= m.t) n++;
                return n;
            }
            text: TL.PROMPT.substring(0, typed)
            color: "#ffffff"
            font.family: m.mono
            font.pixelSize: 46
        }
        // cursor de bloque: parpadea en corcheas, sólido mientras tipea
        Rectangle {
            x: prompt.implicitWidth + 4
            y: prompt.y + 8
            width: 22; height: 38
            color: "#ffffff"
            readonly property bool typing: m.t >= m.keys[0] - 0.05 && m.t < m.enter
            visible: m.t >= 0.2 && (typing || (Math.floor(m.t / (TL.BEAT / 2)) % 2 === 0))
        }
    }

    // ---- el primer cartel: pixel → raya → cartel --------------------------
    Win95Dialog {
        id: first
        readonly property var spec: TL.STACK[0]
        readonly property real u: E.prog(m.t, m.enter + 0.03, TL.b(4) - m.enter - 0.03)
        readonly property real sx: E.outExpo(E.prog(u, 0, 0.32))
        readonly property real sy: u < 0.32 ? 0.012 : E.mix(0.012, 1, E.spring(E.prog(u, 0.32, 0.68), 1.6, 7))
        visible: m.t >= m.enter + 0.03
        k: TL.STACK_K
        baseW: TL.DIALOG_W
        bodyH: TL.DIALOG_BODY
        title: spec.title
        text: spec.text
        icon: spec.icon
        buttons: spec.buttons
        x: (m.width - width) / 2
        y: (m.height - height) / 2
        flash: 1 - E.prog(u, 0.25, 0.45)
        sweep: E.prog(m.t, TL.b(4) - 0.3, 0.26)
        shadow: 8
        transform: Scale {
            origin.x: first.width / 2; origin.y: first.height / 2
            xScale: first.sx; yScale: first.sy
        }
    }
}
