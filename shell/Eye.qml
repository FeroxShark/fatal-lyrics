// fatal-lyrics — el ojo.
//
// Ojo de alambre como el de la pantalla del videoclip: lente en punta, malla de
// radios y anillos concéntricos. Se dibuja UNA vez en un canvas y después sólo
// se lo transforma — abrir el párpado es escalar en vertical, y la pupila, que
// es lo único que late, va aparte.
//
// Vive en su propio archivo desde que hay una grilla de ojos mirando todos
// hacia la pantalla enfocada (`Eyes.qml`): el dibujo es el mismo, cambia el
// tamaño, el desfasaje del parpadeo y hacia dónde mira.
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
    // desfasaje del parpadeo, en ms: es lo que hace que una grilla de ojos no
    // parpadee como un solo bicho
    property int phase: 0
    // hacia dónde mira: -1 todo a la izquierda, 0 al frente, 1 a la derecha
    property real gaze: 0
    Behavior on gaze { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
    // contador: cuando sube, este ojo parpadea YA (el golpe los junta a todos)
    property int blinkNow: 0

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

    transform: Scale {
        origin.x: eye.width / 2
        origin.y: eye.height / 2
        yScale: eye.open
    }

    // Lente, malla e iris van TODOS en el mismo canvas: dibujados por separado,
    // los anillos quedaban corridos del centro de la lente y se notaba enseguida.
    Canvas {
        id: lens
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        readonly property color stroke: eye.colour
        onStrokeChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height;
            const cx = w / 2, cy = h / 2;
            c.strokeStyle = stroke;
            c.lineWidth = Math.max(1.5, h * 0.012);

            // OJO con los números: una curva cuadrática llega a la MITAD de la
            // distancia a su punto de control, así que con 1.05*h la punta caía
            // en 0.525*h — fuera del canvas, y el ojo se veía cortado arriba y
            // abajo. Con 0.94 la curva y su trazo entran justas.
            const arch = h * 0.94;
            const edge = c.lineWidth;
            function lensPath() {
                c.beginPath();
                c.moveTo(cx - w / 2 + edge, cy);
                c.quadraticCurveTo(cx, cy - arch, cx + w / 2 - edge, cy);
                c.quadraticCurveTo(cx, cy + arch, cx - w / 2 + edge, cy);
                c.closePath();
            }

            lensPath();
            c.stroke();

            c.save();
            lensPath();
            c.clip();

            // radios desde el iris hasta el borde
            c.globalAlpha = 0.5;
            const spokes = 44;
            for (let i = 0; i < spokes; i++) {
                const a = (i / spokes) * Math.PI * 2;
                c.beginPath();
                c.moveTo(cx + Math.cos(a) * h * 0.17, cy + Math.sin(a) * h * 0.17);
                c.lineTo(cx + Math.cos(a) * w * 0.75, cy + Math.sin(a) * h * 1.2);
                c.stroke();
            }

            // anillos del iris, concéntricos con la lente
            c.globalAlpha = 0.8;
            for (let k = 1; k <= 7; k++) {
                const r = h * 0.06 * k;
                c.beginPath();
                c.ellipse(cx - r, cy - r, r * 2, r * 2);
                c.stroke();
            }
            c.restore();

            c.globalAlpha = 1;
            c.lineWidth = Math.max(2, h * 0.02);
            lensPath();
            c.stroke();
        }
    }

    // pupila: lo único que se mueve aparte. Centrada, salvo que el ojo esté
    // mirando a un costado — ahí se corre hasta un cuarto del ancho, que es lo
    // que aguanta la lente sin que la pupila se salga del dibujo.
    Rectangle {
        width: eye.height * (0.10 + 0.05 * eye.level + 0.05 * eye.punch + 0.06 * eye.surge)
        height: width
        radius: width / 2
        x: (eye.width - width) / 2 + eye.gaze * eye.width * 0.25
        y: (eye.height - height) / 2
        color: eye.hot
        opacity: 0.92
    }
}
