// fatal-lyrics — motivo `estela` (2026-10-22; en el sorteo, grupo `hot` de `motifGroups`).
//
// La ventana colgada que arrastrás por un Windows que no repinta: cada posición por la que pasa
// queda dibujada, y la pila de ecos hace una escalera de barras de título (el "hall of mirrors"
// de Win95). Un puntero la agarra de la barra. Qué hace con cada señal:
//   · tiempo (`beatN`) — en cada tiempo la ventana se arrastra a otro lugar de la pantalla con el
//     snap de Motion (OutExpo 320 ms); después se asienta y se queda (hold) hasta el próximo. La
//     estela es el pasado de ese recorrido: el eco `i` está donde la ventana estaba `i·gap`
//     segundos antes, así que el dibujo es función pura del reloj, sin historia guardada.
//   · bombo (`thump`) — el resorte de `Thump.js` ABRE la estela (los ecos se separan más) y la
//     ventana respira de tamaño; vuelve con el mismo resorte.
//   · agudos (`fizz`) — el eco más reciente parpadea en `hot`.
//   · densidad (`dens`) — más ecos (hasta 28) y más corridos entre sí.
//   · drop (`dropAmt`) — la estela entera se enciende en `hot`, de a un eco.
// Por debajo la ventana deriva sola (`drift`, acumulada), así los ecos nunca se montan del todo.
//
// Costo: ≤ 28 ecos de 2 Rectangle + el contenido del de adelante; cero Canvas.
import QtQuick
import QtQuick.Shapes
import "../Ease.js" as E
import "../Thump.js" as T

ThumpBase {
    id: m

    readonly property int maxEchoes: 28
    readonly property int echoes: Math.max(10, Math.round((14 + 14 * dens) * quality))

    readonly property real winW: span * 0.42
    readonly property real winH: winW * 0.50
    readonly property real titleH: winW * 0.085

    readonly property var camPhys: T.heavy(phys, 2.2)
    // 0 en reposo; el golpe separa los ecos y la ventana respira
    readonly property real open: T.sum(camPhys, clock, hitT, hitA, 0.0)
    // segundos entre ecos: calmo, apretados; con el golpe y la densidad, abiertos
    readonly property real gap: Math.max(0.012, 0.022 + 0.02 * dens + 0.045 * Math.max(0, open) + 0.012 * temper)

    // dónde cae el arrastre número `n` (centro de la ventana, en px)
    function target(n) {
        const mx = (width - winW) * 0.5, my = (height - winH) * 0.5;
        const u = E.hash(n * 5.31 + seed * 17.0), v = E.hash(n * 9.77 + seed * 3.0 + 7.0);
        return Qt.point(width * 0.5 + (u * 2 - 1) * mx * 0.92, height * 0.5 + (v * 2 - 1) * my * 0.92);
    }
    // dónde está la ventana `s` segundos ANTES de ahora
    function at(s) {
        const t = sinceTick + s;
        const back = Math.floor(t / beatS);
        const age = t - back * beatS;
        const n = beatN - back;
        const a = target(n - 1), b = target(n);
        const k = E.outExpo(E.prog(age, 0, 0.32));
        const lag = drift - s * 0.8;
        return Qt.point(E.mix(a.x, b.x, k) + span * 0.018 * Math.sin(lag * 0.9),
                        E.mix(a.y, b.y, k) + span * 0.014 * Math.cos(lag * 0.7));
    }

    function mixC(a, b, k) { return Qt.rgba(E.mix(a.r, b.r, k), E.mix(a.g, b.g, k), E.mix(a.b, b.b, k), 1); }
    readonly property color panel: mixC(bg, colour, 0.12)
    readonly property real flash: 1 - E.outQuad(bp)

    Repeater {
        model: m.maxEchoes
        delegate: Item {
            id: ec
            required property int index
            // el eco 0 es el de ADELANTE (la ventana de verdad); el resto, los que quedaron atrás
            readonly property int i: index
            readonly property bool live: i < m.echoes
            readonly property point p: m.at(i * m.gap)
            readonly property real age01: i / Math.max(1, m.echoes - 1)
            // pintados de atrás hacia adelante: el eco 0 tapa a todos
            z: m.maxEchoes - i
            visible: live
            width: m.winW * (1 + 0.05 * Math.max(0, m.open))
            height: m.winH * (1 + 0.05 * Math.max(0, m.open))
            x: p.x - width / 2
            y: p.y - height / 2
            // la estela se apaga con la edad; en el drop se prende en `hot` de a un eco
            readonly property real lit: m.dropAmt * (0.5 + 0.5 * Math.sin(m.drift * 2.0 - i * 0.6))

            Rectangle {
                anchors.fill: parent
                color: m.panel
                border.width: Math.max(2, m.span * 0.003)
                border.color: m.mixC(m.bg, ec.lit > 0.6 ? m.hot : m.colour, 0.85 - 0.6 * ec.age01)
            }
            Rectangle {
                x: 2
                y: 2
                width: parent.width - 4
                height: m.titleH
                color: ec.i === 0 ? m.mixC(m.colour, m.hot, 0.6 * m.flash + 0.7 * m.fizz)
                                  : m.mixC(m.bg, ec.lit > 0.6 ? m.hot : m.colour, 0.75 - 0.5 * ec.age01)
                Text {
                    visible: ec.i < 3
                    anchors.verticalCenter: parent.verticalCenter
                    x: m.titleH * 0.4
                    text: "FATAL.EXE (Not Responding)"
                    color: m.bg
                    font.family: m.fontFamily
                    font.pixelSize: m.titleH * 0.82
                }
            }
            // el contenido sólo en la ventana de adelante
            Item {
                visible: ec.i === 0
                anchors.fill: parent
                anchors.topMargin: m.titleH + 4
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        x: m.winH * 0.10
                        y: m.winH * 0.08 + index * m.winH * 0.17
                        width: m.winW * (0.55 + 0.35 * E.hash(index * 3.3 + m.seed))
                        height: m.winH * 0.07
                        color: m.colour
                        opacity: 0.55
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: m.winH * 0.08
                    text: m.nextWord !== "" ? m.nextWord.toUpperCase() : "..."
                    color: m.hot
                    font.family: m.fontFamily
                    font.pixelSize: m.winH * 0.17
                }
            }
        }
    }

    // el puntero, agarrado de la barra de título de la ventana de adelante
    Shape {
        id: cursor
        z: 1000
        readonly property point p: m.at(0)
        x: p.x - m.winW / 2 + m.winW * 0.30
        y: p.y - m.winH / 2 + m.titleH * 0.4
        scale: m.span / 700
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            strokeWidth: 1.5
            strokeColor: m.bg
            fillColor: m.hot
            startX: 0; startY: 0
            PathLine { x: 0; y: 17 }
            PathLine { x: 4; y: 13 }
            PathLine { x: 7; y: 20 }
            PathLine { x: 10; y: 19 }
            PathLine { x: 7; y: 12 }
            PathLine { x: 12; y: 12 }
            PathLine { x: 0; y: 0 }
        }
    }
}
