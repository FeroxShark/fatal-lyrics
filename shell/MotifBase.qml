// fatal-lyrics motivos CRT — lo que todo motivo nuevo recibe de Motif.qml.
//
// Los nombres son los de Motif.qml (y los que Crt.qml le pasa): al integrar,
// el `Component` del Loader de Motif le asigna cada uno igual que a Tunnel o
// Static. Acá además viven los tres relojes que usan todos:
//   · `lt` — el reloj del motivo, `clock mod 15`: todo lo que deriva es
//     periódico en 15 s. La velocidad NUNCA sale del audio (la trampa del
//     hiperespacio y del túnel: `clock × velocidad` teletransporta con cada
//     cambio de volumen); el audio mueve amplitudes, brillos y cuentas.
//   · `bp` — cuánto va del tiempo actual (0..1), desde el último `tick`.
//   · `dropAmt` — 0..1 con el snap de entrada (OutExpo 320 ms) y la salida
//     rápida (InQuad 140 ms) de Motion.qml.
import QtQuick
import "Ease.js" as E

Item {
    id: base

    property color colour: "#7fe4ff"
    property color hot: "#ffffff"
    property color bg: "#04162e"
    // El reloj del tubo llega a 20 Hz en las pantallas sin letra (el Timer de
    // Crt.qml), y un Canvas que repinta con él va a saltos (Ferox 2026-09-27:
    // "le falta fps"). Así que el motivo lleva su PROPIO reloj, `clock`, que
    // avanza cuadro a cuadro con un FrameAnimation (techo `stepMin`) y se
    // re-ancla a `tubeClock` si se despega más de un cuarto de segundo (pausa,
    // pantalla dormida). Con `tubeClock` en -1 (el banco de previews) `clock`
    // se asigna de afuera, como siempre.
    property real tubeClock: -1
    property real clock: 0
    property real clockAcc: 0
    onTubeClockChanged: if (Math.abs(clock - tubeClock) > 0.25) clock = tubeClock
    FrameAnimation {
        running: base.running && base.tubeClock >= 0 && base.visible
        onTriggered: {
            base.clockAcc += frameTime;
            if (base.clockAcc >= base.stepMin - 0.001) {
                base.clock += base.clockAcc;
                base.clockAcc = 0;
            }
        }
    }
    property real level: 0.35
    property real low: 0.4
    property real high: 0.3
    property real pitch: 0.5
    property real energy: 1
    property real surge: 0
    property real seed: 0
    property real quality: 1
    property bool drop: false
    property string section: "verse"
    property int tick: 0
    property int beat: 0
    property int kick: 0
    property real beatMs: 500
    property bool bpmLive: false
    property bool running: true
    property string nextWord: ""
    property int lineNo: -1
    property var lines: []
    property bool linesSynced: true
    property var waveL: []
    property var waveR: []
    property string fontFamily: "monospace"
    property string pixelFamily: "monospace"
    // T4.3: el techo de cuadros que reparte Motif.qml (60 Hz, 30 en el piso de
    // volumen). `paintMin` es el techo propio del motivo: los motivos
    // pesados pueden pedir menos. Los motivos repintan en `onFrame`, no en cada
    // `clockChanged`.
    property real stepMin: 1 / 60
    property real paintMin: 0         // techo propio (0 = el de stepMin)
    property real paintedAt: -1e6
    signal frame()
    onClockChanged: {
        if (tickAt < -1e5) {
            tickAt = clock;       // el primer cuadro sólo arma el reloj
        } else if (clock - tickAt >= beatS * (ownBeat ? 1 : 1.5)) {
            ownBeat = true;
            tickAt = clock;
            ownN++;
        }
        if (!running)
            return;
        // 2 ms de tolerancia: el reloj del tubo avanza 1 ms menos que un cuadro
        if (clock >= paintedAt && clock - paintedAt < Math.max(stepMin, paintMin) - 0.002)
            return;
        paintedAt = clock;
        frame();
    }

    readonly property real loopS: 15
    readonly property real span: Math.min(width, height)
    readonly property bool portrait: height > width
    readonly property real lt: E.wrap(clock, loopS)
    readonly property real beatS: Math.max(beatMs, 1) / 1000

    // `beatN`: el contador de tiempos que usan los motivos, en vez de `tick`.
    // `tick` (beatTick) sólo avanza con compás confiable (`bpmLive`); sin él
    // todo lo que da pasos por tiempo se quedaba clavado (el harmonógrafo con
    // la pluma quieta, Ferox 2026-09-27). Si no llega un `tick` en 1,5 tiempos,
    // el motivo cuenta solo cada `beatMs` hasta que vuelva el de verdad — lo
    // mismo que hace el túnel con su luz.
    property int ownN: 0
    readonly property int beatN: tick + ownN
    property real tickAt: -1e6
    property bool ownBeat: false
    onTickChanged: {
        ownBeat = false;
        tickAt = clock;
    }
    readonly property real sinceTick: Math.max(0, clock - tickAt)
    readonly property real bp: E.clamp01(sinceTick / beatS)

    property real kickAt: -1e6
    onKickChanged: kickAt = clock
    readonly property real sinceKick: Math.max(0, clock - kickAt)

    property real dropAt: -1e6
    onDropChanged: dropAt = clock
    readonly property real dropAmt: drop ? E.outExpo(E.prog(clock, dropAt, 0.32))
                                         : 1 - E.inQuad(E.prog(clock, dropAt, 0.14))
}
