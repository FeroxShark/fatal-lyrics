// fatal-lyrics — motivo `scope`: un osciloscopio de laboratorio.
//
// Era una sola línea en un Canvas, flotando en la pantalla vacía. Ahora es el instrumento entero:
// la figura X-Y con la persistencia del fósforo (cinco trazas que se apagan) y, al lado, los dos
// canales en el tiempo con su disparo, que es lo que hace que se lea como un aparato.
//
// De dónde sale la señal:
//   · `wave` (audio real, L/R): X = izquierdo, Y = derecho. Si los canales son casi iguales
//     (|correlación| > 0.98) una diagonal no dice nada: retrato de fase, la muestra contra ella misma
//     atrasada `d`, la que más separa los ejes.
//   · sin `wave` por más de `waveStaleMs`: senos con una relación que sale de la parte del tema (1 en
//     el silencio, 4/3 en la subida, 2 en el drop, 3/2 el resto). Sin tempo deriva y no cierra.
//
// La fase y la deriva se ACUMULAN: el reloj vale miles de segundos y cualquier cambio de tempo pegaría
// un salto de la figura entera. Se escribe a 30 Hz: una traza no necesita más.
// Costo: un `MShape` (placa de video) con ~1200 tramos, no un Canvas.
import QtQuick
import "../Ease.js" as E

ThumpBase {
    id: m
    property var waveL: []
    property var waveR: []
    property double waveAt: -1     // -1 = no se mira la frescura (el banco)
    property int waveStaleMs: 300

    readonly property real target: section === "quiet" ? 1
        : section === "build" ? (4 / 3)
        : section === "drop" ? 2 : 1.5
    property real ratio: 1.5
    readonly property int turns: !bpmLive ? 3
        : (Math.abs(target - 1.5) < 0.02 ? 2 : (Math.abs(target - 4 / 3) < 0.02 ? 3 : 1))

    readonly property bool wide: width > height * 1.25
    readonly property real mg: span * 0.065
    readonly property real side: wide ? height - 2 * mg : width - 2 * mg
    readonly property rect xyBox: wide ? Qt.rect(mg, mg, side, side)
                                       : Qt.rect(mg, mg, side, side)
    readonly property real gap: mg * 0.7
    readonly property real chX: wide ? mg * 1.7 + side : mg
    readonly property real chY: wide ? mg : mg * 1.7 + side
    readonly property real chW: width - chX - mg
    readonly property real chH: ((wide ? side : height - chY - mg) - gap) / 2
    readonly property rect ch1Box: Qt.rect(chX, chY, chW, chH)
    readonly property rect ch2Box: Qt.rect(chX, chY + chH + gap, chW, chH)

    property string source: "synthetic"
    property real scPhase: 0
    property real wobble: 0
    property double lastStep: -1e9
    property var ghosts: []          // las últimas trazas X-Y, en px, la más vieja primero
    property var ch1: []
    property var ch2: []
    property point dot: Qt.point(0, 0)

    function waveTrace() {
        const l = waveL, r = waveR, n = l ? l.length : 0;
        if (n < 16 || !r || r.length !== n || (waveAt >= 0 && Date.now() - waveAt > waveStaleMs))
            return null;
        let ll = 0, rr = 0, lr = 0;
        for (let i = 0; i < n; i++) {
            ll += l[i] * l[i];
            rr += r[i] * r[i];
            lr += l[i] * r[i];
        }
        const corr = (ll > 0 && rr > 0) ? lr / Math.sqrt(ll * rr) : 1;
        const a = new Array(n), b = new Array(n);
        for (let i = 0; i < n; i++) {
            a[i] = l[i] / 127;
            b[i] = r[i] / 127;
        }
        if (Math.abs(corr) <= 0.98)
            return { mode: "lissajous", x: a, y: b, ch1: a, ch2: b };
        const s = a.map((v, i) => (v + b[i]) / 2);
        let d = 1, best = 2, ss = 0;
        for (let i = 0; i < n; i++)
            ss += s[i] * s[i];
        for (let k = 1; k <= 8; k++) {
            let c = 0;
            for (let i = k; i < n; i++)
                c += s[i] * s[i - k];
            c = ss > 0 ? Math.abs(c) / ss : 1;
            if (c < best) {
                best = c;
                d = k;
            }
        }
        return { mode: "phase", x: s.slice(d), y: s.slice(0, n - d), ch1: a, ch2: b };
    }
    function synthTrace() {
        const amp = 0.70 + 0.22 * level;
        const b = ratio + (bpmLive ? 0 : 0.06 * Math.sin(wobble * 0.8));
        const N = Math.max(120, Math.round(190 * turns * Math.max(quality, 0.5)));
        const x = [], y = [], c1 = [], c2 = [];
        for (let i = 0; i <= N; i++) {
            const t = i / N * Math.PI * 2 * turns;
            x.push(Math.sin(t + scPhase) * amp);
            y.push(Math.sin(b * t) * amp);
        }
        for (let i = 0; i < 64; i++) {
            const t = i / 63 * Math.PI * 4;
            c1.push(Math.sin(t + scPhase) * amp);
            c2.push(Math.sin(b * t + scPhase) * amp);
        }
        return { mode: "synthetic", x: x, y: y, ch1: c1, ch2: c2 };
    }
    // un punto cada tres, por Catmull-Rom: 64 muestras de un agudo si no son un polígono
    function smooth(v) {
        if (v.length > 100)
            return v;
        const out = [], n = v.length;
        for (let i = 0; i < n - 1; i++) {
            const p0 = v[Math.max(i - 1, 0)], p1 = v[i], p2 = v[i + 1], p3 = v[Math.min(i + 2, n - 1)];
            for (let k = 0; k < 3; k++) {
                const t = k / 3, t2 = t * t, t3 = t2 * t;
                out.push(0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                                + (3 * p1 - p0 - 3 * p2 + p3) * t3));
            }
        }
        out.push(v[n - 1]);
        return out;
    }
    // el disparo: arranca en la primera subida por cero, y la onda queda quieta como en un aparato
    function triggered(v) {
        const n = v.length;
        let at = 0;
        for (let i = 1; i < n / 2; i++) {
            if (v[i - 1] < 0 && v[i] >= 0) {
                at = i;
                break;
            }
        }
        return v.slice(at, at + Math.ceil(n / 2));
    }
    function chLine(v, box) {
        const s = smooth(triggered(v)), out = [], n = s.length, mid = box.y + box.height / 2, a = box.height * 0.46;
        for (let i = 0; i < n; i++)
            out.push(Qt.point(box.x + i / (n - 1) * box.width, mid - E.clamp(s[i], -1, 1) * a));
        return [out];
    }
    function step() {
        const dt = clock - lastStep;
        if (dt > 0 && dt < 0.033)
            return;
        lastStep = clock;
        const d = dt > 0 ? Math.min(dt, 0.25) : 0.033;
        scPhase = (scPhase + d / (Math.max(beatMs, 120) * 4 / 1000) * Math.PI * 2) % (Math.PI * 2);
        wobble += d;
        ratio += (target - ratio) * Math.min(1, d * 4.5);
        const tr = waveTrace() || synthTrace();
        if (tr.mode !== source) {
            source = tr.mode;
            console.log("crt: scope " + source);
        }
        const sx = smooth(tr.x), sy = smooth(tr.y), n = Math.min(sx.length, sy.length);
        const cx = xyBox.x + xyBox.width / 2, cy = xyBox.y + xyBox.height / 2, r = xyBox.width * 0.47;
        const pts = new Array(n);
        for (let i = 0; i < n; i++)
            pts[i] = Qt.point(cx + E.clamp(sx[i], -1, 1) * r, cy - E.clamp(sy[i], -1, 1) * r);
        const g = ghosts.slice(-4);
        g.push(pts);
        ghosts = g;
        ch1 = chLine(tr.ch1, ch1Box);
        ch2 = chLine(tr.ch2, ch2Box);
        dot = pts[n - 1];
    }
    onClockChanged: if (running && visible) step()
    Component.onCompleted: step()

    Repeater {
        model: 3
        ShaderEffect {
            required property int index
            readonly property rect box: index === 0 ? m.xyBox : index === 1 ? m.ch1Box : m.ch2Box
            x: box.x
            y: box.y
            width: box.width
            height: box.height
            blending: true
            property color ink: m.colour
            property variant res: Qt.vector2d(width, height)
            property real cell: index === 0 ? box.width / 40 : box.height / 16
            property real major: 5
            property real axes: 1
            property real gain: 1
            fragmentShader: Qt.resolvedUrl("scopegrid.frag.qsb")
        }
    }

    MShape {
        readonly property real w: Math.max(1.5, m.span * 0.0034 * (1 + 0.5 * m.surge))
        styles: [
            { w: w * 0.8, c: E.col(m.colour, 0.10) },
            { w: w * 0.8, c: E.col(m.colour, 0.18) },
            { w: w * 0.9, c: E.col(m.colour, 0.30) },
            { w: w, c: E.col(m.colour, 0.52) },
            { w: w * 1.15, c: E.col(m.colour, 1) },
            { w: w, c: E.col(m.colour, 0.95) },
            { w: w, c: E.col(m.hot, 0.95) }
        ]
        geo: {
            const out = [], g = m.ghosts, pad = 5 - g.length;
            for (let i = 0; i < 5; i++)
                out.push(i >= pad ? [g[i - pad]] : []);
            out.push(m.ch1, m.ch2);
            return out;
        }
    }

    Rectangle {
        readonly property real d: m.span * 0.015 * (1 + 0.8 * m.surge)
        width: d; height: d; radius: d / 2
        x: m.dot.x - d / 2
        y: m.dot.y - d / 2
        color: m.hot
    }

    component Label: Text {
        color: m.colour
        opacity: 0.82
        font.family: m.fontFamily
        font.pixelSize: Math.round(m.span * 0.032)
    }
    Label {
        x: m.xyBox.x + m.span * 0.012
        y: m.xyBox.y + m.span * 0.006
        text: "X-Y  " + (m.source === "phase" ? "PHASE" : m.source === "lissajous" ? "L/R" : "SYNTH")
    }
    Label {
        x: m.ch1Box.x + m.span * 0.012
        y: m.ch1Box.y + m.span * 0.006
        text: "CH1 L"
    }
    Label {
        x: m.ch2Box.x + m.span * 0.012
        y: m.ch2Box.y + m.span * 0.006
        text: "CH2 R"
    }
    Label {
        anchors.right: parent.right
        anchors.rightMargin: m.mg + m.span * 0.012
        y: m.ch1Box.y + m.span * 0.006
        text: (m.bpmLive ? Math.round(60000 / Math.max(m.beatMs, 1)) + " BPM" : "NO SYNC")
    }
    Label {
        anchors.right: parent.right
        anchors.rightMargin: m.mg + m.span * 0.012
        y: m.ch2Box.y + m.span * 0.006
        text: m.drop ? "TRIG  OVER" : "TRIG  AUTO"
    }
}
