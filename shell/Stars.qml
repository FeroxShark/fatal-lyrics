// fatal-lyrics — el hiperespacio (motivo `stars`).
//
// Un cielo de verdad que se cruza volando: lo lejano queda quieto y lo cercano sale del punto de
// fuga y se estira. En el drop el salto: aceleran, la estela se alarga y vira al color caliente; en
// la calma casi se paran. Todo el dibujo está en `stars.frag`.
//
// La distancia se ACUMULA cuadro a cuadro y no sale de multiplicar el reloj por la velocidad: el
// reloj vale miles de segundos, así que cualquier cambio de velocidad (y el drop es el más grande
// de todos) saltaría multiplicado y las estrellas se teletransportarían enteras.
//
// PARED (`docs/PARED.md`): con lienzo común el campo es UNO que sale del foco (la pantalla de la
// letra, o el medio del lienzo) y cruza todas las pantallas; cada una dibuja su ventana (`wallPx`).
// La distancia viajada vive en `wall.share.stars`. Una pantalla sola: todo como siempre.
import QtQuick

WallItem {
    id: stars
    // pared con la letra en una pantalla: campo que sale del foco: las alas espejadas enmarcan la letra (`Wall.fit`)
    wallFit: "mirror"

    property color colour: "#7fe4ff"
    property color hot: "#ffffff"
    property real level: 0.35
    property real low: 0.3
    property real drive: 1
    property real rate: 1
    property bool drop: false
    property bool running: true

    // el salto al hiperespacio: entra y sale con rampa, nunca de golpe
    property real warp: drop ? 1 : 0
    Behavior on warp { enabled: !stars.wallExternal; NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    // en la calma casi se paran: un cielo que se arrastra es lo que hace
    // que después el drop se sienta
    readonly property real speed: (level < 0.12 && !drop
        ? 0.04 : 0.22 + 0.5 * level) * drive * (1 + 3 * warp)

    property real travel: 0
    function wallStep() {
        const S = wall.share, now = wallNow();
        if (!S.stars)
            S.stars = { at: now, travel: 0 };
        const T = S.stars, dt = now - T.at;
        if (dt > 0) {
            // pausa o pantalla dormida: no teletransporta
            T.travel += Math.min(dt, 0.25) * speed * rate;
            T.at = now;
        }
        travel = T.travel;
    }
    onWallTChanged: if (wallExternal && wallShared && running) wallStep()
    FrameTick {
        running: stars.visible && stars.running && !stars.wallExternal
        onTriggered: {
            if (stars.wallShared)
                stars.wallStep();
            else
                stars.travel += frameTime * stars.speed * stars.rate;
        }
    }

    // Los puntos son un shader (`stars.frag`): eran hasta 900 Rectangle por pantalla, cada uno con
    // sus bindings, y aun así se leían como cuatro puntos.
    ShaderEffect {
        anchors.fill: parent
        blending: true

        property real travel: stars.travel
        property real warp: stars.warp
        property real level: stars.level
        property real kick: stars.low
        property real spanPx: stars.span
        property vector4d view: stars.wallPx
        property vector2d fo: stars.walled ? stars.wallFocus : Qt.vector2d(stars.width / 2, stars.height / 2)
        property vector3d ink: Qt.vector3d(stars.colour.r, stars.colour.g, stars.colour.b)
        property vector3d hot: Qt.vector3d(stars.hot.r, stars.hot.g, stars.hot.b)

        fragmentShader: Qt.resolvedUrl("stars.frag.qsb")
    }
}
