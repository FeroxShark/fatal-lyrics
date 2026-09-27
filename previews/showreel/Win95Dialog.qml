// fatal-lyrics showreel — el cartelito, dibujado con geometría EXPLÍCITA.
//
// Es el mismo diálogo de shell.qml (bevel 2px, barra #000080→#1084d0, ícono,
// botones de 76x24 con el default marcado), pero cada rectángulo se ubica con
// números, no con Row/Column: el zoom del drop necesita saber DÓNDE está el
// botón "Aceptar" para meter el próximo diálogo adentro (`buttonRect`).
// Todas las medidas son unidades base × k.
import QtQuick

Item {
    id: d

    property real k: 1
    property real baseW: 420
    property real bodyH: 60                 // alto del cuerpo, en unidades base
    property string title: "fatal.exe"
    property string text: ""
    property color textColor: "#000000"
    property real textSize: 13
    property string icon: "error"           // error | warning | question | info | none
    property var buttons: ["Aceptar"]
    property int defaultIndex: 0
    property int pressedIndex: -1
    property bool hung: false               // colgado: barra gris + "(No responde)"
    property bool inactive: false           // sin foco: barra gris, como Win95 con la de atrás
    property real sweep: -1                 // 0..1: reflejo cruzando la barra; <0 = no
    property real flash: 0                  // destello blanco del nacimiento
    property real progress: -1              // 0..1: barra "Copiando..." en el cuerpo
    property color face: "#c0c0c0"
    property color titleA: hung ? "#5a5a5a" : inactive ? "#808080" : "#000080"
    property color titleB: hung ? "#9a9a9a" : inactive ? "#b8b8b8" : "#1084d0"
    property real shadow: 0                 // sombra dura, en unidades base
    default property alias content: bodyExtra.data

    readonly property real titleH: 26
    property real btnW: 76
    property real btnH: 24
    property real btnGap: 8
    property real btnTextSize: 12
    readonly property real baseH: 2 + titleH + bodyH + btnH + 12 + 2

    width: baseW * k
    height: baseH * k

    // rectángulo del botón i, en coordenadas del diálogo (px, ya × k)
    function buttonRect(i) {
        const n = buttons.length;
        const rowW = n * btnW + (n - 1) * btnGap;
        const x0 = (baseW - rowW) / 2 + i * (btnW + btnGap);
        const y0 = 2 + titleH + bodyH;
        return Qt.rect(x0 * k, y0 * k, btnW * k, btnH * k);
    }
    // área del cuerpo (debajo de la barra, arriba de los botones)
    readonly property rect bodyRect: Qt.rect(2 * k, (2 + titleH) * k, (baseW - 4) * k, bodyH * k)

    // sombra dura desplazada (los carteles apilados se leen por capas)
    Rectangle {
        visible: d.shadow > 0
        x: d.shadow * d.k; y: d.shadow * d.k
        width: d.width; height: d.height
        color: "#000000"
        opacity: 0.45
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        color: d.face
        clip: true

        Rectangle { x: 0; y: 0; width: parent.width; height: 2 * d.k; color: "#ffffff" }
        Rectangle { x: 0; y: 0; width: 2 * d.k; height: parent.height; color: "#ffffff" }
        Rectangle { x: 0; y: parent.height - 2 * d.k; width: parent.width; height: 2 * d.k; color: "#404040" }
        Rectangle { x: parent.width - 2 * d.k; y: 0; width: 2 * d.k; height: parent.height; color: "#404040" }

        // barra de título
        Rectangle {
            id: bar
            x: 2 * d.k; y: 2 * d.k
            width: parent.width - 4 * d.k
            height: d.titleH * d.k
            clip: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: d.titleA }
                GradientStop { position: 1.0; color: d.titleB }
            }
            Rectangle {
                visible: d.sweep >= 0 && d.sweep <= 1
                width: 40 * d.k
                height: parent.height
                x: -width + d.sweep * (parent.width + width)
                color: "#ffffff"
                opacity: 0.5
            }
            Text {
                x: 8 * d.k
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 40 * d.k
                text: d.hung ? d.title + " (No responde)" : d.title
                color: "#ffffff"
                font.pixelSize: Math.max(1, Math.round(12 * d.k))
                font.bold: true
                elide: Text.ElideRight
            }
            // ✕
            Rectangle {
                x: parent.width - (18 + 4) * d.k
                y: (d.titleH - 16) / 2 * d.k
                width: 18 * d.k; height: 16 * d.k
                color: "#c0c0c0"
                Rectangle { x: 0; y: 0; width: parent.width; height: d.k; color: "#ffffff" }
                Rectangle { x: 0; y: 0; width: d.k; height: parent.height; color: "#ffffff" }
                Rectangle { x: 0; y: parent.height - d.k; width: parent.width; height: d.k; color: "#404040" }
                Rectangle { x: parent.width - d.k; y: 0; width: d.k; height: parent.height; color: "#404040" }
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "#000000"
                    font.pixelSize: Math.max(1, Math.round(10 * d.k))
                    font.bold: true
                }
            }
        }

        // ícono
        Canvas {
            id: iconCanvas
            visible: d.icon !== "none"
            x: 16 * d.k
            y: (2 + d.titleH + Math.max(14, (d.bodyH - 32) / 2)) * d.k
            // sin ícono (o gigante, en el zoom del drop) no hay lienzo: un Canvas
            // de miles de px no se puede alocar y QPainter llena el log
            readonly property bool live: d.icon !== "none" && d.k < 20
            width: live ? 32 * d.k : 0; height: width
            property string kind: d.icon
            onKindChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.scale(width / 32, height / 32);
                if (kind === "warning") {
                    c.beginPath(); c.moveTo(16, 2); c.lineTo(30, 29); c.lineTo(2, 29); c.closePath();
                    c.fillStyle = "#ffd800"; c.fill();
                    c.lineWidth = 1.5; c.strokeStyle = "#000000"; c.stroke();
                    c.fillStyle = "#000000"; c.fillRect(14.6, 11, 2.8, 10); c.fillRect(14.6, 23.5, 2.8, 2.8);
                } else if (kind === "error") {
                    c.beginPath(); c.arc(16, 16, 14, 0, Math.PI * 2);
                    c.fillStyle = "#d32f2f"; c.fill();
                    c.strokeStyle = "#7a0000"; c.lineWidth = 1; c.stroke();
                    c.strokeStyle = "#ffffff"; c.lineWidth = 3.2; c.lineCap = "round";
                    c.beginPath(); c.moveTo(10.5, 10.5); c.lineTo(21.5, 21.5);
                    c.moveTo(21.5, 10.5); c.lineTo(10.5, 21.5); c.stroke();
                } else if (kind === "question" || kind === "info") {
                    c.beginPath(); c.arc(16, 16, 14, 0, Math.PI * 2);
                    c.fillStyle = "#2458c8"; c.fill();
                    c.strokeStyle = "#0a1f66"; c.lineWidth = 1; c.stroke();
                    c.fillStyle = "#ffffff";
                    if (kind === "question") {
                        c.textAlign = "center"; c.textBaseline = "middle";
                        c.font = "bold 20px sans-serif"; c.fillText("?", 16, 17);
                    } else {
                        c.beginPath(); c.arc(16, 10.2, 2.3, 0, Math.PI * 2); c.fill();
                        c.fillRect(14.6, 14.2, 2.8, 9.4);
                    }
                }
            }
        }

        // texto del cuerpo
        Text {
            visible: d.text !== ""
            x: (d.icon === "none" ? 16 : 62) * d.k
            y: (2 + d.titleH) * d.k
            width: (d.baseW - (d.icon === "none" ? 32 : 78)) * d.k
            height: (d.progress >= 0 ? d.bodyH * 0.55 : d.bodyH) * d.k
            verticalAlignment: Text.AlignVCenter
            text: d.text
            color: d.textColor
            font.pixelSize: Math.max(1, Math.round(d.textSize * d.k))
            wrapMode: Text.Wrap
        }

        // barra de progreso Win95 (bloques azules en un surco hundido)
        Item {
            visible: d.progress >= 0
            x: 62 * d.k
            y: (2 + d.titleH + d.bodyH * 0.58) * d.k
            width: (d.baseW - 78) * d.k
            height: 16 * d.k
            Rectangle { anchors.fill: parent; color: "#c0c0c0" }
            Rectangle { x: 0; y: 0; width: parent.width; height: d.k; color: "#808080" }
            Rectangle { x: 0; y: 0; width: d.k; height: parent.height; color: "#808080" }
            Rectangle { x: 0; y: parent.height - d.k; width: parent.width; height: d.k; color: "#ffffff" }
            Rectangle { x: parent.width - d.k; y: 0; width: d.k; height: parent.height; color: "#ffffff" }
            Repeater {
                model: d.progress >= 0 ? Math.max(0, Math.floor((parent.width - 4 * d.k) / (10 * d.k))) : 0
                Rectangle {
                    required property int index
                    readonly property int total: Math.floor((parent.width - 4 * d.k) / (10 * d.k))
                    visible: index < Math.floor(d.progress * total + 0.0001)
                    x: 2 * d.k + index * 10 * d.k
                    y: 2 * d.k
                    width: 8 * d.k
                    height: parent.height - 4 * d.k
                    color: "#000080"
                }
            }
        }

        // lo que el módulo quiera meter en el cuerpo (letra, scope...)
        Item {
            id: bodyExtra
            x: d.bodyRect.x; y: d.bodyRect.y
            width: d.bodyRect.width; height: d.bodyRect.height
        }

        // botones
        Repeater {
            model: d.buttons
            Rectangle {
                required property string modelData
                required property int index
                readonly property rect r: d.buttonRect(index)
                readonly property bool isDef: index === d.defaultIndex
                readonly property bool down: index === d.pressedIndex
                x: r.x; y: r.y; width: r.width; height: r.height
                color: down ? "#a8a8a8" : "#c0c0c0"
                border.width: isDef ? d.k : 0
                border.color: "#000000"
                readonly property real m: isDef ? d.k : 0
                Rectangle { x: parent.m; y: parent.m; width: parent.width - 2 * parent.m; height: d.k; color: parent.down ? "#404040" : "#ffffff" }
                Rectangle { x: parent.m; y: parent.m; width: d.k; height: parent.height - 2 * parent.m; color: parent.down ? "#404040" : "#ffffff" }
                Rectangle { x: parent.m; y: parent.height - parent.m - d.k; width: parent.width - 2 * parent.m; height: d.k; color: parent.down ? "#ffffff" : "#404040" }
                Rectangle { x: parent.width - parent.m - d.k; y: parent.m; width: d.k; height: parent.height - 2 * parent.m; color: parent.down ? "#ffffff" : "#404040" }
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: parent.down ? d.k : 0
                    anchors.verticalCenterOffset: parent.down ? d.k : 0
                    text: parent.modelData
                    color: "#000000"
                    font.pixelSize: Math.max(1, Math.round(d.btnTextSize * d.k))
                }
                // foco punteado del botón default
                Rectangle {
                    visible: parent.isDef
                    x: 4 * d.k; y: 4 * d.k
                    width: parent.width - 8 * d.k; height: parent.height - 8 * d.k
                    color: "transparent"
                    border.width: Math.max(1, d.k * 0.8)
                    border.color: "#000000"
                    opacity: 0.55
                }
            }
        }

        Rectangle { anchors.fill: parent; color: "#ffffff"; opacity: d.flash; visible: d.flash > 0.001 }
    }
}
