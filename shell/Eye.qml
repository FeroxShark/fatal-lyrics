// fatal-lyrics — el ojo.
//
// Ojo de alambre como el de la pantalla del videoclip: lente en punta, malla de
// radios y un iris de anillos concéntricos.
//
// Vive en su propio archivo desde que hay más de un ojo por pantalla
// (`Eyes.qml`): el dibujo es el mismo, cambia el tamaño, el desfasaje del
// parpadeo y hacia dónde mira.
//
// EL IRIS ES UN CÍRCULO Y EL PÁRPADO LO TAPA (T4.0): entrecerrar (`lid`, lo mueve el volumen) va en el
// shader, y el iris queda redondo adentro de la almendra. El parpadeo (`open`, 70–260 ms) va por `Scale`:
// aplasta todo un décimo de segundo, el tiempo en que nadie mira la forma del iris.
import QtQuick

Item {
    id: eye

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    property real punch: 0
    property real surge: 0
    // false = quieto (pantalla apagada): el ojo queda abierto, no en blanco
    property bool blinking: true
    // desfasaje del parpadeo, en ms: es lo que hace que varios ojos no
    // parpadeen como un solo bicho
    property int phase: 0
    property real seed: 0.37
    // hacia dónde mira: -1 todo a la izquierda, 0 al frente, 1 a la derecha
    property real gaze: 0
    Behavior on gaze { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
    // contador: cuando sube, este ojo parpadea YA (el golpe los junta a todos)
    property int blinkNow: 0
    // cuánto se entrecierra el párpado sin llegar a parpadear: 1 abierto del
    // todo, 0.45 en calma. Multiplica al parpadeo en vez de pisarlo, así el
    // ojo sigue parpadeando entrecerrado.
    property real lid: 1
    Behavior on lid { NumberAnimation { duration: 520; easing.type: Easing.InOutQuad } }

    property real open: 0

    onVisibleChanged: {
        if (visible) {
            open = 0;
            openAnim.restart();
        }
    }
    Component.onCompleted: if (visible) openAnim.start()
    onBlinkNowChanged: if (visible && blinking) togetherBlink.restart()

    NumberAnimation {
        id: openAnim
        target: eye
        property: "open"
        to: 1
        duration: 850
        easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: togetherBlink
        NumberAnimation { target: eye; property: "open"; to: 0.06; duration: 70; easing.type: Easing.InQuad }
        NumberAnimation { target: eye; property: "open"; to: 1; duration: 210; easing.type: Easing.OutBack }
    }
    SequentialAnimation {
        running: eye.visible && eye.blinking && !togetherBlink.running
        loops: Animation.Infinite
        // el desfasaje se cobra una sola vez, al arrancar el ciclo
        PauseAnimation { duration: 3400 + eye.phase }
        NumberAnimation { target: eye; property: "open"; to: 0.06; duration: 90; easing.type: Easing.InQuad }
        NumberAnimation { target: eye; property: "open"; to: 1; duration: 260; easing.type: Easing.OutBack }
        PauseAnimation { duration: 2100 }
        NumberAnimation { target: eye; property: "open"; to: 0.06; duration: 80 }
        NumberAnimation { target: eye; property: "open"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }

    // sólo el parpadeo: 100 ms de aplastado y vuelve
    transform: Scale {
        origin.x: eye.width / 2
        origin.y: eye.height / 2
        yScale: Math.max(0.03, eye.open)
    }

    // Un shader y no un Canvas: abrir y cerrar el párpado ya no repinta en el procesador.
    ShaderEffect {
        anchors.fill: parent
        blending: true
        property color ink: eye.colour
        property color hot: eye.hot
        property variant res: Qt.vector2d(width, height)
        property real aperture: Math.max(0.12, Math.min(eye.lid, 1))
        property real dx: eye.gaze * eye.width * 0.22
        // la pupila es lo único que late, y a 0.22 del ancho la curva del párpado más cerrado
        // todavía le deja lugar
        property real pupil: eye.height * 0.5 * (0.10 + 0.05 * eye.level + 0.05 * eye.punch + 0.06 * eye.surge)
        property real pulse: Math.min(1, 0.6 * eye.punch + eye.surge)
        property real seed: eye.seed
        fragmentShader: Qt.resolvedUrl("eye.frag.qsb")
    }
}
