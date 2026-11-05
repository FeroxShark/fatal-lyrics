// fatal-lyrics — los ojos.
//
// UN ojo grande que mira a la pantalla donde está la frase, y dos o tres ojos
// chicos en los bordes que aparecen y desaparecen. La grilla de ojos copiados
// que había antes no gustaba (T3.B3) y en la pantalla vertical era peor: quince
// lentes idénticas a la misma escala, con la cámara al tope, quedaban cortadas
// contra el borde.
//
// Lo que se lee acá es UNA mirada: el ojo grande sigue el foco con el iris
// corrido hacia allá y el párpado entrecerrado en calma, abierto en el drop.
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

    // Cuánto se entrecierran TODOS los párpados. Es uno solo para el grande y
    // los chicos: si el grande está a medio cerrar y los chicos abiertos del
    // todo, las almendras tienen relaciones distintas en la misma pantalla y
    // eso es justo lo que Ferox leyó como "los raros son los múltiples".
    readonly property real squint: Math.min(0.45 + 0.35 * level + (drop ? 0.20 : 0), 1)

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
        lid: wall.squint
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

            // T4.1: el ojo chico vive en una caja CUADRADA de lado `side`, y el
            // lugar sale de ese lado — no de fracciones sueltas del ancho y del
            // alto. Con fracciones separadas el margen contra el borde valía
            // distinto en cada monitor (un 4 % de 1080 y un 4 % de 1920 no son
            // el mismo aire) y en la vertical los de arriba y abajo quedaban
            // pegados al canto.
            readonly property real side: wall.span * 0.24
            // El aire contra el borde: 4 % MÁS media caja. El 4 % se mide con
            // el ancho para la x y con el alto para la y (la regla de la safe
            // area del CLAUDE.md), no con el lado corto para las dos: en la
            // apaisada, 4 % de 1080 son 43 px de un ancho de 1920 — 2.2 % —, y
            // ahí la curvatura del tubo ya se come la punta de la almendra
            // (medido: el ojo de la izquierda salía cortado en HDMI-A-2).
            readonly property real mx: wall.width * 0.04 + side / 2
            readonly property real my: wall.height * 0.04 + side / 2

            readonly property var spot: wall.tall
                ? [[wall.width * 0.30, my],
                   [wall.width * 0.70, wall.height - my],
                   [mx, wall.height * 0.63]][index]
                : [[mx, wall.height * 0.28],
                   [wall.width - mx, wall.height * 0.72],
                   [wall.width * 0.50, my]][index]
            // T4.1: holds de por lo menos tres segundos (el lenguaje de
            // movimiento de la corrida 3). Con 2.3 s el de arriba prendía y
            // apagaba antes de que el ojo terminara de abrirse.
            readonly property int period: [3300, 4300, 5300][index]

            x: spot[0] - width / 2
            y: spot[1] - height / 2
            width: side
            height: side

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
            Behavior on opacity {
                NumberAnimation { duration: Motion.enterMs; easing.type: Easing.OutExpo }
            }

            Eye {
                anchors.centerIn: parent
                // la MISMA relación que el ojo grande: el ancho es el lado de
                // la caja y el alto sale de ahí, nunca del alto de la pantalla
                width: slot.side
                height: width * 0.52
                colour: wall.colour
                hot: wall.hot
                level: wall.level
                punch: wall.punch
                surge: wall.surge
                gaze: wall.gaze
                blinking: wall.running
                blinkNow: wall.blinkAll
                lid: wall.squint
                // el desfasaje sale del lugar y de la semilla: determinístico,
                // pero distinto en cada aparición
                phase: Math.round(((slot.index * 37 + wall.seed * 991) % 23) * 190)
            }
        }
    }
}
