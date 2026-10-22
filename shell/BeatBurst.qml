import QtQuick

// El reloj de los glitches espontáneos de UN cartel del modo normal (sin tubo).
//
// Con compás medido (`locked`) cada intento cae sobre un tiempo de LA grilla (`msToNext`, que es
// `msToNextBeat` de shell.qml: la misma cuenta que usa el CRT en `hit()`), con un intento por
// tiempo (uno cada dos si el tema es muy rápido). Sin compás, o si se pierde a mitad de la
// espera, cae al azar de siempre. NO tiene período propio: ningún Timer cuenta tiempos por su
// cuenta (CLAUDE.md, "una sola grilla"). El Timer de QML es grueso (±5 %): se acerca con
// pasos que no se pasan (`stepAim`, `beatStepAim` de shell.qml) y sólo el último llega a la marca.
Item {
    id: bb
    // entradas
    property bool active: false
    property bool locked: false           // crtBeatLock && bpmLive
    property real beatMs: 0
    property var msToNext: null           // function(now) -> ms hasta el próximo tiempo
    property var stepAim: null            // function(left) -> intervalo del próximo paso
    property real glitchiness: 0          // 0..1: edad del cartel
    property real gProb: 1                // multiplicador del nivel de glitch
    // salida: cuánto antes/después de la marca cayó el último (para medir)
    property real lateMs: 0
    signal burst()

    property double dueAt: 0              // marca de la grilla a la que se apunta (0 = al azar)
    property double firedAt: 0

    readonly property real tryProb: (0.55 + 0.4 * glitchiness) * gProb

    function plan() {
        tm.stop();
        dueAt = 0;
        if (!active || gProb <= 0)
            return;
        const now = Date.now();
        if (locked && beatMs > 0 && msToNext && stepAim) {
            const per = beatMs < 300 ? 2 : 1;
            const t0 = Math.max(now + 10, firedAt + beatMs * (per - 0.5));
            dueAt = t0 + msToNext(t0);
            tm.interval = stepAim(dueAt - now);
        } else {
            tm.interval = 160 + Math.random() * (550 - 380 * glitchiness);
        }
        tm.restart();
    }
    onActiveChanged: plan()
    onLockedChanged: plan()
    onGProbChanged: plan()
    Component.onCompleted: plan()

    Timer {
        id: tm
        repeat: false
        onTriggered: {
            if (bb.dueAt > 0) {
                if (!bb.locked) {
                    bb.plan();
                    return;
                }
                const now = Date.now();
                if (now < bb.dueAt - 1) {
                    tm.interval = bb.stepAim(bb.dueAt - now);
                    tm.restart();
                    return;
                }
                bb.firedAt = now;
                bb.lateMs = now - bb.dueAt;
            }
            if (Math.random() < bb.tryProb)
                bb.burst();
            bb.plan();
        }
    }
}
