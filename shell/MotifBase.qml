// fatal-lyrics motivos CRT — lo que todo motivo nuevo recibe de Motif.qml.
//
// Los nombres son los de Motif.qml (y los que Crt.qml le pasa): al integrar,
// el `Component` del Loader de Motif le asigna cada uno igual que a Tunnel o
// Static. Acá además viven los tres relojes que usan todos:
//   · `lt` — el reloj del motivo, `(clock + movOff) mod 15`: todo lo que deriva es
//     periódico en 15 s. La velocidad NUNCA sale del audio (la trampa del
//     hiperespacio y del túnel: `clock × velocidad` teletransporta con cada
//     cambio de volumen); el audio mueve amplitudes, brillos y cuentas.
//   · `bp` — cuánto va del tiempo actual (0..1), desde el último `tick`.
//   · `dropAmt` — 0..1 con el snap de entrada (OutExpo 320 ms) y la salida
//     rápida (InQuad 140 ms) de Motion.qml.
//   · PARED (`wall`, `docs/PARED.md`): con `wall` puesto el motivo dibuja UN lienzo que cruza
//     todas las pantallas y ésta muestra su recorte. Reloj, `movOff`, tiempos (`beatN`) y la
//     física de ThumpBase salen de un objeto que comparten todas las instancias de la pared.
import QtQuick
import "Ease.js" as E
import "Speed.js" as Speed
import "Wall.js" as Wall

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
    onTubeClockChanged: if (!wallClocked && Math.abs(clock - tubeClock) > 0.25) clock = tubeClock
    // Tanda 8, slice movimiento: el ritmo de la música (`rate`, 1 = el de siempre) NO
    // escala `clock` — es el reloj real, y el re-anclaje de arriba lo compara contra el
    // del tubo: escalado, se despegaría y saltaría un cuarto de segundo cada rato. Lo que
    // se escala es un DESPLAZAMIENTO aparte, `movOff`, acumulado de a `dt` (`Speed.js`),
    // que sólo mueve `lt` (lo que deriva). El compás (`bp`, `sinceTick`), los golpes
    // (`sinceKick`) y la entrada del drop (`dropAmt`) siguen en `clock`: son tiempo real.
    // En el banco (`tubeClock` -1) `movOff` se asigna de afuera, igual que `clock`.
    property real rate: 1
    property real movOff: 0
    FrameTick {
        running: base.running && base.tubeClock >= 0 && base.visible
        onTriggered: {
            base.clockAcc += frameTime;
            if (base.clockAcc >= base.stepMin - 0.001) {
                if (base.wallClocked) {
                    base.wallStep();
                } else {
                    base.movOff = Speed.advance(base.movOff, base.clockAcc, base.rate);
                    base.clock += base.clockAcc;
                }
                base.clockAcc = 0;
            }
        }
    }

    // ---- PARED (`Wall.js`, `docs/PARED.md`). `wall` lo arma Crt.qml (null = la pantalla
    // sola, como siempre), todo en px: la esquina de esta pantalla en el lienzo (`x`, `y`), el
    // lienzo (`cw`, `ch`), `span`, el pivote de pared (`px`, `py`, px de lienzo), el origen de
    // la cámara de este tubo (`ox`, `oy`, px de la pantalla), `epoch` (ms) y `share`.
    // `wallCam` = (tirón propio del dibujo, factor de la cámara del tubo, foco x, foco y): el
    // foco es la pantalla con la letra (o el centro), en px de lienzo.
    //
    // `share` es UN objeto JS para todas las instancias de la pared (lo cambia el root cuando
    // se forma una pared nueva). Se muta sin avisar: la primera instancia que corre en un
    // cuadro avanza lo acumulado (`movOff`, el contador de tiempos, la física de ThumpBase) y
    // las demás lo leen. Integrando cada una lo suyo, una pantalla que entra tarde (la que
    // tenía la letra) arrancaría de cero y el dibujo se partiría en la costura.
    property var wall: null
    property vector4d wallCam: Qt.vector4d(1, 1, 0, 0)
    // cómo reparte la pared cuando una pantalla tiene la letra (`Wall.fit`, `docs/PARED.md`):
    // "behind" (el mundo sigue por detrás) o "mirror" (alas espejadas). Cada motivo de pared
    // declara el suyo. `wallEcho` (0..1): un eco tenue y desenfocado detrás de la letra; 0 = sin eco.
    property string wallFit: "behind"
    property real wallEcho: 0
    readonly property bool walled: !!wall
    readonly property bool wallShared: walled && !!wall.share
    // en el banco (`tubeClock` -1) el reloj llega de afuera, el mismo para todas las rebanadas
    readonly property bool wallClocked: walled && tubeClock >= 0
    function wallNow() {
        return wallClocked ? (Date.now() - wall.epoch) / 1000 : clock;
    }
    function wallStep() {
        const t = wallNow(), S = wall.share;
        if (S.movAt === undefined) {
            S.movAt = t;
            S.mov = 0;
        }
        if (t > S.movAt) {
            S.mov = Speed.advance(S.mov, t - S.movAt, rate);
            S.movAt = t;
        }
        movOff = S.mov;
        clock = t;
    }
    // el contador de tiempos de la pared: el `tick` del root, y si no llega, el de 1,5 tiempos
    // de abajo — uno solo para todas
    property int wallN: 0
    function wallBeat() {
        const S = wall.share;
        if (S.beatN === undefined) {
            S.beatN = 0;
            S.tick = tick;
            S.tickAt = clock;
            S.own = false;
        }
        if (S.tick !== tick) {
            S.tick = tick;
            S.beatN++;
            S.tickAt = clock;
            S.own = false;
        } else if (clock - S.tickAt >= beatS * (S.own ? 1 : 1.5)) {
            S.own = true;
            S.tickAt = clock;
            S.beatN++;
        }
        wallN = S.beatN;
        tickAt = S.tickAt;
    }
    Component.onCompleted: if (wallClocked) wallStep()
    // el recorte de ESTA pantalla en px de lienzo; sin pared, la pantalla entera
    readonly property var wallWin: walled
        ? Wall.view({ x: wall.x, y: wall.y }, { w: width, h: height }, { x: wall.px, y: wall.py },
                    { x: wall.ox, y: wall.oy }, wallCam.y, wallCam.x)
        : ({ x: 0, y: 0, w: width, h: height })
    readonly property vector2d wallArea: walled ? Qt.vector2d(wall.cw, wall.ch) : Qt.vector2d(width, height)
    // para los shaders en px de lienzo: p = wallPx.xy + qt_TexCoord0 · wallPx.zw
    readonly property vector4d wallPx: Qt.vector4d(wallWin.x, wallWin.y, wallWin.w, wallWin.h)
    // en unidades de `span` desde el centro del lienzo: uv = wallView.xy + qt_TexCoord0 · wallView.zw
    // (sin pared es el `(qt_TexCoord0 - 0.5) · res / min(res)` de siempre)
    readonly property vector4d wallView: Qt.vector4d((wallWin.x - wallArea.x / 2) / span,
        (wallWin.y - wallArea.y / 2) / span, wallWin.w / span, wallWin.h / span)
    readonly property vector2d wallFocus: walled ? Qt.vector2d(wallCam.z, wallCam.w)
                                                 : Qt.vector2d(width / 2, height / 2)
    property real level: 0.35
    property real low: 0.4
    property real high: 0.3
    property real pitch: 0.5
    property real energy: 1
    property real surge: 0
    property real seed: 0
    property real quality: 1
    property bool drop: false
    // corte seco (`cut` del daemon: la música cae de golpe y vuelve) y flujo de agudos (`hf`,
    // 0..1): los leen el laberinto (planta la marcha y mira al costado) y mystify (se agarra
    // y estira la estela; el color y el resplandor siguen los agudos)
    property bool cut: false
    property real hf: 0
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
    property real stepMin: 0
    property real paintMin: 0         // techo propio (0 = el de stepMin)
    property real paintedAt: -1e6
    signal frame()
    onClockChanged: {
        if (wallShared) {
            wallBeat();
        } else if (tickAt < -1e5) {
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
    readonly property real span: walled ? wall.span : Math.min(width, height)
    readonly property bool portrait: walled ? wall.ch > wall.cw : height > width
    readonly property real lt: E.wrap(clock + movOff, loopS)
    readonly property real beatS: Math.max(beatMs, 1) / 1000

    // `beatN`: el contador de tiempos que usan los motivos, en vez de `tick`.
    // `tick` (beatTick) sólo avanza con compás confiable (`bpmLive`); sin él
    // todo lo que da pasos por tiempo se quedaba clavado (el harmonógrafo con
    // la pluma quieta, Ferox 2026-09-27). Si no llega un `tick` en 1,5 tiempos,
    // el motivo cuenta solo cada `beatMs` hasta que vuelva el de verdad — lo
    // mismo que hace el túnel con su luz.
    property int ownN: 0
    readonly property int beatN: wallShared ? wallN : tick + ownN
    property real tickAt: -1e6
    property bool ownBeat: false
    onTickChanged: {
        if (wallShared) {
            wallBeat();
            return;
        }
        ownBeat = false;
        tickAt = clock;
    }
    readonly property real sinceTick: Math.max(0, clock - tickAt)
    readonly property real bp: E.clamp01(sinceTick / beatS)

    property real kickAt: -1e6
    onKickChanged: kickAt = wallNow()
    readonly property real sinceKick: Math.max(0, clock - kickAt)

    property real dropAt: -1e6
    onDropChanged: dropAt = wallNow()
    readonly property real dropAmt: drop ? E.outExpo(E.prog(clock, dropAt, 0.32))
                                         : 1 - E.inQuad(E.prog(clock, dropAt, 0.14))
}
