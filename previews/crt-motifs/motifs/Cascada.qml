// fatal-lyrics — motivo `cascada` (2026-10-22; en el sorteo, grupo `hot` de `motifGroups`).
//
// El crash de Win95 que nadie puede parar: cada tiempo cae OTRA ventana de error, un escalón
// abajo y a la derecha de la anterior, hasta que la pila llena la pantalla; al doceavo tiempo
// se cierra todo de golpe, con un puente de glitch de 120 ms (`Motion.bridgeMs`), y arranca otra
// vez. Qué hace con cada señal:
//   · tiempo (`beatN`) — una ventana por tiempo. La nueva entra con el snap de Motion (OutExpo
//     320 ms): viene de más arriba-izquierda, un poco más grande, y se asienta. Las viejas se
//     quedan quietas (se ve sólo su barra de título, como en la cascada de verdad).
//   · bombo (`thump`) — la pila entera da un tirón en diagonal con el resorte de `Thump.js`; las
//     ventanas viejas pesan más y responden más tarde (overlap: la sacudida baja por la pila).
//   · agudos (`fizz`) — una franja clara barre la ventana de arriba.
//   · densidad (`dens`) — las barras de las ventanas viejas se encienden más.
//   · carácter (`temper`) — calmo: tirón chico y largo; agitado: grande y seco (viene de `phys`).
// La pila deriva sola (`drift`, acumulada): nunca queda quieta. El texto de la ventana nueva
// nombra la palabra que viene de la letra (`nextWord`).
//
// Costo: 12 ventanas de ~10 Rectangle/Text, sólo las que ya cayeron; nada de Canvas.
import QtQuick
import "../Ease.js" as E
import "../Thump.js" as T

ThumpBase {
    id: m

    readonly property int cyc: 12
    readonly property int cur: ((beatN % cyc) + cyc) % cyc
    readonly property real cycleStart: beatN - cur

    readonly property real winW: span * 0.50
    readonly property real winH: winW * 0.42
    readonly property real step: span * 0.040
    readonly property real titleH: step * 0.96
    readonly property real stackW: winW + (cyc - 1) * step
    readonly property real stackH: winH + (cyc - 1) * step
    readonly property real ox: (width - stackW) / 2 + span * 0.02 * Math.sin(drift * 0.23)
    readonly property real oy: (height - stackH) / 2 + span * 0.015 * Math.cos(drift * 0.31)

    // cuatro masas, de la ventana nueva (liviana) a las del fondo (pesadas)
    readonly property var masses: [1, 1.8, 3, 4.6]
    readonly property var phys4: masses.map(k => T.heavy(phys, k))
    readonly property real kickAmp: span * 0.045 * (0.45 + 0.8 * temper)
    function shift(a) {
        const cls = Math.min(3, Math.floor(a / 3));
        return kickAmp * T.sum(phys4[cls], clock, hitT, hitA, 0.018 * a);
    }

    function mixC(a, b, k) { return Qt.rgba(E.mix(a.r, b.r, k), E.mix(a.g, b.g, k), E.mix(a.b, b.b, k), 1); }
    readonly property color panel: mixC(bg, colour, 0.14)
    readonly property color barOld: mixC(bg, colour, 0.34 + 0.24 * dens)
    readonly property real flash: 1 - E.outQuad(bp)

    readonly property var titles: ["FATAL.EXE", "Error", "KERNEL32", "Stack Fault", "System", "Application Error"]
    readonly property var msgs: ["This program has performed an illegal operation",
                                 "Fatal exception 0E has occurred at 0028:C0011E36",
                                 "A fatal error has occurred",
                                 "General protection fault in module",
                                 "Not enough memory to continue",
                                 "Page fault in module USER.EXE"]
    function pick(list, n, salt) { return list[Math.floor(E.hash(n * 7.13 + salt + seed * 5.0) * list.length)]; }

    // el puente del crash: 120 ms de barras desplazadas cuando la pila se cierra y arranca de nuevo
    readonly property bool bridging: beatN > 0 && cur === 0 && sinceTick < 0.12

    Repeater {
        model: m.cyc
        delegate: Item {
            id: w
            required property int index
            readonly property int a: m.cur - index
            readonly property real n: m.cycleStart + index
            readonly property real e: a === 0 ? E.outExpo(E.prog(m.sinceTick, 0, 0.32)) : 1
            readonly property real k: m.shift(Math.max(a, 0))
            visible: a >= 0
            z: index
            width: m.winW
            height: m.winH
            x: m.ox + index * m.step + k - (1 - e) * m.step * 3.2
            y: m.oy + index * m.step + k * 0.55 - (1 - e) * m.step * 2.4
            scale: 1 + 0.10 * (1 - e)
            opacity: Math.min(1, e * 5)

            Rectangle {
                anchors.fill: parent
                color: m.panel
                border.width: Math.max(2, m.span * 0.003)
                border.color: w.a === 0 ? m.colour : m.mixC(m.bg, m.colour, 0.6)
            }
            Rectangle {
                id: bar
                x: 2
                y: 2
                width: parent.width - 4
                height: m.titleH - 2
                color: w.a === 0 ? m.mixC(m.colour, m.hot, m.flash * 0.7) : m.barOld
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: m.titleH * 0.35
                    text: m.pick(m.titles, w.n, 1.0)
                    color: m.bg
                    font.family: m.fontFamily
                    font.pixelSize: m.titleH * 0.80
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: m.titleH * 0.15
                    anchors.verticalCenter: parent.verticalCenter
                    width: m.titleH * 0.78
                    height: width
                    color: m.panel
                    border.width: 1
                    border.color: m.bg
                    Text {
                        anchors.centerIn: parent
                        text: "x"
                        color: m.colour
                        font.family: m.fontFamily
                        font.pixelSize: m.titleH * 0.72
                    }
                }
            }
            // el cuerpo sólo se ve en la ventana de arriba: las demás lo tapa la que sigue
            Item {
                visible: w.a === 0
                anchors.fill: parent
                anchors.topMargin: m.titleH + 2
                Rectangle {
                    id: icon
                    x: m.winH * 0.07
                    y: m.winH * 0.07
                    width: m.winH * 0.20
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: m.hot
                    Text {
                        anchors.centerIn: parent
                        text: "X"
                        color: m.hot
                        font.family: m.fontFamily
                        font.pixelSize: icon.height * 0.8
                    }
                }
                Text {
                    x: icon.x + icon.width + m.winH * 0.06
                    y: icon.y - 2
                    width: m.winW - x - m.winH * 0.06
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: m.pick(m.msgs, w.n, 2.0) + (m.nextWord !== "" ? "\nCannot find \"" + m.nextWord.toUpperCase() + "\"" : "")
                    color: m.colour
                    font.family: m.fontFamily
                    font.pixelSize: m.winH * 0.115
                    lineHeight: 0.92
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: m.winH * 0.07
                    width: m.winW * 0.20
                    height: m.winH * 0.20
                    color: m.panel
                    border.width: 2
                    border.color: m.colour
                    Text {
                        anchors.centerIn: parent
                        text: "OK"
                        color: m.colour
                        font.family: m.fontFamily
                        font.pixelSize: parent.height * 0.62
                    }
                }
                // agudos: una franja clara barre la ventana de arriba
                Rectangle {
                    width: parent.width
                    height: Math.max(2, m.winH * 0.03)
                    y: parent.height * E.wrap(m.drift * 0.35, 1)
                    color: m.hot
                    opacity: 0.5 * m.fizz
                }
            }
        }
    }

    // glitch del cierre de la pila: tres barras de la pantalla corridas, 2–3 cuadros
    Repeater {
        model: 3
        delegate: Rectangle {
            required property int index
            visible: m.bridging
            z: 100
            readonly property real q: Math.floor(m.clock * 30)
            x: (E.hash(q * 3.1 + index) - 0.5) * m.span * 0.35
            y: m.height * E.hash(q * 1.7 + index * 5.0 + m.seed)
            width: m.width
            height: m.height * (0.03 + 0.06 * E.hash(q + index * 9.0))
            color: index === 1 ? m.hot : m.colour
            opacity: 0.55
        }
    }
}
