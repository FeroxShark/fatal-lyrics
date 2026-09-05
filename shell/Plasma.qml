// fatal-lyrics — el tubo de plasma.
//
// La lámpara de lava: cuatro a seis bolas de campo que se funden entre sí.
// En reposo se ven como UNA burbuja que respira; cuando entra el grave las
// bolas se abren en tres racimos, se estrangulan (cuello visible) y se parten
// en dos, tres o cuatro gotas, que vuelven a fundirse al bajar el nivel.
//
// El reparto de trabajo cambió en la tanda 4b: ANTES las bolas vivían adentro
// del shader como senos del reloj, así que no podían tener inercia y la lámpara
// se veía casi quieta. Ahora la FÍSICA está acá (masa-resorte hacia un objetivo,
// a 60 Hz) y el shader sólo suma el campo de seis bolas que le llegan como
// uniforms. Es lo que permite que un golpe las empuje y que vuelvan solas.
//
// Cada bola tiene un RACIMO (tres, `i % 3`): al abrirse no salen cinco gotas en
// flor sino dos o tres, de tamaños distintos, que es como se parte una burbuja.
//
// Las velocidades se ACUMULAN cuadro a cuadro (el giro de los racimos, la
// órbita de cada bola, la fase de la ondulación del borde): con
// `ángulo = reloj × velocidad` cualquier cambio de tempo multiplica un reloj de
// miles de segundos y todo se teletransporta — misma trampa que el túnel.
import QtQuick

Item {
    id: lamp

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    // T4.3: el techo de cuadros que reparte Motif.qml
    property real stepMin: 1 / 60
    property real level: 0.35
    Behavior on level { NumberAnimation { duration: Motion.levelMs; easing.type: Easing.OutQuad } }
    property real low: 0.4            // los graves: abren la burbuja y la estiran
    Behavior on low { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
    property real surge: 0            // el golpe del tubo: un empujón de más
    property int beat: 0              // el golpe CRUDO: el que parte la burbuja
    property bool drop: false         // en el drop: órbitas al máximo, borde nervioso
    property real energy: 1.0
    property real seed: 0
    property real quality: 1.0
    property real dim: 1.0
    property bool running: true

    // Una bola menos en una pantalla que sufre. El shader las evalúa siempre a
    // las seis (GLSL ES 100 no acepta un tope variable) y las que sobran van
    // con radio cero, que pesa cero.
    readonly property int balls: quality >= 0.9 ? 6 : (quality >= 0.6 ? 5 : 4)

    // Cuánto se abre: 0 = una burbuja sola, 1 = los tres racimos separados.
    // Sale del GRAVE y no del volumen: el volumen en reposo (sin captura) vale
    // lo que valga, el grave en reposo vale 0.4 clavado y ahí `open` es 0.
    readonly property real open: Math.max(0, Math.min(1,
        (low - 0.40) * 2.6 + (drop ? 0.35 : 0)))

    // El vidrio no es redondo: es la forma de la pantalla. Los racimos se
    // reparten en un ÓVALO con esos semiejes (en unidades de `rmin`), no en un
    // círculo — en la vertical se separan sobre todo para arriba y para abajo,
    // que es donde hay lugar. Las gotas siguen siendo REDONDAS: lo que tiene la
    // forma de la pantalla es por dónde se van, no cómo son.
    readonly property real axX: width >= height ? width / Math.max(height, 1) : 1
    readonly property real axY: height > width ? height / Math.max(width, 1) : 1

    // ---- estado de las bolas (posición y velocidad, en unidades de `rmin`:
    // el semieje CHICO del vidrio, o sea el mismo tamaño en la apaisada y en
    // la vertical).
    property var bx: []
    property var by: []
    property var vx: []
    property var vy: []
    property var ph: []               // fase de la órbita propia de cada bola
    property var sd: []               // su semilla (tamaño, velocidad, empujón)
    property real spin: 0             // giro de los racimos, acumulado
    property real wob: 0              // fase de la ondulación del borde, acumulada

    function hash(x) {
        var s = Math.sin(x * 127.1 + 311.7) * 43758.5453;
        return s - Math.floor(s);
    }

    // El ángulo del racimo de la bola `i`: tres direcciones (`i % 3`), que
    // giran lento todas juntas.
    function ang(i) { return spin + (i % 3) * 2.0944; }

    function reseed() {
        spin = seed * 6.283;
        bx = []; by = []; vx = []; vy = []; ph = []; sd = [];
        for (var i = 0; i < 6; i++) {
            var s = hash(seed * 17.3 + i * 5.71);
            sd.push(s);
            ph.push(s * 6.283);
            // nacen ya juntas: la primera imagen es la burbuja, no las gotas
            var a = ang(i);
            bx.push(0.13 * axX * Math.cos(a));
            by.push(0.13 * axY * Math.sin(a));
            vx.push(0); vy.push(0);
        }
        step(0.001);
    }
    // `ready` y no un `Component.onCompleted` pelado: el `seed` se asigna
    // MIENTRAS se crea el objeto, y ahí el ShaderEffect de abajo todavía no
    // existe — escribirle un uniform en ese momento es un ReferenceError.
    property bool ready: false
    onSeedChanged: if (ready) reseed()
    Component.onCompleted: { ready = true; reseed(); }

    property real elong: 0.28 * Math.max(0, Math.min(1, (low - 0.35) * 2.2))

    // El empujón del golpe: cada bola sale con su propia fuerza (por semilla),
    // así se parte en dos o tres gotas y no en cinco iguales.
    onBeatChanged: kickOut(0.34 + 0.75 * Math.max(0, low - 0.3))
    onSurgeChanged: if (surge > 0.9) kickOut(0.30)

    function kickOut(f) {
        if (bx.length < 6)
            return;
        for (var i = 0; i < balls; i++) {
            var a = ang(i);
            var g = f * (0.45 + 1.1 * sd[i]);
            vx[i] += g * axX * Math.cos(a);
            vy[i] += g * axY * Math.sin(a);
        }
    }

    // ---- el paso de la física. Resorte amortiguado hacia el objetivo: el
    // objetivo se abre con el grave y el resorte le pone la INERCIA, que es lo
    // que hace que un golpe separe las gotas y que vuelvan solas.
    function step(dt) {
        if (bx.length < 6)
            return;
        var e = Math.max(energy, 0.35);
        spin += dt * (0.13 + 0.22 * open) * e;
        wob += dt * (0.55 + 0.9 * open + (drop ? 1.6 : 0)) * e;

        var rho = 0.13 + 0.46 * open;         // qué tan lejos van los racimos
        var k = 26.0;                          // el resorte
        var damp = Math.exp(-5.4 * dt);        // y su freno
        for (var i = 0; i < 6; i++) {
            if (i >= balls) {
                setBall(i, 0, 0, 0, 0);
                continue;
            }
            ph[i] += dt * (0.45 + 0.35 * sd[i]) * e;
            var a = ang(i);
            var rp = 0.075 * (0.6 + 0.8 * sd[i]);
            var tx = rho * axX * Math.cos(a) + rp * Math.cos(ph[i]);
            var ty = rho * axY * Math.sin(a) + rp * Math.sin(ph[i]);

            vx[i] = (vx[i] + (tx - bx[i]) * k * dt) * damp;
            vy[i] = (vy[i] + (ty - by[i]) * k * dt) * damp;
            bx[i] += vx[i] * dt;
            by[i] += vy[i] * dt;

            // el radio: al abrirse, cada gota es más chica (la cera es la
            // misma), y así dos racimos separados llegan a partirse de verdad
            var rad = 0.28 * (0.85 + 0.30 * sd[i]) * (1.0 - 0.34 * open);

            // SAFE AREA: la bola entera (con el estirón) adentro del vidrio.
            // Es el freno de la FÍSICA; el del dibujo es el óvalo del shader.
            // se mide contra el ÓVALO del vidrio, que es la misma cuenta que
            // hace el shader: así el freno es el borde que se ve, no un
            // círculo que en la apaisada sobra por los costados
            var nx = bx[i] / axX, ny = by[i] / axY;
            var m = Math.sqrt(nx * nx + ny * ny);
            var lim = 0.97 - rad * (1.0 + elong);
            if (m > lim && m > 0.0001) {
                var f = lim / m;
                bx[i] *= f; by[i] *= f;
                vx[i] *= 0.4; vy[i] *= 0.4;
            }
            setBall(i, bx[i], by[i], rad, a);
        }
    }

    function setBall(i, x, y, r, a) {
        if (!ready)
            return;
        var v = Qt.vector4d(x, y, r, a);
        if (i === 0) glass.b0 = v;
        else if (i === 1) glass.b1 = v;
        else if (i === 2) glass.b2 = v;
        else if (i === 3) glass.b3 = v;
        else if (i === 4) glass.b4 = v;
        else glass.b5 = v;
    }

    property real acc: 0
    FrameAnimation {
        running: lamp.running && lamp.visible
        onTriggered: {
            lamp.acc += frameTime;
            if (lamp.acc >= lamp.stepMin) {
                // un cuadro perdido no puede reventar el resorte
                lamp.step(Math.min(lamp.acc, 0.05));
                lamp.acc = 0;
            }
        }
    }

    ShaderEffect {
        id: glass
        anchors.fill: parent
        blending: true
        // como el resto: con la pantalla quieta la lámpara sigue ahí, congelada
        visible: lamp.width > 0 && lamp.height > 0

        property real level: lamp.level
        property real elong: lamp.elong
        property real wobA: 0.20 + 0.10 * lamp.open + (lamp.drop ? 0.06 : 0)
        property real wobP: lamp.wob
        property real dim: lamp.dim
        property vector2d res: Qt.vector2d(Math.max(width, 1), Math.max(height, 1))
        property vector3d ink: Qt.vector3d(lamp.colour.r, lamp.colour.g, lamp.colour.b)
        property vector3d hot: Qt.vector3d(lamp.hot.r, lamp.hot.g, lamp.hot.b)
        property vector4d b0: Qt.vector4d(0, 0, 0, 0)
        property vector4d b1: Qt.vector4d(0, 0, 0, 0)
        property vector4d b2: Qt.vector4d(0, 0, 0, 0)
        property vector4d b3: Qt.vector4d(0, 0, 0, 0)
        property vector4d b4: Qt.vector4d(0, 0, 0, 0)
        property vector4d b5: Qt.vector4d(0, 0, 0, 0)

        fragmentShader: Qt.resolvedUrl("plasma.frag.qsb")
    }
}
