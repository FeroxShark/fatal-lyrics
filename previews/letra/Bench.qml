// fatal-lyrics — banco de la letra en el tubo (tanda CRT, 2026-10-19), fuera de pantalla.
//
// Replica el bloque `measure` + `wholeWords` de `shell/Crt.qml` (mismos nombres, mismo tamaño
// tope, mismo Text.Fit) con `WordSlot` REAL. `mode`: "stack" = como estaba (una palabra por
// renglón), "rows" = renglones centrados (`Rows.js`). `render.py` le cambia `line`, `sw` y `sh`.
import QtQuick
import "../../shell"
import "../../shell/Rows.js" as Rows

Item {
    id: bench
    property string line: "JUST AS YOU TAKE MY HAND"
    property string mode: "rows"
    property int sw: 1280
    property int sh: 720
    width: sw
    height: sh

    readonly property var words: line.split(/\s+/).filter(w => w.length > 0)
    readonly property real shortSide: Math.min(sw, sh)
    readonly property real pad: Math.round(shortSide * 0.06)
    readonly property string fontFam: "Space Mono"
    readonly property var rows: mode === "rows"
        ? Rows.pick(words, sw - 2 * pad, sh - 2 * pad, 0.46 * shortSide, 0.6, 0.94)
        : words.map((w, i) => [i])
    readonly property real px: measure.fontInfo.pixelSize

    FontLoader { source: "../../shell/fonts/SpaceMono-Bold.ttf" }
    Rectangle { anchors.fill: parent; color: "#06121f" }

    Item {
        id: lyric
        anchors { fill: parent; margins: bench.pad }

        Text {
            id: measure
            anchors.fill: parent
            visible: false
            text: bench.rows.map(r => r.map(i => bench.words[i]).join(" ")).join("\n").toUpperCase()
            font.family: bench.fontFam
            font.bold: true
            font.letterSpacing: 3
            font.pixelSize: Math.round(bench.shortSide * 0.46)
            fontSizeMode: Text.Fit
            minimumPixelSize: 12
            lineHeight: 0.94
            wrapMode: Text.NoWrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Math.round(bench.px * 0.02)
            Repeater {
                model: bench.rows
                Row {
                    id: rowItem
                    required property var modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: bench.mode === "rows" ? implicitWidth : lyric.width
                    spacing: Math.round(bench.px * 0.3)
                    Repeater {
                        model: rowItem.modelData
                        WordSlot {
                            required property int modelData
                            index: modelData
                            word: bench.words[modelData]
                            landed: true
                            fitWidth: bench.mode === "rows"
                            pal: ({ ink: "#9fe8ff", hot: "#ffffff" })
                            fontFamily: bench.fontFam
                            letterSpacing: 3
                            pixelSize: bench.px
                            emphasis: "none"
                        }
                    }
                }
            }
        }
    }
}
