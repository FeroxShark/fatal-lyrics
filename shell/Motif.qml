// fatal-lyrics — what a screen shows while the lyric is somewhere else.
//
// These run only on the screens without text, so the wall stays alive during an
// instrumental instead of going dead. They are meant to look like something a
// machine of that era would put on a tube — a scope trace, a radar sweep, a test
// card — and deliberately not like a music-player spectrum, which reads as a
// widget dropped on top rather than part of the picture.
//
// Cost rules, because two of these can be running next to a shader:
//   · shapes that never change are drawn ONCE into a canvas and then only
//     transformed. That is also what makes the motion smooth: a transform is
//     interpolated every frame, a redraw is not.
//   · line traces that must change repaint at 30 Hz, never per frame
//   · anything made of many pieces is plain rectangles moved by bindings
import QtQuick

Item {
    id: motif

    // eye | scope | radar | rain | stars | testcard | ocean | pond | none
    property string kind: "eye"
    property color colour: "#4fe8ff"
    property color hot: "#e2fdff"
    property real level: 0.35      // 0..1 volumen
    // El volumen llega a 14 Hz: atado directo al brillo o al tamaño, eso no se
    // ve como "respira", se ve como que titila. Acá se suaviza a la velocidad a
    // la que uno percibe que un tema sube, no a la que se mueve la onda.
    Behavior on level { NumberAnimation { duration: 420; easing.type: Easing.OutQuad } }
    property real low: 0.4         // energía de graves
    property real high: 0.3        // energía de agudos
    property int beat: 0           // contador de golpes
    // cuánto se nota cada golpe (lo gradúa `flicker`): 0 = la animación sigue
    // viva, pero no pega un salto en cada bombo
    property real beatAmt: 1
    property real clock: 0         // reloj del tubo, en segundos
    property bool spinning: true   // false = quieto (pantalla apagada)
    // cuánto empuja la parte del tema (silencio ≈ 0.45, estribillo ≈ 1.6): las
    // animaciones se aquietan o se aceleran con la canción, no con el reloj
    property real energy: 1.0
    // cuánta agua se mueve (perilla `water_amp`): la ola del mar y el temblor
    // del laguito. El resto de los motivos no la usa.
    property real waterAmp: 0.55
    // registro de lo que suena (0 grave .. 1 agudo): la frecuencia a la que
    // vibra el laguito
    property real pitch: 0.5
    // El golpe del tubo: cuando la pantalla parpadea, la animación ACOMPAÑA —
    // se acelera y crece un instante. Sin esto el parpadeo es una luz que se
    // mueve sola; con esto es el golpe de la canción atravesando todo.
    // `kick` es un contador: cada vez que sube, se dispara el empujón.
    property int kick: 0
    property real surge: 0
    onKickChanged: {
        surgeDecay.stop();
        surge = 1;
        surgeDecay.start();
    }
    NumberAnimation {
        id: surgeDecay
        target: motif
        property: "surge"
        to: 0
        duration: 460
        easing.type: Easing.OutQuad
    }

    opacity: Math.min(0.62 + 0.30 * surge, 1)

    // pulso del golpe: sube de un saque y baja solo
    property real punch: 0
    NumberAnimation on punch {
        id: punchDecay
        running: false
        to: 0
        duration: 380
        easing.type: Easing.OutQuad
    }
    onBeatChanged: {
        if (motif.beatAmt <= 0.01)
            return;
        punchDecay.stop();
        punch = motif.beatAmt;
        punchDecay.start();
    }

    readonly property real span: Math.min(width, height)
    // velocidad efectiva: la parte del tema, más el empujón del golpe
    readonly property real drive: energy * (1 + 1.6 * surge)

    // y un tirón de tamaño, corto, para que el golpe se vea y no sólo se acelere
    transform: Scale {
        origin.x: motif.width / 2
        origin.y: motif.height / 2
        xScale: 1 + 0.05 * motif.surge
        yScale: 1 + 0.05 * motif.surge
    }

    // ------------------------------------------------------------------- ojo
    // Ojo de alambre como el de la pantalla del videoclip: lente en punta, malla
    // de radios y anillos concéntricos. Se dibuja una vez y se lo transforma —
    // abrir el párpado es escalar en vertical, la pupila late.
    Item {
        id: eye
        anchors.centerIn: parent
        width: motif.span * 0.78
        height: width * 0.52
        visible: motif.kind === "eye"

        property real open: 0
        onVisibleChanged: {
            if (visible) {
                open = 0;
                openAnim.restart();
            }
        }
        Component.onCompleted: if (visible) openAnim.start()
        NumberAnimation {
            id: openAnim
            target: eye
            property: "open"
            to: 1
            duration: 850
            easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            running: eye.visible && motif.spinning
            loops: Animation.Infinite
            PauseAnimation { duration: 3400 }
            NumberAnimation { target: eye; property: "open"; to: 0.06; duration: 90; easing.type: Easing.InQuad }
            NumberAnimation { target: eye; property: "open"; to: 1; duration: 260; easing.type: Easing.OutBack }
            PauseAnimation { duration: 2100 }
            NumberAnimation { target: eye; property: "open"; to: 0.06; duration: 80 }
            NumberAnimation { target: eye; property: "open"; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }

        transform: Scale {
            origin.x: eye.width / 2
            origin.y: eye.height / 2
            yScale: eye.open
        }

        // Lente, malla e iris van TODOS en el mismo canvas: dibujados por
        // separado, los anillos quedaban corridos del centro de la lente y se
        // notaba enseguida.
        Canvas {
            id: lens
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative
            readonly property color stroke: motif.colour
            onStrokeChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const c = getContext("2d");
                c.reset();
                const w = width, h = height;
                const cx = w / 2, cy = h / 2;
                c.strokeStyle = stroke;
                c.lineWidth = Math.max(1.5, h * 0.012);

                // OJO con los números: una curva cuadrática llega a la MITAD de
                // la distancia a su punto de control, así que con 1.05*h la punta
                // caía en 0.525*h — fuera del canvas, y el ojo se veía cortado
                // arriba y abajo. Con 0.94 la curva y su trazo entran justas.
                const arch = h * 0.94;
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

                // radios desde el iris hasta el borde
                c.globalAlpha = 0.5;
                const spokes = 44;
                for (let i = 0; i < spokes; i++) {
                    const a = (i / spokes) * Math.PI * 2;
                    c.beginPath();
                    c.moveTo(cx + Math.cos(a) * h * 0.17, cy + Math.sin(a) * h * 0.17);
                    c.lineTo(cx + Math.cos(a) * w * 0.75, cy + Math.sin(a) * h * 1.2);
                    c.stroke();
                }

                // anillos del iris, concéntricos con la lente
                c.globalAlpha = 0.8;
                for (let k = 1; k <= 7; k++) {
                    const r = h * 0.06 * k;
                    c.beginPath();
                    c.ellipse(cx - r, cy - r, r * 2, r * 2);
                    c.stroke();
                }
                c.restore();

                c.globalAlpha = 1;
                c.lineWidth = Math.max(2, h * 0.02);
                lensPath();
                c.stroke();
            }
        }

        // pupila: lo único que se mueve aparte, clavada al centro exacto
        Rectangle {
            width: eye.height * (0.10 + 0.05 * motif.level + 0.05 * motif.punch + 0.06 * motif.surge)
            height: width
            radius: width / 2
            x: (eye.width - width) / 2
            y: (eye.height - height) / 2
            color: motif.hot
            opacity: 0.92
        }
    }

    // ------------------------------------------------------------ osciloscopio
    // Figura de Lissajous, la que dejaba un osciloscopio de laboratorio: la
    // relación entre los dos ejes se mueve con graves y agudos, así que la figura
    // se abre y se retuerce con la música sin ser "barritas".
    Canvas {
        id: scope
        anchors.centerIn: parent
        width: motif.span * 0.7
        height: width
        visible: motif.kind === "scope"
        renderStrategy: Canvas.Cooperative

        property real phase: 0
        onPhaseChanged: requestPaint()

        Timer {
            interval: 33          // 30 Hz: una traza no necesita más
            repeat: true
            running: scope.visible && motif.spinning
            onTriggered: scope.phase = motif.clock
        }

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height;
            const cx = w / 2, cy = h / 2;
            const rx = w * 0.42, ry = h * 0.42;
            const a = 3 + Math.round(motif.low * 3);
            const b = 2 + Math.round(motif.high * 4);
            const d = phase * 0.6;
            const amp = 0.75 + 0.25 * motif.level;
            c.strokeStyle = motif.colour;
            c.lineWidth = Math.max(1.5, w * 0.006 * (1 + motif.punch + motif.surge));
            c.beginPath();
            for (let i = 0; i <= 220; i++) {
                const t = i / 220 * Math.PI * 2;
                const x = cx + Math.sin(a * t + d) * rx * amp;
                const y = cy + Math.sin(b * t) * ry * amp;
                if (i === 0)
                    c.moveTo(x, y);
                else
                    c.lineTo(x, y);
            }
            c.stroke();

            // el punto del haz, corriendo por la traza
            const t2 = (phase * 1.7 % 1) * Math.PI * 2;
            const px = cx + Math.sin(a * t2 + d) * rx * amp;
            const py = cy + Math.sin(b * t2) * ry * amp;
            c.fillStyle = motif.hot;
            c.beginPath();
            c.ellipse(px - w * 0.012, py - w * 0.012, w * 0.024, w * 0.024);
            c.fill();
        }
    }

    // ------------------------------------------------------------------ radar
    // Barrido de sonar: la aguja gira (puro transform, suavísimo) y los ecos se
    // encienden con los golpes.
    Item {
        id: radar
        anchors.centerIn: parent
        width: motif.span * 0.72
        height: width
        visible: motif.kind === "radar"

        Repeater {
            model: radar.visible ? 4 : 0

            Rectangle {
                required property int index
                anchors.centerIn: parent
                width: radar.width * (0.25 + index * 0.25)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, radar.width * 0.004)
                border.color: motif.colour
                opacity: 0.45
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: radar.width
            height: Math.max(1, radar.width * 0.003)
            color: motif.colour
            opacity: 0.35
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(1, radar.width * 0.003)
            height: radar.height
            color: motif.colour
            opacity: 0.35
        }

        // la aguja
        Item {
            anchors.centerIn: parent
            width: radar.width
            height: radar.height
            rotation: motif.clock * (38 + 22 * motif.level) * motif.drive

            Rectangle {
                x: parent.width / 2
                y: parent.height / 2 - height / 2
                width: parent.width / 2
                height: Math.max(2, radar.width * 0.006)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: motif.hot }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        // ecos que aparecen con el golpe
        Repeater {
            model: radar.visible ? 5 : 0

            Rectangle {
                required property int index
                readonly property real ang: index * 2.31
                readonly property real rad: radar.width * (0.16 + (index % 3) * 0.14)
                x: radar.width / 2 + Math.cos(ang) * rad - width / 2
                y: radar.height / 2 + Math.sin(ang) * rad - height / 2
                width: radar.width * (0.02 + 0.02 * motif.punch)
                height: width
                radius: width / 2
                color: motif.hot
                opacity: 0.25 + 0.7 * motif.punch
            }
        }
    }

    // ----------------------------------------------------------------- lluvia
    // Columnas de caracteres cayendo, como un volcado de datos. Cada columna es
    // un Text largo que baja: se mueve por binding, no se redibuja el texto.
    Item {
        id: rain
        anchors.fill: parent
        visible: motif.kind === "rain"
        clip: true

        readonly property int columns: Math.max(6, Math.round(width / (motif.span * 0.09)))

        Repeater {
            model: rain.visible ? rain.columns : 0

            Text {
                id: drop
                required property int index
                readonly property real speed: (0.35 + (index % 5) * 0.12 + motif.level * 0.5) * motif.drive
                x: index * rain.width / rain.columns
                width: rain.width / rain.columns
                text: {
                    const chars = "01∎▓░╳ΔΣ¥§#*+=<>";
                    let out = "";
                    for (let i = 0; i < 22; i++)
                        out += chars[(index * 7 + i * 13) % chars.length] + "\n";
                    return out;
                }
                color: index % 4 === 0 ? motif.hot : motif.colour
                opacity: 0.35 + 0.4 * motif.level
                font.pixelSize: Math.round(motif.span * 0.055)
                font.family: "monospace"
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 0.95
                y: ((motif.clock * speed * motif.span * 0.5) % (implicitHeight + rain.height)) - implicitHeight
            }
        }
    }

    // ------------------------------------------------------------ hiperespacio
    // Puntos que salen del centro y se estiran: profundidad, y acelera con el
    // volumen. Todo rectángulos movidos por bindings, cero dibujo.
    Item {
        id: stars
        anchors.fill: parent
        visible: motif.kind === "stars"

        Repeater {
            model: stars.visible ? 46 : 0

            Rectangle {
                required property int index
                readonly property real ang: index * 2.399963      // ángulo áureo: reparte parejo
                readonly property real phase: (motif.clock * (0.22 + 0.5 * motif.level) * motif.drive
                    + index / 46) % 1
                readonly property real dist: phase * motif.span * 0.75
                x: stars.width / 2 + Math.cos(ang) * dist - width / 2
                y: stars.height / 2 + Math.sin(ang) * dist - height / 2
                width: Math.max(2, motif.span * 0.006 + dist * 0.03)
                height: Math.max(2, motif.span * 0.005)
                radius: height / 2
                rotation: ang * 180 / Math.PI
                color: index % 7 === 0 ? motif.hot : motif.colour
                opacity: phase * (0.8 - 0.4 * phase)
            }
        }
    }

    // -------------------------------------------------------- carta de ajuste
    // El patrón de prueba que quedaba en el aire cuando terminaba la
    // programación: círculo, rejilla y escalera de grises, con la aguja girando.
    Item {
        id: card
        anchors.centerIn: parent
        width: motif.span * 0.8
        height: width * 0.75
        visible: motif.kind === "testcard"

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: Math.max(2, card.width * 0.005)
            border.color: motif.colour
            opacity: 0.6
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.height * 0.86
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(2, card.width * 0.006)
            border.color: motif.colour
            opacity: 0.75
        }

        Repeater {
            model: card.visible ? 6 : 0
            Rectangle {
                required property int index
                x: card.width * (index + 1) / 7
                width: Math.max(1, card.width * 0.002)
                height: card.height
                color: motif.colour
                opacity: 0.25
            }
        }
        Repeater {
            model: card.visible ? 4 : 0
            Rectangle {
                required property int index
                y: card.height * (index + 1) / 5
                width: card.width
                height: Math.max(1, card.width * 0.002)
                color: motif.colour
                opacity: 0.25
            }
        }

        // escalera de grises que late con los graves
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: card.height * 0.08 }
            height: card.height * 0.1
            spacing: 0

            Repeater {
                model: card.visible ? 8 : 0
                Rectangle {
                    required property int index
                    width: card.width * 0.6 / 8
                    height: card.height * 0.1
                    color: motif.colour
                    opacity: (index + 1) / 9 * (0.5 + 0.5 * motif.low)
                }
            }
        }

        // la aguja: gira siempre, es lo que evita que la carta parezca una foto
        Item {
            anchors.centerIn: parent
            width: card.height * 0.86
            height: width
            rotation: motif.clock * 24 * motif.drive

            Rectangle {
                x: parent.width / 2
                y: parent.height / 2 - height / 2
                width: parent.width / 2
                height: Math.max(2, card.width * 0.008)
                color: motif.hot
                opacity: 0.85
            }
        }
    }

    // ------------------------------------------------------------------- agua
    // Los dos motivos de agua son los únicos que no están hechos de items: son
    // miles de puntos con física propia y eso sólo cierra en la GPU (ver
    // `ocean.frag` y `pond.frag`). Por Loader, para que el shader ni exista
    // mientras la pantalla muestra otra cosa.
    //
    //   ocean = un mar en perspectiva, olas que vienen de lejos
    //   pond  = un plato de agua que TIEMBLA a la frecuencia de lo que suena
    Loader {
        anchors.fill: parent
        active: motif.kind === "ocean"
        visible: active

        sourceComponent: Ocean {
            colour: motif.colour
            crest: motif.hot
            level: motif.level
            low: motif.low
            high: motif.high
            beat: motif.beat
            beatAmt: motif.beatAmt
            energy: motif.energy * (1 + 0.5 * motif.surge)
            amp: motif.waterAmp
            running: motif.spinning
        }
    }

    Loader {
        anchors.fill: parent
        active: motif.kind === "pond"
        visible: active

        sourceComponent: Pond {
            colour: motif.colour
            crest: motif.hot
            level: motif.level
            low: motif.low
            high: motif.high
            pitch: motif.pitch
            beat: motif.beat
            beatAmt: motif.beatAmt
            energy: motif.energy * (1 + 0.5 * motif.surge)
            amp: motif.waterAmp
            running: motif.spinning
        }
    }
}
