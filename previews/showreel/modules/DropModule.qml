// 05 DROP ZOOM — 11.250–13.594
// Golpe (destello + negativo en el vidrio) y un cartel con el osciloscopio
// del audio adentro. En cada bombo la cámara se TIRA a través del botón
// "Aceptar": adentro del botón hay otro cartel igual, y adentro del suyo otro.
// Zoom infinito exacto: cada nivel es el anterior × r alrededor del punto
// fijo x* = o / (1 − r), así que el nivel n+1 visto a escala (1/r)^n es
// idéntico al nivel 1. Un nivel por bombo (snap OutExpo) + deriva continua.
// Cada nivel canta una palabra: NO / RESPONDE / LA / MEMORIA / DE / TU / VOZ.
//
// Integrable: el osciloscopio es el `wave {l,r}` real (64+64 en ±127), el
// mismo que dibuja el motif `scope` del CRT. El zoom a través del botón es
// una entrada de drop para el modo carteles (`cue drop`).
import QtQuick
import QtQuick.Shapes
import ".."
import "../Ease.js" as E
import "../Timeline.js" as TL

Item {
    id: m
    property real t: 0
    property QtObject audio

    readonly property var seg: TL.segment("drop")

    // ---- geometría del cartel del drop (unidades base) --------------------
    readonly property real bw: 420
    readonly property real bodyH: 92
    readonly property real btnW: 96
    readonly property real btnH: 36
    readonly property real bh: 2 + 26 + bodyH + btnH + 12 + 2
    readonly property real btnCx: bw / 2
    readonly property real btnCy: 2 + 26 + bodyH + btnH / 2
    // el hijo entra en el botón con 3 px de aire por lado
    readonly property real r: Math.min((btnW - 6) / bw, (btnH - 4) / bh)
    readonly property real ox: btnCx - r * bw / 2
    readonly property real oy: btnCy - r * bh / 2
    readonly property real fx: ox / (1 - r)          // punto fijo
    readonly property real fy: oy / (1 - r)

    // ---- la cámara ---------------------------------------------------------
    // un nivel por bombo: 85 % en el snap (OutExpo) y 15 % de deriva lineal
    // que dura el tiempo entero, así al llegar al próximo golpe p es entero
    readonly property real p: {
        let s = 0;
        for (let i = 0; i < 4; i++) {
            const t0 = TL.b(25 + i) - 0.02;
            s += 0.85 * E.outExpo(E.prog(t, t0, 0.4)) + 0.15 * E.prog(t, t0, TL.BEAT);
        }
        return s;
    }
    readonly property real slam: E.mix(1.35, 1, E.outExpo(E.prog(t, seg.t0, 0.34)))
    readonly property real base: 0.74 * width / bw * slam
    readonly property real zoom: base * Math.pow(1 / r, p)
    // la cámara descansa con el cartel del nivel n CENTRADO y viaja al centro
    // del n+1 mientras hace zoom: el centro del nivel j (en unidades del 0) es
    // o·(1−r^j)/(1−r) + r^j·(centro)
    function centerOf(j) {
        const rj = Math.pow(r, j);
        return Qt.point(ox * (1 - rj) / (1 - r) + rj * bw / 2, oy * (1 - rj) / (1 - r) + rj * bh / 2);
    }
    readonly property int pn: Math.floor(p)
    readonly property real pf: p - pn
    readonly property point c0: centerOf(pn)
    readonly property point c1: centerOf(pn + 1)
    // el centro de la mira se mueve en la escala del zoom (no lineal): así
    // el punto que se acerca no "patina" en pantalla
    readonly property real pw: (Math.pow(1 / r, pf) - 1) / (1 / r - 1)
    readonly property real tx: E.mix(c0.x, c1.x, pw)
    readonly property real ty: E.mix(c0.y, c1.y, pw)
    readonly property real beatEnv: audio ? Math.exp(-Math.max(0, t - audio.lastBeatAt) / 0.12) : 0
    readonly property real shakeX: (E.hash(Math.floor(t * 60)) - 0.5) * 22 * beatEnv
    readonly property real shakeY: (E.hash(Math.floor(t * 60) + 5) - 0.5) * 14 * beatEnv

    readonly property var palettes: [
        ["#000080", "#1084d0"], ["#800000", "#e0502a"], ["#005f5f", "#22b8b0"],
        ["#3c0078", "#a050e0"], ["#101010", "#707070"], ["#000080", "#1084d0"],
        ["#800000", "#e0502a"], ["#005f5f", "#22b8b0"], ["#3c0078", "#a050e0"]
    ]
    readonly property var titles: ["fatal.exe", "memoria.sys", "voz.dll", "letra.tmp",
                                   "eco.exe", "fatal.exe", "memoria.sys", "voz.dll", "letra.tmp"]

    // ---- fondo: negro con estrellas que se estiran con la velocidad -------
    Rectangle { anchors.fill: parent; color: m.p > 1.2 ? "#c0c0c0" : "#000000" }
    Repeater {
        model: m.p < 1.2 ? 90 : 0
        Rectangle {
            required property int index
            readonly property real ang: E.hash(index * 1.31) * Math.PI * 2
            readonly property real rad: (E.hash(index * 7.1) * 0.9 + 0.1) * Math.exp((m.p % 1) * 2.2) * 700
            readonly property real len: 6 + 260 * m.beatEnv + 40 * (m.p % 1)
            x: m.width / 2 + Math.cos(ang) * rad
            y: m.height / 2 + Math.sin(ang) * rad
            width: len
            height: 2
            color: "#dff6ff"
            opacity: 0.7
            transformOrigin: Item.Left
            rotation: ang * 180 / Math.PI
        }
    }

    // ---- los niveles -------------------------------------------------------
    Repeater {
        model: 9
        Win95Dialog {
            id: lv
            required property int index
            readonly property real rj: Math.pow(m.r, index)
            // esquina del nivel j en unidades del nivel 0: o·(1−r^j)/(1−r)
            readonly property real ax: m.ox * (1 - rj) / (1 - m.r)
            readonly property real ay: m.oy * (1 - rj) / (1 - m.r)
            readonly property int target: Math.floor(m.p + 1e-6)
            readonly property real nextStep: TL.b(25 + index)
            k: m.zoom * rj
            visible: k > 0.02 && k < 45
            x: m.width / 2 + m.zoom * (ax - m.tx) + m.shakeX
            y: m.height / 2 + m.zoom * (ay - m.ty) + m.shakeY
            baseW: m.bw
            bodyH: m.bodyH
            btnW: m.btnW
            btnH: m.btnH
            btnTextSize: 15
            title: m.titles[index]
            titleA: m.palettes[index][0]
            titleB: m.palettes[index][1]
            icon: "none"
            buttons: ["Aceptar"]
            // el botón se hunde justo antes de que la cámara lo atraviese
            pressedIndex: m.t >= nextStep - 0.09 && m.t < nextStep + 0.05 ? 0 : -1
            sweep: E.prog(m.t, TL.b(24 + index), 0.24)

            // la palabra de este nivel
            Text {
                x: 16 * lv.k
                width: 230 * lv.k
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: TL.DROP_WORDS[Math.min(lv.index, TL.DROP_WORDS.length - 1)]
                font.pixelSize: Math.max(1, (TL.DROP_WORDS[Math.min(lv.index, 6)].length > 5 ? 28 : 44) * lv.k)
                font.bold: true
                font.letterSpacing: -1 * lv.k
                color: m.palettes[lv.index][0]
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 1
            }
            // osciloscopio: el `wave` L/R, en Lissajous
            Rectangle {
                x: 250 * lv.k; y: 8 * lv.k
                width: 150 * lv.k; height: (m.bodyH - 16) * lv.k
                color: "#08140c"
                border.color: "#404040"
                border.width: Math.max(1, lv.k)
                clip: true
                Shape {
                    anchors.fill: parent
                    visible: lv.k < 30
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: "#6dff9c"
                        strokeWidth: Math.max(1, 1.6 * lv.k)
                        fillColor: "transparent"
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline {
                            path: {
                                const w = m.audio ? m.audio.wave : { l: [], r: [] };
                                const pts = [];
                                const W = 150 * lv.k, H = (m.bodyH - 16) * lv.k;
                                for (let i = 0; i < w.l.length; i++)
                                    pts.push(Qt.point(W / 2 + w.l[i] / 127 * W * 0.46, H / 2 + w.r[i] / 127 * H * 0.44));
                                if (pts.length) pts.push(pts[0]);
                                return pts;
                            }
                        }
                    }
                }
            }
        }
    }
}
