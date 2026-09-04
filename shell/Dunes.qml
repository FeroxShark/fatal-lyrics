// fatal-lyrics — las dunas.
//
// Un desierto de granos sueltos, hermano del mar: la física entera vive en
// `dunes.frag` y acá arriba queda sólo lo que el shader no puede saber — el
// reloj, los colores de la pantalla, dónde cae cada pisotón y cuándo el tema
// se abre y la arena se queda en el aire.
//
// La diferencia con el mar es qué se mueve: el paisaje NO se mueve, se mueve
// la cámara. Con `seed` distinto en cada aparición (y la semilla es el
// `motifGen` de la pared cruzado con el número de pantalla) las lomas están en
// otro lado, y como los tres períodos del paneo no se dividen entre sí, la
// toma no vuelve nunca a un cuadro que ya mostró.
import QtQuick

Item {
    id: sand

    property color colour: "#4fe8ff"     // color del grano
    property color crest: "#e2fdff"      // color de la cresta de la loma
    property real level: 0.35            // volumen 0..1
    // Igual que en el mar: el nivel llega a 14 Hz y atado directo a algo que se
    // ve es titileo, no respiración.
    Behavior on level { NumberAnimation { duration: Motion.levelMs; easing.type: Easing.OutQuad } }
    property real high: 0.3              // agudos → cuánto vibra la arena suspendida
    property int beat: 0                 // contador de golpes
    property real beatAmt: 1             // lo gradúa `flicker`: 0 = nadie pisa
    property real energy: 1.0            // parte del tema: la velocidad del paneo
    property real quality: 1.0           // `crt.quality`: tope de granos
    property real seed: 0                // 0..1, re-sorteada en cada aparición
    property real dim: 1.0
    property bool running: true
    // El drop llega como un booleano y NO como un umbral sobre `energy`: la
    // energía que le llega al motif viene multiplicada por el aviso del salto
    // (×1.6 en la pantalla destino al final de CADA verso), así que un umbral
    // ahí levantaría la arena en cualquier estrofa.
    property bool drop: false

    // Reloj propio, como el del mar: el del tubo va a 20 Hz en las pantallas
    // sin letra y con eso el paneo se ve a saltos. Avanza con el frameTime real
    // y publica ~70 veces por segundo.
    property real clock: 0
    property real pending: 0
    FrameAnimation {
        running: sand.running && sand.visible
        onTriggered: {
            sand.pending += frameTime;
            if (sand.pending >= 0.0142) {
                sand.clock += sand.pending;
                sand.pending = 0;
            }
        }
    }

    // La arena que levita: sube con rampa y cae JUNTA, más rápido y acelerando
    // (InQuad, que es lo que hace una piedra). Dos animaciones y no un
    // `Behavior`, justamente porque subir y caer no duran lo mismo.
    property real lift: 0
    onDropChanged: {
        liftAnim.stop();
        liftAnim.to = drop ? 1 : 0;
        liftAnim.duration = drop ? 900 : 620;
        liftAnim.easing.type = drop ? Easing.OutQuad : Easing.InQuad;
        liftAnim.start();
    }
    NumberAnimation {
        id: liftAnim
        target: sand
        property: "lift"
    }

    // Dos pisotones a la vez: con uno solo, dos golpes seguidos cortaban el
    // salto anterior en el aire.
    property vector4d jump1: Qt.vector4d(0, 0, -99, 0)
    property vector4d jump2: Qt.vector4d(0, 0, -99, 0)
    property int jumpSlot: 0
    onBeatChanged: {
        if (beatAmt <= 0.01 || !running)
            return;
        // cae en cualquier lado del campo, no siempre en el centro: si el
        // pisotón fuera siempre el mismo punto, el desierto entero respiraría
        // al mismo tiempo y volvemos al parpadeo
        const x = (Math.random() * 2 - 1) * 2.4;
        const z = 1.6 + Math.random() * 4.5;
        const step = Qt.vector4d(x, z, sand.clock,
                                 (0.6 + 0.8 * sand.level) * sand.beatAmt);
        if (jumpSlot === 0)
            jump1 = step;
        else
            jump2 = step;
        jumpSlot = 1 - jumpSlot;
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true
        visible: sand.width > 0 && sand.height > 0

        property real t: sand.clock
        property real seed: sand.seed
        property real level: sand.level
        property real high: sand.high
        property real speed: Math.max(0.35, sand.energy)
        property real lift: sand.lift
        property real qual: sand.quality
        property real dim: sand.dim
        property variant res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property variant jump1: sand.jump1
        property variant jump2: sand.jump2
        property variant ink: Qt.vector3d(sand.colour.r, sand.colour.g, sand.colour.b)
        property variant hot: Qt.vector3d(sand.crest.r, sand.crest.g, sand.crest.b)

        fragmentShader: Qt.resolvedUrl("dunes.frag.qsb")
    }
}
