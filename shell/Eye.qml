// fatal-lyrics — el ojo.
//
// Ojo de alambre como el de la pantalla del videoclip: lente en punta, malla de
// radios y un iris de anillos concéntricos.
//
// Vive en su propio archivo desde que hay más de un ojo por pantalla
// (`Eyes.qml`): el dibujo es el mismo, cambia el tamaño, el desfasaje del
// parpadeo y hacia dónde mira.
//
// T4.0 — EL IRIS ES UN CÍRCULO Y EL PÁRPADO LO TAPA. Hasta la tanda 4 el ojo
// entero era un Canvas con un `Scale` de `yScale` encima, así que entrecerrar
// aplastaba TODO: los anillos del iris eran óvalos que seguían la elipse del
// párpado (se ve en `docs/plans/ref-fluidez/ferox-eyes-vertical.jpg` — el ojo
// grande mide 975×280 px, relación 0.29, y adentro los anillos son ovalados).
// Un ojo real es un iris circular que los párpados tapan, no uno que se achata.
//
// El truco es partir la abertura en dos, porque las dos mitades tienen costos
// distintos:
//
//   · `lid` (entrecerrar, lento, lo mueve el volumen) va DIBUJADO: el canvas
//     recorta con la almendra del momento y los anillos se dibujan redondos
//     adentro. Se cuantiza a pasos de 0.05 para no repintar con cada muestra
//     de audio.
//   · `open` (el parpadeo, 70–260 ms) va por `Scale`, como antes. Aplasta todo
//     por un décimo de segundo, que es exactamente el tiempo en que nadie mira
//     la forma del iris — y a cambio un parpadeo no cuesta veinte repintados.
//
// Y el iris se CORRE hacia donde mira, con la pupila en su centro. Antes la
// pupila viajaba sola hasta un cuarto del ancho y quedaba como una mancha
// blanca al lado de los anillos, sin nada alrededor.
import QtQuick

Item {
    id: eye

    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35
    property real punch: 0
    property real surge: 0
    // false = quieto (pantalla apagada): el ojo queda abierto, no en blanco
    property bool blinking: true
    // desfasaje del parpadeo, en ms: es lo que hace que varios ojos no
    // parpadeen como un solo bicho
    property int phase: 0
    // hacia dónde mira: -1 todo a la izquierda, 0 al frente, 1 a la derecha
    property real gaze: 0
    Behavior on gaze { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
    // contador: cuando sube, este ojo parpadea YA (el golpe los junta a todos)
    property int blinkNow: 0
    // cuánto se entrecierra el párpado sin llegar a parpadear: 1 abierto del
    // todo, 0.45 en calma. Multiplica al parpadeo en vez de pisarlo, así el
    // ojo sigue parpadeando entrecerrado.
    property real lid: 1
    Behavior on lid { NumberAnimation { duration: 520; easing.type: Easing.InOutQuad } }
    // lo que ve el dibujo: pasos de 0.05. El párpado lo mueve el volumen, que
    // llega a 10 Hz — sin cuantizar, el canvas se repinta con cada muestra.
    readonly property real lidQ: Math.max(0.12, Math.round(Math.min(lid, 1) * 20) / 20)

    property real open: 0

    onVisibleChanged: {
        if (visible) {
            open = 0;
            openAnim.restart();
        }
    }
    Component.onCompleted: if (visible) openAnim.start()
    onBlinkNowChanged: if (visible && blinking) togetherBlink.restart()

    NumberAnimation {
        id: openAnim
        target: eye
        property: "open"
        to: 1
        duration: 850
        easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: togetherBlink
        NumberAnimation { target: eye; property: "open"; to: 0.06; duration: 70; easing.type: Easing.InQuad }
        NumberAnimation { target: eye; property: "open"; to: 1; duration: 210; easing.type: Easing.OutBack }
    }
    SequentialAnimation {
        running: eye.visible && eye.blinking && !togetherBlink.running
        loops: Animation.Infinite
        // el desfasaje se cobra una sola vez, al arrancar el ciclo
        PauseAnimation { duration: 3400 + eye.phase }
        NumberAnimation { target: eye; property: "open"; to: 0.06; duration: 90; easing.type: Easing.InQuad }
        NumberAnimation { target: eye; property: "open"; to: 1; duration: 260; easing.type: Easing.OutBack }
        PauseAnimation { duration: 2100 }
        NumberAnimation { target: eye; property: "open"; to: 0.06; duration: 80 }
        NumberAnimation { target: eye; property: "open"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }

    // sólo el parpadeo: 100 ms de aplastado y vuelve
    transform: Scale {
        origin.x: eye.width / 2
        origin.y: eye.height / 2
        yScale: Math.max(0.03, eye.open)
    }

    // El radio del iris se mide contra el ALTO del ojo, que es lo que lo hace
    // circular en las tres pantallas: el ancho depende de la forma del monitor,
    // el alto es siempre 0.52 del ancho y el iris siempre 0.30 del alto. Lo que
    // el párpado hace es TAPARLO, no achicarlo.
    readonly property real irisR: height * 0.30
    // Cuánto se corre el iris al mirar de costado, en pasos de un vigésimo (el
    // canvas se repinta con esto, y el tween de `gaze` dura 350 ms).
    readonly property real irisDx: Math.round(gaze * 20) / 20 * width * 0.22

    Canvas {
        id: lens
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        readonly property color stroke: eye.colour
        readonly property real aperture: eye.lidQ
        readonly property real dx: eye.irisDx
        onStrokeChanged: requestPaint()
        onApertureChanged: requestPaint()
        onDxChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height;
            if (w <= 0 || h <= 0)
                return;
            const cx = w / 2, cy = h / 2;
            c.strokeStyle = stroke;
            c.lineWidth = Math.max(1.5, h * 0.012);

            // OJO con los números: una curva cuadrática llega a la MITAD de la
            // distancia a su punto de control, así que con 1.05*h la punta caía
            // en 0.525*h — fuera del canvas, y el ojo se veía cortado arriba y
            // abajo. Con 0.94 la curva y su trazo entran justas.
            //
            // El párpado entra ACÁ: la almendra se cierra achicando su arco, y
            // como el recorte sale de esta misma curva, lo de adentro se tapa
            // con la forma del párpado en vez de aplastarse.
            const arch = h * 0.94 * aperture;
            const edge = c.lineWidth;
            function lensPath() {
                c.beginPath();
                c.moveTo(cx - w / 2 + edge, cy);
                c.quadraticCurveTo(cx, cy - arch, cx + w / 2 - edge, cy);
                c.quadraticCurveTo(cx, cy + arch, cx - w / 2 + edge, cy);
                c.closePath();
            }

            lensPath();
            c.stroke();

            c.save();
            lensPath();
            c.clip();

            const r = h * 0.30;          // el iris, siempre el mismo
            const ix = cx + dx;

            // los radios de la esclera: salen del borde del iris y se abren
            // hasta la punta de la almendra. Se achatan con el párpado porque
            // son la superficie del ojo, no el iris.
            c.globalAlpha = 0.45;
            const spokes = 44;
            for (let i = 0; i < spokes; i++) {
                const a = (i / spokes) * Math.PI * 2;
                const ca = Math.cos(a), sa = Math.sin(a);
                c.beginPath();
                c.moveTo(ix + ca * r, cy + sa * r * aperture);
                c.lineTo(cx + ca * w * 0.75, cy + sa * h * 1.2 * aperture);
                c.stroke();
            }

            // el iris: radios cortos y anillos concéntricos, TODO circular. Lo
            // que se ve de él es la tajada que deja el párpado, igual que en un
            // ojo de verdad.
            c.globalAlpha = 0.5;
            for (let i = 0; i < spokes; i++) {
                const a = (i / spokes) * Math.PI * 2;
                c.beginPath();
                c.moveTo(ix + Math.cos(a) * r * 0.22, cy + Math.sin(a) * r * 0.22);
                c.lineTo(ix + Math.cos(a) * r, cy + Math.sin(a) * r);
                c.stroke();
            }
            c.globalAlpha = 0.8;
            for (let k = 1; k <= 6; k++) {
                const rr = r * k / 6;
                c.beginPath();
                c.ellipse(ix - rr, cy - rr, rr * 2, rr * 2);
                c.stroke();
            }
            c.restore();

            c.globalAlpha = 1;
            c.lineWidth = Math.max(2, h * 0.02);
            lensPath();
            c.stroke();
        }
    }

    // La pupila: un círculo en el CENTRO del iris. Es lo único que late, y por
    // eso es lo único que queda afuera del canvas — el latido llega a 10 Hz y
    // repintar por él sería repintar siempre.
    //
    // Entra en la almendra sin recortarla: mide como mucho 0.13·h de radio y a
    // 0.22 del ancho la curva del párpado más cerrado todavía tiene 0.15·h.
    Rectangle {
        readonly property real d: eye.height
            * (0.10 + 0.05 * eye.level + 0.05 * eye.punch + 0.06 * eye.surge)
        width: d
        height: d
        radius: d / 2
        x: eye.width / 2 - d / 2 + eye.irisDx
        y: eye.height / 2 - d / 2
        color: eye.hot
        opacity: 0.92
    }
}
