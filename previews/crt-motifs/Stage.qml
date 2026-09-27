// fatal-lyrics motivos CRT — una pantalla del CRT, sin letra, con UN motivo.
//
// Arma lo mismo que Crt.qml para una pantalla en el instrumental: la cara
// (fondo de la paleta `b`, tubo apagado), el motivo con el latido de Motif.qml
// (opacidad y tirón de tamaño de `pace = normal`) y las DOS pasadas del tubo
// con los `.qsb` reales de `shell/`: `signal.frag` (el cable) → `crt.frag` (el
// vidrio). Los uniforms salen de una fila de `crtTubeTable` y de las mismas
// cuentas de Crt.qml para una pantalla sin letra (bloom 0, ruido ×1.6).
//
// El reloj que ven los shaders es `t mod 15`: el ruido del vidrio también
// cierra el loop (en el overlay es `tubeTime`, que no necesita cerrar nada).
import QtQuick
import "Loop.js" as L
import "Ease.js" as E

Item {
    id: stage
    width: 1920
    height: 1080

    property real t: 0
    property string kind: "mystify"
    property string tube: "trinitron"
    property string scheme: "ado"
    property bool glassOn: true

    readonly property var schemes: ({
        dragons: { bg: "#170604", ink: "#ff8a2b", hot: "#ffe0b0" },
        ado: { bg: "#04162e", ink: "#7fe4ff", hot: "#ffffff" },
        poison: { bg: "#04120a", ink: "#9dff3d", hot: "#e8ffc4" },
        bloodline: { bg: "#12030a", ink: "#ff5c7a", hot: "#ffd6de" },
        vapor: { bg: "#0d0a2b", ink: "#6ff2ff", hot: "#e6ffff" },
        bone: { bg: "#150c05", ink: "#ffb457", hot: "#ffe6c2" },
    })
    // copia de `crtTubeTable` (shell.qml); `custom` con las perillas default
    readonly property var tubes: ({
        trinitron: { curvature: 0.35, scanlines: 0.40, chroma: 0.30, noise: 0.12, roll: 0.15,
                     vignette: 0.55, composite: 0.35, maskType: 0, maskPitch: 2.4, mono: 0, monoTint: "#ffffff" },
        pvm: { curvature: 0.50, scanlines: 0.65, chroma: 0.15, noise: 0.05, roll: 0.0,
               vignette: 0.50, composite: 0.0, maskType: 2, maskPitch: 3.0, mono: 0, monoTint: "#ffffff" },
        arcade: { curvature: 1.20, scanlines: 0.75, chroma: 0.80, noise: 0.25, roll: 0.60,
                  vignette: 1.0, composite: 0.15, maskType: 1, maskPitch: 4.0, mono: 0, monoTint: "#ffffff" },
        green: { curvature: 0.90, scanlines: 0.55, chroma: 0.0, noise: 0.35, roll: 0.60,
                 vignette: 0.90, composite: 0.15, maskType: 0, maskPitch: 3.0, mono: 1, monoTint: "#33ff66" },
        amber: { curvature: 0.90, scanlines: 0.55, chroma: 0.0, noise: 0.30, roll: 0.50,
                 vignette: 0.90, composite: 0.15, maskType: 0, maskPitch: 3.0, mono: 1, monoTint: "#ffb000" },
    })
    readonly property var pal: schemes[scheme] || schemes.ado
    readonly property var tb: tubes[tube] || tubes.trinitron
    readonly property real shaderT: E.wrap(t, L.LOOP)

    FontLoader { id: vt323; source: "../../shell/fonts/VT323-Regular.ttf" }
    FontLoader { id: pixel; source: "../../shell/fonts/PressStart2P-Regular.ttf" }

    LoopFeed { id: feed; t: stage.t }

    // lo que el motivo lee del root, con los nombres de Motif.qml
    readonly property var contract: ["clock", "level", "low", "high", "pitch", "energy", "drop",
        "section", "tick", "beat", "kick", "beatMs", "bpmLive", "surge", "nextWord", "lineNo",
        "lines", "linesSynced", "waveL", "waveR"]

    Item {
        id: face
        anchors.fill: parent
        Rectangle { id: bgRect; anchors.fill: parent; color: stage.pal.bg }

        // el latido de Motif.qml con `pace = normal`: 0.80 + 0.15 de opacidad
        // con el golpe, y un tirón de tamaño del 2 %
        Item {
            id: motifBox
            anchors.fill: parent
            clip: true
            opacity: 0.80 + 0.15 * feed.surge
            transform: Scale {
                origin.x: motifBox.width / 2; origin.y: motifBox.height / 2
                xScale: 1 + 0.02 * feed.surge; yScale: xScale
            }
            Loader {
                id: loader
                anchors.fill: parent
                source: "motifs/" + stage.kind.charAt(0).toUpperCase() + stage.kind.slice(1) + ".qml"
                onLoaded: {
                    const it = item;
                    for (const k of stage.contract)
                        if (k in it)
                            it[k] = Qt.binding(() => feed[k]);
                    it.colour = Qt.binding(() => stage.pal.ink);
                    it.hot = Qt.binding(() => stage.pal.hot);
                    if ("bg" in it) it.bg = Qt.binding(() => stage.pal.bg);
                    if ("seed" in it) it.seed = 0.37;
                    if ("fontFamily" in it) it.fontFamily = vt323.name;
                    if ("pixelFamily" in it) it.pixelFamily = pixel.name;
                }
            }
        }
    }

    ShaderEffectSource {
        id: stageTex
        sourceItem: face
        hideSource: stage.glassOn
        visible: false
        smooth: true
        live: true
    }

    ShaderEffect {
        id: signalPass
        anchors.fill: parent
        visible: false
        blending: false
        property variant src: stageTex
        property variant prev: stageTex
        property variant burn: stageTex
        property real burnL: 0
        property variant tint: stage.tb.mono > 0.5 ? stage.color3(stage.tb.monoTint) : stage.color3(stage.pal.ink)
        property real persist: 0
        property real dt: 1 / 60
        property real light: 0
        property color bg: stage.pal.bg
        property real t: stage.shaderT
        property real composite: stage.tb.composite
        property variant res: Qt.vector2d(stage.width, stage.height)
        property real glitch: 0
        property real quality: 1
        fragmentShader: "../../shell/signal.frag.qsb"
    }
    ShaderEffectSource {
        id: signalTex
        sourceItem: signalPass
        visible: false
        smooth: false
        live: true
    }
    ShaderEffect {
        id: glass
        anchors.fill: parent
        visible: stage.glassOn
        blending: false
        property variant src: signalTex
        property real t: stage.shaderT
        property real curvature: stage.tb.curvature
        property real scanline: stage.tb.scanlines
        property real chroma: stage.tb.chroma
        // pantalla sin letra: Crt.qml apaga el bloom
        property real bloom: 0
        property real noiseAmt: stage.tb.noise * 1.6
        property real glitch: 0
        property real roll: stage.tb.roll
        // una vuelta cada 4 tiempos (crt.beat_lock): 8 vueltas en el loop
        property real rollPhase: E.wrap(stage.t / (4 * L.BEAT), 1)
        property real alarm: 0
        property real vignette: stage.tb.vignette
        // pantalla sin foco: × 0.6, flicker default 0.25² de la perilla
        property real pulse: feed.beatPulse * (0.55 + 0.45 * feed.energy) * 0.6 * 0.0625
        property real blink: 0
        property real interlacePhase: 0
        property real tubeLevel: 1
        property real maskType: stage.tb.maskType
        property real maskPitch: stage.tb.maskPitch
        property real mono: stage.tb.mono
        property variant monoTint: stage.color3(stage.tb.monoTint)
        property variant tint: stage.tb.mono > 0.5 ? stage.color3(stage.tb.monoTint) : stage.color3(stage.pal.ink)
        property real degauss: 0
        property variant res: Qt.vector2d(stage.width, stage.height)
        fragmentShader: "../../shell/crt.frag.qsb"
    }

    function color3(c) {
        const q = Qt.color(c);
        return Qt.vector3d(q.r, q.g, q.b);
    }
}
