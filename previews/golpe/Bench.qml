// fatal-lyrics — banco del golpe del bajo y de los agudos (Ferox 2026-10-19), fuera de pantalla.
//
// Un `Motif` REAL de `shell/` (radar), sin vidrio ni letra. `render.py` le sube `bass` (el
// contador de bombos) con la amplitud y la caída que le toca a un tema lento y a uno agitado
// (`bassAmt`/`bassMs`, los números de `crtPaceTable` por carácter), y le sube `hat` para
// disparar los destellos de los agudos.
import QtQuick
import "../../shell"

Item {
    width: 1280
    height: 720

    property alias bass: m.bass
    property alias bassAmt: m.bassAmt
    property alias bassMs: m.bassMs
    property alias hat: m.hat
    readonly property real bump: m.bump
    readonly property real scaleNow: 1 + m.scaleAmt * m.surge + m.bassAmt * m.bump

    Rectangle { anchors.fill: parent; color: "#04162e" }
    Motif {
        id: m
        anchors.fill: parent
        kind: "radar"
        colour: "#4fe8ff"
        hot: "#ffffff"
        bg: "#04162e"
        spinning: true
        level: 0.5
    }
}
