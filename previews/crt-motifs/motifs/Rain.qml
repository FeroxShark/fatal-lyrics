// fatal-lyrics — motivo `rain`: lluvia de caracteres (el dibujo está en `rain.frag`).
//
// Eran 21 `Text` largos bajando enteros: una persiana de letras quietas. Ahora cada columna tiene
// cabeza, cola y caracteres que cambian, en tres planos, y el bombo baja como un frente caliente.
//
// PARED (`docs/PARED.md`): las columnas siguen de una pantalla a la otra (`wallView`).
//
// Los caracteres son una textura horneada una vez (`live: false`). En una vista previa el `Text`
// rinde con la fuente del motivo.
import QtQuick
import "../Ease.js" as E

ThumpBase {
    id: m
    wallFit: "behind"
    property string fontFamily: "monospace"

    readonly property string glyphs: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ#$%&*+=<>/\\|?!@^~{}[]()-_:;."

    Grid {
        id: atlasItem
        width: 16 * 96
        height: 4 * 96
        columns: 16
        visible: false
        layer.enabled: false
        Repeater {
            model: 64
            Item {
                required property int index
                width: 96
                height: 96
                Text {
                    anchors.centerIn: parent
                    text: m.glyphs.charAt(index)
                    color: "white"
                    font.family: m.fontFamily
                    font.pixelSize: 92
                    renderType: Text.QtRendering
                }
            }
        }
    }
    ShaderEffectSource {
        id: atlasTex
        sourceItem: atlasItem
        hideSource: true
        live: false
        smooth: true
        visible: false
        textureSize: Qt.size(atlasItem.width, atlasItem.height)
    }
    Component.onCompleted: atlasTex.scheduleUpdate()
    onFontFamilyChanged: atlasTex.scheduleUpdate()

    ShaderEffect {
        anchors.fill: parent
        property color ink: m.colour
        property color hot: m.hot
        property color bg: m.bg
        property vector4d hitAge: m.hitAge
        property vector4d hitAmp: m.hitAmp
        property vector4d hitSeed: m.hitSeed
        property vector4d view: m.wallView
        // cae con el ritmo de la música (`clock + movOff`, `rate`) y con el carácter del tema (`drift`)
        property real drift: 0.35 * (m.clock + m.movOff) + 0.4 * m.drift
        property real dens: m.dens
        property real fizz: m.fizz
        property real dropAmt: m.dropAmt
        property real seed: E.hash(m.seed * 3.17 + 0.7)
        property real topU: m.walled ? -m.wallArea.y / 2 / m.span : m.wallView.y
        property variant atlas: atlasTex
        fragmentShader: Qt.resolvedUrl("rain.frag.qsb")
    }
}
