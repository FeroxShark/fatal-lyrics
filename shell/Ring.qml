// fatal-lyrics — the ring that counts the next line down.
//
// It is drawn on the screen where the NEXT line is going to land, and it is
// eaten away until the line gets there. That is the whole point: the wall
// stops being a thing that reacts to the lyric and becomes a thing that is
// waiting for it, on the right screen, with the right amount of time left.
//
// It is not a progress bar. It is consumed a STEP PER BEAT when the tempo is
// known -- so it counts in the units the song is actually made of -- and only
// falls back to the clock when there is no tempo to trust. Between beats it
// breathes with the volume, which is what keeps it alive while nothing is
// being eaten.
//
// It lives inside `stage`, so the glass, the bloom and the scanlines run over
// it like over everything else. Outside of that it would read as a widget
// dropped on the tube.
import QtQuick

Item {
    id: ring

    property color colour: "#4fe8ff"
    property color hot: "#ffffff"
    // volumen 0..1: el aro respira ±4% entre golpe y golpe
    property real level: 0.35
    // cuándo llega la línea, en reloj local (Date.now). El aro se calcula solo
    // cuánto falta: pasarle un "faltan tantos ms" desde afuera obligaría a
    // refrescarlo por binding varias veces por segundo.
    property double dueAt: 0
    // cuánto faltaba cuando el aro apareció: es lo que fija el tamaño del paso
    property real total: 0
    property bool stepped: false      // true = se consume por beats
    property real beatMs: 500
    property int beat: 0              // contador de beats del compás
    property int cue: 0               // aviso de drop: doble aro un cuadro
    // el golpe de graves que ya le llega al motivo: es lo que come el aro
    // cuando no hay compás confiable (T3.B10)
    property int kick: 0
    property real low: 0.4            // graves 0..1: con esto respira
    property int screen: -1           // sólo para el log

    // el último golpe: el aro colapsa a un punto y entrega la línea
    signal collapsed()

    // 0..1 de aro comido
    property real eaten: 0
    // la estela: de dónde a dónde fue el último bocado, y cuándo
    property real trailFrom: 0
    property double trailAt: 0
    property real ghost: 0            // el doble aro del `cue`
    property bool collapsing: false
    property real dotAmt: 0
    property real lineAmt: 0

    // ---- la espiral (T3.B1): el aro no se enrosca, se DESARMA.
    // El tramo ya consumido se suelta en 3-5 hebras que giran cada una a su
    // velocidad (angular por compás, radial por volumen) y se recogen al centro
    // sobre los últimos 3 s. Una línea enroscada era un dibujo; esto es el aro
    // deshaciéndose, que es lo que el aro significa.
    //
    // Los ángulos se ACUMULAN cuadro a cuadro (`ang += vel * dt`). Con
    // `ángulo = reloj × velocidad` cualquier cambio de tempo multiplica un
    // reloj de miles de segundos y las hebras se teletransportan: es la misma
    // trampa del túnel y del hiperespacio.
    property var strandAng: []
    property double strandLast: 0
    readonly property int strandN: 3 + (Math.abs(Math.round(dueAt / 97)) % 3)

    readonly property real step: total > 0 ? Math.min(beatMs / total, 1) : 0

    // ------------------------------------------------- comer sin compás (B10)
    // El `bpm conf > 0.6` casi nunca se cumple, y con el reloj puro el aro no
    // reaccionaba a nada: bajaba parejo y parecía un cronómetro. Sin compás el
    // arco avanza POR GOLPE, con el escalón que corresponda al tiempo que
    // falta: si viene comiendo de más el escalón se achica solo, si viene de
    // menos se agranda, así llega a cero justo cuando cae la línea. Y si el
    // tema tampoco tiene golpes (ni compás), recién ahí el reloj — pero
    // deslizándose, no clavado.
    property real kickEma: 600         // cada cuánto viene pegando el grave
    property double lastKickAt: 0
    property bool kickLive: false
    readonly property string ringMode: stepped ? "beat"
                                               : (kickLive ? "kick" : "lineal")
    property real lwBoost: 0           // el trazo engorda en cada escalón
    NumberAnimation on lwBoost {
        id: lwDecay
        running: false
        from: 1; to: 0; duration: 260; easing.type: Easing.OutQuad
    }

    function bite(now, amount) {
        trailFrom = eaten;
        trailAt = now;
        eaten = Math.min(eaten + amount, 1);
        lwDecay.restart();
    }

    onKickChanged: {
        if (!visible || stepped || collapsing || total <= 0)
            return;
        const now = Date.now();
        if (lastKickAt > 0) {
            const gap = Math.max(250, Math.min(now - lastKickAt, 1500));
            kickEma = kickEma * 0.7 + gap * 0.3;
        }
        lastKickAt = now;
        kickLive = true;
        const left = Math.max(dueAt - now, 0);
        // cuántos golpes quedan hasta que caiga la línea: el escalón es lo que
        // falta repartido entre ellos
        const rest = Math.max(1, left / Math.max(kickEma, 120));
        bite(now, Math.min((1 - eaten) / rest, 0.5));
    }

    onRingModeChanged: if (visible)
        console.log("crt: ring mode=" + ringMode + " screen=" + screen);

    function reset() {
        collapseAnim.stop();
        ghostDecay.stop();
        collapsing = false;
        dotAmt = 0;
        lineAmt = 0;
        ghost = 0;
        eaten = 0;
        trailFrom = 0;
        trailAt = 0;
        const a = [];
        for (let i = 0; i < strandN; i++)
            a.push(0);
        strandAng = a;
        strandLast = 0;
        lwDecay.stop();
        lwBoost = 0;
        lastKickAt = 0;
        kickLive = false;
    }
    // otra línea, otro aro: el `dueAt` es lo que cambia en cada verso
    onDueAtChanged: reset()
    onVisibleChanged: {
        if (!visible)
            return;
        reset();
        console.log("crt: ring mode=" + ringMode + " screen=" + screen
            + " in=" + Math.round(total));
    }

    // Un escalón por beat, sin suavizar: el aro tiene que contar en tiempos,
    // y un tiempo se ve como un salto. Lo que suaviza es la estela, no el paso.
    onBeatChanged: {
        if (!visible || !stepped || collapsing)
            return;
        trailFrom = eaten;
        trailAt = Date.now();
        eaten = Math.min(eaten + step, 1);
    }

    // el aviso del drop: el aro se duplica corrido unos píxeles y vuelve
    onCueChanged: {
        if (!visible)
            return;
        ghostDecay.stop();
        ghost = 1;
        ghostDecay.start();
    }
    NumberAnimation {
        id: ghostDecay
        target: ring
        property: "ghost"
        to: 0
        duration: 140
        easing.type: Easing.OutQuad
    }

    // El final: punto → raya. Es el apagado de tubo al revés, y es a propósito:
    // la línea entra por donde el aro se fue.
    SequentialAnimation {
        id: collapseAnim
        NumberAnimation { target: ring; property: "dotAmt"; from: 0; to: 1;
                          duration: 120; easing.type: Easing.InQuad }
        NumberAnimation { target: ring; property: "lineAmt"; from: 0; to: 1;
                          duration: 130; easing.type: Easing.OutQuad }
        ScriptAction { script: ring.collapsed() }
    }

    Timer {
        interval: 33          // 30 Hz: un trazo no necesita más
        repeat: true
        running: ring.visible
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now();
            const left = Math.max(ring.dueAt - now, 0);
            // las hebras giran: cada una acumula SU ángulo con el dt real, así
            // un cambio de compás las acelera desde donde estaban
            if (ring.strandAng.length > 0) {
                const dt = ring.strandLast > 0
                    ? Math.min(now - ring.strandLast, 120) : 0;
                ring.strandLast = now;
                if (dt > 0) {
                    const bm = Math.max(ring.beatMs, 220);
                    const a = ring.strandAng;
                    for (let i = 0; i < a.length; i++) {
                        // media vuelta a vuelta y media por compás, y el
                        // volumen la empuja: una hebra se separa de la otra
                        const v = (0.5 + 0.35 * i) * (1 + 0.5 * ring.level)
                            * Math.PI * 2 / bm;
                        a[i] += v * dt * (i % 2 === 0 ? 1 : -0.75);
                    }
                    ring.strandAng = a;
                }
            }
            // ni compás ni graves: el reloj, pero deslizándose hacia él en vez
            // de quedar clavado, así el aro sigue pareciendo algo que come.
            // Un tema con golpes no entra nunca acá: `kickLive` lo tapa.
            if (!ring.stepped && !ring.collapsing && ring.total > 0) {
                if (ring.lastKickAt > 0
                        && now - ring.lastKickAt > 2 * ring.kickEma)
                    ring.kickLive = false;
                if (!ring.kickLive) {
                    const goal = Math.max(0, Math.min(1 - left / ring.total, 1));
                    if (goal > ring.eaten)
                        ring.eaten = ring.eaten + (goal - ring.eaten) * 0.18;
                }
            }
            // el último tiempo: colapsa. Con un compás lento el punto tiene que
            // salir antes, o la línea llega con el aro todavía entero.
            if (!ring.collapsing
                    && left <= Math.max(ring.stepped ? ring.beatMs : 260, 220)) {
                ring.collapsing = true;
                collapseAnim.restart();
            }
            arc.requestPaint();
        }
    }

    Canvas {
        id: arc
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

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

        // Las hebras: el tramo YA COMIDO se suelta. Cada una es un pedazo del
        // arco consumido, girado por su propio ángulo acumulado y metido hacia
        // adentro; sobre los últimos 3 s se recogen al centro, que es de donde
        // después sale la línea.
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

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height;
            const cx = w / 2, cy = h / 2;
            const side = Math.min(w, h);
            const lw = Math.max(3, side * 0.016) * (1 + 0.6 * ring.lwBoost);
            c.lineWidth = lw;
            c.lineCap = "round";

            if (ring.collapsing) {
                // punto y raya: lo mismo que el tubo apagándose, al revés
                const dot = Math.max(lw * 0.9, side * 0.012);
                c.globalAlpha = 1;
                c.fillStyle = ring.hot;
                if (ring.lineAmt <= 0.01) {
                    const r = dot * (1 + 2 * (1 - ring.dotAmt));
                    c.beginPath();
                    c.ellipse(cx - r, cy - r, r * 2, r * 2);
                    c.fill();
                } else {
                    const half = side * 0.30 * ring.lineAmt;
                    c.globalAlpha = 1 - ring.lineAmt * 0.7;
                    c.fillRect(cx - half, cy - dot / 2, half * 2, dot);
                }
                return;
            }

            const left = Math.max(ring.dueAt - Date.now(), 0);
            // ±10% con los GRAVES: entre golpe y golpe el aro sigue vivo, y
            // con el ±4% del nivel general no se veía nada
            const breath = 1 + 0.10 * (2 * Math.min(ring.low, 1) - 1);
            // último tramo: se achica hacia el centro, de donde va a salir la línea
            const gather = left < 3000 ? 1 - left / 3000 : 0;
            const shrink = 1 - 0.55 * gather;
            const r = side * 0.28 * breath * shrink;
            // entre 8 s y 3 s el aro se va DESARMANDO: lo comido se suelta en
            // hebras, cada vez más separadas
            const spiral = left > 8000 ? 0
                : Math.max(0, Math.min((8000 - left) / 5000, 1));

            const a0 = -Math.PI / 2;
            const rem = Math.max(0, 1 - ring.eaten);
            const aEnd = a0 + rem * Math.PI * 2;

            // ---- la estela: el tramo recién comido no desaparece, se apaga
            const fade = Math.max(ring.stepped ? ring.beatMs : ring.kickEma, 200);
            const age = ring.trailAt > 0 ? Date.now() - ring.trailAt : fade;
            if (age < fade && ring.eaten > ring.trailFrom) {
                const t = 1 - age / fade;
                const tFrom = a0 + (1 - ring.eaten) * Math.PI * 2;
                const tTo = a0 + (1 - ring.trailFrom) * Math.PI * 2;
                // el corrimiento de crominancia: rojo a un lado, azul al otro.
                // El fósforo del tubo no se apaga en el mismo instante en los
                // tres canales, y eso es lo que hace que la estela se lea como
                // algo que estuvo prendido y no como una línea más floja.
                const off = lw * 0.22 + 2;
                const st = Math.max(8, Math.min(40, Math.round((tTo - tFrom) * 14)));
                c.globalAlpha = 0.18 * t;
                c.strokeStyle = "#ff3b30";
                c.save(); c.translate(-off, 0);
                traceArc(c, cx, cy, r, r, tFrom, tTo, st);
                c.restore();
                c.strokeStyle = "#3b6bff";
                c.save(); c.translate(off, 0);
                traceArc(c, cx, cy, r, r, tFrom, tTo, st);
                c.restore();
                c.globalAlpha = 0.25 * t;
                c.strokeStyle = ring.colour;
                traceArc(c, cx, cy, r, r, tFrom, tTo, st);
            }

            // ---- las hebras de lo ya comido, si el aro ya se está desarmando
            if (spiral > 0.01)
                traceStrands(c, cx, cy, r, aEnd, lw, spiral, gather);

            // ---- lo que queda del aro
            c.strokeStyle = ring.colour;
            c.globalAlpha = 1;
            traceArc(c, cx, cy, r, r, a0, aEnd,
                     Math.max(10, Math.min(90, Math.round((aEnd - a0) * 14))));

            // ---- el doble aro del aviso de drop
            if (ring.ghost > 0.01) {
                const dx = 6 + 2 * ring.ghost;
                c.globalAlpha = 0.55 * ring.ghost;
                c.strokeStyle = ring.hot;
                c.save(); c.translate(dx, -dx * 0.4);
                traceArc(c, cx, cy, r, r, a0, aEnd,
                         Math.max(10, Math.min(90, Math.round((aEnd - a0) * 14))));
                c.restore();
            }
        }
    }
}
