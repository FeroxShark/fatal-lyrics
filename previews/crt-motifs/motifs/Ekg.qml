// fatal-lyrics — motivo `ekg`: un monitor de hospital.
//
// Las tres trazas barren de izquierda a derecha y el cursor BORRA lo que había de la vuelta anterior:
// en pantalla conviven el latido de hace cuatro segundos y el de recién. Eso lo hace leer como una
// máquina: una onda de audio se mueve entera, un cardiograma se escribe.
//   · ECG    — un latido por tiempo (`tick`, ya cuantizado; sin tempo, los golpes `beat`)
//   · PLETH  — la onda de pulso, un cuarto de segundo después de cada latido
//   · RESP   — la respiración: lenta, y más honda con el volumen
// Los números son del tema: HR es el BPM de verdad. En silencio la línea queda plana y dice ASYSTOLE.
//
// El QRS tiene PISO (T3.B9): con la altura saliendo sólo del golpe, un tema bajo dibuja latidos de
// dos píxeles. Se escribe a 30 Hz con `MShape` (placa de video), no con Canvas.
import QtQuick
import "../Ease.js" as E

ThumpBase {
    id: m
    property real beatAmt: 1

    readonly property int slots: Math.max(120, Math.round(240 * Math.max(quality, 0.4)))
    readonly property int erase: Math.max(4, Math.round(slots * 0.03))
    readonly property real sampleHz: slots / 4

    readonly property bool wide: width > height * 1.25
    readonly property real mg: span * 0.055
    // los números, a la derecha; en la vertical, arriba
    readonly property real numW: wide ? Math.max(width * 0.24, span * 0.42) : width - 2 * mg
    readonly property real numH: wide ? height - 2 * mg : span * 0.40
    readonly property rect plot: wide
        ? Qt.rect(mg, mg, width - 3 * mg - numW, height - 2 * mg)
        : Qt.rect(mg, 2 * mg + numH, width - 2 * mg, height - 3 * mg - numH)
    // alto de cada carril (el ECG es el grande) y su línea de base
    readonly property var lanes: [
        { y: plot.y, h: plot.height * 0.50, base: 0.68, amp: 0.56 },
        { y: plot.y + plot.height * 0.50, h: plot.height * 0.25, base: 0.76, amp: 0.56 },
        { y: plot.y + plot.height * 0.75, h: plot.height * 0.25, base: 0.52, amp: 0.34 }
    ]

    property var leads: [[], [], []]
    property int cursor: 0
    property double lastStep: -1e9
    property double acc: 0
    property double lastLoud: -1e9
    property bool silent: false
    property real qrs: 2           // > 1 = no hay latido en curso
    property real qrsAmp: 1
    property real plethIn: -1
    property real pleth: 2
    property real respPh: 0
    property real respAmp: 0.6
    readonly property int qrsLen: Math.max(8, Math.round(slots * 0.09))
    property int hitCount: 0

    function wave(u) {
        if (u < 0.14) return 0.13 * Math.sin(Math.PI * u / 0.14);       // P
        if (u < 0.20) return 0;
        if (u < 0.25) return -0.16 * Math.sin(Math.PI * (u - 0.20) / 0.05);  // Q
        if (u < 0.33) return Math.sin(Math.PI * (u - 0.25) / 0.08);     // R
        if (u < 0.41) return -0.30 * Math.sin(Math.PI * (u - 0.33) / 0.08);  // S
        if (u < 0.52) return 0;
        if (u < 0.82) return 0.24 * Math.sin(Math.PI * (u - 0.52) / 0.30);   // T
        return 0;
    }
    // la onda de pulso: sube rápido, baja con la muesca dicrótica
    function plethWave(u) {
        if (u < 0.25) return Math.sin(u / 0.25 * Math.PI / 2);
        return Math.max(0, 1 - (u - 0.25) / 0.75) * (0.62 + 0.38 * Math.cos((u - 0.25) * 12));
    }
    function strike() {
        if (!running || silent)
            return;
        qrsAmp = Math.min(0.45 + 0.55 * beatAmt * (0.5 + 0.5 * level), 1.15);
        qrs = 0;
        plethIn = 0.25;
        hitCount++;
    }
    onTickChanged: if (bpmLive) strike()
    onBeatChanged: if (!bpmLive) strike()

    function reset() {
        const mk = () => {
            const a = new Array(slots);
            for (let i = 0; i < slots; i++)
                a[i] = 0;
            return a;
        };
        leads = [mk(), mk(), mk()];
        cursor = 0;
    }
    onSlotsChanged: reset()

    function step() {
        const dt = clock - lastStep;
        if (dt > 0 && dt < 0.033)
            return;
        lastStep = clock;
        if (level > 0.04)
            lastLoud = clock;
        silent = clock - lastLoud > 2;
        const L = leads;
        if (L[0].length !== slots)
            return;
        acc += dt > 0 ? Math.min(dt, 0.25) * sampleHz : 1;
        const n = Math.floor(acc);
        acc -= n;
        for (let k = 0; k < n; k++) {
            const sd = cursor * 3.1 + hitCount * 0.7;
            let e = (E.hash(sd) - 0.5) * (silent ? 0.012 : 0.03);
            if (qrs <= 1) {
                e += wave(qrs) * qrsAmp;
                qrs += 1 / qrsLen;
            }
            if (plethIn >= 0) {
                plethIn -= 1 / sampleHz;
                if (plethIn < 0)
                    pleth = 0;
            }
            let p = 0;
            if (pleth <= 1) {
                p = plethWave(pleth) * qrsAmp;
                pleth += 1 / (sampleHz * 0.55);
            }
            respPh += (0.28 + 0.12 * dens) / sampleHz * Math.PI * 2;
            respAmp += ((silent ? 0 : 0.45 + 0.55 * level) - respAmp) * 0.01;
            const r = Math.sin(respPh) * respAmp;
            L[0][cursor] = e;
            L[1][cursor] = p;
            L[2][cursor] = r;
            cursor = (cursor + 1) % slots;
        }
        leads = L;
        rebuild();
    }
    // cuatro tandas por edad, de la vuelta vieja (tenue) a lo recién escrito
    property var geos: [[], [], [], []]
    function rebuild() {
        const out = [[], [], [], []], n = slots;
        const X = i => plot.x + i / (n - 1) * plot.width;
        for (let l = 0; l < 3; l++) {
            const a = leads[l], ln = lanes[l];
            const base = ln.y + ln.h * ln.base, amp = ln.h * ln.amp;
            let cur = null, curB = -1;
            for (let i = 0; i < n; i++) {
                if (((i - cursor + n) % n) < erase) {
                    cur = null;
                    continue;
                }
                const age = (cursor - 1 - i + n) % n;
                const B = Math.max(0, 3 - Math.floor(age / (n - erase) * 4));
                const p = Qt.point(X(i), base - a[i] * amp);
                if (B !== curB || !cur) {
                    const nu = cur ? [cur[cur.length - 1]] : [];
                    cur = nu;
                    curB = B;
                    out[B].push(cur);
                }
                cur.push(p);
            }
        }
        geos = out;
    }
    function headY(l) {
        const a = leads[l], ln = lanes[l];
        if (!a || !a.length)
            return ln.y;
        return ln.y + ln.h * ln.base - a[(cursor - 1 + slots) % slots] * ln.h * ln.amp;
    }
    onClockChanged: if (running && visible) step()
    Component.onCompleted: { reset(); lastLoud = clock; rebuild(); }

    ShaderEffect {
        x: m.plot.x
        y: m.plot.y
        width: m.plot.width
        height: m.plot.height
        blending: true
        property color ink: m.colour
        property variant res: Qt.vector2d(width, height)
        property real cell: m.span / 36
        property real major: 5
        property real axes: 0
        property real gain: 0.8
        fragmentShader: Qt.resolvedUrl("scopegrid.frag.qsb")
    }

    MShape {
        readonly property real w: Math.max(2, m.span * 0.0042)
        styles: [
            { w: w, c: E.col(m.colour, 0.24) },
            { w: w, c: E.col(m.colour, 0.42) },
            { w: w, c: E.col(m.colour, 0.68) },
            { w: w * 1.1, c: E.col(m.colour, 1) }
        ]
        geo: m.geos
    }

    // las cabezas que escriben
    Repeater {
        model: 3
        Rectangle {
            required property int index
            readonly property real d: m.span * (index === 0 ? 0.017 : 0.012)
            width: d; height: d; radius: d / 2
            x: m.plot.x + ((m.cursor - 1 + m.slots) % m.slots) / (m.slots - 1) * m.plot.width - d / 2
            y: m.headY(index) - d / 2
            color: m.hot
        }
    }

    component Label: Text {
        color: m.colour
        font.family: m.fontFamily
    }
    Label { x: m.plot.x + m.span * 0.012; y: m.lanes[0].y + m.span * 0.008; text: "II"; opacity: 0.8; font.pixelSize: Math.round(m.span * 0.032) }
    Label { x: m.plot.x + m.span * 0.012; y: m.lanes[1].y + m.span * 0.008; text: "PLETH"; opacity: 0.8; font.pixelSize: Math.round(m.span * 0.032) }
    Label { x: m.plot.x + m.span * 0.012; y: m.lanes[2].y + m.span * 0.008; text: "RESP"; opacity: 0.8; font.pixelSize: Math.round(m.span * 0.032) }

    // los números
    readonly property int hr: m.silent ? 0 : Math.round(60000 / Math.max(m.beatMs, 1))
    readonly property int spo2: m.silent ? 0 : Math.round(94 + 5 * E.clamp01(m.level))
    readonly property int rr: m.silent ? 0 : Math.round(12 + 14 * m.dens)
    readonly property string alarm: m.silent ? "ASYSTOLE" : m.hr > 150 ? "TACHY" : m.drop ? "HR HIGH" : ""
    // el corazón late con el golpe: el número grande se aclara un instante
    property real pulse: 0
    onHitCountChanged: { pulse = 1; pulseOff.restart(); }
    NumberAnimation { id: pulseOff; target: m; property: "pulse"; to: 0; duration: 260; easing.type: Easing.OutQuad }

    Item {
        x: m.wide ? m.width - m.mg - m.numW : m.mg
        y: m.mg
        width: m.numW
        height: m.numH
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: m.colour
            border.width: Math.max(1, m.span * 0.0016)
            opacity: 0.55
        }
        Column {
            anchors.left: parent.left
            anchors.leftMargin: m.span * 0.03
            anchors.verticalCenter: parent.verticalCenter
            spacing: m.span * (m.wide ? 0.03 : 0.004)
            Label { text: "HR  bpm"; opacity: 0.8; font.pixelSize: Math.round(m.span * 0.036) }
            Text {
                text: m.silent ? "--" : String(m.hr)
                color: Qt.tint(m.colour, Qt.rgba(m.hot.r, m.hot.g, m.hot.b, m.pulse))
                font.family: m.fontFamily
                font.pixelSize: Math.round(m.span * (m.wide ? 0.21 : 0.14))
                lineHeight: 0.85
            }
            Row {
                spacing: m.span * 0.05
                Column {
                    Label { text: "SpO2 %"; opacity: 0.8; font.pixelSize: Math.round(m.span * 0.032) }
                    Label { text: m.silent ? "--" : String(m.spo2); font.pixelSize: Math.round(m.span * 0.09) }
                }
                Column {
                    Label { text: "RESP"; opacity: 0.8; font.pixelSize: Math.round(m.span * 0.032) }
                    Label { text: m.silent ? "--" : String(m.rr); font.pixelSize: Math.round(m.span * 0.09) }
                }
            }
            Text {
                visible: m.alarm !== ""
                text: "*** " + m.alarm
                color: m.hot
                font.family: m.fontFamily
                font.pixelSize: Math.round(m.span * 0.045)
                opacity: (m.bp < 0.5 || !m.bpmLive) ? 1 : 0.35
            }
        }
    }
}
