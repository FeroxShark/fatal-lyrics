// fatal-lyrics — los ojos.
//
// UN ojo grande que mira a la pantalla donde está la frase, y dos o tres ojos
// chicos en los bordes que aparecen y desaparecen. La grilla de ojos copiados
// que había antes no gustaba (T3.B3) y en la pantalla vertical era peor: quince
// lentes idénticas a la misma escala, con la cámara al tope, quedaban cortadas
// contra el borde.
//
// Lo que se lee acá es UNA mirada: el ojo grande sigue el foco con la pupila
// estirada hacia allá y el párpado entrecerrado en calma, abierto en el drop.
// Los chicos son el público, no una textura: van y vienen, cada uno con su
// propio reloj, y nunca están los tres a la vez por casualidad más de un rato.
//
// El reparto de los chicos depende de la FORMA de la pantalla, no de un número
// fijo: en horizontal van a izquierda y derecha (que es donde están las otras
// pantallas de la pared), en vertical arriba y abajo. Una de las pantallas de
// Ferox es vertical: cualquier dibujo nuevo se prueba con el ancho y el alto
// dados vuelta.
import QtQuick

Item {
    id: wall

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    property real punch: 0
    property real surge: 0
    // hacia dónde miran (-1 izquierda .. 1 derecha); el tween está en cada ojo
    property real gaze: 0
    property int kick: 0
    property real seed: 0
    property bool drop: false
    property bool running: true
    // el lado corto de la pantalla: la medida del ojo grande
    property real span: Math.min(width, height)

    readonly property bool tall: height > width

    // el golpe los junta: un contador que cada ojo mira para parpadear YA
    property int blinkAll: 0
    onKickChanged: if (running) blinkAll++

    // ---- el ojo grande
    Eye {
        id: big
        anchors.centerIn: parent
        // En horizontal el lado corto es el ALTO, así que medir el ojo contra
        // `span` lo deja chico: con 1.15 ocupa medio ancho y sigue entrando de
        // sobra en el alto (la lente mide 0.52 de su ancho).
        width: wall.span * (wall.tall ? 0.92 : 1.15)
        height: width * 0.52
        colour: wall.colour
        hot: wall.hot
        level: wall.level
        punch: wall.punch
        surge: wall.surge
        gaze: wall.gaze
        blinking: wall.running
        blinkNow: wall.blinkAll
        // en calma el ojo está entrecerrado y en el drop se abre entero: es lo
        // que hace que la pantalla apagada tenga estado sin cambiar de dibujo
        lid: Math.min(0.45 + 0.35 * wall.level + (wall.drop ? 0.20 : 0), 1)
        pupilStretch: 0.9 * Math.abs(wall.gaze)
    }

    // ---- los chicos, en los bordes
    // Tres lugares fijos por forma de pantalla. Cada uno aparece y desaparece
    // con su propio reloj, y los relojes son primos entre sí: con el mismo
    // intervalo los tres pestañearían juntos y volvería a leerse como grilla.
    Repeater {
        model: 3

        Item {
            id: slot
            required property int index

            // T4.1: los lugares dejan el 4 % de aire contra el borde. Con
            // 0.09 / 0.91 el ojo chico quedaba a 43 px del canto en una
            // pantalla de 1920 — no cortado, pero pegado, que es la mitad de
            // la sensación de "se sale de la pantalla".
            readonly property var spot: wall.tall
                ? [[0.30, 0.13], [0.70, 0.87], [0.19, 0.63]][index]
                : [[0.13, 0.28], [0.87, 0.72], [0.50, 0.13]][index]
            readonly property int period: [2300, 3100, 4300][index]

            x: wall.width * spot[0] - width / 2
            y: wall.height * spot[1] - height / 2
            width: wall.span * 0.24
            height: width * 0.52

            // arranca prendido el primero: una pantalla que aparece con los tres
            // apagados tarda dos segundos en ser el motivo de los ojos
            property bool on: index === 0
            Timer {
                interval: slot.period
                repeat: true
                running: wall.running && wall.visible
                onTriggered: slot.on = !slot.on
            }

            opacity: on ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.InOutQuad } }

            Eye {
                anchors.fill: parent
                colour: wall.colour
                hot: wall.hot
                level: wall.level
                punch: wall.punch
                surge: wall.surge
                gaze: wall.gaze
                blinking: wall.running
                blinkNow: wall.blinkAll
                pupilStretch: 0.7 * Math.abs(wall.gaze)
                // el desfasaje sale del lugar y de la semilla: determinístico,
                // pero distinto en cada aparición
                phase: Math.round(((slot.index * 37 + wall.seed * 991) % 23) * 190)
            }
        }
    }
}
