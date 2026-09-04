// fatal-lyrics — la mancha.
//
// La lámina de Rorschach: simétrica por construcción (todo lo que dibuja
// `rorschach.frag` es función de `abs(x - 0.5)`) y viva porque el umbral del
// ruido baja con el volumen. Acá arriba queda lo que el shader no puede saber:
// el reloj, los colores de la pantalla y el salpicón del golpe.
import QtQuick

Item {
    id: blot

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    Behavior on level { NumberAnimation { duration: 420; easing.type: Easing.OutQuad } }
    property real pitch: 0.5          // el registro: cuánto se retuerce
    property real seed: 0             // 0..1: otra lámina en cada aparición
    property real energy: 1.0         // la parte del tema: la deriva del ruido
    property real dim: 1.0
    property int kick: 0
    property bool running: true

    // El salpicón dura CASI un cuadro. Con 90 ms se ve el salto y vuelve; con
    // medio segundo la mancha late, que es otra cosa (y ya la hace el volumen).
    property real splash: 0
    onKickChanged: {
        if (!running)
            return;
        splashAnim.stop();
        splash = 1;
        splashAnim.start();
    }
    NumberAnimation {
        id: splashAnim
        target: blot
        property: "splash"
        to: 0
        duration: 90
        easing.type: Easing.OutQuad
    }

    // Reloj propio: el del tubo va a 20 Hz en las pantallas sin letra y la
    // deriva de la tinta se vería a saltos.
    property real clock: 0
    property real pending: 0
    FrameAnimation {
        running: blot.running && blot.visible
        onTriggered: {
            blot.pending += frameTime * Math.max(blot.energy, 0.35);
            if (blot.pending >= 0.0142) {
                blot.clock += blot.pending;
                blot.pending = 0;
            }
        }
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true
        // nunca atado a `running`: con la pantalla quieta la mancha tiene que
        // estar ahí, sin moverse
        visible: blot.width > 0 && blot.height > 0

        property real t: blot.clock
        property real seed: blot.seed
        property real level: blot.level
        property real pitch: blot.pitch
        property real splash: blot.splash
        property real dim: blot.dim
        property variant res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property variant ink: Qt.vector3d(blot.colour.r, blot.colour.g, blot.colour.b)
        property variant hot: Qt.vector3d(blot.hot.r, blot.hot.g, blot.hot.b)

        fragmentShader: Qt.resolvedUrl("rorschach.frag.qsb")
    }
}
