// fatal-lyrics — el laguito.
//
// Un plato de agua hecho de puntos, temblando a la frecuencia de lo que suena:
// el registro del tema decide la apretura del dibujo y la velocidad del
// temblor, el volumen cuánto se sacude, y cada golpe tira una piedra que se
// abre y rebota contra el borde. Toda la física está en `pond.frag`; acá
// arriba sólo el reloj, los colores y de dónde cae cada piedra.
//
// PARED (`docs/PARED.md`): con lienzo común el agua es UNA para todas las pantallas (cada una
// dibuja su ventana, `wallView`) y los anillos salen del foco (la pantalla de la letra, o el
// medio del lienzo): cruzan las pantallas vecinas. El reloj y las piedras salen de la pared
// (`WallBase`: azar de la semilla compartida, no `Math.random`).
import QtQuick

WallBase {
    id: dish
    // pared con la letra en una pantalla: campo que sale del foco: las alas espejadas enmarcan la letra (`Wall.fit`)
    wallFit: "mirror"

    property color colour: "#4fe8ff"
    property color crest: "#e2fdff"
    // T4.3: el techo de cuadros que reparte Motif.qml
    property real stepMin: 0
    property real level: 0.35
    Behavior on level { NumberAnimation { duration: 0; easing.type: Easing.OutQuad } }
    property real low: 0.4
    property real high: 0.3
    // el registro de lo que suena (0 grave .. 1 agudo): ESTO es la frecuencia
    // a la que vibra el agua
    property real pitch: 0.5
    Behavior on pitch { NumberAnimation { duration: 0; easing.type: Easing.InOutQuad } }
    property int beat: 0
    property real beatAmt: 1
    property real energy: 1.0
    property real amp: 0.55
    property real dim: 1.0
    property bool running: true

    // Reloj propio: el del tubo va a 20 Hz en las pantallas sin letra y un
    // temblor a 20 Hz es una animación rota. Avanza con el frameTime real y
    // publica ~70 veces por segundo.
    // tanda 8, slice movimiento: el ritmo de la música (`Speed.js`, 1 = el de siempre).
    // Multiplica el `dt` que se ACUMULA, nunca el reloj: cambia la velocidad, no salta.
    property real rate: 1
    property real clock: 0
    property real pending: 0
    FrameTick {
        running: dish.running && dish.visible && !dish.clockExternal
        onTriggered: {
            dish.pending += frameTime;
            if (dish.pending >= dish.stepMin) {
                if (dish.wallClocked)
                    dish.clock = dish.wallTime(dish.rate);
                else
                    dish.clock += dish.pending * dish.rate;
                dish.pending = 0;
            }
        }
    }
    Component.onCompleted: if (wallClocked) clock = wallTime(rate)

    property vector4d rip1: Qt.vector4d(0, 0, -99, 0)
    property vector4d rip2: Qt.vector4d(0, 0, -99, 0)
    property int ripSlot: 0
    onBeatChanged: {
        if (beatAmt <= 0.01 || !running)
            return;
        // cae en cualquier lado del plato, no siempre en el centro
        // en pared el sitio sale de la semilla y el golpe (igual en todas las pantallas)
        let ang = Math.random() * Math.PI * 2;
        let rad = Math.sqrt(Math.random()) * 0.3;
        let t0 = dish.clock, slot = ripSlot;
        if (walled) {
            ang = wallHash(beat * 3 + 1) * Math.PI * 2;
            rad = Math.sqrt(wallHash(beat * 3 + 2)) * 0.3;
            t0 = wallStamp(beat, dish.clock);
            slot = beat & 1;
        }
        const drop = Qt.vector4d(Math.cos(ang) * rad, Math.sin(ang) * rad,
                                 t0, (0.35 + 0.75 * dish.level) * dish.beatAmt);
        if (slot === 0)
            rip1 = drop;
        else
            rip2 = drop;
        ripSlot = 1 - slot;
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true

        property real t: dish.clock
        property real amp: dish.amp
        property real pitch: dish.pitch
        property real level: dish.level
        property real swell: dish.low
        property real chop: dish.high
        property real speed: Math.max(0.35, dish.energy)
        property real dim: dish.dim
        property variant res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property variant rip1: dish.rip1
        property variant rip2: dish.rip2
        property vector4d view: dish.wallView
        // hasta dónde llega el agua desde el foco: la esquina más lejana del lienzo
        property vector4d wcfg: Qt.vector4d(dish.wallCfg.x, dish.wallCfg.y, dish.wallReach, 0)
        property variant fo: dish.wallFocusU
        property variant ink: Qt.vector3d(dish.colour.r, dish.colour.g, dish.colour.b)
        property variant hot: Qt.vector3d(dish.crest.r, dish.crest.g, dish.crest.b)

        fragmentShader: Qt.resolvedUrl("pond.frag.qsb")
    }
}
