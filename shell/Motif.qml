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
    // ---- T4.3: la amplitud del latido, que la gradúa `pace` desde el root.
    // Los números viven en UNA tabla (`crtPaceTable`, shell.qml) y llegan acá
    // como properties: repartidos por los archivos, `wild` — que tiene que
    // devolver exactamente lo de antes — no se podría verificar.
    property real opaMin: 0.62     // opacidad en reposo
    property real opaSpan: 0.30    // cuánto sube en el golpe
    property real scaleAmt: 0.05   // el tirón de tamaño del golpe
    property real surgeK: 1.6      // cuánto acelera el golpe
    property real driveMin: 0.0    // y el piso y el techo de esa aceleración
    property real driveMax: 99
    property real driveDrop: 99

    property real level: 0.35      // 0..1 volumen
    // El volumen llega a 14 Hz: atado directo al brillo o al tamaño, eso no se
    // ve como "respira", se ve como que titila. Acá se suaviza a la velocidad a
    // la que uno percibe que un tema sube, no a la que se mueve la onda.
    Behavior on level { NumberAnimation { duration: Motion.levelMs; easing.type: Easing.OutQuad } }
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
    // el nombre del tema, para el rótulo de la carta de ajuste. Vacío = el
    // tubo no sabe qué suena y la carta dice el nombre del programa.
    property string title: ""
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
    // NO son el destino, y el aro (T3.A5) las apaga del todo: por pantalla se
    // ve UNA animación, nunca el aro contando encima de un dibujo. Va como
    // factor aparte y no pisando `opacity` desde afuera: asignarle un binding
    // nuevo desde Crt.qml se llevaría puesto el acompañamiento del golpe
    // (`surge`), que es lo que hace que la pared entera pegue junta.
    //
    // Los 220 ms son los del apagado del aro: más largo y el aro cuenta un
    // tiempo entero con el motivo todavía visible debajo.
    property real dim: 1
    Behavior on dim { NumberAnimation { duration: Motion.dimMs; easing.type: Easing.OutQuad } }

    // El PUENTE entre un dibujo y el siguiente (T4.3). Va aparte de `dim` a
    // propósito: `dim` tiene Behavior, así que el cambio de `kind` caería con
    // el dibujo viejo todavía a media luz. Acá no hay Behavior — la curva es
    // la que manda Crt.qml y nada más.
    property real swap: 1

    opacity: Math.min(opaMin + opaSpan * surge, 1) * dim * swap

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

    // T4.3: cada cuánto tiene DERECHO a moverse un dibujo, en segundos.
    //
    // Los motivos con física propia corren con un `FrameAnimation`, que va al
    // refresh del monitor — 200 Hz en uno de los de prueba. Ya acumulaban el
    // `frameTime` y sólo escribían su reloj cada 14.2 ms (70 Hz), que es un
    // número inventado; acá pasa a ser 60 Hz de verdad, y 30 cuando la pantalla
    // está en el piso de volumen (nadie distingue 30 de 60 en una animación de
    // fondo que se mueve sola). Cada escritura del reloj es un uniform nuevo
    // para el shader o un repintado del Canvas: la mitad de escrituras es la
    // mitad de ese trabajo.
    readonly property real stepMin: (!spinning || level <= 0.12) ? (1 / 30) : (1 / 60)

    // El lado corto de la pantalla: la medida de toda figura centrada (el ojo,
    // el osciloscopio, la carta de ajuste). T4.1: el item mide exactamente lo
    // que mide la pantalla, así que es una división menos — hasta la tanda 3
    // esto descontaba el overscan de la cámara, que ya no existe.
    readonly property real span: Math.min(width, height)
    // Velocidad efectiva: la parte del tema, más el empujón del golpe, ACOTADA.
    // Sin el piso y el techo iba de 0.45× a 6.7× dentro de un mismo tema: eso
    // no se lee como "la animación acompaña", se lee como que la animación es
    // otra. La referencia de fluidez pide deriva de velocidad UNIFORME con un
    // latido chico encima; el drop es lo único que puede empujar de verdad.
    readonly property real drive: Math.max(driveMin, Math.min(
        energy * (1 + surgeK * surge), drop ? driveDrop : driveMax))

    // y un tirón de tamaño, corto, para que el golpe se vea y no sólo se acelere
    transform: Scale {
        origin.x: motif.width / 2
        origin.y: motif.height / 2
        xScale: 1 + motif.scaleAmt * motif.surge
        yScale: 1 + motif.scaleAmt * motif.surge
    }

    // T3.A2: UN solo dibujo por pantalla, garantizado por construcción.
    //
    // Hasta acá cada motivo era un item con su propio `visible` (los seis
    // viejos) o su propio `active` (los diez por Loader), y alcanzaba que uno
    // se quedara prendido para que se vieran dos encima — el agua sin recortar
    // sobre otra animación. Ahora el que elige es UN Loader: `sourceComponent`
    // es una property sola, así que dos componentes no pueden estar vivos a la
    // vez ni por un cuadro. El `clip` es la otra mitad de la garantía: nada
    // pinta fuera de la caja del motivo.
    //
    // De paso deja de existir lo que no se ve: el ojo, el osciloscopio, el
    // radar, la lluvia, el hiperespacio y la carta de ajuste estaban SIEMPRE
    // instanciados, seis dibujos por pantalla con cinco invisibles.
    Loader {
        anchors.fill: parent
        clip: true
        sourceComponent: motif.kind === "eye" ? eyeC
            : motif.kind === "eyes" ? eyesC
            : motif.kind === "scope" ? scopeC
            : motif.kind === "radar" ? radarC
            : motif.kind === "rain" ? rainC
            : motif.kind === "stars" ? starsC
            : motif.kind === "testcard" ? testcardC
            : motif.kind === "ocean" ? oceanC
            : motif.kind === "pond" ? pondC
            : motif.kind === "dunes" ? dunesC
            : motif.kind === "ekg" ? ekgC
            : motif.kind === "rorschach" ? rorschachC
            : motif.kind === "plasma" ? plasmaC
            : motif.kind === "tunnel" ? tunnelC
            : motif.kind === "static" ? staticC
            : motif.kind === "textsea" ? textseaC
            : null
    }

    // ------------------------------------------------------------------- ojo
    // El dibujo vive en `Eye.qml`: es el mismo ojo que usa la grilla del motivo
    // `eyes`, sólo que acá va uno solo y del tamaño de la pantalla.
    Component {
        id: eyeC

        Item {
            Eye {
                anchors.centerIn: parent
                width: motif.span * 0.78
                height: width * 0.52
                colour: motif.colour
                hot: motif.hot
                level: motif.level
                punch: motif.punch
                surge: motif.surge
                blinking: motif.spinning
            }
        }
    }

    // ------------------------------------------------------------------ ojos
    // La misma lente: uno grande que mira a la pantalla donde está la frase (y
    // se da vuelta cuando la frase avisa que se va a otra) más dos o tres
    // chicos en los bordes, que van y vienen. La grilla de quince copias se
    // sacó en la tanda 3 (B3).
    //
    // Son cuatro Canvas como mucho y existen sólo mientras el Loader tiene
    // puesta la grilla, que es lo que hace que no pesen el 90 % del tiempo en
    // que la pantalla muestra otra cosa.
    Component {
        id: eyesC

        Eyes {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            punch: motif.punch
            surge: motif.surge
            gaze: motif.gaze
            kick: motif.kick
            seed: motif.seed
            drop: motif.drop
            // la misma regla que el ojo solo y el osciloscopio: lo que va
            // CENTRADO se mide contra el lado corto de la pantalla
            span: motif.span
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
    Component {
        id: scopeC

        Item {
            Canvas {
                id: scope
                anchors.centerIn: parent
                // T4.3b: la figura ocupaba un tercio del ancho de la vertical y
                // se leía como un garabato en el medio de una pantalla vacía.
                // La caja es CUADRADA y sale del lado corto: la misma figura en
                // las tres pantallas, y entra dentro del 92 % en las dos formas.
                width: motif.span * 0.86
                height: width
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
                    // T4.3b: la amplitud de REPOSO también tiene que llenar la
                    // caja. Con 0.55 y el player parado (`level` en el piso) la
                    // figura quedaba a la mitad de su propio marco.
                    const amp = 0.78 + 0.20 * motif.level;
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
        }
    }

    // ------------------------------------------------------------------ radar
    // Barrido de sonar: la aguja gira (puro transform, suavísimo) y los ecos se
    // encienden con los golpes.
    Component {
        id: radarC

        Item {
            Item {
                id: radar
                anchors.centerIn: parent
                width: motif.span * 0.72
                height: width

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
        }
    }

    // ----------------------------------------------------------------- lluvia
    // Columnas de caracteres cayendo, como un volcado de datos. Cada columna es
    // un Text largo que baja: se mueve por binding, no se redibuja el texto.
    Component {
        id: rainC

        Item {
            id: rain
            anchors.fill: parent
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
    Component {
        id: starsC

        Item {
            id: stars
            anchors.fill: parent

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

            // T4.3b: eran 46 y en la cara clara del tubo se leían como cuatro
            // puntos. La densidad y el brillo son lo que hace que un campo de
            // estrellas sea un campo: 46 puntos repartidos por fase dejan la
            // mitad cerca del centro, donde casi no se ven.
            readonly property int count: 110

            Repeater {
                model: stars.visible ? stars.count : 0

                Rectangle {
                    required property int index
                    readonly property real ang: index * 2.399963      // ángulo áureo: reparte parejo
                    readonly property real phase: (stars.travel + index / stars.count) % 1
                    // llegan hasta el borde: con 0.75 el campo terminaba antes
                    // que la pantalla y quedaba un marco vacío alrededor
                    readonly property real dist: phase * motif.span * 1.05
                    x: stars.width / 2 + Math.cos(ang) * dist - width / 2
                    y: stars.height / 2 + Math.sin(ang) * dist - height / 2
                    // la estela: en el hiperespacio el punto deja de ser un punto
                    width: Math.max(3, motif.span * 0.009 + dist * 0.03 * (1 + 4 * stars.warp))
                    height: Math.max(3, motif.span * 0.008)
                    radius: height / 2
                    rotation: ang * 180 / Math.PI
                    color: index % 7 === 0 ? motif.hot
                        : Qt.tint(motif.colour, Qt.rgba(motif.hot.r, motif.hot.g,
                                                        motif.hot.b, 0.75 * stars.warp))
                    // el piso de brillo: una estrella que nace invisible y
                    // tarda media pantalla en aparecer no es una estrella
                    opacity: Math.min(1, 0.30 + phase * 1.1) * (1 - 0.35 * phase * phase)
                }
            }
        }
    }

    // -------------------------------------------------------- carta de ajuste
    // T4.3 — UNA CARTA DE AJUSTE DE VERDAD, no un marco con un círculo. Lo que
    // quedaba en el aire cuando terminaba la programación tenía siempre las
    // mismas cuatro cosas, y son las cuatro que faltaban: las barras de color
    // arriba, la escalera de grises abajo, el círculo con la rejilla fina en el
    // medio (la rejilla sirve para ver la convergencia, y por eso va DENTRO del
    // círculo y recortada por él) y el rótulo de la emisora con la hora.
    //
    // Reparto: todo se mide con el LADO CORTO y se ancla al 92 % del cuadro, así
    // que la misma carta entra igual en la vertical y en la apaisada — barras
    // arriba, escalera abajo, círculo en el medio, y el medio es lo que sobra.
    //
    // El único Canvas es el círculo: la rejilla recortada por una circunferencia
    // no se puede hacer con `clip`, que es rectangular. Las barras, la escalera,
    // la aguja y el rótulo son items, que se animan gratis — un Canvas del
    // tamaño de la pantalla repintándose con cada muestra de graves es
    // exactamente lo que no se puede pagar.
    Component {
        id: testcardC

        Item {
            id: card

            // safe area: nada toca el canto del tubo
            readonly property real mx: width * 0.04
            readonly property real my: height * 0.04
            readonly property real cw: width - mx * 2
            readonly property real ch: height - my * 2
            readonly property real sp: motif.span
            readonly property real barsH: sp * 0.12
            readonly property real stepsH: sp * 0.09
            readonly property real gap: sp * 0.05
            readonly property real midY: my + barsH + gap
            readonly property real midH: Math.max(sp * 0.2, ch - barsH - stepsH - gap * 2)
            readonly property real dia: Math.min(cw, midH) * 0.92

            // el segundo entero: la aguja camina de a un tick, como un reloj de
            // pared, y no se desliza. `clock` es el reloj del tubo en segundos.
            readonly property int sec: Math.floor(motif.clock)
            property string stamp: Qt.formatTime(new Date(), "hh:mm:ss")
            onSecChanged: stamp = Qt.formatTime(new Date(), "hh:mm:ss")

            // ---- las barras de color, arriba. La SMPTE son siete combinaciones
            // de R, G y B prendidos o apagados (blanco, amarillo, cian, verde,
            // magenta, rojo, azul), y eso es lo que va acá: la máscara de la
            // barra MULTIPLICA al color caliente del tema. Con una rampa de
            // luminancia sobre un solo tinte —el primer intento— las siete
            // barras salían siete azules y no se distinguían de la escalera de
            // grises de abajo, que es justo lo que la escalera ya hace.

            Row {
                x: card.mx
                y: card.my
                width: card.cw
                height: card.barsH
                spacing: 0

                Repeater {
                    model: card.visible ? 7 : 0
                    Rectangle {
                        required property int index
                        // blanco · amarillo · cian · verde · magenta · rojo · azul
                        readonly property int mask: [7, 6, 3, 2, 5, 4, 1][index]
                        width: card.cw / 7
                        height: card.barsH
                        color: Qt.rgba(motif.hot.r * ((mask & 4) ? 1 : 0.10),
                                       motif.hot.g * ((mask & 2) ? 1 : 0.10),
                                       motif.hot.b * ((mask & 1) ? 1 : 0.10), 1)
                        opacity: 0.9
                    }
                }
            }

            // ---- la escalera de grises, abajo. Late con los graves: es la
            // única parte de la carta que se mueve con el tema.
            Row {
                x: card.mx
                y: card.my + card.ch - card.stepsH
                width: card.cw
                height: card.stepsH
                spacing: 0
                opacity: 0.55 + 0.45 * motif.low

                Repeater {
                    model: card.visible ? 8 : 0
                    Rectangle {
                        required property int index
                        width: card.cw / 8
                        height: card.stepsH
                        readonly property real lu: index / 7
                        color: Qt.rgba(motif.colour.r * lu, motif.colour.g * lu,
                                       motif.colour.b * lu, 1)
                    }
                }
            }

            // ---- el círculo con la rejilla y la cruz
            Item {
                id: dial
                x: card.mx + (card.cw - card.dia) / 2
                y: card.midY + (card.midH - card.dia) / 2
                width: card.dia
                height: card.dia

                Canvas {
                    id: disc
                    anchors.fill: parent
                    renderStrategy: Canvas.Cooperative

                    // El Canvas no se repinta solo: con la pantalla quieta no
                    // hay Timer que lo llame y la carta saldría en blanco (la
                    // misma trampa del cardiograma).
                    onVisibleChanged: if (visible) requestPaint()
                    Component.onCompleted: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections {
                        target: motif
                        function onColourChanged() { disc.requestPaint(); }
                        function onHotChanged() { disc.requestPaint(); }
                    }

                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        const d = width;
                        if (d <= 4)
                            return;
                        const r = d / 2, cx = r, cy = r;
                        const lw = Math.max(2, d * 0.004);

                        // la rejilla, recortada por el círculo: es para lo que
                        // sirve el círculo de una carta de ajuste
                        c.save();
                        c.beginPath();
                        c.arc(cx, cy, r - lw, 0, Math.PI * 2);
                        c.clip();
                        c.strokeStyle = motif.colour;
                        c.globalAlpha = 0.38;
                        c.lineWidth = Math.max(1, d * 0.0025);
                        const cells = 10;
                        for (let i = 1; i < cells; i++) {
                            const p = i / cells * d;
                            c.beginPath(); c.moveTo(p, 0); c.lineTo(p, d); c.stroke();
                            c.beginPath(); c.moveTo(0, p); c.lineTo(d, p); c.stroke();
                        }
                        c.restore();

                        // dos circunferencias: la de afuera y la del cuarto
                        c.globalAlpha = 0.85;
                        c.strokeStyle = motif.colour;
                        c.lineWidth = lw;
                        c.beginPath(); c.arc(cx, cy, r - lw, 0, Math.PI * 2); c.stroke();
                        c.globalAlpha = 0.45;
                        c.lineWidth = Math.max(1, lw * 0.6);
                        c.beginPath(); c.arc(cx, cy, r * 0.5, 0, Math.PI * 2); c.stroke();

                        // los doce ticks de la hora
                        c.globalAlpha = 0.7;
                        c.lineWidth = lw;
                        for (let k = 0; k < 12; k++) {
                            const ang = k / 12 * Math.PI * 2 - Math.PI / 2;
                            const long = (k % 3 === 0) ? 0.10 : 0.055;
                            c.beginPath();
                            c.moveTo(cx + Math.cos(ang) * r * (1 - long),
                                     cy + Math.sin(ang) * r * (1 - long));
                            c.lineTo(cx + Math.cos(ang) * r * 0.96,
                                     cy + Math.sin(ang) * r * 0.96);
                            c.stroke();
                        }

                        // la cruz del centro
                        c.globalAlpha = 0.9;
                        c.strokeStyle = motif.hot;
                        c.lineWidth = lw;
                        const arm = r * 0.16;
                        c.beginPath(); c.moveTo(cx - arm, cy); c.lineTo(cx + arm, cy); c.stroke();
                        c.beginPath(); c.moveTo(cx, cy - arm); c.lineTo(cx, cy + arm); c.stroke();
                    }
                }

                // ---- la aguja: camina de a un segundo con snap, no se desliza.
                // El ángulo se ACUMULA (sec * 6): con el resto de 360 la aguja
                // volvería para atrás una vuelta entera cada minuto.
                Item {
                    id: hand
                    anchors.fill: parent
                    rotation: card.sec * 6
                    Behavior on rotation {
                        NumberAnimation {
                            duration: Motion.enterFastMs
                            easing.type: Easing.OutExpo
                        }
                    }

                    Rectangle {
                        x: parent.width / 2
                        y: parent.height / 2 - height / 2
                        width: parent.width * 0.44
                        height: Math.max(2, card.dia * 0.010)
                        transformOrigin: Item.Left
                        rotation: -90          // el cero de la aguja son las 12
                        color: motif.hot
                        opacity: 0.9
                    }
                }
            }

            // ---- el rótulo de la emisora y la hora, con la fuente del tubo
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: card.midY + (card.midH - card.dia) / 2 - card.gap * 0.9
                text: (motif.title || "FATAL LYRICS").toUpperCase()
                color: motif.hot
                opacity: 0.85
                font.family: motif.fontFamily
                font.pixelSize: Math.max(8, card.sp * 0.038)
                font.letterSpacing: card.sp * 0.006
                width: card.cw
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: card.midY + (card.midH + card.dia) / 2 + card.gap * 0.2
                text: card.stamp
                color: motif.colour
                opacity: 0.8
                font.family: motif.fontFamily
                font.pixelSize: Math.max(8, card.sp * 0.046)
                font.letterSpacing: card.sp * 0.010
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // ------------------------------------------------------------------- agua
    // Los dos motivos de agua son los únicos que no están hechos de items: son
    // miles de puntos con física propia y eso sólo cierra en la GPU (ver
    // `ocean.frag` y `pond.frag`).
    //
    //   ocean = un mar en perspectiva, olas que vienen de lejos
    //   pond  = un plato de agua que TIEMBLA a la frecuencia de lo que suena
    Component {
        id: oceanC

        Ocean {
            colour: motif.colour
            crest: motif.hot
            level: motif.level
            stepMin: motif.stepMin
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
    Component {
        id: dunesC

        Dunes {
            colour: motif.colour
            crest: motif.hot
            level: motif.level
            stepMin: motif.stepMin
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
    // cursor borra la vuelta anterior. Son 240 muestras y un Canvas: no tiene
    // por qué existir mientras la pantalla muestra otra cosa.
    Component {
        id: ekgC

        Ekg {
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
    Component {
        id: rorschachC

        Rorschach {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            stepMin: motif.stepMin
            pitch: motif.pitch
            seed: motif.seed
            energy: motif.energy
            kick: motif.kick
            tick: motif.tick
            running: motif.spinning
        }
    }

    // ---------------------------------------------------------------- plasma
    // La lámpara de lava: bolas de campo que se funden entre sí
    // (`plasma.frag`). Los graves las empujan para arriba y el golpe del tubo
    // les hace temblar la superficie.
    Component {
        id: plasmaC

        Plasma {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            stepMin: motif.stepMin
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
    Component {
        id: tunnelC

        Tunnel {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            stepMin: motif.stepMin
            pitch: motif.pitch
            energy: motif.energy
            seed: motif.seed
            kick: motif.kick
            running: motif.spinning
        }
    }

    // -------------------------------------------------------------- estática
    // La pantalla sin señal que una vez por compás casi engancha algo. El ruido
    // y la máscara viven en `static.frag`.
    Component {
        id: staticC

        Static {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            stepMin: motif.stepMin
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
    Component {
        id: textseaC

        TextSea {
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            stepMin: motif.stepMin
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

    Component {
        id: pondC

        Pond {
            colour: motif.colour
            crest: motif.hot
            level: motif.level
            stepMin: motif.stepMin
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
