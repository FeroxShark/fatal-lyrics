// fatal-lyrics — banco de los shaders del vidrio y del túnel, fuera de pantalla.
//
// Una pantalla sola, sin reloj que corra: `crt.frag` sobre un campo parejo (donde
// el moiré se ve de una, porque no hay nada que lo tape) o sobre el túnel quieto,
// y `tunnel.frag` pelado. `dir` apunta a la carpeta de los `.qsb`, así se rinde el
// antes (una copia) y el después (`shell/`) con el mismo banco.
//
// Sin ruido, sin barra, sin latido: lo que queda en la imagen es la máscara y las
// scanlines y nada más, que es lo que se mide.
import QtQuick

Item {
    id: stage
    width: 1920
    height: 1080

    property string dir: "../../shell"
    property string source: "flat"      // flat | tunnel
    property bool glassOn: true
    property color field: "#d8b890"
    // el peine en su contraste máximo: |sin(1.6·t)| = 1 (con el período de 2 px
    // el `+ t·1.6` no lo hace caminar, le hace latir el contraste)
    property real t: 3001.202732
    property real travel: 431.7
    property real roll: 0.0
    property real seed: 0.37
    property real bend: 0.45
    // < 0: la del tubo; >= 0: la pisa (la prueba de "plano, igual que antes")
    property real curvOverride: -1

    // copia de `crtTubeTable` (shell.qml); `custom` con las perillas default
    readonly property var tubes: ({
        custom: { curvature: 0.6, scanlines: 0.5, chroma: 0.5, vignette: 0.6,
                  maskType: 0, maskPitch: 3.0, mono: 0, monoTint: "#ffffff" },
        trinitron: { curvature: 0.35, scanlines: 0.40, chroma: 0.30, vignette: 0.55,
                     maskType: 0, maskPitch: 2.4, mono: 0, monoTint: "#ffffff" },
        pvm: { curvature: 0.50, scanlines: 0.65, chroma: 0.15, vignette: 0.50,
               maskType: 2, maskPitch: 3.0, mono: 0, monoTint: "#ffffff" },
        arcade: { curvature: 1.20, scanlines: 0.75, chroma: 0.80, vignette: 1.0,
                  maskType: 1, maskPitch: 4.0, mono: 0, monoTint: "#ffffff" },
        green: { curvature: 0.90, scanlines: 0.55, chroma: 0.0, vignette: 0.90,
                 maskType: 0, maskPitch: 3.0, mono: 1, monoTint: "#33ff66" },
        amber: { curvature: 0.90, scanlines: 0.55, chroma: 0.0, vignette: 0.90,
                 maskType: 0, maskPitch: 3.0, mono: 1, monoTint: "#ffb000" },
    })
    property string tube: "custom"
    readonly property var tb: tubes[tube] || tubes.custom

    Item {
        id: face
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: stage.source === "flat" ? stage.field : "#0b0704" }
        ShaderEffect {
            anchors.fill: parent
            visible: stage.source === "tunnel"
            blending: true
            property real t: stage.travel
            property real ct: 12.3
            property real twist: 0.08
            property real roll: stage.roll
            property real seed: stage.seed
            property real level: 0.55
            property real bend: stage.bend
            property real blur: 0
            property real lightDepth: stage.travel + 4.0
            property real lightAmt: 0.3
            property real dim: 1.0
            property variant res: Qt.vector2d(width, height)
            property variant ink: Qt.vector3d(0.85, 0.62, 0.36)
            property variant hot: Qt.vector3d(1.0, 0.9, 0.76)
            fragmentShader: stage.dir + "/tunnel.frag.qsb"
        }
    }

    ShaderEffectSource {
        id: faceTex
        sourceItem: face
        hideSource: stage.glassOn
        visible: false
        smooth: true
    }

    ShaderEffect {
        anchors.fill: parent
        visible: stage.glassOn
        blending: false
        property variant src: faceTex
        property real t: stage.t
        property real curvature: stage.curvOverride >= 0 ? stage.curvOverride : stage.tb.curvature
        property real scanline: stage.tb.scanlines
        property real chroma: stage.tb.chroma
        property real bloom: 0
        property real noiseAmt: 0
        property real glitch: 0
        property real roll: 0
        property real rollPhase: 0
        property real alarm: 0
        property real vignette: 0
        property real pulse: 0
        property real blink: 0
        property real interlacePhase: 0
        property real tubeLevel: 1
        property real maskType: stage.tb.maskType
        property real maskPitch: stage.tb.maskPitch
        property real mono: stage.tb.mono
        property variant monoTint: stage.color3(stage.tb.monoTint)
        property variant tint: stage.color3(stage.tb.mono > 0.5 ? stage.tb.monoTint : "#ffb457")
        property real degauss: 0
        property variant res: Qt.vector2d(width, height)
        fragmentShader: stage.dir + "/crt.frag.qsb"
    }

    function color3(c) {
        const q = Qt.color(c);
        return Qt.vector3d(q.r, q.g, q.b);
    }
}
