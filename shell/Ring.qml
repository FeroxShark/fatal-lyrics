// fatal-lyrics — el aro que cuenta la línea que viene.
//
// Se dibuja en la pantalla DONDE VA A CAER la próxima línea, en el hueco en
// que ya no se canta nada, y se vacía hasta que la frase llega. Eso es todo lo
// que hace: la pared deja de reaccionar a la letra y pasa a estar esperándola,
// en la pantalla correcta, con el tiempo que falta a la vista.
//
// TANDA 4 — es un CRONÓMETRO, y se tiene que leer como tal en un segundo.
// Hasta acá era un arco que se comía por golpes: no tenía número, ni escala, ni
// referencia, avanzaba a saltos irregulares y contaba contra un instante que no
// era el bueno. Lo que cambió:
//
//   * **El reloj manda.** `eaten = 1 - left/span`, cada cuadro, contra el `due`
//     que manda el daemon (el instante en que va a salir el próximo `show`, con
//     su offset ya descontado). El compás y los graves NO deciden cuánto se
//     comió: sólo cómo se ve el bocado — un mordisco de ±2 % que vuelve al
//     valor real en `Motion.enterFastMs`. Antes el golpe decidía el avance, y
//     con golpes cada 3 s quedaba un tercio del arco al vencer el tiempo.
//   * **Número, ticks y escala.** Doce marcas fijas como un reloj, una marca
//     larga por cada segundo entero que falta, y el número en el centro con la
//     fuente del tubo: entero mientras falte más de un segundo, décimas en el
//     último. El número entra con snap `OutExpo`.
//   * **La espera es tranquila.** Respiración de ±3 % (no ±10), deriva de 2°/s
//     que nunca para, un pulso del trazo por segundo entero, y UN solo evento
//     al final: el colapso, que termina exactamente en la hora.
//
// Vive adentro de `stage`, así que el vidrio, el bloom y las scanlines le pasan
// por encima como a todo lo demás. Afuera de eso se leería como un widget
// apoyado sobre el tubo.
import QtQuick

Item {
    id: ring

    property color colour: "#4fe8ff"
    property color hot: "#ffffff"
    property string fontFamily: ""
    // volumen 0..1: el aro respira entre golpe y golpe
    property real level: 0.35
    // cuándo llega la línea, en reloj local (Date.now). El aro se calcula solo
    // cuánto falta: pasarle un "faltan tantos ms" desde afuera obligaría a
    // refrescarlo por binding varias veces por segundo.
    property double dueAt: 0
    // el aro está puesto (lo decide `crtRingLive` en el root, que es el que
    // tiene la memoria). Cuando se cae, el aro NO desaparece de golpe: se va
    // con la raya, encima de la letra que entra.
    property bool armed: false
    // sube cuando la línea que se espera es OTRA. El reenvío de la misma línea
    // (el ajuste de sync) corrige `dueAt` sin reiniciar la cuenta.
    property int gen: 0
    property real beatMs: 500
    property int beat: 0              // contador de beats del compás
    property int cue: 0               // aviso de drop: doble aro un cuadro
    // el golpe de graves que ya le llega al motivo: con esto se dibuja el
    // mordisco, que es lo único que el ritmo decide todavía
    property int kick: 0
    property real low: 0.4            // graves 0..1: con esto respira
    property int screen: -1           // sólo para el log

    // el último golpe: el aro entrega la línea
    signal collapsed()

    visible: armed || farewell > 0.01 || fadeAnim.running

    // ---- el hueco que se cuenta, congelado al aparecer
    // Se mide UNA vez, cuando el aro se prende: `dueAt` se puede corregir
    // después (un golpe de sync mueve la hora) y el arco tiene que acusar ese
    // movimiento, no reescalarse para disimularlo.
    property real span: 4000
    property double startedAt: 0
    // los huecos largos son otra cosa: ahí el aro es una espera, y lo comido se
    // suelta en hebras. En un hueco normal eso sería una animación de más.
    readonly property bool longWait: span > 7000

    // 0..1 de aro comido, por reloj y nada más
    property real eaten: 0
    // el mordisco: lo que el ritmo dibuja encima del valor real
    property real bite: 0
    property real ghost: 0            // el doble aro del `cue`
    property bool collapsing: false
    property real dotAmt: 0
    property real lineAmt: 0
    property real farewell: 0         // la raya de despedida, encima de la letra
    property real fade: 1             // el apagado si la línea no llegó nunca
    // la hora venció y la línea no llegó: se acabó la espera. A partir de acá
    // no hay raya de entrega — no hay nada que entregar.
    property bool timedOut: false
    property real lwBoost: 0          // el trazo engorda en el tick de cada segundo
    property int secsLeft: -1         // segundos enteros que faltan (para el tick)
    property real drift: 0            // la deriva de los ticks, en radianes

    // el modo es del DIBUJO, no de la cuenta: con compás el mordisco cae en el
    // tiempo, sin compás en el grave, y sin ninguno de los dos no hay mordisco
    property bool stepped: false
    readonly property string ringMode: stepped ? "beat"
                                               : (kickLive ? "kick" : "lineal")
    property bool kickLive: false
    property double lastKickAt: 0

    // ---- las hebras (T3.B1), ahora sólo para la espera larga.
    // Los ángulos se ACUMULAN cuadro a cuadro (`ang += vel * dt`). Con
    // `ángulo = reloj × velocidad` cualquier cambio de tempo multiplica un
    // reloj de miles de segundos y las hebras se teletransportan: es la misma
    // trampa del túnel y del hiperespacio.
    property var strandAng: []
    property double strandLast: 0
    readonly property int strandN: 3 + (Math.abs(Math.round(dueAt / 97)) % 3)

    // ---- el texto del número
    readonly property string label: {
        if (secsLeft < 0)
            return "";
        return secsLeft >= 1 ? String(secsLeft) : (tenths / 10).toFixed(1);
    }
    property int tenths: 0

    function reset() {
        collapseAnim.stop();
        farewellAnim.stop();
        fadeAnim.stop();
        ghostDecay.stop();
        biteDecay.stop();
        lwDecay.stop();
        collapsing = false;
        dotAmt = 0;
        lineAmt = 0;
        ghost = 0;
        eaten = 0;
        bite = 0;
        lwBoost = 0;
        farewell = 0;
        fade = 1;
        timedOut = false;
        drift = 0;
        kickLive = false;
        lastKickAt = 0;
        startedAt = Date.now();
        // el hueco es lo que falta AHORA: en un instrumental largo el aro
        // aparece recién cuando quedan 8 s, y esos 8 s son su arco entero
        span = Math.max(dueAt - startedAt, 400);
        // el número ya nace en su valor. Dejándolo en -1, el primer cuadro lo
        // subía de golpe y el segundo entero caía unas decenas de ms después:
        // dos snaps adentro de 120 ms, que es justo el tartamudeo que la
        // referencia de fluidez prohíbe en una entrada.
        secsLeft = Math.max(Math.floor(span / 1000), 0);
        tenths = Math.max(Math.floor(span / 100), 0);
        const a = [];
        for (let i = 0; i < strandN; i++)
            a.push(0);
        strandAng = a;
        strandLast = 0;
    }

    onArmedChanged: {
        if (armed) {
            farewell = 0;
            reset();
            console.log("crt: ring mode=" + ringMode + " screen=" + screen
                + " in=" + Math.round(span) + " long=" + longWait);
            return;
        }
        // la línea llegó (o el reparto cambió). El aro no se corta seco: la
        // raya sale encima de la entrada de la letra, que es lo que ata las dos
        // cosas — la frase entra por donde el aro se fue.
        if (timedOut)
            return;             // venció sin línea: ya se estaba yendo solo
        fadeAnim.stop();
        farewell = 1;
        farewellAnim.restart();
        console.log("crt: ring dash screen=" + screen + " at=" + Date.now()
            + " due=" + Math.round(dueAt));
    }
    // otra línea, otro aro. `dueAt` solo NO alcanza: un reenvío de la misma
    // línea trae la hora corregida y borrar la cuenta ahí sería devolver el aro
    // a lleno cada vez que se toca el sync.
    onGenChanged: if (armed) reset();

    // ------------------------------------------------------- el mordisco
    // El ritmo ya no decide cuánto se comió (eso lo dice el reloj): decide
    // cómo se ve. Un mordisco chico que adelanta el arco un 2 % y vuelve solo.
    NumberAnimation on bite {
        id: biteDecay
        running: false
        from: 1; to: 0; duration: Motion.enterFastMs; easing.type: Easing.OutExpo
    }
    NumberAnimation on lwBoost {
        id: lwDecay
        running: false
        from: 1; to: 0; duration: 260; easing.type: Easing.OutQuad
    }

    onKickChanged: {
        if (!visible || collapsing)
            return;
        lastKickAt = Date.now();
        kickLive = true;
        if (!stepped)
            biteDecay.restart();
    }
    onBeatChanged: {
        if (!visible || !stepped || collapsing)
            return;
        biteDecay.restart();
    }
    onRingModeChanged: if (visible)
        console.log("crt: ring mode=" + ringMode + " screen=" + screen);

    // el aviso del drop: el aro se duplica corrido unos píxeles y vuelve
    onCueChanged: {
        if (!visible)
            return;
        ghostDecay.stop();
        ghost = 1;
        ghostDecay.start();
    }
    // El doble aro se quedaba 140 ms desvaneciéndose desde el primer cuadro, y
    // un efecto que empieza a irse en cuanto aparece no se llega a ver. Se
    // queda quieto 120 ms — el mínimo de T3.B6 — y recién ahí se apaga.
    SequentialAnimation {
        id: ghostDecay
        PauseAnimation { duration: Motion.bridgeMs }
        NumberAnimation {
            target: ring
            property: "ghost"
            to: 0
            duration: Motion.exitMs
            easing.type: Easing.OutQuad
        }
    }

    // ---- el final: el aro se recoge a un punto, y termina EXACTAMENTE en la
    // hora. Antes largaba también la raya y terminaba 260 ms antes: la línea
    // llegaba con el aro ya apagado y las dos cosas no se leían juntas.
    readonly property int collapseMs: 250
    SequentialAnimation {
        id: collapseAnim
        NumberAnimation { target: ring; property: "dotAmt"; from: 0; to: 1;
                          duration: ring.collapseMs; easing.type: Easing.InQuad }
        ScriptAction { script: {
            ring.tenths = 0;
            console.log("crt: ring zero screen=" + ring.screen
                + " at=" + Date.now() + " due=" + Math.round(ring.dueAt));
        } }
    }
    // la raya: sale cuando llega la línea, no cuando vence el reloj
    SequentialAnimation {
        id: farewellAnim
        NumberAnimation { target: ring; property: "lineAmt"; from: 0; to: 1;
                          duration: 100; easing.type: Easing.OutQuad }
        ScriptAction { script: {
            ring.collapsed();
            ring.farewell = 0;
        } }
    }
    // ...y si no llegó nunca, el aro se apaga solo medio segundo después
    SequentialAnimation {
        id: fadeAnim
        PauseAnimation { duration: 500 }
        ScriptAction { script: ring.timedOut = true }
        NumberAnimation { target: ring; property: "fade"; to: 0;
                          duration: Motion.exitMs; easing.type: Easing.InQuad }
    }

    Timer {
        interval: 33          // 30 Hz: un trazo no necesita más
        repeat: true
        running: ring.visible
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now();
            const left = ring.dueAt - now;
            const dt = ring.strandLast > 0
                ? Math.min(now - ring.strandLast, 120) : 0;
            ring.strandLast = now;
            // la deriva: 2°/s que no paran nunca. Es lo que hace que el hold no
            // parezca congelado sin que pase nada (ver fluidez-referencia.md).
            if (dt > 0)
                ring.drift += 0.0349 * dt / 1000;
            // las hebras giran: cada una acumula SU ángulo con el dt real, así
            // un cambio de compás las acelera desde donde estaban
            if (ring.longWait && dt > 0 && ring.strandAng.length > 0) {
                const bm = Math.max(ring.beatMs, 220);
                const a = ring.strandAng;
                for (let i = 0; i < a.length; i++) {
                    // media vuelta a vuelta y media por compás, y el volumen la
                    // empuja: una hebra se separa de la otra
                    const v = (0.5 + 0.35 * i) * (1 + 0.5 * ring.level)
                        * Math.PI * 2 / bm;
                    a[i] += v * dt * (i % 2 === 0 ? 1 : -0.75);
                }
                ring.strandAng = a;
            }
            // el grave se da por muerto si no vuelve: el modo del dibujo tiene
            // que decir la verdad aunque el tema se haya quedado callado
            if (ring.kickLive && now - ring.lastKickAt > 2500)
                ring.kickLive = false;

            // ---- la cuenta: reloj y nada más
            if (!ring.collapsing)
                ring.eaten = Math.max(0, Math.min(1 - left / ring.span, 1));

            // ---- el número, y el tick de cada segundo entero
            const secs = left > 0 ? Math.floor(left / 1000) : 0;
            const t = left > 0 ? Math.floor(left / 100) : 0;
            if (secs !== ring.secsLeft) {
                ring.secsLeft = secs;
                if (ring.visible && secs >= 0) {
                    numSnap.restart();
                    lwDecay.restart();
                }
            }
            if (secs < 1 && t !== ring.tenths) {
                ring.tenths = t;
                numSnap.restart();
            }

            // el último tramo: se recoge al punto, y llega a él en la hora
            if (!ring.collapsing && left <= ring.collapseMs) {
                ring.collapsing = true;
                collapseAnim.restart();
            }
            // vencida la hora sin línea: se queda en 0.0 quieto y recién
            // después se va. El `show` cae 0–300 ms tarde (el poll del daemon):
            // ese jitter no se persigue, se espera.
            if (left <= 0 && !fadeAnim.running && ring.fade > 0.99
                    && ring.farewell < 0.01)
                fadeAnim.restart();
            arc.requestPaint();
        }
    }

    // ---- el número: la fuente del tubo, en el centro. Es lo que hace que se
    // lea como una cuenta regresiva y no como un adorno que se vacía.
    Text {
        id: num
        anchors.centerIn: parent
        text: ring.label
        visible: ring.farewell < 0.01 && ring.label !== ""
        color: ring.colour
        opacity: ring.fade
        font.family: ring.fontFamily
        font.pixelSize: Math.max(14, Math.min(parent.width, parent.height) * 0.15)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        transform: Scale {
            origin.x: num.width / 2
            origin.y: num.height / 2
            xScale: num.snap
            yScale: num.snap
        }
        property real snap: 1
        NumberAnimation {
            id: numSnap
            target: num
            property: "snap"
            from: 1.18
            to: 1
            duration: Motion.enterFastMs
            easing.type: Easing.OutExpo
        }
    }

    Canvas {
        id: arc
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        opacity: ring.fade

        // Un arco entre dos radios: con r0 === r1 es un pedazo de aro, y con
        // r1 < r0 es una hebra que se va metiendo hacia adentro. Los pasos se
        // piden según lo que mide el arco — una hebra corta con 90 puntos es
        // gastar tres veces más de lo que se ve.
        function traceArc(c, cx, cy, r0, r1, from, to, steps) {
            c.beginPath();
            for (let i = 0; i <= steps; i++) {
                const f = i / steps;
                const a = from + (to - from) * f;
                const rr = r0 + (r1 - r0) * f;
                const x = cx + Math.cos(a) * rr;
                const y = cy + Math.sin(a) * rr;
                if (i === 0)
                    c.moveTo(x, y);
                else
                    c.lineTo(x, y);
            }
            c.stroke();
        }

        // Las hebras: el tramo YA COMIDO se suelta. Sólo en la espera larga —
        // en un hueco normal el aro dura dos o tres segundos y desarmarlo sería
        // el segundo evento de una pantalla que tiene presupuesto para uno.
        function traceStrands(c, cx, cy, r, aEnd, lw, spiral, gather) {
            const n = ring.strandAng.length;
            if (n === 0)
                return;
            const span = Math.max(0, ring.eaten) * Math.PI * 2;
            if (span < 0.15)
                return;
            const seg = span / n;
            const off = lw * 0.22 + 2;
            for (let i = 0; i < n; i++) {
                const turn = ring.strandAng[i] * spiral;
                const from = aEnd + i * seg + turn;
                const to = from + seg * (0.72 + 0.28 * spiral);
                // radio: cada hebra en su plano, empujada por el volumen, y
                // todas recogidas al centro en el tramo final
                const depth = (0.10 + 0.30 * (i + 1) / n) * spiral
                    * (0.6 + 0.9 * Math.min(ring.level, 1));
                const r0 = r * (1 - depth) * (1 - 0.92 * gather);
                const r1 = r0 * (1 - 0.22 * spiral);
                const steps = Math.max(8, Math.min(30, Math.round(seg * 14)));
                // el corrimiento de crominancia: la hebra deja estela porque el
                // fósforo no se apaga a la vez en los tres canales
                c.globalAlpha = 0.20 * spiral * (1 - gather * 0.5);
                c.strokeStyle = "#ff3b30";
                c.save(); c.translate(-off, 0);
                traceArc(c, cx, cy, r0, r1, from, to, steps);
                c.restore();
                c.strokeStyle = "#3b6bff";
                c.save(); c.translate(off, 0);
                traceArc(c, cx, cy, r0, r1, from, to, steps);
                c.restore();
                c.globalAlpha = (0.55 + 0.35 * spiral) * (1 - gather * 0.35);
                c.strokeStyle = ring.colour;
                traceArc(c, cx, cy, r0, r1, from, to, steps);
            }
            c.globalAlpha = 1;
        }

        // La escala: doce marcas fijas alrededor, como la esfera de un reloj, y
        // una marca LARGA por cada segundo entero que falta. Sin escala el arco
        // que se vacía puede ser cualquier cosa; con ella se lee cuánto queda
        // aunque el número no se mire.
        function traceDial(c, cx, cy, r, lw) {
            const dr = ring.drift;
            c.lineWidth = Math.max(1, lw * 0.35);
            c.globalAlpha = 0.35;
            c.strokeStyle = ring.colour;
            for (let i = 0; i < 12; i++) {
                const a = -Math.PI / 2 + i * Math.PI / 6 + dr;
                const r0 = r * 1.06, r1 = r * 1.11;
                c.beginPath();
                c.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0);
                c.lineTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1);
                c.stroke();
            }
            // los segundos: dónde va a estar la cabeza del arco en cada uno.
            // Van sobre el tramo que TODAVÍA no se comió: son los que faltan.
            const secs = Math.min(Math.floor(ring.span / 1000), 12);
            c.lineWidth = Math.max(1.5, lw * 0.5);
            c.globalAlpha = 0.6;
            for (let k = 1; k <= secs; k++) {
                const f = 1 - k * 1000 / ring.span;   // 0..1 de arco comido
                if (f < ring.eaten - 0.001)
                    continue;
                const a = -Math.PI / 2 + f * Math.PI * 2;
                const r0 = r * 1.03, r1 = r * 1.15;
                c.beginPath();
                c.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0);
                c.lineTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1);
                c.stroke();
            }
            c.globalAlpha = 1;
        }

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height;
            const cx = w / 2, cy = h / 2;
            const side = Math.min(w, h);
            const lw = Math.max(3, side * 0.016) * (1 + 0.4 * ring.lwBoost);
            c.lineCap = "round";

            // la raya de despedida: el apagado del tubo al revés, encima de la
            // letra que está entrando
            if (ring.farewell > 0.01) {
                const dot = Math.max(lw * 0.9, side * 0.012);
                const half = side * 0.30 * ring.lineAmt;
                c.globalAlpha = 1 - ring.lineAmt * 0.7;
                c.fillStyle = ring.hot;
                c.fillRect(cx - half, cy - dot / 2, half * 2, dot);
                return;
            }

            c.lineWidth = lw;
            const left = Math.max(ring.dueAt - Date.now(), 0);
            // ±3% con los GRAVES. Eran ±10 y con el número al lado se leía como
            // un latido, no como una espera: la referencia de fluidez pide
            // amplitud chica sobre deriva uniforme, no lo contrario.
            const breath = 1 + 0.03 * (2 * Math.min(ring.low, 1) - 1);
            // último tramo: se achica hacia el centro, de donde va a salir la
            // línea. Sólo el último segundo y medio — antes de eso el aro se
            // queda quieto, que es el punto.
            const gather = left < 1500 ? 1 - left / 1500 : 0;
            // ...y el colapso es ESE mismo movimiento terminado: el aro se
            // recoge al centro y llega justo en la hora. Sin raya y sin punto
            // encima del número: la raya es la entrega, y hasta que la línea no
            // llegue no hay nada que entregar (el `show` cae 0–300 ms tarde por
            // el poll del daemon, y ese jitter se espera quieto en "0.0").
            const shrink = (1 - 0.25 * gather) * (1 - 0.94 * ring.dotAmt);
            const r = side * 0.28 * breath * shrink;
            // la espera larga: el aro se va DESARMANDO mientras falta mucho, y
            // se recompone sobre los últimos segundos
            const spiral = !ring.longWait ? 0
                : Math.max(0, Math.min((ring.span - left) / 3000, 1))
                  * Math.max(0, Math.min(left / 4000, 1));

            // el arco se vacía EN SENTIDO HORARIO DESDE LAS 12: el hueco nace
            // arriba y crece con el reloj, que es como se lee una cuenta
            // regresiva. Antes el extremo retrocedía hacia las 12 y el ojo lo
            // leía al revés.
            const a0 = -Math.PI / 2;
            const gone = Math.max(0, Math.min(ring.eaten + 0.02 * ring.bite, 1));
            const aFrom = a0 + gone * Math.PI * 2;
            const aTo = a0 + Math.PI * 2;

            if (!ring.collapsing) {
                traceDial(c, cx, cy, r, lw);
                c.lineWidth = lw;
            }

            // ---- las hebras de lo ya comido, sólo en la espera larga
            if (spiral > 0.01 && !ring.collapsing)
                traceStrands(c, cx, cy, r, aFrom, lw, spiral, gather);

            // ---- lo que queda del aro
            c.strokeStyle = ring.colour;
            c.globalAlpha = 1;
            const steps = Math.max(10, Math.min(90, Math.round((aTo - aFrom) * 14)));
            if (aTo - aFrom > 0.01)
                traceArc(c, cx, cy, r, r, aFrom, aTo, steps);

            // ---- el doble aro del aviso de drop
            if (ring.ghost > 0.01) {
                const dx = 6 + 2 * ring.ghost;
                c.globalAlpha = 0.55 * ring.ghost;
                c.strokeStyle = ring.hot;
                c.save(); c.translate(dx, -dx * 0.4);
                traceArc(c, cx, cy, r, r, aFrom, aTo, steps);
                c.restore();
            }
        }
    }
}
