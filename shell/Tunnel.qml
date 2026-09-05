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
// El túnel se DOBLA (T5.1): la posición del centro de un anillo es función de
// su profundidad, así que el fondo se corre hacia un lado y la boca se queda
// donde está — se ve que se viaja hacia una curva. Antes el centro derivaba
// como UN offset para toda la imagen, que mueve la boca tanto como el fondo y
// se lee como el tubo entero corriéndose de costado. La cuenta vive en el
// shader (depende de la profundidad, o sea del píxel); acá sólo va la amplitud.
//
// La curva slithera con un reloj aparte (`ct`), que corre aunque el tema esté
// callado: si dependiera sólo de la distancia, en el silencio el túnel quedaría
// clavado y se leería como un dibujo pintado en el vidrio.
import QtQuick

Item {
    id: tube

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    // T4.3: el techo de cuadros que reparte Motif.qml
    property real stepMin: 1 / 60
    property real pending: 0
    property real level: 0.35
    Behavior on level { NumberAnimation { duration: Motion.levelMs; easing.type: Easing.OutQuad } }
    // Cuánto se dobla, en RADIOS DE TUBO: cuánto se aparta el eje del túnel de
    // la línea de la vista. En pantalla eso vale una fracción del radio de cada
    // anillo (`c = r·C/2`), así que la boca no se corre y el fondo sí. Tiene
    // techo: con |C| ≥ 2 el desplazamiento supera al radio, el mapa se pliega y
    // salen garras encima de los anillos del medio.
    property real bend: 0.45
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
            // T4.3: el techo de cuadros. La velocidad se ACUMULA (la distancia
            // recorrida es del túnel, no `reloj * velocidad`), así que juntar
            // dos cuadros en uno no lo teletransporta: recorre lo mismo.
            tube.pending += frameTime;
            if (tube.pending < tube.stepMin)
                return;
            const speed = (0.22 + 1.05 * tube.level) * Math.max(tube.energy, 0.35);
            tube.travel += tube.pending * speed;
            tube.clock += tube.pending;
            tube.pending = 0;
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
        property real bend: tube.bend
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
