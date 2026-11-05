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
import QtQuick.Shapes

Item {
    id: motif

    // eye | scope | radar | rain | stars | testcard | ocean | pond | dunes
    // | static | textsea | eyes | ekg | rorschach | plasma | tunnel
    // | swarm | splitflap | maze | pipes | defrag | mystify | vector | harmonograph
    // | membrana | cintas | giroscopio | cascada | estela | pixelsort | julia | truchet | vitral | none
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
    // tanda 8, slice movimiento (`shell/Speed.js`): el RITMO de los dibujos según cómo
    // se mueve la música ahora (1 = el de siempre) y lo que ese ritmo ya le corrió al
    // reloj de dibujo, acumulado en Crt.qml. `mclock` es el reloj de DIBUJO de los que
    // no llevan física propia; `clock` sigue siendo el real (compás, golpes). La física
    // propia (agua, arena, plasma...) y los de loop reciben `rate` y lo multiplican por
    // su `frameTime`: integran ellos, nunca `t · rate`.
    property real rate: 1
    property real movOff: 0
    readonly property real mclock: clock + movOff
    property color bg: "#04162e" // la cara del tubo (los motivos de loop pintan paletas y paredes con ella)
    property bool spinning: true   // false = quieto (pantalla apagada)
    // el tubo apagado (tanda 6, corrida 0): a diferencia de `spinning`, esto
    // DESACTIVA el `Loader` de abajo entero. Un dibujo con física propia
    // (plasma, túnel) sigue corriendo su `FrameAnimation` con `visible: false`
    // — vivo bajo negro sigue gastando CPU — así que la instancia se destruye.
    property bool dark: false
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
    // la forma de onda real (`wave`, corrida 7): la lee sólo el scope
    property var waveL: []
    property var waveR: []
    property double waveAt: 0
    property int waveStaleMs: 300
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
    // tanda 7, corrida 6: el artista/álbum de la carta del intro. Con texto, reemplaza la
    // hora bajo el círculo (la aguja sigue caminando); vacío = la hora, como siempre.
    property string info: ""
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
    // El golpe del bajo, cada bombo (Ferox 2026-10-19): `bass` es el contador, `bassAmt` el
    // tirón de tamaño (ya escalado por el carácter del tema) y `bassMs` lo que tarda en
    // volver. Aparte de `surge` (el pico del tema, uno cada tanto): éste pasa en CADA golpe.
    property int bass: 0
    property real bassAmt: 0.02
    property int bassMs: 150
    property real bump: 0
    // Para los motivos de golpe físico (`ThumpBase.qml`): la fuerza de cada golpe (0..1), la
    // densidad de la música (`crtDensity`), el carácter del tema (0 calmo .. 1 agitado,
    // `crtCharacter`) y la valencia del mood en 0..1
    property real thumpAmt: 1
    property real density: 0.5
    property real character: 0.5
    property real valence: 0.5
    onBassChanged: {
        bumpDecay.stop();
        bump = 1;
        bumpDecay.start();
    }
    NumberAnimation {
        id: bumpDecay
        target: motif
        property: "bump"
        to: 0
        duration: motif.bassMs
        easing.type: Easing.OutQuad
    }
    // Los agudos (hi-hat, o los que cambian si no llega): un destello CHICO y propio sobre
    // el dibujo, una crucecita que aparece en otro lugar cada vez y se apaga rápido. `hat`
    // es un nivel 0..1; cada subida marcada dispara uno (`hatAmt` = el brillo, de `pace`).
    property real hat: 0
    property real hatAmt: 0.85
    property real hatPrev: 0
    property int glintN: 0
    property double glintAt: 0
    onHatChanged: {
        const rise = hat - hatPrev;
        hatPrev = hat;
        const now = Date.now();
        if (hat > 0.2 && rise > 0.06 && now - glintAt > 90 && !dark && spinning) {
            glintAt = now;
            glintN++;
            const g = glints.itemAt(glintN % 4);
            if (g)
                g.fire(Math.min(1, 0.45 + hat));
        }
    }
    Repeater {
        id: glints
        model: 4
        delegate: Item {
            id: glint
            // por encima del dibujo (el Loader, declarado antes, queda abajo)
            z: 5
            property real a: 0
            readonly property real arm: Math.max(4, motif.span * 0.022)
            function fire(k) {
                x = motif.width * (0.12 + 0.76 * Math.random()) - arm;
                y = motif.height * (0.12 + 0.76 * Math.random()) - arm;
                glintAnim.stop();
                a = k * motif.hatAmt;
                glintAnim.start();
            }
            width: arm * 2
            height: arm * 2
            visible: a > 0.01
            opacity: Math.min(a, 1)
            NumberAnimation on a {
                id: glintAnim
                running: false
                to: 0
                duration: 170
                easing.type: Easing.OutQuad
            }
            Rectangle { anchors.centerIn: parent; width: parent.width; height: Math.max(1.5, glint.arm * 0.16); color: motif.hot }
            Rectangle { anchors.centerIn: parent; width: Math.max(1.5, glint.arm * 0.16); height: parent.height; color: motif.hot }
        }
    }
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
    // señales finas: corte seco y agudos (los leen el laberinto, Maze.qml, y Mystify.qml) y la
    // perilla de los huevos de pascua del laberinto (`crt.maze_eggs`)
    property bool cut: false
    property real hf: 0
    property bool eggs: true

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

    // Techo propio de cuadros de los motivos: ninguno. Quién marca el paso es `FrameTick`
    // (`crt.frames`); un techo acá encima se traba en múltiplos del latido (1/60 daba 48 fps) y
    // el piso de 30 fps con volumen bajo se notaba justo en lo lento.
    readonly property real stepMin: 0

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
    readonly property real zoomNow: 1 + scaleAmt * surge + bassAmt * bump
    // ---- PARED (`docs/PARED.md`): los dibujos que saben extenderse (`motifWall` en shell.qml)
    // reciben de Crt.qml el lienzo de la pared (null = la pantalla sola), el factor de la
    // cámara del tubo y el foco en px de lienzo. En pared el tirón NO va por este Scale: sobre
    // el centro de cada pantalla partiría la costura. Lo aplica el dibujo sobre el pivote de
    // pared (`Wall.view`).
    property var wall: null
    property real wallCamS: 1
    property point wallFocus: Qt.point(0, 0)
    readonly property vector4d wallCam: Qt.vector4d(zoomNow, wallCamS, wallFocus.x, wallFocus.y)
    // lo que declara el dibujo para la pantalla de la letra (`Wall.fit`): Crt.qml arma con eso
    // la ventana espejada y el eco
    readonly property string wallFit: drawing.item && drawing.item.wallFit !== undefined ? drawing.item.wallFit : "behind"
    readonly property real wallEcho: drawing.item && drawing.item.wallEcho !== undefined ? drawing.item.wallEcho : 0
    transform: Scale {
        origin.x: motif.width / 2
        origin.y: motif.height / 2
        xScale: motif.wall ? 1 : motif.zoomNow
        yScale: motif.wall ? 1 : motif.zoomNow
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
        id: drawing
        anchors.fill: parent
        clip: true
        active: !motif.dark
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
            : motif.kind === "swarm" ? swarmC
            : motif.kind === "splitflap" ? splitflapC
            : motif.kind === "maze" ? mazeC
            : motif.kind === "pipes" ? pipesC
            : motif.kind === "defrag" ? defragC
            : motif.kind === "mystify" ? mystifyC
            : motif.kind === "vector" ? vectorC
            : motif.kind === "harmonograph" ? harmonographC
            : motif.kind === "membrana" ? membranaC
            : motif.kind === "cintas" ? cintasC
            : motif.kind === "giroscopio" ? giroscopioC
            : motif.kind === "cascada" ? cascadaC
            : motif.kind === "estela" ? estelaC
            : motif.kind === "pixelsort" ? pixelsortC
            : motif.kind === "julia" ? juliaC
            : motif.kind === "truchet" ? truchetC
            : motif.kind === "vitral" ? vitralC
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
                // la misma medida que el ojo grande de `Eyes.qml`
                width: motif.span * (parent.height > parent.width ? 0.92 : 1.15)
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
    // Un osciloscopio de laboratorio (`Scope.qml`).
    Component {
        id: scopeC

        Scope {
            fontFamily: motif.fontFamily
            waveL: motif.waveL
            waveR: motif.waveR
            waveAt: motif.waveAt
            waveStaleMs: motif.waveStaleMs
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // ------------------------------------------------------------------ radar
    // Una pantalla de radar (`Radar.qml`, `radar.frag`).
    Component {
        id: radarC

        Radar {
            fontFamily: motif.fontFamily
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // ----------------------------------------------------------------- lluvia
    // Lluvia de caracteres (`Rain.qml`, `rain.frag`). Cruza la pared.
    Component {
        id: rainC

        Rain {
            // pared: el lienzo común y la cámara (ver arriba, `wall`)
            wall: motif.wall
            wallCam: motif.wallCam
            fontFamily: motif.fontFamily
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
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

        Stars {
            // pared: el lienzo común y la cámara (ver arriba, `wall`)
            wall: motif.wall
            wallCam: motif.wallCam
            colour: motif.colour
            hot: motif.hot
            level: motif.level
            low: motif.low
            drive: motif.drive
            rate: motif.rate
            drop: motif.drop
            running: motif.spinning
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

            // El segundo entero: la aguja camina de a un tick, como un reloj de
            // pared, y no se desliza. Sale de la hora DE VERDAD y no del reloj
            // del tubo (que corre escalado por la parte del tema): la aguja y
            // el rótulo son la misma hora, así que tienen que salir del mismo
            // tick. Un reloj que marca las 10:41:23 con la aguja en cualquier
            // parte del cuadrante es un reloj roto.
            //
            // El ángulo se ACUMULA y siempre hacia adelante: con `getSeconds()
            // * 6` pelado, el paso de 354° a 0° es un `Behavior` que se da toda
            // la vuelta para atrás una vez por minuto.
            property real handAngle: 0
            property int wall: -1
            property string stamp: Qt.formatTime(new Date(), "hh:mm:ss")

            function tickClock() {
                var d = new Date();
                if (d.getSeconds() === wall)
                    return;
                wall = d.getSeconds();
                stamp = Qt.formatTime(d, "hh:mm:ss");
                var step = wall * 6 - (handAngle % 360);
                if (step < 0)
                    step += 360;
                handAngle += step;
            }
            // 200 ms y no 1000: un timer de un segundo entero se corre contra
            // el segundo del reloj y la aguja salta de a dos tics.
            Timer {
                interval: 200
                repeat: true
                running: card.visible
                triggeredOnStart: true
                onTriggered: card.tickClock()
            }
            Component.onCompleted: {
                tickClock();
                handAngle = wall * 6;   // la primera aparición ya nace en hora
            }

            // ---- las barras de color, arriba. La SMPTE son siete combinaciones
            // de R, G y B prendidos o apagados (blanco, amarillo, cian, verde,
            // magenta, rojo, azul), y eso es lo que va acá. Con una rampa de
            // luminancia sobre un solo tinte —el primer intento— las siete
            // barras salían siete azules y no se distinguían de la escalera de
            // grises de abajo, que es justo lo que la escalera ya hace.

            // El marco negro es lo que las hace legibles en CUALQUIER cara: la barra blanca
            // sobre una cara clara (fondo cian o crema) se comía con el fondo.
            Rectangle {
                x: card.mx - card.barsH * 0.06
                y: card.my - card.barsH * 0.06
                width: card.cw + card.barsH * 0.12
                height: card.barsH * 1.12
                color: "#0b0b0b"
                opacity: 0.9
            }

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
                        // color PROPIO de la carta, no derivado de la cara (corrida 6b): con
                        // `motif.hot` como base, en un esquema claro (tinta oscura) las siete
                        // barras salían casi negras. Barras al 80% como las de un generador
                        // real; el canal apagado queda en 0, así que son siete colores
                        // distintos en cualquier cara, clara u oscura
                        color: Qt.rgba((mask & 4) ? 0.8 : 0,
                                       (mask & 2) ? 0.8 : 0,
                                       (mask & 1) ? 0.8 : 0, 1)
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

                // ---- la aguja: camina de a un segundo con snap, no se desliza,
                // y marca los segundos de la hora que dice el rótulo de abajo.
                Item {
                    id: hand
                    anchors.fill: parent
                    rotation: card.handAngle
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
                text: (motif.title || "").toUpperCase()
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
                text: motif.info !== "" ? motif.info.toUpperCase() : card.stamp
                color: motif.colour
                opacity: 0.8
                font.family: motif.fontFamily
                font.pixelSize: Math.max(8, card.sp * (motif.info !== "" ? 0.034 : 0.046))
                font.letterSpacing: card.sp * 0.010
                width: card.cw
                elide: Text.ElideRight
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
            // pared: el lienzo común y la cámara (ver arriba, `wall`)
            wall: motif.wall
            wallCam: motif.wallCam
            tubeClock: motif.clock
            seed: motif.seed
            colour: motif.colour
            rate: motif.rate
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
            // pared: el lienzo común y la cámara (ver arriba, `wall`)
            wall: motif.wall
            wallCam: motif.wallCam
            tubeClock: motif.clock
            colour: motif.colour
            rate: motif.rate
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
            fontFamily: motif.fontFamily
            beatAmt: motif.beatAmt
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
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
            rate: motif.rate
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
    // (`plasma.frag`). Los graves abren la burbuja y la estiran; el golpe
    // CRUDO (`beat`, no el pico del tubo) le pega el empujón que la parte en
    // gotas, y el resorte de `Plasma.qml` las vuelve a juntar.
    Component {
        id: plasmaC

        Plasma {
            colour: motif.colour
            rate: motif.rate
            hot: motif.hot
            level: motif.level
            stepMin: motif.stepMin
            low: motif.low
            kick: motif.kick
            beat: motif.beat
            drop: motif.drop
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
            // pared: el lienzo común y la cámara (ver arriba, `wall`)
            wall: motif.wall
            wallCam: motif.wallCam
            colour: motif.colour
            rate: motif.rate
            hot: motif.hot
            level: motif.level
            stepMin: motif.stepMin
            pitch: motif.pitch
            low: motif.low
            beat: motif.beat
            tick: motif.tick
            bpmLive: motif.bpmLive
            drop: motif.drop
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
            rate: motif.rate
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
            rate: motif.rate
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
            // pared: el lienzo común y la cámara (ver arriba, `wall`)
            wall: motif.wall
            wallCam: motif.wallCam
            tubeClock: motif.clock
            seed: motif.seed
            colour: motif.colour
            rate: motif.rate
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

    // ------------------------------------------------------ los de loop (15 s)
    // Ocho motivos que salieron de `previews/crt-motifs/` (ahí está el render
    // offscreen de cada uno por el vidrio real). Heredan de `MotifBase.qml`:
    // son función pura de `clock` (lo que deriva es periódico en 15 s) y lo
    // que avanza a los saltos lo hace por `tick`/`kick`, nunca por velocidad.
    // Todos reciben lo mismo; cada uno lee lo suyo.
    Component {
        id: swarmC

        Swarm {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            nextWord: motif.nextWord
            lineNo: motif.lineNo
            lines: motif.lines
            linesSynced: motif.linesSynced
            fontFamily: motif.fontFamily
            running: motif.spinning
        }
    }
    Component {
        id: splitflapC

        Splitflap {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            nextWord: motif.nextWord
            lineNo: motif.lineNo
            lines: motif.lines
            linesSynced: motif.linesSynced
            fontFamily: motif.fontFamily
            running: motif.spinning
        }
    }
    Component {
        id: mazeC

        Maze {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            cut: motif.cut
            hf: motif.hf
            eggs: motif.eggs
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            nextWord: motif.nextWord
            lineNo: motif.lineNo
            lines: motif.lines
            linesSynced: motif.linesSynced
            fontFamily: motif.fontFamily
            running: motif.spinning
        }
    }
    Component {
        id: pipesC

        Pipes {
            // pared: el lienzo común y la cámara (ver arriba, `wall`)
            wall: motif.wall
            wallCam: motif.wallCam
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            nextWord: motif.nextWord
            lineNo: motif.lineNo
            lines: motif.lines
            linesSynced: motif.linesSynced
            fontFamily: motif.fontFamily
            running: motif.spinning
            hf: motif.hf
            // el golpe físico (`Pipes.qml` es un ThumpBase): bombo, agudos, densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }
    Component {
        id: defragC

        Defrag {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            nextWord: motif.nextWord
            lineNo: motif.lineNo
            lines: motif.lines
            linesSynced: motif.linesSynced
            fontFamily: motif.fontFamily
            running: motif.spinning
        }
    }
    Component {
        id: mystifyC

        Mystify {
            // pared: el lienzo común y la cámara (ver arriba, `wall`)
            wall: motif.wall
            wallCam: motif.wallCam
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            cut: motif.cut
            hf: motif.hf
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            nextWord: motif.nextWord
            lineNo: motif.lineNo
            lines: motif.lines
            linesSynced: motif.linesSynced
            fontFamily: motif.fontFamily
            running: motif.spinning
        }
    }
    Component {
        id: vectorC

        Vector {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            nextWord: motif.nextWord
            lineNo: motif.lineNo
            lines: motif.lines
            linesSynced: motif.linesSynced
            fontFamily: motif.fontFamily
            running: motif.spinning
        }
    }
    Component {
        id: harmonographC

        Harmonograph {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            nextWord: motif.nextWord
            lineNo: motif.lineNo
            lines: motif.lines
            linesSynced: motif.linesSynced
            fontFamily: motif.fontFamily
            running: motif.spinning
        }
    }

    // membrana: el parche de un bombo en perspectiva, malla de fósforo (`membrana.frag`).
    // Resorte de `Thump.js` por golpe; cámara = la misma masa, más pesada.
    Component {
        id: membranaC

        Membrana {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // cintas: cintas de fósforo a distintas profundidades que el bombo comba y retuerce
    // (`cintas.frag`). Las de atrás pesan más: la ola baja por la pila.
    Component {
        id: cintasC

        Cintas {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // giroscopio: cardán de aros anidados en 3D (`giroscopio.frag`, raymarch). Un resorte por
    // aro, el de adentro salta primero.
    Component {
        id: giroscopioC

        Giroscopio {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // cascada: diálogos de error que se apilan en cascada, uno por tiempo, hasta que el 12º revienta y vuelve a empezar (`Cascada.qml`).
    Component {
        id: cascadaC

        Cascada {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // estela: una ventana colgada que el cursor arrastra dejando el efecto de "Not Responding" (`Estela.qml`).
    Component {
        id: estelaC

        Estela {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // pixelsort: la silueta de ventanas ordenada por brillo en tiras, estilo glitch (`pixelsort.frag`).
    Component {
        id: pixelsortC

        Pixelsort {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // julia: las curvas de nivel de un conjunto de Julia que respira con el bombo (`julia.frag`).
    Component {
        id: juliaC

        Julia {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // truchet: baldosas de arcos que giran de a un cuarto de vuelta al compás, con una onda por golpe (`truchet.frag`).
    Component {
        id: truchetC

        Truchet {
            // pared: el lienzo común y la cámara (ver arriba, `wall`)
            wall: motif.wall
            wallCam: motif.wallCam
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }

    // vitral: vidrio de Voronoi emplomado; el bombo empuja los vidrios y los agudos prenden facetas (`vitral.frag`).
    Component {
        id: vitralC

        Vitral {
            colour: motif.colour
            hot: motif.hot
            bg: motif.bg
            tubeClock: motif.clock
            rate: motif.rate
            stepMin: motif.stepMin
            level: motif.level
            low: motif.low
            high: motif.high
            hf: motif.hf
            pitch: motif.pitch
            energy: motif.energy
            surge: motif.surge
            seed: motif.seed
            quality: motif.quality
            drop: motif.drop
            section: motif.section
            tick: motif.tick
            beat: motif.beat
            kick: motif.kick
            beatMs: motif.beatMs
            bpmLive: motif.bpmLive
            running: motif.spinning
            // el golpe físico: bombo (con `b` de respaldo, ya resuelto en shell.qml), agudos,
            // densidad y carácter del tema
            thump: motif.bass
            thumpAmt: motif.thumpAmt
            hat: motif.hat
            mov: motif.density
            character: motif.character
            valence: motif.valence
        }
    }
}
