// fatal-lyrics — el tubo de plasma.
//
// La lámpara de lava: cuatro a seis bolas de luz que se juntan y se separan
// adentro del vidrio. La física está en `plasma.frag` (campos 1/r² sumados, la
// superficie donde la suma cruza uno) y acá arriba queda el reloj, los colores
// y cuánto se agita.
//
// El reloj YA viene multiplicado por la parte del tema: en la estrofa la cera
// se mueve despacio y en el estribillo se apura, sin que el shader tenga que
// saber en qué parte del tema va.
import QtQuick

Item {
    id: lamp

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    Behavior on level { NumberAnimation { duration: 420; easing.type: Easing.OutQuad } }
    property real low: 0.4            // los graves: empujan las bolas para arriba
    Behavior on low { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
    property real surge: 0            // el golpe del tubo: la superficie tiembla
    property real energy: 1.0
    property real seed: 0
    property real quality: 1.0
    property real dim: 1.0
    property bool running: true

    // Una bola menos en una pantalla que sufre. El shader recorre siempre seis
    // (GLSL ES 100 no acepta un tope variable) y las que sobran pesan cero.
    readonly property real balls: quality >= 0.9 ? 6 : (quality >= 0.6 ? 5 : 4)

    // Reloj propio, escalado por la energía: es la velocidad de la cera.
    property real clock: 0
    property real pending: 0
    FrameAnimation {
        running: lamp.running && lamp.visible
        onTriggered: {
            lamp.pending += frameTime * Math.max(lamp.energy, 0.35);
            if (lamp.pending >= 0.0142) {
                lamp.clock += lamp.pending;
                lamp.pending = 0;
            }
        }
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true
        // como el resto: con la pantalla quieta la lámpara sigue ahí, congelada
        visible: lamp.width > 0 && lamp.height > 0

        property real t: lamp.clock
        property real seed: lamp.seed
        property real level: lamp.level
        property real low: lamp.low
        property real agit: lamp.surge
        property real count: lamp.balls
        property real dim: lamp.dim
        property variant res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property variant ink: Qt.vector3d(lamp.colour.r, lamp.colour.g, lamp.colour.b)
        property variant hot: Qt.vector3d(lamp.hot.r, lamp.hot.g, lamp.hot.b)

        fragmentShader: Qt.resolvedUrl("plasma.frag.qsb")
    }
}
