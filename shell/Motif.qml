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

    // eye | scope | radar | rain | stars | testcard | ocean | pond | dunes
    // | static | textsea | eyes | ekg | rorschach | plasma | tunnel | none
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
    // La semilla de ESTA aparición (el `motifGen` de la pared cruzado con el
    // número de pantalla). Los motivos que arman un paisaje la usan para que
    // nunca salga dos veces el mismo: sin ella, el mismo dibujo aparecería
    // idéntico cada 25 segundos.
    property real seed: 0
    // `crt.quality`: un motivo no puede bajarle los cuadros a la pantalla
    // enfocada, así que los que dibujan muchas cosas achican la cuenta acá.
    property real quality: 1.0
    // El compás, para los motivos que se mueven POR COMPÁS y no por reloj:
    // `tick` es el contador de tiempos del root (no el de bombos), `beatMs` lo
    // que dura uno y `bpmLive` si hay que creerles.
    property int tick: 0
    property real beatMs: 500
    property bool bpmLive: false
    // en qué verso va el tema (índice dentro de la letra entera; -1 = no se
    // sabe) y la primera palabra de la línea que VIENE. Los usa la estática
    // para formar algo que signifique alguna cosa.
    property int lineNo: -1
    property string nextWord: ""
    // la letra entera del tema, y si tiene tiempos. La marea de texto la hace
    // correr; sin tiempos corre igual pero sin resaltar ninguna línea.
    property var lines: []
    property bool linesSynced: true
    property string fontFamily: "monospace"
    // Hacia dónde miran los ojos: -1 a la izquierda, 0 al frente, 1 a la
    // derecha. Lo decide Crt.qml, que es el único que sabe dónde está la frase.
    property real gaze: 0
    // ¿el tema está en un drop? Llega como booleano y NO como umbral sobre
    // `energy`: la energía viene multiplicada por el aviso del salto, así que
    // un umbral acá se dispararía al final de cualquier verso.
    property bool drop: false
    // en qué parte del tema va (quiet | verse | build | drop). El osciloscopio
    // la usa para elegir la relación entre sus dos ejes: es lo que cambia la
    // figura al pasar del verso al estribillo.
    property string section: "verse"
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

    // El aviso de a dónde salta la frase (T2.1) apaga un poco las pantallas que
    // NO son el destino. Va como factor aparte y no pisando `opacity` desde
    // afuera: asignarle un binding nuevo desde Crt.qml se llevaría puesto el
    // acompañamiento del golpe (`surge`), que es lo que hace que la pared
    // entera pegue junta.
    property real dim: 1
    Behavior on dim { NumberAnimation { duration: 380; easing.type: Easing.OutQuad } }

    opacity: Math.min(0.62 + 0.30 * surge, 1) * dim

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

    // T3.A1: cuánto más grande que la pantalla es este item. El motivo se
    // dibuja siempre para el zoom más lejano de la cámara (`Crt.overscan`), y
    // eso es lo que hace que lo que va a sangre no deje borde. Pero las
    // figuras centradas se miden contra la PANTALLA y no contra la caja: si
    // `span` creciera con el overscan, el ojo y la carta de ajuste saldrían un
    // 22 % más grandes y en el drop quedarían recortados.
    property real overscan: 1
    readonly property real span: Math.min(width, height) / overscan
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
    // El dibujo vive en `Eye.qml`: es el mismo ojo que usa la grilla del motivo
    // `eyes`, sólo que acá va uno solo y del tamaño de la pantalla.
    Eye {
        anchors.centerIn: parent
        width: motif.span * 0.78
        height: width * 0.52
        visible: motif.kind === "eye"
        colour: motif.colour
        hot: motif.hot
        level: motif.level
        punch: motif.punch
        surge: motif.surge
        blinking: motif.spinning
    }

    // ------------------------------------------------------------------ ojos
    // La misma lente, chiquita y repetida: una grilla de ojos que miran todos
    // hacia la pantalla donde está la frase (y se dan vuelta cuando la frase
    // avisa que se va a otra).
    //
    // Por Loader y no siempre viva: la grilla son hasta quince ojos y cada ojo
    // es un Canvas. Quince Canvas invisibles pesan lo mismo que quince Canvas
    // visibles a la hora de existir, y la pantalla muestra otra cosa el 90 % del
    // tiempo.
    Loader {
        anchors.fill: parent
        active: motif.kind === "eyes"
        visible: active

        sourceComponent: Eyes {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            punch: motif.punch
            surge: motif.surge
            gaze: motif.gaze
            kick: motif.kick
            seed: motif.seed
            running: motif.spinning
        }
    }

    // ------------------------------------------------------------ osciloscopio
    // La figura de Lissajous de un osciloscopio de laboratorio: dos senos, uno
    // por eje. Lo que se ve no es el dibujo sino la RELACIÓN entre las dos
    // frecuencias — si es un número redondo la figura se cierra y queda quieta,
    // y si no, gira y no cierra nunca.
    //
    // Con tempo confiable la relación sale de la parte del tema (1 en el
    // silencio, 3/2 en la estrofa, 4/3 en el puente, 2 en el drop) y la figura
    // CIERRA: es una figura estable que da una vuelta por compás. Sin tempo la
    // relación deriva sola y la figura no cierra: caos, que es exactamente lo
    // que hacía un osciloscopio con una señal que no enganchaba.
    //
    // La fase y la deriva se ACUMULAN, no salen de multiplicar el reloj: el
    // reloj vale miles de segundos y cualquier cambio de tempo pegaría un salto
    // de la figura entera (la misma trampa del hiperespacio y del túnel).
    Canvas {
        id: scope
        anchors.centerIn: parent
        width: motif.span * 0.7
        height: width
        visible: motif.kind === "scope"
        renderStrategy: Canvas.Cooperative

        // la relación entre los ejes, por parte del tema; el tween es lo que
        // hace que la figura se transforme en vez de cambiar de golpe
        readonly property real target: motif.section === "quiet" ? 1
            : motif.section === "build" ? (4 / 3)
            : motif.section === "drop" ? 2 : 1.5
        property real ratio: target
        Behavior on ratio { NumberAnimation { duration: 600; easing.type: Easing.InOutCubic } }

        // cuántas vueltas hay que dibujar para que cierre: el denominador de la
        // relación (3/2 cierra en dos, 4/3 en tres)
        readonly property int turns: !motif.bpmLive ? 3
            : (Math.abs(ratio - 1.5) < 0.02 ? 2 : (Math.abs(ratio - 4 / 3) < 0.02 ? 3 : 1))

        property real phase: 0        // el giro de la figura: una vuelta por compás
        property real wobble: 0       // la deriva de la relación cuando no hay tempo

        Timer {
            interval: 33          // 30 Hz: una traza no necesita más
            repeat: true
            running: scope.visible && motif.spinning
            onTriggered: {
                const dt = 0.033;
                const bar = Math.max(motif.beatMs, 120) * 4 / 1000;
                scope.phase = (scope.phase + dt / bar * Math.PI * 2) % (Math.PI * 2);
                scope.wobble += dt;
                scope.requestPaint();
            }
        }

        onVisibleChanged: if (visible) requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const c = getContext("2d");
            c.reset();
            const w = width, h = height;
            if (w <= 0 || h <= 0)
                return;
            const cx = w / 2, cy = h / 2;
            const rx = w * 0.42, ry = h * 0.42;
            const amp = 0.55 + 0.40 * motif.level;
            // sin tempo la relación se va sola: la figura no cierra
            const b = ratio + (motif.bpmLive ? 0 : 0.06 * Math.sin(wobble * 0.8));
            const steps = Math.max(140, Math.round(240 * turns * Math.max(motif.quality, 0.5)));

            c.strokeStyle = motif.colour;
            c.lineWidth = Math.max(1.5, w * 0.006 * (1 + motif.punch + motif.surge));
            c.lineJoin = "round";
            c.beginPath();
            for (let i = 0; i <= steps; i++) {
                const t = i / steps * Math.PI * 2 * turns;
                const x = cx + Math.sin(t + phase) * rx * amp;
                const y = cy + Math.sin(b * t) * ry * amp;
                if (i === 0)
                    c.moveTo(x, y);
                else
                    c.lineTo(x, y);
            }
            c.stroke();

            // el punto del haz, corriendo por la traza
            const t2 = (wobble * 1.1 % 1) * Math.PI * 2 * turns;
            const px = cx + Math.sin(t2 + phase) * rx * amp;
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
    // Puntos que salen del centro y se estiran. En el drop el salto: aceleran,
    // la estela se alarga y vira al color caliente; en la calma casi se paran y
    // el cielo queda quieto.
    //
    // La distancia se ACUMULA cuadro a cuadro y no sale de multiplicar el reloj
    // por la velocidad: el reloj vale miles de segundos, así que cualquier
    // cambio de velocidad (y el drop es el más grande de todos) saltaría
    // multiplicado y las estrellas se teletransportarían enteras.
    Item {
        id: stars
        anchors.fill: parent
        visible: motif.kind === "stars"

        // el salto al hiperespacio: entra y sale con rampa, nunca de golpe
        property real warp: motif.drop ? 1 : 0
        Behavior on warp { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        // en la calma casi se paran: un cielo que se arrastra es lo que hace
        // que después el drop se sienta
        readonly property real speed: (motif.level < 0.12 && !motif.drop
            ? 0.04 : 0.22 + 0.5 * motif.level) * motif.drive * (1 + 3 * stars.warp)

        property real travel: 0
        FrameAnimation {
            running: stars.visible && motif.spinning
            onTriggered: stars.travel += frameTime * stars.speed
        }

        Repeater {
            model: stars.visible ? 46 : 0

            Rectangle {
                required property int index
                readonly property real ang: index * 2.399963      // ángulo áureo: reparte parejo
                readonly property real phase: (stars.travel + index / 46) % 1
                readonly property real dist: phase * motif.span * 0.75
                x: stars.width / 2 + Math.cos(ang) * dist - width / 2
                y: stars.height / 2 + Math.sin(ang) * dist - height / 2
                // la estela: en el hiperespacio el punto deja de ser un punto
                width: Math.max(2, motif.span * 0.006 + dist * 0.03 * (1 + 4 * stars.warp))
                height: Math.max(2, motif.span * 0.005)
                radius: height / 2
                rotation: ang * 180 / Math.PI
                color: index % 7 === 0 ? motif.hot
                    : Qt.tint(motif.colour, Qt.rgba(motif.hot.r, motif.hot.g,
                                                    motif.hot.b, 0.75 * stars.warp))
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

    // ----------------------------------------------------------------- arena
    // Las dunas son el desierto del mar: la misma técnica de puntos en
    // perspectiva (`dunes.frag`), pero el paisaje está quieto y lo que se
    // mueve es la cámara. Cada golpe es un pisotón que levanta la arena; en el
    // drop la arena se queda flotando.
    Loader {
        anchors.fill: parent
        active: motif.kind === "dunes"
        visible: active

        sourceComponent: Dunes {
            colour: motif.colour
            crest: motif.hot
            level: motif.level
            high: motif.high
            beat: motif.beat
            beatAmt: motif.beatAmt
            energy: motif.energy * (1 + 0.5 * motif.surge)
            quality: motif.quality
            seed: motif.seed
            drop: motif.drop
            running: motif.spinning
        }
    }

    // ----------------------------------------------------------- cardiograma
    // El monitor de hospital: la traza se ESCRIBE de izquierda a derecha y el
    // cursor borra la vuelta anterior. Va por Loader como los demás: son 240
    // muestras y un Canvas, y no tiene por qué existir mientras la pantalla
    // muestra otra cosa.
    Loader {
        anchors.fill: parent
        active: motif.kind === "ekg"
        visible: active

        sourceComponent: Ekg {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            beat: motif.beat
            beatAmt: motif.beatAmt
            tick: motif.tick
            bpmLive: motif.bpmLive
            quality: motif.quality
            seed: motif.seed
            running: motif.spinning
        }
    }

    // ---------------------------------------------------------------- mancha
    // La lámina de Rorschach: ruido umbralizado y simétrico (`rorschach.frag`).
    // El umbral baja con el volumen, así que la mancha CRECE con la canción en
    // vez de sólo aclararse.
    Loader {
        anchors.fill: parent
        active: motif.kind === "rorschach"
        visible: active

        sourceComponent: Rorschach {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            pitch: motif.pitch
            seed: motif.seed
            energy: motif.energy
            kick: motif.kick
            running: motif.spinning
        }
    }

    // ---------------------------------------------------------------- plasma
    // La lámpara de lava: bolas de campo que se funden entre sí
    // (`plasma.frag`). Los graves las empujan para arriba y el golpe del tubo
    // les hace temblar la superficie.
    Loader {
        anchors.fill: parent
        active: motif.kind === "plasma"
        visible: active

        sourceComponent: Plasma {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            low: motif.low
            surge: motif.surge
            energy: motif.energy
            seed: motif.seed
            quality: motif.quality
            running: motif.spinning
        }
    }

    // ----------------------------------------------------------------- túnel
    // Anillos que vienen de frente (`tunnel.frag`). La distancia viajada se
    // acumula adentro de `Tunnel.qml`: multiplicar el reloj por la velocidad
    // haría saltar todos los anillos en cada cambio de volumen.
    Loader {
        anchors.fill: parent
        active: motif.kind === "tunnel"
        visible: active

        sourceComponent: Tunnel {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            pitch: motif.pitch
            energy: motif.energy
            seed: motif.seed
            running: motif.spinning
        }
    }

    // -------------------------------------------------------------- estática
    // La pantalla sin señal que una vez por compás casi engancha algo. El ruido
    // y la máscara viven en `static.frag`.
    Loader {
        anchors.fill: parent
        active: motif.kind === "static"
        visible: active

        sourceComponent: Static {
            overscan: motif.overscan
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            high: motif.high
            seed: motif.seed
            tick: motif.tick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            lineNo: motif.lineNo
            nextWord: motif.nextWord
            fontFamily: motif.fontFamily
            running: motif.spinning
        }
    }

    // ------------------------------------------------------- marea de texto
    // La letra entera subiendo como los créditos del final, con el verso que
    // suena encendido al pasar.
    Loader {
        anchors.fill: parent
        active: motif.kind === "textsea"
        visible: active

        sourceComponent: TextSea {
            overscan: motif.overscan
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            lines: motif.lines
            synced: motif.linesSynced
            lineNo: motif.lineNo
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            fontFamily: motif.fontFamily
            seed: motif.seed
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
