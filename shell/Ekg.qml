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

    // El QRS tiene PISO (T3.B9). Con la altura saliendo sólo del parpadeo del
    // tubo, un tema bajo dibujaba latidos de dos píxeles y el cardiograma
    // parecía una línea plana con ruido. El piso es el 45 % de la escala; lo
    // que la música mueve es el resto.
    function strike() {
        if (!running || silent)
            return;
        qrsAmp = Math.min(0.45 + 0.55 * beatAmt * (0.5 + 0.5 * level), 1.15);
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

    // La rejilla de papel de ECG: cuadrito chico y, cada cinco, el grueso, MUY tenue (alfa
    // bajo: compite con el bloom del vidrio). Se pinta UNA vez por tamaño o color, no por
    // cuadro: el motivo sigue costando lo que costaba. Una línea gruesa pasa por la base.
    Canvas {
        id: grid
        anchors.fill: parent
        anchors.margins: Math.min(parent.width, parent.height) * 0.08
        renderStrategy: Canvas.Cooperative
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: ekg; function onColourChanged() { grid.requestPaint(); } }
        onVisibleChanged: if (visible) requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height;
            if (w <= 0 || h <= 0)
                return;
            const g = Math.max(8, Math.min(w, h) / 36);
            const mid = h * 0.62;
            c.strokeStyle = ekg.colour;
            for (let pass = 0; pass < 2; pass++) {
                // 0 = el cuadrito, 1 = el grueso (cada cinco)
                c.globalAlpha = pass ? 0.13 : 0.06;
                c.lineWidth = pass ? Math.max(1.5, g * 0.09) : Math.max(1, g * 0.05);
                c.beginPath();
                for (let k = -Math.ceil(mid / g); k * g < h - mid + g; k++) {
                    if ((k % 5 !== 0) !== !pass)
                        continue;
                    const y = mid + k * g;
                    if (y < 0 || y > h)
                        continue;
                    c.moveTo(0, y);
                    c.lineTo(w, y);
                }
                for (let k = 0; k * g <= w; k++) {
                    if ((k % 5 !== 0) !== !pass)
                        continue;
                    c.moveTo(k * g, 0);
                    c.lineTo(k * g, h);
                }
                c.stroke();
            }
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
            // T4.3b: los grosores se miden con el LADO CORTO, no con el alto.
            // Con el alto, la misma traza sale de 13 px en la apaisada y de 23
            // en la vertical: no es el mismo dibujo en las dos pantallas.
            const span = Math.min(w, h);
            const mid = h * 0.62;
            const amp = span * 0.42;

            // la línea de base: lo que queda cuando no hay nada. Un píxel a
            // secas desaparece en 1080p con la curvatura del vidrio encima.
            c.strokeStyle = ekg.colour;
            c.globalAlpha = 0.22;
            c.lineWidth = Math.max(2, span / 540);
            c.beginPath();
            c.moveTo(0, mid);
            c.lineTo(w, mid);
            c.stroke();

            // el rastro con brillo decreciente: el latido de hace cuatro segundos pesa
            // menos que el de recién. Seis tandas de la más vieja (alfa 0.28) a la nueva
            // (1); una muestra va en la tanda que le toca por su EDAD (cuántas muestras
            // atrás del cursor), y cada tanda arranca desde el punto anterior para que
            // no queden cortes entre una y otra
            c.strokeStyle = ekg.colour;
            c.lineWidth = Math.max(2, span * 0.007);
            c.lineJoin = "round";
            c.lineCap = "round";
            const NB = 6;
            const live = n - ekg.gap;
            const inGap = i => ((i - ekg.cursor + n) % n) < ekg.gap;
            const bucketOf = i => Math.max(0, NB - 1 - Math.floor(((ekg.cursor - 1 - i + n) % n) / live * NB));
            const X = i => i / (n - 1) * w;
            const Y = i => mid - a[i] * amp;
            for (let B = 0; B < NB; B++) {
                c.globalAlpha = 0.28 + 0.72 * Math.pow(B / (NB - 1), 1.2);
                c.beginPath();
                let pen = false;
                for (let i = 0; i < n; i++) {
                    // el hueco del cursor: lo de adelante ya se borró
                    if (inGap(i)) {
                        pen = false;
                        continue;
                    }
                    if (bucketOf(i) !== B) {
                        pen = false;
                        continue;
                    }
                    if (!pen) {
                        if (i > 0 && !inGap(i - 1))
                            c.moveTo(X(i - 1), Y(i - 1));
                        else
                            c.moveTo(X(i), Y(i));
                        pen = true;
                    }
                    c.lineTo(X(i), Y(i));
                }
                c.stroke();
            }
            c.globalAlpha = 1;

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
