// fatal-lyrics — el túnel.
//
// Anillos que vienen de frente. La geometría vive en `tunnel.frag`; acá arriba
// va lo único que el shader no puede saber: **cuánto se viajó**.
//
// Y eso es a propósito. La distancia se ACUMULA cuadro a cuadro con la
// velocidad del momento; no es un reloj multiplicado por la velocidad. Con un
// reloj por velocidad, cada cambio de volumen teletransporta todos los anillos,
// porque a esa altura el reloj vale cientos de segundos y el salto se multiplica
// entero. Es la misma trampa que tenía el hiperespacio.
//
// El centro deriva con un reloj aparte (`ct`), que corre aunque el tema esté
// callado: si derivara con la distancia, en el silencio el túnel quedaría
// clavado y se leería como un blanco pintado en el vidrio.
import QtQuick

Item {
    id: tube

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    Behavior on level { NumberAnimation { duration: Motion.levelMs; easing.type: Easing.OutQuad } }
    property real pitch: 0.5          // el registro: la torsión
    Behavior on pitch { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
    property real energy: 1.0
    property real seed: 0
    property real dim: 1.0
    property bool running: true
    property int kick: 0

    // El anillo que enciende el golpe. No hace falta moverlo: un valor fijo de
    // `depth` se abre solo mientras `travel` crece, así que el golpe sólo dice
    // A QUÉ PROFUNDIDAD plantarlo. Siete anillos adentro es como una vuelta y
    // media de tubo: se lo ve venir.
    property real pulseDepth: 0
    property real pulseAmt: 0
    onKickChanged: {
        if (!running)
            return;
        pulseDepth = travel + 7;
        pulseFade.restart();
    }
    NumberAnimation {
        id: pulseFade
        target: tube
        property: "pulseAmt"
        from: 1; to: 0
        duration: 900
        easing.type: Easing.OutQuad
    }

    // distancia viajada (anillos), y los segundos pelados para la deriva
    property real travel: 0
    property real clock: 0
    FrameAnimation {
        running: tube.running && tube.visible
        onTriggered: {
            const speed = (0.22 + 1.05 * tube.level) * Math.max(tube.energy, 0.35);
            tube.travel += frameTime * speed;
            tube.clock += frameTime;
        }
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true
        // NUNCA atado a `running`: el túnel de una pasada anterior salía en
        // blanco y se sacó por eso. Con la pantalla quieta dibuja igual, sin
        // avanzar.
        visible: tube.width > 0 && tube.height > 0

        property real t: tube.travel
        property real ct: tube.clock
        property real twist: tube.pitch - 0.5
        property real seed: tube.seed
        property real level: tube.level
        property real pulseDepth: tube.pulseDepth
        property real pulseAmt: tube.pulseAmt
        property real dim: tube.dim
        property variant res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property variant ink: Qt.vector3d(tube.colour.r, tube.colour.g, tube.colour.b)
        property variant hot: Qt.vector3d(tube.hot.r, tube.hot.g, tube.hot.b)

        fragmentShader: Qt.resolvedUrl("tunnel.frag.qsb")
    }
}
