// Hoja de muestra de las fuentes de la letra del CRT (tanda 8). La letra se
// dibuja como en `shell/Crt.qml`: MAYÚSCULAS, `font.bold` sólo con archivo Bold
// (`crtFontBold` de shell.qml; tanda letra: las Regular-only ya no se engordan
// en sintético, y acá se ven las dos líneas, antes y después), tracking de
// 0.03 em (`lyricTrackingEm`). Carga los MISMOS archivos que `shell/shell.qml`.
// Render: `./fontsheet.py` (offscreen, nunca abre ventana).
import QtQuick

Rectangle {
    id: sheet
    width: 1920
    height: 1400
    color: "#0b1418"

    readonly property string phrase: "¿Por qué no volvés, corazón? Año del pingüino"

    // clave → [archivo, qué es, mazos de `crtFontPools` donde está]
    readonly property var rows: [
        ["plex", "IBMPlexMono-Bold.ttf", "IBM Plex Mono Bold", "typed · soft", true],
        ["space", "SpaceMono-Bold.ttf", "Space Mono Bold", "hard · burn", true],
        ["chakra", "ChakraPetch-Bold.ttf", "Chakra Petch Bold", "hard · burn", true],
        ["syne", "SyneMono-Regular.ttf", "Syne Mono (sólo Regular)", "soft", false],
        ["vt323", "VT323-Regular.ttf", "VT323 (sólo Regular)", "typed · burn", false],
        ["share", "ShareTechMono-Regular.ttf", "Share Tech Mono (sólo Regular)", "typed · soft", false],
        ["dot", "DotGothic16-Regular.ttf", "DotGothic16 (sólo Regular)", "CJK", false],
        ["system", "", "sistema", "hard · soft", true],
    ]

    Text {
        x: 40; y: 24
        text: "cartelitos · fuentes de la letra — sin negrita sintética donde no hay archivo Bold"
        color: "#6f8f96"; font.pixelSize: 26; font.family: "monospace"
    }

    Column {
        x: 40; y: 80
        spacing: 10
        Repeater {
            model: sheet.rows
            Item {
                required property var modelData
                width: 1840; height: modelData[4] ? 128 : 190
                FontLoader {
                    id: fl
                    source: modelData[1] === "" ? "" : "../../shell/fonts/" + modelData[1]
                }
                Text {
                    y: 0
                    text: modelData[0] + " — " + modelData[2]
                        + (modelData[1] === "" ? " (en este render: " + line.fontInfo.family + ")" : "")
                        + " — set: " + modelData[3] + (modelData[4] ? "" : " — arriba: antes (bold sintético) · abajo: ahora")
                    color: "#6f8f96"; font.pixelSize: 22; font.family: "monospace"
                }
                // antes: lo que hacía la letra con `font.bold: true` sobre un Regular
                Text {
                    visible: !modelData[4]
                    y: 32; width: parent.width; height: 60
                    text: sheet.phrase.toUpperCase()
                    color: "#5a8a96"
                    font.family: fl.name
                    font.bold: true
                    font.letterSpacing: 3
                    font.pixelSize: 48
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 20
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    id: line
                    y: modelData[4] ? 32 : 96; width: parent.width; height: 90
                    text: sheet.phrase.toUpperCase()
                    color: "#7fe3d6"
                    font.family: modelData[1] === "" ? "" : fl.name
                    font.bold: modelData[4]
                    font.letterSpacing: Math.round(72 * 0.03 * 10) / 10
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
