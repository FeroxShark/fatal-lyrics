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

    readonly property real step: total > 0 ? Math.min(beatMs / total, 1) : 0

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
    }
    // otra línea, otro aro: el `dueAt` es lo que cambia en cada verso
    onDueAtChanged: reset()
    onVisibleChanged: if (visible) reset()

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
            const left = Math.max(ring.dueAt - Date.now(), 0);
            // sin compás confiable el aro baja con el reloj, pero sigue
            // respirando: lo que se pierde es el paso, no la vida
            if (!ring.stepped && !ring.collapsing && ring.total > 0) {
                ring.trailFrom = ring.eaten;
                ring.trailAt = Date.now();
                ring.eaten = Math.max(0, Math.min(1 - left / ring.total, 1));
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

        function traceRing(c, cx, cy, r, from, to, turns, inner) {
            // un arco, y si `turns` > 0 la punta sigue enroscándose hacia
            // adentro: el extremo consumido se mete en el centro en vez de
            // quedar cortado en el aire
            const steps = 90;
            c.beginPath();
            for (let i = 0; i <= steps; i++) {
                const a = from + (to - from) * i / steps;
                const x = cx + Math.cos(a) * r;
                const y = cy + Math.sin(a) * r;
                if (i === 0)
                    c.moveTo(x, y);
                else
                    c.lineTo(x, y);
            }
            if (turns > 0.01) {
                const spin = turns * Math.PI * 2;
                const coil = 70;
                for (let i = 1; i <= coil; i++) {
                    const f = i / coil;
                    const a = to + spin * f;
                    const rr = r * (1 - f * (1 - inner));
                    c.lineTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr);
                }
            }
            c.stroke();
        }

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height;
            const cx = w / 2, cy = h / 2;
            const side = Math.min(w, h);
            const lw = Math.max(3, side * 0.016);
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
            // ±4% con el volumen: entre golpe y golpe el aro sigue vivo
            const breath = 1 + 0.04 * (2 * Math.min(ring.level, 1) - 1);
            // último tramo: se achica hacia el centro, de donde va a salir la línea
            const shrink = left < 3000 ? 0.45 + 0.55 * (left / 3000) : 1;
            const r = side * 0.28 * breath * shrink;
            // entre 8 s y 3 s el aro se abre en espiral, cada vez más enroscado
            const turns = left > 8000 ? 0
                : 1.5 * Math.max(0, Math.min((8000 - left) / 5000, 1));

            const a0 = -Math.PI / 2;
            const rem = Math.max(0, 1 - ring.eaten);
            const aEnd = a0 + rem * Math.PI * 2;

            // ---- la estela: el tramo recién comido no desaparece, se apaga
            const fade = Math.max(ring.beatMs, 200);
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
                c.globalAlpha = 0.18 * t;
                c.strokeStyle = "#ff3b30";
                c.save(); c.translate(-off, 0);
                traceRing(c, cx, cy, r, tFrom, tTo, 0, 1);
                c.restore();
                c.strokeStyle = "#3b6bff";
                c.save(); c.translate(off, 0);
                traceRing(c, cx, cy, r, tFrom, tTo, 0, 1);
                c.restore();
                c.globalAlpha = 0.25 * t;
                c.strokeStyle = ring.colour;
                traceRing(c, cx, cy, r, tFrom, tTo, 0, 1);
            }

            // ---- lo que queda del aro
            c.strokeStyle = ring.colour;
            c.globalAlpha = 1;
            traceRing(c, cx, cy, r, a0, aEnd, turns, 0.15);

            // ---- el doble aro del aviso de drop
            if (ring.ghost > 0.01) {
                const dx = 6 + 2 * ring.ghost;
                c.globalAlpha = 0.55 * ring.ghost;
                c.strokeStyle = ring.hot;
                c.save(); c.translate(dx, -dx * 0.4);
                traceRing(c, cx, cy, r, a0, aEnd, turns, 0.15);
                c.restore();
            }
        }
    }
}
