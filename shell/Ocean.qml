// fatal-lyrics — el mar.
//
// Un campo de puntos sueltos sobre el agua: cada uno tiene su propia altura,
// su propia fase y su propia forma de acomodarse después de un golpe. No es un
// mesh ni una malla deformada — es una partícula por punto, resuelta en
// `ocean.frag`, que es donde vive toda la física.
//
// Acá arriba sólo queda lo que el shader no puede saber: el reloj, los colores
// de la pantalla, y de dónde sale cada piedra que cae al agua cuando la canción
// pega. Los golpes NO se dibujan como un flash: tiran una onda circular que
// tarda en llegar a cada punto. Eso es lo que hace que el ritmo se vea como
// agua moviéndose y no como una pantalla titilando — la lección cara de las
// pasadas anteriores del modo CRT.
import QtQuick

Item {
    id: sea

    property color colour: "#4fe8ff"     // color base del punto
    property color crest: "#e2fdff"      // color de la cresta
    property real level: 0.35            // volumen 0..1
    // Igual que en Motif: el nivel llega a 14 Hz. Atado directo a nada que se
    // vea, eso es titileo; suavizado, es el mar que se levanta cuando el tema
    // sube.
    Behavior on level { NumberAnimation { duration: 420; easing.type: Easing.OutQuad } }
    property real low: 0.4               // graves → el oleaje largo
    property real high: 0.3              // agudos → el picadito de la superficie
    property int beat: 0                 // contador de golpes
    property real beatAmt: 1             // lo gradúa `flicker`: 0 = nadie tira piedras
    property real energy: 1.0            // parte del tema: silencio ≈ 0.45, pico ≈ 1.6
    property real amp: 0.55              // perilla de altura de ola
    property real dim: 1.0               // 1 = el mar ES la imagen; menos = va de fondo
    property bool running: true

    // Reloj propio. El del tubo va a 20 Hz en las pantallas sin letra y con eso
    // el agua se ve a saltos. Este avanza con el frameTime real (o sea, la
    // velocidad es exacta) pero sólo publica el valor ~70 veces por segundo: en
    // un monitor de 200 Hz eso es un tercio de los redibujos, y a ojo es lo
    // mismo.
    property real clock: 0
    property real pending: 0
    FrameAnimation {
        running: sea.running && sea.visible
        onTriggered: {
            sea.pending += frameTime;
            if (sea.pending >= 0.0142) {
                sea.clock += sea.pending;
                sea.pending = 0;
            }
        }
    }

    // Dos piedras a la vez: con una sola, dos golpes seguidos cortaban la onda
    // anterior de golpe y se notaba el corte.
    property vector4d rip1: Qt.vector4d(0, 0, -99, 0)
    property vector4d rip2: Qt.vector4d(0, 0, -99, 0)
    property int ripSlot: 0
    onBeatChanged: {
        if (beatAmt <= 0.01 || !running)
            return;
        // cae lejos y a un costado: si siempre cayera en el centro, el mar
        // entero respiraría al mismo tiempo y volvemos al parpadeo
        const x = (Math.random() * 2 - 1) * 2.6;
        const z = 1.8 + Math.random() * 5.5;
        const drop = Qt.vector4d(x, z, sea.clock,
                                 (0.5 + 0.9 * sea.level) * sea.beatAmt);
        if (ripSlot === 0)
            rip1 = drop;
        else
            rip2 = drop;
        ripSlot = 1 - ripSlot;
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true
        visible: sea.width > 0 && sea.height > 0

        property real t: sea.clock
        property real amp: sea.amp
        property real swell: sea.low
        property real chop: sea.high
        property real level: sea.level
        // la sección manda la velocidad del agua: un verso tranquilo es marea,
        // el estribillo es mar picado
        property real speed: Math.max(0.35, sea.energy)
        property real haze: 1.0
        property real dim: sea.dim
        property variant res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property variant rip1: sea.rip1
        property variant rip2: sea.rip2
        property variant ink: Qt.vector3d(sea.colour.r, sea.colour.g, sea.colour.b)
        property variant hot: Qt.vector3d(sea.crest.r, sea.crest.g, sea.crest.b)

        fragmentShader: Qt.resolvedUrl("ocean.frag.qsb")
    }
}
