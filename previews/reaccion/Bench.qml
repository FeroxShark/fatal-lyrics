// fatal-lyrics — banco de la reacción fina del vidrio (tanda 8), fuera de pantalla.
//
// Una pantalla del CRT: la cara (letra o, con `screen: "motif"`, un dibujo tenue
// sin letra) → `crt.frag` de `dir`. Los uniforms nuevos salen de `shell/React.js`
// — las MISMAS funciones que llama `Crt.qml` — alimentadas por la partitura
// sintética de `Score.js`. El reloj es `t`, que lo avanza `render.py`: el cuadro
// de un `t` dado es siempre el mismo.
//
// `mode: "before"` apaga los cuatro uniforms nuevos (y `dir` apunta a los `.qsb`
// viejos): lo que queda es el vidrio de la tanda 7 con la misma partitura.
import QtQuick
import "../../shell/React.js" as React
import "Score.js" as S

Item {
    id: stage
    width: 1920
    height: 1080

    property real t: 0
    property string dir: "../../shell"
    property string mode: "after"          // after | before
    property string screen: "text"         // text | motif
    property string tube: "trinitron"
    // sin estática ni barra: para medir un canal solo
    property bool clean: false
    property bool pulseOff: false
    // la fila de `crtPaceTable` y las constantes de Motion.qml: las lee render.py de
    // los archivos reales (acá no hay singleton ni root)
    property var pace: ({ cutDepth: 0.55, cutFlash: 0.30, fizzAmt: 0.70, grainMove: 0.80,
                          dirtMin: 1.0, dirtMax: 3.0 })
    property var motion: ({ exitMs: 140, holdMs: 1500, levelMs: 420, enterMs: 320 })

    // copia de `crtTubeTable` (shell.qml), las filas que usa la hoja
    readonly property var tubes: ({
        trinitron: { curvature: 0.35, scanlines: 0.40, chroma: 0.30, bloom: 1.10, noise: 0.12,
                     vignette: 0.55, maskType: 0, maskPitch: 2.4, mono: 0, monoTint: "#ffffff" },
        arcade: { curvature: 1.20, scanlines: 0.75, chroma: 0.80, bloom: 1.40, noise: 0.25,
                  vignette: 1.0, maskType: 1, maskPitch: 4.0, mono: 0, monoTint: "#ffffff" },
        green: { curvature: 0.90, scanlines: 0.55, chroma: 0.0, bloom: 1.50, noise: 0.35,
                 vignette: 0.90, maskType: 0, maskPitch: 3.0, mono: 1, monoTint: "#33ff66" },
    })
    readonly property var tb: tubes[tube] || tubes.trinitron
    readonly property color bg: "#150c05"
    readonly property color ink: "#ffb457"

    readonly property bool after: mode === "after"
    // el reloj de la partitura → lo que el root tendría en ese momento
    readonly property bool cutOn: S.cut(t)
    readonly property real backAt: t >= S.CUT_BACK ? S.CUT_BACK : -1
    readonly property real dirt: S.dirt(t)
    readonly property real pump: S.pump(t)
    readonly property real dirtMult: 1 + (pace.dirtMin + (pace.dirtMax - pace.dirtMin) * dirt - 1)
    readonly property bool focused: screen === "text"

    FontLoader { id: vt323; source: "../../shell/fonts/VT323-Regular.ttf" }

    Item {
        id: face
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: stage.bg }
        Column {
            visible: stage.screen === "text"
            anchors.centerIn: parent
            spacing: 24
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "NO QUIERO QUE SE APAGUE"
                color: stage.ink
                font.family: vt323.name
                font.pixelSize: 150
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "la luz del televisor"
                color: Qt.darker(stage.ink, 2.2)
                font.family: vt323.name
                font.pixelSize: 90
            }
        }
        // sin letra: unos aros tenues, lo que haría un motivo quieto
        Repeater {
            model: stage.screen === "motif" ? 6 : 0
            Rectangle {
                anchors.centerIn: parent
                width: 160 + index * 150
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 6
                border.color: Qt.darker(stage.ink, 1.4 + index * 0.35)
            }
        }
    }

    ShaderEffectSource {
        id: faceTex
        sourceItem: face
        hideSource: true
        visible: false
        smooth: true
    }

    ShaderEffect {
        anchors.fill: parent
        blending: false
        property variant src: faceTex
        property real t: stage.t + 100.0
        property real curvature: stage.tb.curvature
        property real scanline: stage.tb.scanlines
        property real chroma: stage.tb.chroma * 1.0
        property real bloom: stage.focused ? stage.tb.bloom * 0.75 : 0
        // lo mismo que Crt.qml con `rest` = 1: texto ×1, sin letra ×1.6
        property real noiseAmt: stage.clean ? 0 : stage.tb.noise * stage.dirtMult * (stage.focused ? 1 : 1.6)
        property real glitch: 0
        property real roll: stage.clean ? 0 : 0.15
        property real rollPhase: (stage.t * 0.085) % 1
        property real alarm: 0
        property real vignette: stage.tb.vignette
        // el golpe del bajo al valor que se VE con flicker 1 (sin el ×flickerAmt de la
        // perilla default 0.25²): así la hoja compara ejes a la misma escala
        property real pulse: stage.pulseOff ? 0 : S.beatPulse(stage.t) * (stage.focused ? 1 : 0.6)
        property real blink: 0
        property real interlacePhase: 0
        property real tubeLevel: 1
        property real maskType: stage.tb.maskType
        property real maskPitch: stage.tb.maskPitch
        property real mono: stage.tb.mono
        property variant monoTint: stage.color3(stage.tb.monoTint)
        property variant tint: stage.color3(stage.tb.mono > 0.5 ? stage.tb.monoTint : stage.ink)
        property real degauss: 0
        property real cutDim: stage.after
            ? React.cutDim(stage.t, S.CUT_ON, stage.cutOn, stage.pace.cutDepth,
                           stage.motion.exitMs, stage.motion.holdMs, stage.motion.levelMs) : 0
        property real backFlash: stage.after
            ? React.backFlash(stage.t, stage.backAt, S.CUT_F, stage.pace.cutFlash, stage.motion.enterMs) : 0
        property real fizz: stage.after
            ? React.fizz(S.hf(stage.t), stage.pace.fizzAmt) * (stage.focused ? 1 : 0.6) : 0
        property real grain: stage.after ? React.grain(stage.dirt, stage.pump, stage.pace.grainMove) : 0
        property real grainPhase: stage.after ? stage.phaseAt(stage.t) : 0
        property variant res: Qt.vector2d(width, height)
        fragmentShader: stage.dir + "/crt.frag.qsb"
    }

    // la fase acumulada, como en Crt.qml: se integra la partitura a 60 Hz desde 0
    function phaseAt(t) {
        let p = 0;
        const n = Math.floor(t * 60);
        for (let k = 1; k <= n; k++) {
            const tk = k / 60;
            p = React.grainAdvance(p, 1 / 60,
                React.grain(S.dirt(tk), S.pump(tk), stage.pace.grainMove));
        }
        return p;
    }

    function color3(c) {
        const q = Qt.color(c);
        return Qt.vector3d(q.r, q.g, q.b);
    }
}
