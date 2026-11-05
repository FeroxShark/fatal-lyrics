// fatal-lyrics — el reloj de cuadros del tubo. Reemplaza a `FrameAnimation` en todo lo que dibuja:
// misma cara (`running`, `frameTime`, `onTriggered`), pero con los dos modos de `crt.frames`.
//
// Por qué no alcanza con FrameAnimation (medido 2026-11-05, TRAMPAS "Reloj de cuadros"): el proceso
// tiene UN solo reloj de animaciones, al refresco de la pantalla primaria (144 Hz), para las tres
// ventanas. Ni la de 200 Hz puede ir más rápido ni la de 60 queda alineada.
//
//   sync (default): todas las pantallas avanzan en la misma grilla absoluta, a los Hz de la más
//     lenta. Sale de `Date.now()` y no de un acumulador: cada instancia, en cualquier ventana, cae
//     en el mismo escalón, y un acumulador con techo se traba en múltiplos del latido (3 × 6,9 ms
//     = 48 fps, que es lo que pasaba). Es además el modo barato: nadie le pide cuadros de más a
//     la ventana.
//   max: cada ventana avanza con SUS cuadros reales (`frameSwapped`) y pide el siguiente.
import QtQuick

Item {
    id: tick
    property bool running: false
    property real frameTime: 1 / 60
    signal triggered()

    readonly property var win: tick.Window.window
    property double lastAt: 0
    property double lastStep: -1
    onRunningChanged: { lastAt = 0; lastStep = -1; }

    function fire(now) {
        tick.frameTime = lastAt > 0 ? Math.min((now - lastAt) / 1000, 0.25) : 1 / Motion.syncHz;
        lastAt = now;
        tick.triggered();
    }

    FrameAnimation {
        running: tick.running && !Motion.framesMax
        onTriggered: {
            const now = Date.now();
            const step = Math.floor(now * Motion.syncHz / 1000);
            if (step !== tick.lastStep) {
                tick.lastStep = step;
                tick.fire(now);
            }
        }
    }
    Connections {
        target: tick.win
        enabled: tick.running && Motion.framesMax
        function onFrameSwapped() {
            tick.fire(Date.now());
            tick.win.requestUpdate();
        }
    }
    // una ventana sin nada sucio no intercambia y este reloj no arrancaría nunca
    Timer {
        interval: 100
        repeat: true
        running: tick.running && Motion.framesMax && tick.win !== null
        onTriggered: if (Date.now() - tick.lastAt > 90) tick.win.requestUpdate()
    }
}
