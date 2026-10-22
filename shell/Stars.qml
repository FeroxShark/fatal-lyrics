// fatal-lyrics — el hiperespacio (motivo `stars`).
//
// Puntos que salen del centro y se estiran. En el drop el salto: aceleran, la estela se alarga y
// vira al color caliente; en la calma casi se paran y el cielo queda quieto.
//
// La distancia se ACUMULA cuadro a cuadro y no sale de multiplicar el reloj por la velocidad: el
// reloj vale miles de segundos, así que cualquier cambio de velocidad (y el drop es el más grande
// de todos) saltaría multiplicado y las estrellas se teletransportarían enteras.
//
// PARED (`docs/PARED.md`): con lienzo común el campo es UNO que sale del foco (la pantalla de la
// letra, o el medio del lienzo) y cruza todas las pantallas; cada una dibuja las estrellas que
// caen en su ventana (`wallWin`). El campo se estira (`k`: cuántas veces más largo es el radio que
// en una pantalla sola): más estrellas, y la fase avanza `1/k` de rápido, así que una estrella
// recorre los mismos píxeles por segundo que en una pantalla sola. La distancia viajada vive en
// `wall.share.stars`. Una pantalla sola: todo como siempre.
import QtQuick

WallItem {
    id: stars
    // pared con la letra en una pantalla: campo que sale del foco: las alas espejadas enmarcan la letra (`Wall.fit`)
    wallFit: "mirror"

    property color colour: "#7fe4ff"
    property color hot: "#ffffff"
    property real level: 0.35
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

    // hasta dónde llega el campo: el borde (con 0.75 el campo terminaba antes que la pantalla y
    // quedaba un marco vacío alrededor). En pared, la esquina más lejana del lienzo desde el foco.
    readonly property real reach: {
        if (!walled)
            return span * 1.05;
        const f = wallFocus, a = wallArea;
        return Math.hypot(Math.max(f.x, a.x - f.x), Math.max(f.y, a.y - f.y)) * 1.03;
    }
    readonly property real k: Math.max(1, reach / (span * 1.05))

    property real travel: 0
    function wallStep() {
        const S = wall.share, now = wallNow();
        if (!S.stars)
            S.stars = { at: now, travel: 0 };
        const T = S.stars, dt = now - T.at;
        if (dt > 0) {
            // pausa o pantalla dormida: no teletransporta
            T.travel += Math.min(dt, 0.25) * speed * rate / k;
            T.at = now;
        }
        travel = T.travel;
    }
    onWallTChanged: if (wallExternal && wallShared && running) wallStep()
    FrameAnimation {
        running: stars.visible && stars.running && !stars.wallExternal
        onTriggered: {
            if (stars.wallShared)
                stars.wallStep();
            else
                stars.travel += frameTime * stars.speed * stars.rate;
        }
    }

    // T4.3b: eran 46 y en la cara clara del tubo se leían como cuatro puntos. La densidad y el
    // brillo son lo que hace que un campo de estrellas sea un campo: 46 puntos repartidos por fase
    // dejan la mitad cerca del centro, donde casi no se ven. En pared la densidad se conserva a
    // media distancia del foco (la cantidad crece con k^1,5, no k²: son ítems por pantalla).
    readonly property int count: walled ? Math.min(900, Math.round(110 * Math.pow(k, 1.5))) : 110

    // px de pantalla por px de lienzo (la ventana ya lleva la cámara y el tirón del golpe)
    readonly property real kz: walled && wallWin.w > 0 ? width / wallWin.w : 1

    Repeater {
        model: stars.visible ? stars.count : 0

        Rectangle {
            required property int index
            readonly property real ang: index * 2.399963      // ángulo áureo: reparte parejo
            readonly property real phase: (stars.travel + index / stars.count) % 1
            readonly property real dist: phase * stars.reach
            // la estela: en el hiperespacio el punto deja de ser un punto. `dist / k` = el largo
            // que tendría en una pantalla sola
            readonly property real dEq: dist / stars.k
            // el centro de la estrella en la pantalla: sin pared, el medio; en pared, el punto
            // del lienzo menos la esquina de la ventana
            readonly property real cx: stars.walled
                ? (stars.wallFocus.x + Math.cos(ang) * dist - stars.wallWin.x) * stars.kz
                : stars.width / 2 + Math.cos(ang) * dist
            readonly property real cy: stars.walled
                ? (stars.wallFocus.y + Math.sin(ang) * dist - stars.wallWin.y) * stars.kz
                : stars.height / 2 + Math.sin(ang) * dist
            // las que caen fuera de la ventana no se pintan (media estrella de margen para la estela)
            visible: !stars.walled || (cx > -width && cx < stars.width + width
                                       && cy > -width && cy < stars.height + width)
            x: cx - width / 2
            y: cy - height / 2
            width: Math.max(3, stars.span * 0.009 + dEq * 0.03 * (1 + 4 * stars.warp))
            height: Math.max(3, stars.span * 0.008)
            radius: height / 2
            rotation: ang * 180 / Math.PI
            color: index % 7 === 0 ? stars.hot
                : Qt.tint(stars.colour, Qt.rgba(stars.hot.r, stars.hot.g,
                                                stars.hot.b, 0.75 * stars.warp))
            // el piso de brillo: una estrella que nace invisible y
            // tarda media pantalla en aparecer no es una estrella
            opacity: Math.min(1, 0.30 + phase * 1.1) * (1 - 0.35 * phase * phase)
        }
    }
}
