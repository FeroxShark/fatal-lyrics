// fatal-lyrics — los ojos.
//
// Una grilla de ojos chicos (el mismo dibujo de `Eye.qml`) mirando todos hacia
// la pantalla donde está la frase. En una pared de tres monitores eso se lee
// solo: la pantalla apagada no está haciendo un dibujo, está MIRANDO a la que
// tiene la letra. Y cuando el aviso del salto dice que la frase se va a otra,
// los ojos se dan vuelta antes de que llegue.
//
// Parpadean fuera de fase entre sí — todos juntos serían un solo bicho con
// muchos ojos, y lo que se busca es un público. En el golpe del tubo sí
// parpadean todos a la vez.
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
    property bool running: true

    // La grilla se sortea con la semilla de esta aparición: 3×2 a 5×3. Sin eso
    // la pared de ojos sería siempre la misma foto.
    readonly property int cols: 3 + Math.floor(Math.min(seed, 0.999) * 3)
    readonly property int rows: 2 + Math.floor(Math.min((seed * 7) % 1, 0.999) * 2)

    // el golpe los junta: un contador que cada ojo mira para parpadear YA
    property int blinkAll: 0
    onKickChanged: if (running) blinkAll++

    Grid {
        anchors.centerIn: parent
        columns: wall.cols
        rows: wall.rows
        spacing: 0

        Repeater {
            model: wall.cols * wall.rows

            Item {
                id: cell
                required property int index
                width: wall.width / wall.cols
                height: wall.height / wall.rows

                Eye {
                    anchors.centerIn: parent
                    width: cell.width * 0.78
                    height: Math.min(width * 0.52, cell.height * 0.8)
                    colour: wall.colour
                    hot: wall.hot
                    level: wall.level
                    punch: wall.punch
                    surge: wall.surge
                    gaze: wall.gaze
                    blinking: wall.running
                    blinkNow: wall.blinkAll
                    // el desfasaje sale del lugar en la grilla y de la semilla:
                    // determinístico, pero distinto en cada aparición
                    phase: Math.round(((cell.index * 37 + wall.seed * 991) % 23) * 190)
                }
            }
        }
    }
}
