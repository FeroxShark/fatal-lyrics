// fatal-lyrics — banco de CALIDAD del tubo (CRT, 2026-10-22), fuera de pantalla.
//
// La cadena REAL de `Crt.qml` sin el resto: `stage` (letra + fondo) -> ShaderEffectSource
// (`stageTex`, a `texQ x ss`) -> `signal.frag` -> ShaderEffectSource (`signalTex`) -> `crt.frag`.
// Los mismos .qsb y los mismos nombres de propiedad; `dir` apunta a la carpeta de los .qsb
// (el antes es una copia). Lo que se mira: bordes del texto (¿escalones?, ¿borroso?),
// scanlines y máscara (¿finas y nítidas?), bloom, banding del fondo oscuro, dithering.
//
// Si cambia una propiedad de `glass` o `signalPass` en `Crt.qml`, cambiarla acá también.
import QtQuick

Item {
    id: bench
    property string dir: "../../shell"
    property int sw: 1920
    property int sh: 1080
    width: sw
    height: sh

    property real ss: 1.0               // `crt.supersample`
    property real texQ: 1.0             // `crtQuality`
    property string tube: "trinitron"
    property real composite: 0.0
    property real bloomK: 1.0
    property real t: 12.345

    readonly property var tubes: ({
        custom: { curvature: 0.6, scanlines: 0.5, chroma: 0.5, vignette: 0.6, bloom: 1.0,
                  composite: 0.0, maskType: 0, maskPitch: 3.0, mono: 0, monoTint: "#ffffff" },
        trinitron: { curvature: 0.35, scanlines: 0.40, chroma: 0.30, vignette: 0.55, bloom: 1.10,
                     composite: 0.35, maskType: 0, maskPitch: 2.4, mono: 0, monoTint: "#ffffff" },
        pvm: { curvature: 0.50, scanlines: 0.65, chroma: 0.15, vignette: 0.50, bloom: 1.0,
               composite: 0.0, maskType: 2, maskPitch: 3.0, mono: 0, monoTint: "#ffffff" },
        arcade: { curvature: 1.20, scanlines: 0.75, chroma: 0.80, vignette: 1.0, bloom: 1.3,
                  composite: 0.5, maskType: 1, maskPitch: 4.0, mono: 0, monoTint: "#ffffff" },
        green: { curvature: 0.90, scanlines: 0.55, chroma: 0.0, vignette: 0.90, bloom: 1.2,
                 composite: 0.0, maskType: 0, maskPitch: 3.0, mono: 1, monoTint: "#33ff66" },
    })
    readonly property var tb: tubes[tube] || tubes.custom

    FontLoader { id: fnt; source: "../../shell/fonts/SpaceMono-Bold.ttf" }

    // ---- la letra plana (`stage`)
    Item {
        id: stage
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0a1a30" }
                GradientStop { position: 1.0; color: "#050b16" }
            }
        }
        // fondo oscuro suave: el caso del banding (8 bits en una rampa casi plana)
        Rectangle {
            x: 0; y: 0; width: parent.width; height: parent.height * 0.10
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#050b16" }
                GradientStop { position: 1.0; color: "#0b1d36" }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.22
            text: "JUST AS YOU"
            font.family: fnt.name; font.bold: true
            font.pixelSize: bench.sh * 0.20
            font.letterSpacing: 3
            color: "#9fe8ff"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.46
            text: "TAKE MY HAND"
            font.family: fnt.name; font.bold: true
            font.pixelSize: bench.sh * 0.20
            font.letterSpacing: 3
            color: "#ffffff"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.76
            text: "write my number down tonight 0123456789"
            font.family: fnt.name; font.bold: true
            font.pixelSize: bench.sh * 0.034
            color: "#9fe8ff"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.82
            text: "Small body copy the eye must still read: lorem ipsum 123"
            font.family: fnt.name
            font.pixelSize: bench.sh * 0.020
            color: "#cfeeff"
        }
        // líneas finas y diagonales: el peor caso de escalón
        Rectangle { x: parent.width * 0.08; y: parent.height * 0.90; width: parent.width * 0.84; height: 2; color: "#ffb457" }
        Rectangle { x: parent.width * 0.08; y: parent.height * 0.92; width: parent.width * 0.84; height: 1; color: "#ffb457" }
        Rectangle {
            x: parent.width * 0.05; y: parent.height * 0.08
            width: 3; height: parent.height * 0.14; color: "#ff5577"
            rotation: 18; antialiasing: true
        }
        Rectangle {
            x: parent.width * 0.93; y: parent.height * 0.08
            width: 2; height: parent.height * 0.14; color: "#77ff99"
            rotation: -23; antialiasing: true
        }
    }

    ShaderEffectSource {
        id: stageTex
        sourceItem: stage
        hideSource: true
        visible: false
        smooth: bench.ss > 1.001 || bench.smoothTex
        live: true
        textureSize: Qt.size(Math.round(bench.sw * bench.texQ * bench.ss),
                             Math.round(bench.sh * bench.texQ * bench.ss))
    }
    property bool smoothTex: false

    ShaderEffect {
        id: signalPass
        anchors.fill: parent
        visible: false
        blending: false
        property variant src: stageTex
        property variant prev: stageTex
        property variant burn: stageTex
        property real burnL: 0
        property variant tint: Qt.vector3d(0.62, 0.91, 1.0)
        property real persist: 0
        property real dt: 0.016
        property real light: 0
        property color bg: "#06121f"
        property real t: bench.t
        property real composite: bench.tb.composite * bench.composite
        property variant res: Qt.vector2d(bench.sw, bench.sh)
        property real glitch: 0
        property real quality: bench.texQ
        fragmentShader: bench.dir + "/signal.frag.qsb"
    }

    ShaderEffectSource {
        id: signalTex
        sourceItem: signalPass
        visible: false
        smooth: bench.smoothTex
        live: true
        textureSize: stageTex.textureSize
    }

    ShaderEffect {
        id: glass
        anchors.fill: parent
        blending: false
        property variant src: signalTex
        property real t: bench.t
        property real curvature: bench.tb.curvature
        property real scanline: bench.tb.scanlines
        property real chroma: bench.tb.chroma
        property real bloom: bench.tb.bloom * bench.bloomK
        property real noiseAmt: 0.12
        property real tubeLevel: 1
        property real degauss: 0
        property real cutDim: 0
        property real backFlash: 0
        property real fizz: 0
        property real grain: 0
        property real grainPhase: 0
        property real glitch: 0
        property real roll: 0.15
        property real rollPhase: 0.4
        property real alarm: 0
        property real vignette: bench.tb.vignette
        property real pulse: 0
        property real blink: 0
        property real interlacePhase: 0
        property variant res: Qt.vector2d(bench.sw, bench.sh)
        property variant texRes: Qt.vector2d(stageTex.textureSize.width, stageTex.textureSize.height)
        property real maskType: bench.tb.maskType
        property real maskPitch: bench.tb.maskPitch
        property real mono: bench.tb.mono
        property variant monoTint: bench.c3(bench.tb.monoTint)
        property variant tint: bench.tb.mono > 0.5 ? bench.c3(bench.tb.monoTint) : Qt.vector3d(0.62, 0.91, 1.0)
        fragmentShader: bench.dir + "/crt.frag.qsb"
    }

    function c3(c) {
        const q = Qt.color(c);
        return Qt.vector3d(q.r, q.g, q.b);
    }
}
