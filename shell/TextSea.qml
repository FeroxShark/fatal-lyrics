// fatal-lyrics — la marea de texto.
//
// La letra ENTERA del tema (el evento `lyrics`) corriendo hacia arriba como
// los créditos del final, chiquita, en una columna centrada. La línea que se
// está cantando pasa encendida y con halo; el resto va apagado. Es la única
// animación que dice de qué habla el tema en vez de acompañarlo: en una
// pantalla lateral se lee como la letra impresa pasando de largo mientras el
// verso que suena está en la de al lado.
//
// El paso es el COMPÁS (una línea por tiempo, o ~0.8 s sin tempo confiable) y
// además hay un tirón suave hacia la línea que suena: sin él, a los dos versos
// la columna va por cualquier lado y la línea encendida queda fuera de
// pantalla. Con la letra sin sincronizar no hay línea actual y sólo corre.
import QtQuick

Item {
    id: sea

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    Behavior on level { NumberAnimation { duration: Motion.levelMs; easing.type: Easing.OutQuad } }
    property bool running: true
    property string fontFamily: "monospace"
    property real seed: 0

    // la letra entera: [{ t0, t1, text }]
    property var lines: []
    // el verso que suena (índice en `lines`); -1 = no se sabe y no se resalta
    property int lineNo: -1
    property bool synced: true

    property real beatMs: 500
    property bool bpmLive: false
    // lo que tarda en subir UNA línea
    readonly property real stepMs: bpmLive && beatMs > 0 ? beatMs : 800

    // T4.1: la caja mide lo que mide la pantalla, así que el renglón se mide
    // contra ella directo (antes descontaba el overscan de la cámara).
    readonly property real lineH: Math.max(2, Math.round(height * 0.032))
    readonly property real fontPx: Math.max(1, Math.round(height * 0.020))

    // Tope: una letra de doscientas líneas son doscientos bindings por cuadro y
    // nadie ve más allá de la pantalla. Se recorta alrededor del verso que
    // suena, no por el principio.
    readonly property int cap: 90
    readonly property int from: Math.max(0, Math.min((lineNo >= 0 ? lineNo : 0) - cap / 2,
                                                     lines.length - cap))
    readonly property var shown: lines.slice(Math.max(from, 0),
                                             Math.max(from, 0) + cap)

    // dónde está la columna, medida en líneas
    property real scroll: 0
    FrameAnimation {
        running: sea.running && sea.visible && sea.lines.length > 0
        onTriggered: {
            const dt = frameTime;
            sea.scroll += dt * 1000 / sea.stepMs;
            // el tirón hacia el verso que suena: es una corrección lenta, no un
            // salto — la columna nunca deja de subir parejo
            if (sea.synced && sea.lineNo >= 0)
                sea.scroll += (sea.lineNo - sea.scroll) * Math.min(dt * 1.1, 0.4);
        }
    }
    onLineNoChanged: {
        // entrar a mitad de tema (o un rebobinado) deja la columna a cincuenta
        // líneas: eso no se corrige subiendo, se salta
        if (synced && lineNo >= 0 && Math.abs(lineNo - scroll) > 6)
            scroll = lineNo;
    }

    Item {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.7
        height: parent.height
        clip: true

        Repeater {
            model: sea.shown

            Item {
                id: row
                required property int index
                required property var modelData
                readonly property int lineIdx: Math.max(sea.from, 0) + index
                readonly property bool current: sea.synced && sea.lineNo === lineIdx

                width: column.width
                height: sea.lineH
                y: column.height * 0.5 + (lineIdx - sea.scroll) * sea.lineH
                visible: y > -sea.lineH * 2 && y < column.height + sea.lineH

                // El halo de la línea que suena son dos copias escaladas. No hay
                // desenfoque en este shell (Qt5Compat.GraphicalEffects no se
                // importa en ningún lado) y dos copias grandes y transparentes
                // se leen igual de bien a este tamaño de letra.
                Text {
                    anchors.centerIn: parent
                    visible: row.current
                    text: row.modelData.text || ""
                    color: sea.hot
                    opacity: 0.22 + 0.12 * sea.level
                    scale: 1.18
                    font.family: sea.fontFamily
                    font.pixelSize: sea.fontPx
                    horizontalAlignment: Text.AlignHCenter
                    width: column.width
                    elide: Text.ElideRight
                }
                Text {
                    anchors.centerIn: parent
                    visible: row.current
                    text: row.modelData.text || ""
                    color: sea.hot
                    opacity: 0.42
                    scale: 1.07
                    font.family: sea.fontFamily
                    font.pixelSize: sea.fontPx
                    horizontalAlignment: Text.AlignHCenter
                    width: column.width
                    elide: Text.ElideRight
                }
                Text {
                    anchors.centerIn: parent
                    text: row.modelData.text || ""
                    color: row.current ? sea.hot : sea.colour
                    opacity: row.current ? 1 : 0.35
                    font.family: sea.fontFamily
                    font.pixelSize: sea.fontPx
                    horizontalAlignment: Text.AlignHCenter
                    width: column.width
                    elide: Text.ElideRight
                }
            }
        }
    }
}
