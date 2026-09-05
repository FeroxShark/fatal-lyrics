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
    property bool drop: false
    property real seed: 0
    property real dim: 1.0
    property bool running: true
    property int kick: 0

    // ---- LA LUZ QUE CORRE (T5.3)
    //
    // En cada tiempo se planta una banda de luz en la boca y se la empuja pared
    // adentro, lejos de la cámara: es lo único acá que dice hacia dónde se
    // viaja. Reemplaza al anillo que plantaba el golpe — un aro viniendo y una
    // luz yéndose, los dos en el mismo tiempo, se leen como una falla y no como
    // un pulso.
    //
    // De dónde salen los tiempos, en este orden (el mismo que el cardiograma):
    // del `tick` cuantizado si hay compás confiable, del onset crudo si no, y
    // si no llega ninguno de los dos, de un período fijo — un túnel sin luz que
    // corra es un dibujo quieto.
    property real low: 0.4
    Behavior on low { NumberAnimation { duration: Motion.levelMs; easing.type: Easing.OutQuad } }
    property int beat: 0
    property int tick: 0
    property real beatMs: 500
    property bool bpmLive: false

    // qué tan adelante de la cámara va la luz, y cuánto le queda
    property real lightAhead: 0
    property real lightAmt: 0
    property double lastLightAt: 0

    onTickChanged: if (bpmLive) lightRun(1.0)
    onBeatChanged: if (!bpmLive) lightRun(1.0)
    // El golpe del tubo no planta una luz propia: le sube el brillo a la que ya
    // está corriendo. Dos luces con 100 ms de diferencia son dos eventos, y por
    // pantalla va uno.
    onKickChanged: {
        if (lightAmt > 0.15)
            lightAmt = Math.min(1.0, lightAmt + 0.25);
        else
            lightRun(0.85);
    }

    function lightRun(gain) {
        if (!running || !visible)
            return;
        var now = Date.now();
        if (now - lastLightAt < 140)
            return;
        lastLightAt = now;
        lightPeak = Math.min(1.0, gain * (0.45 + 0.9 * Math.max(0, low - 0.30)));
        lightRunAnim.restart();
    }

    property real lightPeak: 0.6
    ParallelAnimation {
        id: lightRunAnim
        NumberAnimation {
            target: tube; property: "lightAhead"
            from: 0.5; to: 13
            duration: 900; easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: tube; property: "lightAmt"
            from: tube.lightPeak; to: 0
            duration: 900; easing.type: Easing.InQuad
        }
    }

    // El período fijo del final de la cadena: si en un segundo y medio no llegó
    // ni un tiempo ni un golpe, la luz sale igual.
    Timer {
        interval: 900
        repeat: true
        running: tube.running && tube.visible
        onTriggered: if (Date.now() - tube.lastLightAt > 1500) tube.lightRun(0.7)
    }

    // distancia viajada (anillos), los segundos pelados para la deriva de la
    // curva, y el giro del tubo sobre su eje (T5.2), en vueltas.
    //
    // El giro se ACUMULA, como la distancia: con `vuelta = reloj × velocidad`
    // cualquier cambio de registro multiplica un reloj de miles de segundos y
    // toda la pared de ladrillos se teletransporta. Tiene una base constante,
    // así que en el silencio el tubo sigue girando despacio (la deriva del
    // video de referencia: velocidad uniforme que nunca para).
    property real travel: 0
    property real clock: 0
    property real roll: 0

    // El drop: el túnel acelera y las dovelas se barren en el sentido del
    // viaje. Las dos van por una animación de CÁMARA (un solo movimiento por
    // cambio de parte, `Motion.cameraMs`, `OutExpo`) y no por un `Behavior`
    // sobre algo que se recalcula solo: eso último no es una transición, es un
    // filtro que nunca llega.
    property real rush: 1
    property real blur: 0
    onDropChanged: rushAnim.restart()
    ParallelAnimation {
        id: rushAnim
        NumberAnimation {
            target: tube; property: "rush"
            to: tube.drop ? 2.4 : 1.0
            duration: Motion.cameraMs; easing.type: Easing.OutExpo
        }
        NumberAnimation {
            target: tube; property: "blur"
            to: tube.drop ? 1.0 : 0.0
            duration: Motion.cameraMs; easing.type: Easing.OutExpo
        }
    }
    FrameAnimation {
        running: tube.running && tube.visible
        onTriggered: {
            // T4.3: el techo de cuadros. La velocidad se ACUMULA (la distancia
            // recorrida es del túnel, no `reloj * velocidad`), así que juntar
            // dos cuadros en uno no lo teletransporta: recorre lo mismo.
            tube.pending += frameTime;
            if (tube.pending < tube.stepMin)
                return;
            // La velocidad es CONSTANTE fuera del drop (T5.4). Antes salía de
            // `level` y de `energy`, y las dos se mueven todo el tiempo: la
            // energía además llega ×1.25 en la pantalla a la que va a saltar la
            // frase, así que el túnel pegaba un tirón cada vez que estaba por
            // caer una línea ahí. Eso es justo lo que la regla de fluidez
            // prohíbe — la deriva es de velocidad uniforme y el único que la
            // cambia es el drop. Al volumen le queda un ±3 %, que es respirar.
            const speed = 0.78 * (1 + 0.06 * (tube.level - 0.4)) * tube.rush;
            tube.travel += tube.pending * speed;
            tube.clock += tube.pending;
            tube.roll += tube.pending * (0.012 + 0.055 * (tube.pitch - 0.5));
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
        property real roll: tube.roll
        property real bend: tube.bend
        property real blur: tube.blur
        property real seed: tube.seed
        property real level: tube.level
        // la luz corre HACIA EL FONDO: su profundidad va más rápido que la
        // distancia viajada, si no se quedaría clavada en la pared
        property real lightDepth: tube.travel + tube.lightAhead
        property real lightAmt: tube.lightAmt
        property real dim: tube.dim
        property variant res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property variant ink: Qt.vector3d(tube.colour.r, tube.colour.g, tube.colour.b)
        property variant hot: Qt.vector3d(tube.hot.r, tube.hot.g, tube.hot.b)

        fragmentShader: Qt.resolvedUrl("tunnel.frag.qsb")
    }
}
