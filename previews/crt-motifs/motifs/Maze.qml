// maze — el "Laberinto 3D" de Windows 95: la cámara camina un pasillo en anillo.
//
// La ruta es la de siempre: 8 adelante, doblar, 6 adelante, doblar… 32 acciones
// = la vuelta entera, y cada acción es un snap de Motion (OutExpo, 340 ms) y
// después quieta hasta el próximo tiempo: se camina AL PASO de la canción, no
// deslizando. Lo que cambió (tanda 8) es QUIÉN reparte los pasos:
//   · MARCHA: la posición es un CONTADOR de pasos (`walked`), nunca `t·ritmo`.
//     En cada tiempo la marcha cobra un crédito de `rate` (el `mov` de la música:
//     1 = un paso por tiempo). Con 0.6 hay tiempos en que se queda parada; con
//     1.6 alguno da dos pasos de una. A ritmo 1 exacto `walked == beatN`: la
//     marcha de antes, cuadro por cuadro.
//   · CORTE SECO (`cut`): se planta. Los créditos no se pierden, se acumulan; al
//     volver la música da el paso atrasado (como mucho tres) de un saque. Mientras
//     dura, se queda mirando hacia un costado (±24°, OutExpo).
//   · AGUDOS (`hf`): un golpe de agudos que sube de 0.55 le hace echar un vistazo al
//     costado (±17°) y volver en 0.55 s. Máximo uno cada cuatro pasos, y el lado
//     sale de la semilla: no es un tic.
//   · `drop`: la niebla se abre y la cuadrícula del piso se enciende y late.
//   · `high` en la subida: la niebla respira con los platillos.
// Huevos de pascua (`eggs`, perilla `crt.maze_eggs`): como el salvapantallas
// original, dibujados por código en `maze.frag`. RAROS: 22 % de que una vuelta traiga
// uno, sembrado con `seed` (`Maze.js: plan`). Un cartel al fondo de un tramo (una
// carita, un diálogo de error de Win95, una salida), una rata que cruza, o un
// poliedro que al tocarlo da vuelta el mundo. Y el mundo se da vuelta también en el
// pico del estribillo: al entrar el drop, 40 % de las veces, y vuelve al terminar.
//
// El dibujo vive en `maze.frag` (raycaster por píxel); acá sólo la cámara y el estado.
// Costo en el overlay: un ShaderEffect de pantalla completa, ≤ 40 pasos de DDA
// por píxel. Lo más caro de estos ocho en GPU, lo más barato en CPU.
import QtQuick
import "../Ease.js" as E
import "../Maze.js" as M

MotifBase {
    id: m

    // perilla `crt.maze_eggs`; `egg` fuerza un tipo (smiley|dialog|exit|rat|rock|flip):
    // lo usan el banco y las pruebas, en el overlay queda vacío (sorteo sembrado)
    property bool eggs: true
    property string egg: ""

    // ---- la marcha -------------------------------------------------------
    property int walked: 0            // pasos dados (contador, entero)
    property int lastBeat: 0
    property real acc: 0              // crédito fraccionario (o el atrasado del corte)
    property real sFrom: 0            // desde dónde viene el paso en curso
    property real stepAt: -1e6
    property real glide: 0.34
    property bool started: false
    readonly property real e: E.outExpo(E.prog(clock, stepAt, glide))
    readonly property real s: E.mix(sFrom, walked, e)
    readonly property var pz: M.pose(s)
    // la última acción fue caminar (no doblar): sólo ahí el paso hace rebotar la cámara
    readonly property bool walking: M.LEG_ENDS.indexOf(M.wrap(walked - 1, M.LOOP_STEPS)) < 0

    function takeSteps(n) {
        if (n <= 0) return;
        sFrom = s;
        walked += n;
        stepAt = clock;
        glide = n > 4 ? 0 : 0.34 + 0.1 * Math.min(n - 1, 3);
    }

    onBeatNChanged: {
        if (!started) return;
        const d = beatN - lastBeat;
        lastBeat = beatN;
        if (d < 0) {                  // el reloj volvió atrás (el banco): corrida entera
            walked += d;
            sFrom += d;
            doneAct = -1e9;           // lo ya mostrado se vuelve a mostrar
            return;
        }
        if (cut) {
            acc += d * Math.max(0.25, Math.min(rate, 2.6));
            return;
        }
        const c = M.credit(acc, d, rate);
        acc = c.acc;
        takeSteps(c.steps);
    }
    // arranca donde arrancaba `wrap(beatN, 32)`: hacia el estado siguiente
    Component.onCompleted: {
        walked = beatN + 1;
        lastBeat = beatN;
        sFrom = beatN;
        started = true;
        refreshEgg();
    }

    // ---- la mirada: yaw con OutExpo entre dos estampas de reloj ---------
    property real yawFrom: 0
    property real yawTo: 0
    property real yawAt: -1e6
    property real glanceEnd: -1
    property int glanceSlot: -1
    property bool hfHigh: false
    readonly property real yaw: E.mix(yawFrom, yawTo, E.outExpo(E.prog(clock, yawAt, 0.32)))

    function lookAt(target) {
        yawFrom = yaw;
        yawTo = target;
        yawAt = clock;
    }

    onCutChanged: {
        if (!started) return;
        if (cut) {
            glanceEnd = -1;
            lookAt(M.side(seed, Math.floor(walked / 4)) * 0.42);
        } else {
            lookAt(0);
            const n = Math.floor(acc + 1e-9);
            acc -= n;
            takeSteps(Math.min(n, 3));
        }
    }
    onFrame: {
        if (!cut) {
            if (hf < 0.3) hfHigh = false;
            else if (hf > 0.55 && !hfHigh) {
                hfHigh = true;
                const slot = Math.floor(walked / 4);
                if (slot !== glanceSlot && clock - yawAt > 0.9) {
                    glanceSlot = slot;
                    glanceEnd = clock + 0.55;
                    lookAt(M.side(seed, slot) * 0.30);
                }
            }
            if (glanceEnd > 0 && clock > glanceEnd) {
                glanceEnd = -1;
                lookAt(0);
            }
        }
        if (eggKind === "rat" && clock - eggAt > ratS) endEgg();
    }

    // ---- los huevos ------------------------------------------------------
    readonly property real ratS: 1.1
    property string eggKind: ""
    property var eggPlan: null
    property real eggAt: -1e6
    property int doneAct: -1e9
    property bool rockFlipOn: false
    property int rockFlipUntil: 0
    property bool dropFlipOn: false
    property int dropN: 0
    readonly property bool flipOn: rockFlipOn || dropFlipOn

    function endEgg() {
        if (eggPlan) doneAct = eggPlan.act;
        eggKind = "";
        eggPlan = null;
    }
    function refreshEgg() {
        if (!started) return;
        if (rockFlipOn && walked >= rockFlipUntil) rockFlipOn = false;
        if (!eggs || egg === "flip") {
            if (eggKind !== "") endEgg();
            return;
        }
        if (eggKind === "") {
            const p = M.active(seed, walked, egg);
            if (p && p.act !== doneAct) {
                eggPlan = p;
                eggKind = p.kind;
                eggAt = clock;
            }
        } else if (!M.inWindow(eggPlan, walked)) {
            endEgg();
        } else if (eggKind === "rock" && walked >= eggPlan.act + 3) {
            rockFlipOn = !rockFlipOn;
            rockFlipUntil = walked + 16;
            endEgg();
        }
    }
    onWalkedChanged: refreshEgg()
    onEggsChanged: {
        if (!eggs) dropFlipOn = false;
        refreshEgg();
    }
    onEggChanged: { doneAct = -1e9; refreshEgg(); }

    onDropChanged: {
        if (drop) {
            dropN++;
            dropFlipOn = eggs && (egg === "flip" || (egg === "" && M.hash2(seed + 9.9, dropN) < 0.4));
        } else dropFlipOn = false;
    }

    // el mundo da vuelta: 0..1 (media vuelta) con OutExpo entre dos estampas
    property real rollFrom: 0
    property real rollTo: 0
    property real rollAt: -1e6
    readonly property real rollNow: E.mix(rollFrom, rollTo, E.outExpo(E.prog(clock, rollAt, 0.6)))
    onFlipOnChanged: {
        rollFrom = rollNow;
        rollTo = flipOn ? 1 : 0;
        rollAt = clock;
    }

    ShaderEffect {
        anchors.fill: parent
        property variant res: Qt.vector2d(width, height)
        property variant cam: Qt.vector3d(m.pz[0], m.pz[1],
            m.pz[2] + m.yaw + 0.025 * Math.sin(2 * Math.PI * m.lt / m.loopS * 2))
        property real bob: m.walking ? -0.012 * Math.sin(Math.PI * E.prog(m.clock, m.stepAt, 0.3)) : 0
        property real pulse: E.clamp01(Math.exp(-m.sinceTick / 0.12) * (0.45 + 0.55 * m.dropAmt) + 0.3 * m.surge)
        property real dropAmt: m.dropAmt
        property real fogK: 0.17 + (m.section === "build" ? 0.12 * m.high : 0)
        property real seed: m.seed
        property real lt: m.lt
        property real roll: Math.PI * m.rollNow
        // el huevo: celda, tipo (0 nada, 1 carita, 2 diálogo, 3 salida, 4 rata, 5 poliedro) y edad en s
        property variant egg: Qt.vector4d(m.eggPlan ? m.eggPlan.cell[0] : 0, m.eggPlan ? m.eggPlan.cell[1] : 0,
            m.eggKind === "" ? 0 : M.EGG_KIND[m.eggKind], Math.max(0, m.clock - m.eggAt))
        // hacia dónde mira el cartel (el rumbo de la cámara), cuánto se ve (0..1)
        property variant eggB: Qt.vector4d(m.eggPlan ? m.eggPlan.dir[0] : 0, m.eggPlan ? m.eggPlan.dir[1] : 0,
            E.prog(m.clock, m.eggAt, 0.32), 0)
        property color ink: m.colour
        property color hot: m.hot
        property color bg: m.bg
        fragmentShader: Qt.resolvedUrl("maze.frag.qsb")
    }
}
