// Hoja de muestra de las fuentes de la letra del CRT (tanda 8). La letra se
// dibuja como en `shell/Crt.qml`: MAYÚSCULAS, `font.bold: true`,
// `letterSpacing: 3`. Carga los MISMOS archivos que `shell/shell.qml`.
// Render: `./fontsheet.py` (offscreen, nunca abre ventana).
import QtQuick

Rectangle {
    id: sheet
    width: 1920
    height: 1080
    color: "#0b1418"

    readonly property string phrase: "¿Por qué no volvés, corazón? Año del pingüino"

    // clave → [archivo, qué es, mazos de `crtFontPools` donde está]
    readonly property var rows: [
        ["plex", "IBMPlexMono-Bold.ttf", "IBM Plex Mono Bold · NUEVA", "typed · soft"],
        ["space", "SpaceMono-Bold.ttf", "Space Mono Bold · NUEVA", "hard · burn"],
        ["chakra", "ChakraPetch-Bold.ttf", "Chakra Petch Bold · NUEVA", "hard · burn"],
        ["syne", "SyneMono-Regular.ttf", "Syne Mono · NUEVA", "soft"],
        ["vt323", "VT323-Regular.ttf", "VT323 · ya estaba", "typed · burn"],
        ["share", "ShareTechMono-Regular.ttf", "Share Tech Mono · ya estaba", "typed · soft"],
        ["system", "", "sistema · ya estaba", "hard · soft"],
    ]

    Text {
        x: 40; y: 24
        text: "cartelitos · fuentes de la letra (tanda 8) — fuera Press Start 2P"
        color: "#6f8f96"; font.pixelSize: 26; font.family: "monospace"
    }

    Column {
        x: 40; y: 80
        spacing: 10
        Repeater {
            model: sheet.rows
            Item {
                required property var modelData
                width: 1840; height: 128
                FontLoader {
                    id: fl
                    source: modelData[1] === "" ? "" : "../../shell/fonts/" + modelData[1]
                }
                Text {
                    y: 0
                    text: modelData[0] + " — " + modelData[2]
                        + (modelData[1] === "" ? " (en este render: " + line.fontInfo.family + ")" : "")
                        + " — set: " + modelData[3]
                    color: "#6f8f96"; font.pixelSize: 22; font.family: "monospace"
                }
                Text {
                    id: line
                    y: 32; width: parent.width; height: 90
                    text: sheet.phrase.toUpperCase()
                    color: "#7fe3d6"
                    font.family: modelData[1] === "" ? "" : fl.name
                    font.bold: true
                    font.letterSpacing: 3
                    font.pixelSize: 72
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 20
                    verticalAlignment: Text.AlignVCenter
                    Component.onCompleted: console.log("fontsheet:", modelData[0], "->", fontInfo.family, fontInfo.styleName)
                }
            }
        }
    }
}
