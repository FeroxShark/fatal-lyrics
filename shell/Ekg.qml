// fatal-lyrics — el cardiograma.
//
// Un monitor de hospital: la traza barre de izquierda a derecha y el cursor
// BORRA lo que había de la vuelta anterior, así que en pantalla conviven el
// latido de hace cuatro segundos y el de recién. Eso es lo que lo hace leer
// como una máquina y no como una onda de audio: una onda de audio se mueve
// entera, un cardiograma se escribe.
//
// De dónde salen los latidos:
//   · con tempo confiable, del `tick` del root — que YA está cuantizado al
//     compás real. El contador de golpes crudo (`beat`) son onsets sueltos: con
//     ese, el QRS cae donde el bombo pega fuerte, no donde va el tiempo.
//   · sin tempo, del contador de golpes, que es lo único que hay.
//   · en silencio, ninguno: la línea queda plana con un temblor de nada y
//     parpadea un punto en el borde. El pitido, sin sonido.
//
// El trazo se repinta a 30 Hz y NO por cuadro: es un `Canvas` cooperativo, y
// una traza no necesita más. La cuenta de muestras baja con `quality`, que es
// lo único que este dibujo puede achicar sin dejar de ser el mismo.
import QtQuick

Item {
    id: ekg

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    property real beatAmt: 1
    property int beat: 0
    property int tick: 0
    property bool bpmLive: false
    property real quality: 1.0
    property real seed: 0
    property bool running: true

    // cuántas muestras entran en la pantalla: cuatro segundos de barrido a
    // 30 Hz con dos muestras por paso
    readonly property int slots: Math.max(90, Math.round(240 * Math.max(quality, 0.4)))
    // el hueco que deja el cursor por delante, en muestras
    readonly property int gap: Math.max(4, Math.round(slots * 0.03))

    property var samples: []
    property int cursor: 0

    // El silencio se mide contra el reloj, no contra un contador de golpes: un
    // tema puede tener el bombo callado dos segundos y seguir sonando.
    property double lastLoudAt: 0
    onLevelChanged: if (level > 0.04) lastLoudAt = Date.now()
    property bool silent: true
    // la pantalla quieta ES silencio: el Timer que recalcula `silent` está
    // parado justamente ahí, así que se fija a mano al apagarse
    onRunningChanged: if (!running) silent = true

    // El QRS se escribe MIENTRAS el cursor avanza, no de una: `qrsPhase` va de
    // 0 a 1 a lo largo de las muestras que dura el complejo. Con el latido
    // pintado de golpe en un solo punto, sería un pico de un pixel.
    property real qrsPhase: 2       // > 1 = no hay latido en curso
    property real qrsAmp: 1
    readonly property int qrsLen: Math.max(8, Math.round(slots * 0.09))

    function strike() {
        if (!running || beatAmt <= 0.01 || silent)
            return;
        qrsAmp = beatAmt * (0.5 + 0.5 * level);
        qrsPhase = 0;
    }
    onTickChanged: if (bpmLive) strike()
    onBeatChanged: if (!bpmLive) strike()

    // La forma de un latido, de la P a la T. Los tramos son los de un ECG de
    // verdad y no una campana: lo que se reconoce a simple vista es la subida
    // corta y el pozo que la precede, no la altura.
    function wave(u) {
        if (u < 0.14)                      // P
            return 0.13 * Math.sin(Math.PI * u / 0.14);
        if (u < 0.20)                      // segmento
            return 0;
        if (u < 0.25)                      // Q
            return -0.16 * Math.sin(Math.PI * (u - 0.20) / 0.05);
        if (u < 0.33)                      // R
            return Math.sin(Math.PI * (u - 0.25) / 0.08);
        if (u < 0.41)                      // S
            return -0.30 * Math.sin(Math.PI * (u - 0.33) / 0.08);
        if (u < 0.52)
            return 0;
        if (u < 0.82)                      // T
            return 0.24 * Math.sin(Math.PI * (u - 0.52) / 0.30);
        return 0;
    }

    function reset() {
        const a = new Array(slots);
        for (let i = 0; i < slots; i++)
            a[i] = 0;
        samples = a;
        cursor = 0;
        trace.requestPaint();
    }
    onSlotsChanged: reset()
    Component.onCompleted: reset()

    Timer {
        interval: 33
        repeat: true
        running: ekg.visible && ekg.running
        onTriggered: {
            ekg.silent = Date.now() - ekg.lastLoudAt > 2000;
            const a = ekg.samples;
            if (!a || a.length !== ekg.slots)
                return;
            // dos muestras por paso: el barrido tarda ~4 s en cruzar
            for (let k = 0; k < 2; k++) {
                let v = (Math.random() - 0.5) * (ekg.silent ? 0.012 : 0.03);
                if (ekg.qrsPhase <= 1) {
                    v += ekg.wave(ekg.qrsPhase) * ekg.qrsAmp;
                    ekg.qrsPhase += 1 / ekg.qrsLen;
                }
                a[ekg.cursor] = v;
                ekg.cursor = (ekg.cursor + 1) % ekg.slots;
            }
            ekg.samples = a;
            trace.requestPaint();
        }
    }

    Canvas {
        id: trace
        anchors.fill: parent
        anchors.margins: Math.min(parent.width, parent.height) * 0.08
        renderStrategy: Canvas.Cooperative

        // Sin esto, un cardiograma que nace con la pantalla quieta
        // (`spinning = false`) no se dibujaría nunca: el Timer está parado y
        // `onPaint` no lo llama nadie. Plano, pero nunca vacío.
        onVisibleChanged: if (visible) requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height;
            const a = ekg.samples;
            if (!a || a.length < 4 || w <= 0 || h <= 0)
                return;
            const n = a.length;
            const mid = h * 0.62;
            const amp = h * 0.34;

            // la línea de base: lo que queda cuando no hay nada
            c.strokeStyle = ekg.colour;
            c.globalAlpha = 0.18;
            c.lineWidth = 1;
            c.beginPath();
            c.moveTo(0, mid);
            c.lineTo(w, mid);
            c.stroke();

            c.globalAlpha = 1;
            c.strokeStyle = ekg.colour;
            c.lineWidth = Math.max(1.5, h * 0.012);
            c.lineJoin = "round";
            c.beginPath();
            let pen = false;
            for (let i = 0; i < n; i++) {
                // el hueco del cursor: lo de adelante ya se borró
                const ahead = (i - ekg.cursor + n) % n;
                if (ahead >= 0 && ahead < ekg.gap) {
                    pen = false;
                    continue;
                }
                const x = i / (n - 1) * w;
                const y = mid - a[i] * amp;
                if (!pen) {
                    c.moveTo(x, y);
                    pen = true;
                } else {
                    c.lineTo(x, y);
                }
            }
            c.stroke();

            // el cursor, la cabeza caliente que escribe
            const cx = ((ekg.cursor - 1 + n) % n) / (n - 1) * w;
            const cy = mid - a[(ekg.cursor - 1 + n) % n] * amp;
            c.fillStyle = ekg.hot;
            c.beginPath();
            c.ellipse(cx - h * 0.014, cy - h * 0.014, h * 0.028, h * 0.028);
            c.fill();
        }
    }

    // El pitido, sin sonido: en silencio parpadea un punto en el borde. Es un
    // item aparte y no parte del trazo porque en silencio el Timer del canvas
    // puede estar parado (pantalla quieta) y un parpadeo pintado ahí adentro se
    // congelaría prendido o apagado.
    Rectangle {
        id: pip
        visible: ekg.silent
        width: Math.max(4, Math.min(parent.width, parent.height) * 0.022)
        height: width
        radius: width / 2
        color: ekg.hot
        anchors.right: parent.right
        anchors.rightMargin: parent.width * 0.04
        y: parent.height * 0.62 - height / 2

        SequentialAnimation on opacity {
            running: pip.visible
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 120 }
            PauseAnimation { duration: 180 }
            NumberAnimation { to: 0.05; duration: 300 }
            PauseAnimation { duration: 900 }
        }
    }
}
