// 03 KINETIC TYPE — 4.688–7.500
// El cartel se abre para alojar la letra. Cada palabra entra cuando la canta
// el `words` del LRC enhanced; cada letra cae desde la barra de título con
// overshoot (stagger 22 ms), gira y se asienta. La palabra que suena va en el
// azul del karaoke (#000080), las cantadas en negro. "fatal" se ESCAPA del
// cartel en el bombo siguiente: sale roja, grande, por encima del marco, y en
// su lugar queda la silueta quemada (burn-in). En el último tambor todas las
// letras vuelan y el cartel muere como en shell.qml (se aplasta en alto).
//
// Integrable: `words:[[t,w]]` ya viaja en el `show`. La entrada por letra es
// una alternativa al karaoke por color; el escape de UNA palabra es un
// candidato natural para `word_fx` (hoy sólo pega en el tubo del CRT).
import QtQuick
import ".."
import "../Ease.js" as E
import "../Timeline.js" as TL

Item {
    id: m
    property real t: 0
    property QtObject audio

    readonly property var seg: TL.segment("kinetic")
    readonly property var lyric: TL.LYRIC
    readonly property real k: 2.25
    readonly property real breakAt: TL.b(12)
    readonly property real dieAt: TL.b(15)
    readonly property real beatEnv: audio ? Math.exp(-Math.max(0, t - audio.lastBeatAt) / 0.14) : 0
    readonly property int fatalIdx: 1

    function wordAt(tt) {
        let idx = -1;
        for (let i = 0; i < lyric.words.length; i++) if (lyric.words[i][0] <= tt) idx = i;
        return idx;
    }
    readonly property int cur: wordAt(t)

    // ---- fondo -------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#0d3a40" }
            GradientStop { position: 1; color: "#051a1e" }
        }
    }
    // la palabra que suena, gigante y quieta de fondo; la deriva nunca para
    Text {
        visible: m.cur >= 0
        readonly property real enter: m.cur >= 0 ? E.outExpo(E.prog(m.t, m.lyric.words[m.cur][0], 0.32)) : 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 30
        x: 120 - (m.t - m.seg.t0) * 60 + (1 - enter) * 160
        opacity: 0.55 * enter
        text: m.cur >= 0 ? m.lyric.words[m.cur][1].toUpperCase() : ""
        color: "#12505a"
        font.pixelSize: 520
        font.bold: true
        font.letterSpacing: -12
    }
    // anillos con forma de ventana que salen del cartel en cada bombo
    Repeater {
        model: 6
        Rectangle {
            required property int index
            readonly property real kt: TL.b(10 + index)
            readonly property real p: E.prog(m.t, kt, 0.9)
            readonly property real s: 1 + E.outExpo(p) * 1.1
            visible: m.t >= kt && p < 1
            width: dlg.width * s
            height: dlg.height * s
            x: (m.width - width) / 2
            y: (m.height - height) / 2
            color: "transparent"
            border.color: "#3fd6d6"
            border.width: 3
            opacity: Math.pow(1 - p, 2) * 0.55
        }
    }

    // ---- el cartel ----------------------------------------------------------
    Win95Dialog {
        id: dlg
        readonly property real open: E.outExpo(E.prog(m.t, m.seg.t0, 0.32))
        readonly property real die: E.inQuad(E.prog(m.t, m.dieAt + 0.06, 0.2))
        readonly property real shake: E.decay(m.t, m.breakAt, 0.22)
        k: m.k * (1 + 0.012 * m.beatEnv)
        baseW: 440
        bodyH: E.mix(TL.DIALOG_BODY, 124, open)
        title: "voz.dll — karaoke"
        icon: "none"
        buttons: ["Aceptar", "Cancelar"]
        x: (m.width - width) / 2 + (E.hash(Math.floor(m.t * 60)) - 0.5) * 26 * shake
        y: (m.height - height) / 2 + (E.hash(Math.floor(m.t * 60) + 7) - 0.5) * 18 * shake
        shadow: 12
        sweep: E.prog(m.t, m.seg.t0 + 0.04, 0.24)
        flash: 0.9 * (1 - E.prog(m.t, m.dieAt + 0.02, 0.1)) * (m.t >= m.dieAt ? 1 : 0)
        visible: die < 1
        transform: Scale {
            origin.x: dlg.width / 2; origin.y: dlg.height / 2
            yScale: 1 - dlg.die
            xScale: 1 + 0.08 * dlg.die
        }
    }

    // ---- la letra (capa aparte: tiene que poder salirse del marco) ---------
    Item {
        id: lyr
        x: dlg.x + dlg.bodyRect.x
        y: dlg.y + dlg.bodyRect.y
        width: dlg.bodyRect.width
        height: dlg.bodyRect.height

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 26

            Repeater {
                model: m.lyric.words
                Item {
                    id: word
                    required property var modelData
                    required property int index
                    readonly property real tw: modelData[0]
                    readonly property string w: modelData[1]
                    readonly property bool isFatal: index === m.fatalIdx
                    readonly property real brk: isFatal ? E.outExpo(E.prog(m.t, m.breakAt, 0.34)) : 0
                    readonly property color ink: index === m.cur ? "#000080" : "#000000"
                    width: chars.implicitWidth
                    height: chars.implicitHeight

                    // la silueta quemada que deja "fatal" al irse
                    Text {
                        visible: word.isFatal && m.t >= m.breakAt
                        opacity: 0.55 * (1 - E.prog(m.t, m.dieAt, 0.12))
                        text: word.w
                        font.pixelSize: 74
                        font.bold: true
                        color: "#8c8c8c"
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -6
                            color: "transparent"
                            border.color: "#000000"
                            border.width: 1
                            opacity: 0.5
                        }
                    }

                    Row {
                        id: chars
                        transform: [
                            Scale {
                                origin.x: chars.width / 2; origin.y: chars.height / 2
                                xScale: 1 + word.brk * 1.5; yScale: xScale
                            },
                            Rotation {
                                origin.x: chars.width / 2; origin.y: chars.height / 2
                                angle: -5 * word.brk + (word.isFatal && m.t > m.breakAt ? E.noise(m.t * 2) * 2 : 0)
                            },
                            Translate {
                                y: -330 * word.brk + (word.isFatal ? E.noise(m.t * 1.3 + 4) * 10 * word.brk : 0)
                                x: 40 * word.brk
                            }
                        ]
                        Repeater {
                            model: word.w.length
                            Item {
                                id: ch
                                required property int index
                                readonly property real tc: word.tw + index * 0.022
                                readonly property real a: E.prog(m.t, tc, 0.3)
                                // la explosión final: cada letra con su dirección
                                readonly property real boom: E.outExpo(E.prog(m.t, m.dieAt, 0.46))
                                readonly property real ang: (E.hash2(word.index, index) - 0.5) * Math.PI * 1.4 - Math.PI / 2
                                readonly property real dist: 500 + E.hash2(index, word.index + 9) * 700
                                width: glyph.implicitWidth
                                height: glyph.implicitHeight
                                visible: m.t >= tc
                                opacity: E.clamp01((m.t - tc) / 0.05) * (1 - E.prog(m.t, m.dieAt + 0.2, 0.26))

                                // sombra dura sólo cuando "fatal" está afuera
                                Text {
                                    visible: word.isFatal && word.brk > 0.01
                                    x: 5; y: 5
                                    text: word.w.charAt(ch.index)
                                    font.pixelSize: 74
                                    font.bold: true
                                    color: "#000000"
                                    opacity: 0.8 * word.brk
                                }
                                Text {
                                    id: glyph
                                    text: word.w.charAt(ch.index)
                                    font.pixelSize: 74
                                    font.bold: true
                                    color: word.isFatal && word.brk > 0.01 ? Qt.tint(word.ink, Qt.rgba(0.83, 0.18, 0.18, word.brk)) : word.ink
                                }
                                transform: [
                                    Translate {
                                        y: (1 - E.outBack(ch.a, 2.4)) * -80 + Math.sin(ch.ang) * ch.dist * ch.boom
                                        x: Math.cos(ch.ang) * ch.dist * ch.boom
                                    },
                                    Scale {
                                        origin.x: ch.width / 2; origin.y: ch.height
                                        xScale: E.mix(0.6, 1, E.outExpo(ch.a)) * (1 + ch.boom * 0.8)
                                        yScale: E.mix(1.7, 1, E.outExpo(ch.a)) * (1 + ch.boom * 0.8)
                                    },
                                    Rotation {
                                        origin.x: ch.width / 2; origin.y: ch.height / 2
                                        angle: (1 - E.outExpo(ch.a)) * (E.hash2(ch.index, word.index) - 0.5) * 60
                                               + ch.boom * (E.hash2(word.index + 3, ch.index) - 0.5) * 540
                                    }
                                ]
                            }
                        }
                    }
                }
            }
        }
    }
}
