// fatal-lyrics — la estática que arma cosas.
//
// Una pantalla sin señal, con una gracia: una vez por compás el ruido se pone
// de acuerdo y forma algo durante un tiempo — un círculo, el número de verso,
// o la primera palabra de la línea que VIENE (la anticipación de la tanda 2) —
// y enseguida se deshace.
//
// La forma no se dibuja: se captura. Un `Text` (o un círculo) escondido va a un
// `ShaderEffectSource` y entra al shader como máscara; adentro de la máscara el
// grano es más fino y más brillante, que es lo que se lee como "la señal casi
// engancha". Pintar la forma de un color sería una calcomanía pegada encima.
//
// La palabra se congela CUANDO ARRANCA la convergencia y no se lee del vivo:
// `next` cambia cuando cae la línea siguiente, y entonces la palabra mutaría a
// mitad de camino.
import QtQuick

Item {
    id: snow

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    Behavior on level { NumberAnimation { duration: Motion.levelMs; easing.type: Easing.OutQuad } }
    property real high: 0.3
    property real seed: 0
    property real dim: 1.0
    property bool running: true
    property string fontFamily: "monospace"
    // el compás: con tempo confiable la forma cae cada cuatro tiempos, y si no
    // hay tempo, cada 2.4 s (cuatro tiempos de un tema cualquiera)
    property int tick: 0
    property real beatMs: 500
    property bool bpmLive: false

    // qué puede formar: el número de esta línea (dos dígitos) y la primera
    // palabra de la que viene. -1 y "" son válidos: sin ellos queda el círculo
    // y el signo de pregunta.
    property int lineNo: -1
    property string nextWord: ""

    // Reloj propio: el del tubo va a 20 Hz en las pantallas sin letra, y el
    // ruido se cuantiza igual adentro del shader.
    property real clock: 0
    property real pending: 0
    FrameAnimation {
        running: snow.running && snow.visible
        onTriggered: {
            snow.pending += frameTime;
            if (snow.pending >= 0.028) {
                snow.clock += snow.pending;
                snow.pending = 0;
            }
        }
    }

    // 0 = ruido pelado, 1 = la forma cuajó
    property real form: 0
    // 0 círculo | 1 número | 2 palabra
    property int shape: 0
    // cuánto dura la ventana legible: un tiempo, y nunca más de 1.2 s aunque el
    // tema sea lentísimo
    readonly property real formMs: Math.min(beatMs > 0 ? beatMs : 700, 1200)

    property int bar: 0
    onTickChanged: {
        if (!bpmLive)
            return;
        bar = (bar + 1) % 4;
        if (bar === 0)
            snow.converge();
    }
    Timer {
        interval: 2400
        repeat: true
        running: snow.running && snow.visible && !snow.bpmLive
        onTriggered: snow.converge()
    }

    // lo que se va a formar, CONGELADO al arrancar: `nextWord` cambia cuando
    // cae la línea siguiente, y con el binding vivo la palabra mutaría en el
    // medio de la convergencia
    property string shownWord: "?"
    property int shownNo: 0

    function converge() {
        if (!running)
            return;
        // rotación al azar entre las tres formas; el número sólo si se sabe en
        // qué verso va el tema
        const roll = Math.random();
        shape = roll < 0.34 ? 0 : (roll < 0.67 && lineNo >= 0 ? 1 : 2);
        shownNo = Math.max(lineNo, 0) % 100;
        shownWord = nextWord !== "" ? nextWord.toUpperCase() : "?";
        // la máscara se re-captura ACÁ y en ningún otro lado: es lo único que
        // cambió. Ver el comentario de `maskSrc`.
        maskSrc.scheduleUpdate();
        formAnim.restart();
    }

    SequentialAnimation {
        id: formAnim
        NumberAnimation {
            target: snow; property: "form"; to: 1
            duration: Math.round(snow.formMs * 0.5); easing.type: Easing.OutQuad
        }
        PauseAnimation { duration: Math.round(snow.formMs * 0.3) }
        NumberAnimation {
            target: snow; property: "form"; to: 0
            duration: Math.round(snow.formMs * 0.5); easing.type: Easing.InQuad
        }
    }

    // ---- la máscara. NO va con `visible: false`: adentro de un item invisible
    // no se dibuja nada y la captura sale vacía (la misma trampa que el burn-in
    // de los carteles). Se esconde con `hideSource` del ShaderEffectSource.
    Item {
        id: maskItem
        width: snow.width
        height: snow.height

        Rectangle {
            anchors.centerIn: parent
            visible: snow.shape === 0
            width: Math.min(parent.width, parent.height) * 0.42
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(4, width * 0.09)
            border.color: "white"
        }

        Text {
            anchors.centerIn: parent
            visible: snow.shape !== 0
            // el número va en dos dígitos: es un contador de pantalla vieja, no
            // una cuenta. La palabra, entera y en mayúsculas.
            text: snow.shape === 1 ? ("0" + snow.shownNo).slice(-2) : snow.shownWord
            color: "white"
            font.family: snow.fontFamily
            font.pixelSize: Math.round(Math.min(parent.width, parent.height) * 0.38)
            font.bold: true
            // sin achicarse, una palabra larga se sale de la pantalla y la
            // máscara queda cortada por los dos costados
            fontSizeMode: Text.HorizontalFit
            width: parent.width * 0.86
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // `live: false`: la forma cambia UNA vez por compás, y con la captura viva
    // el `Text` se re-renderiza en cada cuadro del tubo para dar exactamente la
    // misma textura. Se re-captura a mano cuando la forma cambia (`converge`) y
    // cuando cambia el tamaño — y una vez al nacer, porque con `live: false` no
    // hay textura hasta la primera actualización y la máscara saldría vacía.
    ShaderEffectSource {
        id: maskSrc
        sourceItem: maskItem
        hideSource: true
        live: false
        width: Math.max(snow.width, 1)
        height: Math.max(snow.height, 1)
        onWidthChanged: scheduleUpdate()
        onHeightChanged: scheduleUpdate()
        Component.onCompleted: scheduleUpdate()
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true
        visible: snow.width > 0 && snow.height > 0

        property real t: snow.clock
        property real form: snow.form
        property real seed: snow.seed
        property real level: snow.level
        property real high: snow.high
        property real dim: snow.dim
        property variant res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property variant ink: Qt.vector3d(snow.colour.r, snow.colour.g, snow.colour.b)
        property variant hot: Qt.vector3d(snow.hot.r, snow.hot.g, snow.hot.b)
        property variant mask: maskSrc

        fragmentShader: Qt.resolvedUrl("static.frag.qsb")
    }
}
