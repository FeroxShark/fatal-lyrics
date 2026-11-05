// El banco no tiene `Motion` ni ventanas de verdad: acá `FrameTick` es un FrameAnimation común.
import QtQuick

Item {
    id: tick
    property bool running: false
    property real frameTime: 1 / 60
    signal triggered()
    FrameAnimation {
        running: tick.running
        onTriggered: { tick.frameTime = frameTime; tick.triggered(); }
    }
}
