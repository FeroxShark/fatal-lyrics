// fatal-lyrics — banco de los motivos de Motif.qml (radar, lluvia, ekg, textsea, vector,
// harmonograph...), fuera de pantalla. Un `Motif` REAL de `shell/` con la cara del tubo
// detrás y SIN vidrio; `render.py` le sube el reloj, el tempo y el volumen en tiempo real.
import QtQuick
import "../../shell"

Item {
    id: root
    width: 1280
    height: 720

    property alias kind: m.kind
    property alias clock: m.clock
    property alias level: m.level
    property alias tick: m.tick
    property alias beat: m.beat
    property alias kick: m.kick
    property alias bpmLive: m.bpmLive
    property alias beatMs: m.beatMs
    property alias drop: m.drop
    property alias lines: m.lines
    property alias lineNo: m.lineNo
    property alias linesSynced: m.linesSynced
    property alias seed: m.seed
    property alias rate: m.rate

    Rectangle { anchors.fill: parent; color: "#04162e" }
    Motif {
        id: m
        anchors.fill: parent
        colour: "#4fe8ff"
        hot: "#ffffff"
        bg: "#04162e"
        spinning: true
        level: 0.5
    }
}
