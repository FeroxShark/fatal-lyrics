// fatal-lyrics — la mancha.
//
// La lámina de Rorschach: simétrica por construcción (todo lo que dibuja
// `rorschach.frag` es función de `abs(x - 0.5)`) y viva porque el umbral del
// ruido baja con el volumen. Acá arriba queda lo que el shader no puede saber:
// el reloj, los colores de la pantalla y el salpicón del golpe.
import QtQuick

Item {
    id: blot

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    Behavior on level { NumberAnimation { duration: Motion.levelMs; easing.type: Easing.OutQuad } }
    property real pitch: 0.5          // el registro: cuánto se retuerce
    property real seed: 0             // 0..1: otra lámina en cada aparición
    property real energy: 1.0         // la parte del tema: la deriva del ruido
    property real dim: 1.0
    property int kick: 0
    property bool running: true
    property int tick: 0              // el compás: cada 8 tiempos, otra familia

    // ---- las familias (T3.B2)
    // Todas las láminas parecían la misma bola deformándose. La silueta ahora
    // sale de seis números, y una familia es un juego de valores para ellos.
    // Cambiar de familia es reasignarlos: los `Behavior` de abajo hacen el
    // cruce en 400 ms, así que la mancha se TRANSFORMA en vez de aparecer otra.
    //
    // [spike, lobe, hole, sx, sy, spat]
    readonly property var families: [
        [0.00, 0.00, 0.00, 1.00, 1.00, 0.00],   // redonda (la de siempre)
        [0.26, 0.00, 0.00, 1.00, 1.00, 0.00],   // con púas
        [0.04, 0.19, 0.00, 1.05, 0.92, 0.00],   // dos lóbulos
        [0.05, 0.00, 0.85, 1.00, 1.00, 0.00],   // con agujeros
        [0.05, 0.00, 0.00, 1.85, 0.72, 0.00],   // alargada a lo ancho
        [0.05, 0.00, 0.00, 0.70, 1.75, 0.00],   // alargada a lo alto
        [0.08, 0.06, 0.10, 1.00, 1.00, 0.30]    // salpicada
    ]

    property real famSpike: 0
    property real famLobe: 0
    property real famHole: 0
    property real famSx: 1
    property real famSy: 1
    property real famSpat: 0
    Behavior on famSpike { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on famLobe  { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on famHole  { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on famSx    { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on famSy    { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on famSpat  { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

    property int famIdx: -1
    function rollFamily() {
        // la semilla de la aparición decide la primera; después va rotando sin
        // repetir la anterior, que es lo que haría que no se note el cambio
        let n = famIdx < 0
            ? Math.floor(Math.abs(seed * 1013) % families.length)
            : (famIdx + 1 + Math.floor(Math.abs(seed * 7919 + famIdx * 31 + clock * 13)
                                       % (families.length - 1))) % families.length;
        famIdx = n;
        const f = families[n];
        famSpike = f[0]; famLobe = f[1]; famHole = f[2];
        famSx = f[3]; famSy = f[4]; famSpat = f[5];
        famClock.restart();
    }
    Component.onCompleted: rollFamily()
    onSeedChanged: { famIdx = -1; rollFamily(); }

    property int famBeats: 0
    onTickChanged: {
        if (++famBeats < 8)
            return;
        famBeats = 0;
        rollFamily();
    }
    // sin compás no llega ningún `tick`: la lámina igual tiene que cambiar
    Timer {
        id: famClock
        interval: 5200
        repeat: true
        running: blot.running && blot.visible
        onTriggered: blot.rollFamily()
    }

    // El salpicón dura CASI un cuadro. Con 90 ms se ve el salto y vuelve; con
    // medio segundo la mancha late, que es otra cosa (y ya la hace el volumen).
    property real splash: 0
    onKickChanged: {
        if (!running)
            return;
        splashAnim.stop();
        splash = 1;
        splashAnim.start();
    }
    NumberAnimation {
        id: splashAnim
        target: blot
        property: "splash"
        to: 0
        duration: 90
        easing.type: Easing.OutQuad
    }

    // Reloj propio: el del tubo va a 20 Hz en las pantallas sin letra y la
    // deriva de la tinta se vería a saltos.
    property real clock: 0
    property real pending: 0
    FrameAnimation {
        running: blot.running && blot.visible
        onTriggered: {
            blot.pending += frameTime * Math.max(blot.energy, 0.35);
            if (blot.pending >= 0.0142) {
                blot.clock += blot.pending;
                blot.pending = 0;
            }
        }
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true
        // nunca atado a `running`: con la pantalla quieta la mancha tiene que
        // estar ahí, sin moverse
        visible: blot.width > 0 && blot.height > 0

        property real t: blot.clock
        property real seed: blot.seed
        property real level: blot.level
        property real pitch: blot.pitch
        property real splash: blot.splash
        property real dim: blot.dim
        property real famSpike: blot.famSpike
        property real famLobe: blot.famLobe
        property real famHole: blot.famHole
        property real famSx: blot.famSx
        property real famSy: blot.famSy
        property real famSpat: blot.famSpat
        property variant res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property variant ink: Qt.vector3d(blot.colour.r, blot.colour.g, blot.colour.b)
        property variant hot: Qt.vector3d(blot.hot.r, blot.hot.g, blot.hot.b)

        fragmentShader: Qt.resolvedUrl("rorschach.frag.qsb")
    }
}
