// fatal-lyrics — CRT mode: one full-bleed cathode ray tube per monitor.
//
// The lyric is laid out flat inside `stage`, which is drawn into a texture and
// pushed through crt.frag: glass curvature, phosphor bloom, aperture grille,
// scanlines, RGB split, torn bands and static.
//
// With the director on, the screens are not clones: one is in focus, the phrase
// continues on the next one, and the quiet ones run an animation instead. What
// is shown where always follows the lyric clock; the music only drives how hard
// everything glows, shakes and breathes.
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: crt

    // el root del shell (estado de la letra + config); `scr` es el monitor,
    // `idx`/`total` la posición de esta pantalla en el arreglo
    required property var ctl
    required property var scr
    required property int idx
    required property int total

    screen: scr
    // No es `ctl.crtOn` directo: apagar el tubo es una animación (el colapso de
    // abajo), y la ventana tiene que sobrevivir a esos ~400 ms. Se prende de
    // una y se apaga cuando el colapso termina.
    property bool tubeOn: false
    visible: tubeOn
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "cartelitos-crt"
    exclusionMode: ExclusionMode.Ignore
    color: "black"
    anchors { left: true; right: true; top: true; bottom: true }

    // Cómo se sale del tubo (exit_on):
    //   "mouse"    — el tubo agarra el puntero: cursor escondido, y moverlo,
    //                clickear o girar la rueda devuelven el escritorio.
    //   "keyboard" — el tubo agarra el teclado: CUALQUIER tecla lo apaga.
    // No se puede tener las dos: en Hyprland, una capa con foco de teclado deja
    // de recibir puntero (probado con Exclusive y con OnDemand), así que el
    // cursor no se podría esconder ni el click saldría. Con el teclado agarrado
    // lo pide una sola pantalla — si lo piden las tres se pelean por el foco.
    readonly property bool grabKeyboard: ctl.crtExitOn === "keyboard"
    WlrLayershell.keyboardFocus: grabKeyboard && idx === 0 && ctl.crtOn
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            event.accepted = true;
            crt.ctl.crtExit();
        }
    }

    // ------------------------------------------------------ apagado de tubo
    // Un tubo no se apaga: la imagen se cae a una línea horizontal, la línea se
    // junta en un punto y el punto se queda un momento prendido en el fósforo.
    // Esconder la ventana de una es lo único que delata que esto es software.
    property real offX: 1
    property real offY: 1
    property real dotOpacity: 0
    SequentialAnimation {
        id: offAnim
        NumberAnimation { target: crt; property: "offY"; from: 1; to: 0.01; duration: 180; easing.type: Easing.InQuad }
        ParallelAnimation {
            NumberAnimation { target: crt; property: "offX"; from: 1; to: 0; duration: 120; easing.type: Easing.InQuad }
            NumberAnimation { target: crt; property: "dotOpacity"; to: 1; duration: 60 }
        }
        PauseAnimation { duration: 80 }
        ScriptAction {
            script: {
                crt.tubeOn = false;
                crt.offX = 1;
                crt.offY = 1;
                crt.dotOpacity = 0;
            }
        }
    }
    Connections {
        target: crt.ctl
        function onCrtOnChanged() {
            if (crt.ctl.crtOn) {
                offAnim.stop();
                crt.offX = 1;
                crt.offY = 1;
                crt.dotOpacity = 0;
                crt.tubeOn = true;
            } else if (crt.tubeOn) {
                offAnim.restart();
            }
        }
    }
    // el interruptor puede estar prendido ANTES de que exista esta ventana (el
    // FileView carga primero): sin esto no hay cambio del que enterarse
    Component.onCompleted: tubeOn = ctl.crtOn

    // ------------------------------------------------------------- fósforos
    // Ya no elige la pantalla: el root sirve DOS caras que combinan (una
    // prendida y una de tubo oscuro) y acá se toma la que corresponde. Así la
    // pared nunca tiene tres colores distintos peleándose.
    readonly property bool alarmLine: ctl.crtPlan.alarm && showsText
    readonly property var pal: ctl.crtFace(idx, alarmLine)

    // el contagio de color se ve solo con la transición del fondo; no hace falta
    // sacudir la señal encima

    // ------------------------------------------------------ qué le toca a ésta
    // El director reparte la línea en pedazos con pantalla y horario; esta
    // pantalla mira sólo el suyo. Sin director, `mode` es "all" y todas muestran
    // la línea entera (el comportamiento de antes).
    property var shot: ({ text: "", active: false, past: false, reveal: 0 })
    readonly property bool allMode: ctl.crtShot.mode === "all"
    // IOWN (T3.2): las pantallas no se reparten nada — todas dibujan LA MISMA
    // palabra gigante, cada una en el tramo de pared que le toca
    readonly property bool iownMode: ctl.crtShot.mode === "iown"

    readonly property string lineText: ctl.crtLine.text
    // Sin letra hay DOS situaciones distintas y antes eran una sola:
    //   standby      — no suena nada. Barras de ajuste y "NO SIGNAL".
    //   instrumental — suena, pero este pedazo no tiene letra (o no la hay).
    //                  La pared sigue viva: todas las pantallas con su
    //                  animación al ritmo y la enfocada diciendo qué suena.
    // "NO SIGNAL" con música puesta es la señal equivocada: dice que el
    // programa se cayó cuando lo único que pasa es que nadie está cantando.
    readonly property bool noLyric: lineText === ""
    readonly property bool standby: noLyric && !ctl.musicLive
    readonly property bool instrumental: noLyric && ctl.musicLive
    readonly property bool showsText: !noLyric && (allMode || shot.active || shot.past)
    readonly property bool focused: !noLyric && (allMode || shot.active)
    readonly property bool burned: !allMode && shot.past && !shot.active
    readonly property bool idle: !noLyric && !showsText

    // ------------------------------------------------ el aviso del salto (T2.1)
    // La frase todavía está acá, pero la pantalla a la que va a saltar YA se
    // puso nerviosa: su animación se acelera y toma el color de la enfocada,
    // mientras las otras apagadas se corren un paso atrás. Es lo único que
    // dice a dónde mirar ANTES de que el texto llegue; sin esto el salto se
    // descubre cuando ya pasó.
    //
    // La rampa es el último 40% de la línea medido con crtProgress() — el
    // reloj de la letra, no uno propio: así el aviso dura lo que dura el verso
    // y no se corta a la mitad en una línea corta.
    property real foreRamp: 0
    readonly property bool foreOn: ctl.crtForeshadow && !noLyric
        && ctl.crtNextFocus >= 0 && ctl.crtNextFocus !== ctl.crtShot.focus
    readonly property bool foreTarget: foreOn && ctl.crtNextFocus === idx && !showsText
    readonly property bool foreOther: foreOn && ctl.crtNextFocus !== idx && !showsText
    readonly property real foreAmt: foreTarget ? foreRamp : 0
    // el color de la pantalla ENFOCADA: es el que se va mudando al destino.
    // El tween de 400 ms vale para cualquier cambio de color del motif de esta
    // pantalla, contagio de paleta incluido — que también se ve mejor así.
    property color motifColour: foreAmt > 0.02
        ? ctl.crtFace(ctl.crtShot.focus, false).ink : pal.ink
    Behavior on motifColour { ColorAnimation { duration: 400; easing.type: Easing.OutQuad } }

    // T3.8 (idea 24): tres minutos sin nada que mostrar y sin música, y el tubo
    // se duerme — cinco cuadros por segundo y la estática apagada. Se despierta
    // solo, en cuanto vuelve a haber señal.
    property bool deepSleep: false
    Timer {
        interval: 180000
        running: crt.visible && crt.standby && !crt.deepSleep
        onTriggered: crt.deepSleep = true
    }
    onStandbyChanged: {
        if (!standby)
            deepSleep = false;
    }

    // el texto de ESTA pantalla: el pedazo del director, o la línea entera
    // (partida por posición si `split` mandó cortarla) cuando no hay director
    readonly property string myText: allMode
        ? (ctl.crtPlan.layout === "split" ? ctl.crtSlice(lineText, idx, total) : lineText)
        : shot.text
    readonly property var myWords: myText.split(/\s+/).filter(w => w.length > 0)

    readonly property string layout: {
        if (allMode)
            return ctl.crtPlan.layout;
        // con director el pedazo ya viene corto: apilado si es una o dos palabras
        if (myWords.length <= 2)
            return "stack";
        return ctl.crtPlan.layout === "type" ? "type" : "plain";
    }

    // avance del pedazo (0..1) y momento en el que entra cada palabra: se
    // reparte por largo, igual que el karaoke de los carteles
    property real reveal: 1
    function painted(i) {
        return i < Math.ceil(reveal * myWords.length + 0.001);
    }
    // Tiempos por palabra de la línea (LRC "enhanced"), pero SÓLO si esta
    // pantalla está mostrando la línea entera: con el texto partido (layout
    // "split" o modo director) el índice de la palabra acá no es el índice de
    // la palabra en la línea, y además `reveal` avanza sobre la ventana del
    // pedazo, no sobre la de la línea. Ahí el reparto por largo es lo único
    // que cierra.
    readonly property var lineWords: (allMode && layout !== "split"
        && (ctl.crtLine.words || []).length === myWords.length)
        ? ctl.crtLine.words : null

    function dueFrac(i) {
        const lw = lineWords;
        if (lw)
            return ctl.karaokeFracAt(ctl.crtLine.t0 || 0, ctl.crtLine.t1 || 0, lw[i][0]);
        const n = myWords.length;
        if (n <= 1)
            return 0;
        let total = 0;
        let acc = 0;
        for (let k = 0; k < n; k++) {
            const w = myWords[k].length + 1;
            if (k < i)
                acc += w;
            total += w;
        }
        return acc / total;
    }

    // un solo reloj para el contenido: qué pedazo va y cuánto lleva pintado
    Timer {
        interval: 80
        repeat: true
        running: crt.visible && !crt.noLyric
        triggeredOnStart: true
        onTriggered: {
            const st = crt.ctl.crtChunkState(crt.idx);
            crt.shot = st;
            crt.reveal = st.reveal;
            // la rampa del aviso sale del mismo reloj: no necesita animación
            // propia, el avance de la línea YA es la rampa
            crt.foreRamp = Math.max(0, Math.min(
                (crt.ctl.crtProgress() - 0.6) / 0.4, 1));
        }
    }

    // ---------------------------------------------------- lo que manda el audio
    // El sonido NO decide qué se ve ni dónde: sólo cuánto late todo. Sin captura
    // (o con `audio = false`) esto queda en un valor tranquilo y no se nota.
    readonly property bool live: ctl.audLive
    readonly property real rest: ctl.crtIntensity
    readonly property string entryStyle: ctl.crtEntryStyle()
    property real pump: 0.35
    Behavior on pump { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
    Timer {
        interval: 70
        repeat: true
        running: crt.visible
        triggeredOnStart: true
        onTriggered: {
            // el nivel del momento, pero pesado por la parte del tema: el mismo
            // volumen no significa lo mismo en el silencio que en el estribillo
            const base = crt.live ? crt.ctl.audLevel : 0.35;
            const boost = crt.ctl.sectionEnergy * (crt.ctl.building ? 1.15 : 1);
            crt.pump = Math.min(base * boost, 1.3);
        }
    }

    // El latido llega del root, una sola vez para toda la pared: la pantalla con
    // la letra pega el fogonazo y las otras multiplican su animación. Antes esto
    // lo disparaba cada pantalla por su cuenta y el empujón no salía de la que
    // parpadeaba, así que se veía una luz sola moviéndose.
    property real beatPulse: 0
    property real beatBlink: 0
    property int surgeGen: 0
    // Con el compás medido (T4.1) el fogonazo dura una fracción del tiempo en
    // vez de unos ms fijos: así se apaga justo antes del golpe siguiente en vez
    // de quedar corto en un tema lento y pisado en uno rápido.
    NumberAnimation {
        id: beatAnim
        target: crt
        property: "beatPulse"
        from: 1
        to: 0
        duration: crt.ctl.bpmLive
            ? Math.round(Math.min(Math.max(crt.ctl.beatMs * 0.4, 120), 400)) : 190
        easing.type: Easing.OutQuad
    }
    NumberAnimation {
        id: blinkAnim
        target: crt
        property: "beatBlink"
        from: 0.5 * crt.ctl.flickerAmt
        to: 0
        duration: crt.ctl.bpmLive
            ? Math.round(Math.min(Math.max(crt.ctl.beatMs * 0.2, 60), 200)) : 90
        easing.type: Easing.OutQuad
    }

    // ---- el pulso del compás
    // El fogonazo del pico es un momento del tema (flickerGen, un par por
    // canción). Esto es lo otro: el tubo respirando EN TIEMPO, todo el tema,
    // apenas — lo que hace que la pared se lea como si siguiera la música y no
    // como si reaccionara tarde. Lo gradúa la misma perilla del parpadeo, así
    // que con flicker = 0 la pantalla sigue quieta.
    property real gridPulse: 0
    NumberAnimation {
        id: gridAnim
        target: crt
        property: "gridPulse"
        from: 1
        to: 0
        duration: crt.ctl.beatMs > 0 ? Math.round(Math.max(crt.ctl.beatMs * 0.5, 90)) : 250
        easing.type: Easing.OutQuad
    }
    Connections {
        target: crt.ctl
        enabled: crt.visible && crt.ctl.bpmLive
        function onBeatTickChanged() {
            if (crt.ctl.crtFlicker > 0.01)
                gridAnim.restart();
        }
    }
    // ---- el aviso del golpe (T4.2)
    // El daemon avisa un par de segundos antes de que cambie la parte, pero
    // sólo si el tema ya se escuchó otra vez. La cámara se acerca despacio
    // durante esos segundos y REVIENTA cuando el golpe llega de verdad: eso es
    // lo que se lee como que el tubo lo estaba esperando, y no que se enteró
    // tarde. Sin mapa del tema no llega ningún aviso y todo queda como antes.
    property real cueZoom: 1
    NumberAnimation {
        id: cueAnim
        target: crt
        property: "cueZoom"
        from: 1
        to: 1.055
        duration: 2000
        easing.type: Easing.InQuad
    }
    NumberAnimation {
        id: cueRelease
        target: crt
        property: "cueZoom"
        to: 1
        duration: 340
        easing.type: Easing.OutQuad
    }
    Connections {
        target: crt.ctl
        enabled: crt.visible
        function onCueGenChanged() {
            if (crt.ctl.crtCamera <= 0.01)
                return;
            cueRelease.stop();
            cueAnim.duration = Math.round(Math.max(crt.ctl.cueIn * 1000, 400));
            cueAnim.restart();
        }
        function onSectionGenChanged() {
            // llegó el golpe: se suelta el acercamiento y se rompe la pantalla
            if (crt.cueZoom <= 1.001)
                return;
            cueAnim.stop();
            cueRelease.restart();
            crt.hit(1);
        }
    }
    Connections {
        target: crt.ctl
        enabled: crt.visible
        function onFlickerGenChanged() {
            beatAnim.restart();
            if (crt.ctl.flickerHard)
                blinkAnim.restart();
            if (crt.focused)
                flash.pulse();
            crt.surgeGen++;      // acá y en las otras: la pared entera acompaña
        }
    }

    // ------------------------------------------------------- glitch bursts
    property real glitchAmt: 0
    NumberAnimation on glitchAmt {
        id: glitchDecay
        running: false
        to: 0
        duration: 420
        easing.type: Easing.OutQuad
    }
    // Un solo portero para TODOS los glitches. Había cinco cosas distintas
    // pidiéndolo — cada palabra, cada golpe, el cambio de línea, el contagio de
    // color y la interferencia sola — y sumadas dejaban la pantalla vibrando sin
    // parar. Ahora entra uno cada tanto: el que llega tarde se descarta, salvo
    // que venga mucho más fuerte que el que está sonando.
    property double lastHitAt: 0
    // con el compás medido la espera se redondea a un número entero de tiempos:
    // el glitch entra en el pulso del tema, no en el medio
    readonly property int hitGap: Math.round(
        ctl.quantize(1200 / Math.max(ctl.crtIntensity, 0.25)))
    function hit(amount) {
        const now = Date.now();
        if (now - lastHitAt < hitGap && amount < glitchAmt * 1.5)
            return;
        lastHitAt = now;
        glitchDecay.stop();
        glitchAmt = Math.min(amount, 1);
        glitchDecay.start();
    }

    // ------------------------------------------------------ cambio de canal
    // El verso entra como cuando se cambiaba de canal a mano: la pantalla se
    // llena de estática, pega un cuadro rojo y recién ahí aparece el texto,
    // roto, que se acomoda solo (lo deshace glitchDecay, no otra animación).
    // Quién lo dispara lo decide el root (crtShot.chan), así que la pared
    // entera cambia de canal junta — que es lo que hace un televisor.
    property real chanNoise: 0
    property bool chanFlash: false
    SequentialAnimation {
        id: chanAnim
        PropertyAction { target: crt; property: "chanNoise"; value: 1 }
        PauseAnimation { duration: 60 }
        PropertyAction { target: crt; property: "chanFlash"; value: true }
        PauseAnimation { duration: 16 }
        PropertyAction { target: crt; property: "chanFlash"; value: false }
        PropertyAction { target: crt; property: "chanNoise"; value: 0 }
        // el texto ya está puesto: la rotura es la del emisor de siempre, no
        // una segunda fuente de glitch compitiendo con hit()
        ScriptAction { script: crt.hit(1.0) }
    }

    // cambio de línea: patada de señal, y el verso viejo queda quemado atrás
    property string ghostText: ""
    property real ghostFade: 0
    Connections {
        target: crt.ctl
        function onCrtSerialChanged() {
            crt.ghostText = crt.myText;
            crt.ghostFade = crt.showsText ? 0.55 : 0;
            ghostAnim.restart();
            // ÚNICA patada de señal fija: cuando cambia el verso, y SÓLO en la
            // pantalla donde cae la frase. Pateando las tres, con doce versos por
            // minuto la pared se rompía casi cada segundo — medido: 36 roturas en
            // 50 s contra 12 así. Todo lo demás (cada palabra, cada golpe, el
            // contagio de color) ya no rompe nada.
            const sh = crt.ctl.crtShot;
            const mine = sh.mode === "all" || (sh.chunks.length > 0
                && sh.chunks[0].screen === crt.idx);
            if (mine) {
                crt.hit(0.35 + Math.random() * 0.3);
            }
            crt.reveal = 0;
            if (sh.chan)
                chanAnim.restart();
        }
    }
    NumberAnimation {
        id: ghostAnim
        target: crt
        property: "ghostFade"
        to: 0
        duration: 900
        easing.type: Easing.InQuad
    }

    // interferencia espontánea: la programa el root, y sólo para una pantalla
    Connections {
        target: crt.ctl
        enabled: crt.visible
        function onInterfGenChanged() {
            if (crt.ctl.interfScreen !== crt.idx)
                return;
            crt.hit((0.12 + Math.random() * 0.35) * crt.ctl.crtIntensity
                * crt.ctl.sectionEnergy);
        }
    }

    // ------------------------------------------------------------- capa plana
    readonly property real shortSide: Math.min(width, height)
    readonly property real pad: Math.round(shortSide * 0.06)
    readonly property string fontFamily: ctl.crtFont

    // Reloj del tubo, y el techo de cuadros del modo.
    //
    // Con FrameAnimation esto corría al refresh de cada monitor — 200 Hz en uno
    // de los de prueba — redibujando tres pantallas enteras con shader para un efecto
    // que es ruido — plata tirada. Va a 60, que ya no se distingue, y la pantalla
    // sin letra a 20. Ahí está la mayor parte del ahorro de tener tres tubos.
    property real tubeTime: 0
    // posición de la palabra del IOWN en ESTA pantalla, refrescada por cuadro
    property real iownX: 0
    property real iownProg: 0
    // T0.12: modo degradado por GPU. Promedio móvil del frame time; tres
    // segundos seguidos por encima de 28ms (bajo 36fps) y se baja quality a
    // 0.75 una sola vez — no vuelve a subir sola, eso lo hace el hot-reload
    // del TOML si Ferox toca la perilla.
    property real frameAvgMs: 1000 / 60
    property real slowSince: -1
    FrameAnimation {
        running: crt.visible && (crt.showsText || crt.standby) && !crt.deepSleep
        onTriggered: {
            crt.tubeTime += frameTime;
            // el IOWN se mueve por cuadro: con el muestreo de 80 ms del reloj
            // del contenido, una palabra cruzando tres pantallas va a saltos.
            // songPos() extrapola con el reloj local, así que preguntarle cada
            // cuadro sale gratis y da una traslación continua.
            if (crt.iownMode) {
                crt.iownProg = crt.ctl.crtProgress();
                crt.iownX = crt.ctl.crtIownX(crt.idx);
            }
            crt.frameAvgMs = crt.frameAvgMs * 0.9 + frameTime * 1000 * 0.1;
            if (crt.frameAvgMs <= 28) {
                crt.slowSince = -1;
            } else {
                if (crt.slowSince < 0)
                    crt.slowSince = crt.tubeTime;
                else if (crt.tubeTime - crt.slowSince > 3 && crt.ctl.crtQuality > 0.75) {
                    crt.ctl.crtQuality = 0.75;
                    console.log("crt: quality auto 0.75");
                }
            }
        }
    }
    Timer {
        // el instrumental va por acá (20 fps, que es lo que necesita un motif);
        // dormido, 5 fps
        interval: crt.deepSleep ? 200 : 50
        repeat: true
        running: crt.visible && !crt.showsText && (!crt.standby || crt.deepSleep)
        onTriggered: crt.tubeTime += crt.deepSleep ? 0.2 : 0.05
    }

    // Encuadre: la pantalla con la letra se acerca y abre el cuadro; la que no,
    // queda lejos y con las bandas más gruesas. Eso es la "cámara" moviéndose.
    // Encuadre: nada de barras ni marcos — pantalla llena, cero distracción. Lo
    // único que se mueve es un acercamiento lento y continuo, que es de dónde
    // sale la sensación de fluidez: transformación sobre algo quieto, no
    // redibujo. La pantalla enfocada se acerca; la apagada queda un poco atrás.
    readonly property real cam: ctl.crtCamera
    // el acercamiento fijo es de la cámara; el que sigue al volumen es latido, y
    // el latido lo gradúa `flicker`: con la perilla en cero la cámara no respira
    // con la música, se queda quieta donde la puso el encuadre
    property real camZoom: 1 + cam * (focused
        ? 0.030 + 0.022 * pump * ctl.crtFlicker : 0.004)
    Behavior on camZoom { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

    Item {
        id: stage
        anchors.fill: parent

        // T5.3: modo karaoke. El tubo no se apaga (eso es el colapso, y deja la
        // ventana muerta): se queda OSCURO, esperando. No es standby — standby
        // dice "NO SIGNAL", que es la señal equivocada: acá hay señal, falta la
        // voz. El shader ya multiplica todo por qt_Opacity, así que oscurecer
        // el `stage` entero apaga también la estática y el fósforo.
        opacity: crt.ctl.singGlow

        // el FBO sólo existe mientras el tubo se ve, y se dibuja a menos
        // resolución de la que sale: el shader después le pasa curvatura, bloom
        // y grilla de fósforo por arriba, así que la diferencia no se ve — y sí
        // se nota en lo que cuesta tener tres pantallas enteras corriendo
        layer.enabled: crt.visible
        layer.textureSize: Qt.size(Math.max(1, Math.round(width * crt.ctl.crtQuality)),
                                   Math.max(1, Math.round(height * crt.ctl.crtQuality)))
        layer.samplerName: "src"
        layer.effect: ShaderEffect {
            blending: false
            property real t: crt.tubeTime
            property real curvature: crt.ctl.crtCurvature
            property real scanline: crt.ctl.crtScanlines
            // `intensity` es la perilla única: mueve el ruido, la separación de
            // canales y la barra que rueda, además de los golpes de glitch
            property real chroma: crt.ctl.crtChroma * (0.45 + 0.55 * crt.rest)
            // el fósforo late con la música; en la pantalla apagada se va a cero
            // y el shader se saltea las ocho muestras del bloom
            property real bloom: crt.showsText
                ? crt.ctl.crtBloom * (0.72 + 0.55 * crt.pump * crt.ctl.flickerAmt) : 0
            // el cambio de canal se lleva puesta la perilla: la estática de la
            // transición no es "ruido de fondo", es la pantalla sin señal
            property real noiseAmt: crt.chanNoise > 0 ? 1
                : crt.deepSleep ? 0
                : crt.ctl.crtNoise * (0.35 + 0.65 * crt.rest)
                * (crt.standby ? 3.5 : (crt.showsText ? 1 : 1.6))
            property real glitch: Math.min(crt.glitchAmt, 1)
            // La barra que rueda va atada al verso: arranca con el peso de
            // siempre y llega al doble sobre el final de la línea, así el
            // rodillo deja de ser un ciclo suelto del shader y acompaña a la
            // letra. Se refresca con los eventos de posición (1/s), que es la
            // velocidad a la que se percibe que la barra "carga".
            property real roll: crt.ctl.crtRoll * (0.25 + 0.75 * crt.rest)
                * (1 + crt.ctl.crtProgress())
            property real alarm: (crt.alarmLine || crt.chanFlash) ? 1 : 0
            property real vignette: crt.ctl.crtVignette
            // el titileo llega desde el audio, no del reloj del shader
            // el latido tiene su propia perilla (`flicker`), aparte de la
            // intensidad general: es lo primero que uno quiere bajar
            property real pulse: crt.beatPulse * (0.55 + 0.45 * crt.ctl.sectionEnergy)
                * (crt.focused ? 1 : 0.6) * crt.ctl.flickerAmt
            property real blink: crt.beatBlink
            property variant res: Qt.vector2d(Math.max(crt.width, 1), Math.max(crt.height, 1))
            property variant tint: crt.pal.tint
            fragmentShader: Qt.resolvedUrl("crt.frag.qsb")
        }

        Rectangle {
            anchors.fill: parent
            color: crt.pal.bg
            // El contagio se ve, pero no se dispara. Las dos caras de la paleta
            // son una clara y una oscura: cambiar de cara es dar vuelta la
            // pantalla entera, y en 190 ms eso no se lee como que el color se
            // mudó — se lee como un flash. Casi un segundo y es un lavado.
            Behavior on color { ColorAnimation { duration: 900; easing.type: Easing.InOutQuad } }
        }

        // ---- todo lo que la cámara mueve va acá adentro
        Item {
            id: camera
            anchors.fill: parent
            // el tirón del latido va acá, así la pantalla CON la letra también
            // acompaña el parpadeo y no sólo las de al lado
            transform: [
                Scale {
                    origin.x: camera.width / 2
                    origin.y: camera.height / 2
                    xScale: crt.camZoom * crt.cueZoom * (1 + 0.035 * crt.beatPulse
                                           + 0.02 * crt.gridPulse * crt.ctl.crtFlicker)
                    yScale: crt.camZoom * crt.cueZoom * (1 + 0.035 * crt.beatPulse
                                           + 0.02 * crt.gridPulse * crt.ctl.crtFlicker)
                },
                // el colapso del apagado: va aparte del encuadre para no pisarle
                // el binding a la cámara mientras el tubo se muere
                Scale {
                    origin.x: camera.width / 2
                    origin.y: camera.height / 2
                    xScale: crt.offX
                    yScale: crt.offY
                }
            ]

            // la pantalla prendida respira: el fondo sube y baja con la música,
            // no hay un "resplandor" separado porque el fondo YA es la luz
            Rectangle {
                anchors.fill: parent
                color: crt.pal.bg
                Behavior on color { ColorAnimation { duration: 900; easing.type: Easing.InOutQuad } }
                // el "respira" seguía el nivel del audio a 14 Hz: cada sílaba
                // movía el brillo de la pantalla entera. Ahora lo gradúa la
                // misma perilla del parpadeo.
                opacity: crt.showsText
                    ? 0.10 + 0.16 * crt.pump * crt.ctl.flickerAmt : 0.05
            }


            // ---- verso anterior, quemado en el fósforo mientras se apaga
            Text {
                anchors { fill: parent; margins: crt.pad }
                visible: crt.ghostFade > 0.01 && crt.showsText
                opacity: crt.ghostFade
                text: crt.ghostText.toUpperCase()
                color: crt.pal.dim
                font.family: crt.fontFamily
                font.bold: true
                font.letterSpacing: 2
                font.pixelSize: Math.round(crt.shortSide * 0.30)
                fontSizeMode: Text.Fit
                minimumPixelSize: 10
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            // ---- el pedazo que le toca a esta pantalla
            //
            // Con director, cada palabra APARECE cuando se canta: entra en blanco,
            // pega un tirón de señal y se asienta en el color. Nada de tener la
            // frase entera puesta y ir iluminándola — eso se lee como un karaoke,
            // y lo que se busca es que algo la escriba en la pantalla al momento.
            // ---- IOWN: una palabra sola, del alto de la pantalla, cruzando la
            // pared de derecha a izquierda mientras dura la línea. No se corta
            // ni se reparte: sale por el borde de un monitor y entra por el del
            // siguiente, así que la pared se lee como una pantalla sola.
            Text {
                id: iownWord
                visible: crt.iownMode && crt.showsText
                // el ancho propio entra en la cuenta para que la palabra salga
                // ENTERA por la izquierda al terminar la línea
                x: crt.iownX - crt.iownProg * implicitWidth
                anchors.verticalCenter: parent.verticalCenter
                text: crt.myText.toUpperCase()
                color: crt.pal.ink
                font.family: crt.fontFamily
                font.bold: true
                font.letterSpacing: 6
                font.pixelSize: Math.round(crt.shortSide * 0.7)
            }

            Item {
                id: lyric
                anchors { fill: parent; margins: crt.pad }
                visible: crt.showsText && !crt.iownMode
                // el pedazo que ya pasó queda prendido pero bajo, como fósforo
                // que todavía no se apagó: así se lee la frase entera de un vistazo
                opacity: crt.burned ? 0.42 : 1

                // Texto invisible que sólo sirve para saber a qué tamaño entra el
                // pedazo entero: las palabras sueltas después usan ESE tamaño, así
                // no queda cada una de un tamaño distinto.
                Text {
                    id: measure
                    anchors.fill: parent
                    visible: false
                    // se mide con una palabra por renglón, que es como se van a
                    // acomodar: centradas y grandes, como los monitores del clip
                    text: crt.myWords.join("\n").toUpperCase()
                    font.family: crt.fontFamily
                    font.bold: true
                    font.letterSpacing: 3
                    // una letra sola se merece la pantalla entera: es el golpe
                    // deletreado del estribillo, no una palabra más
                    font.pixelSize: Math.round(crt.shortSide
                        * (crt.myText.replace(/[^0-9a-zà-ÿ]/gi, "").length <= 2 ? 0.78 : 0.46))
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 12
                    lineHeight: 0.94
                    wrapMode: Text.NoWrap
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                // modo viejo (focus = "all"): la línea entera, iluminándose
                Text {
                    anchors.fill: parent
                    visible: crt.allMode
                    text: {
                        let out = "";
                        for (let i = 0; i < crt.myWords.length; i++) {
                            const c = crt.painted(i) ? crt.pal.hot : crt.pal.ink;
                            out += '<font color="' + c + '">'
                                + crt.ctl.htmlEscape(crt.myWords[i].toUpperCase()) + "</font> ";
                        }
                        return out;
                    }
                    textFormat: Text.StyledText
                    font.family: crt.fontFamily
                    font.bold: true
                    font.letterSpacing: 3
                    font.pixelSize: measure.fontInfo.pixelSize
                    lineHeight: 0.94
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                // modo director: una palabra por vez, apareciendo
                Column {
                    id: words
                    anchors.centerIn: parent
                    width: parent.width
                    visible: !crt.allMode
                    spacing: Math.round(measure.fontInfo.pixelSize * 0.02)

                    Repeater {
                        model: crt.allMode ? [] : crt.myWords

                        Item {
                            id: slot
                            required property int index
                            required property string modelData
                            width: words.width
                            height: label.implicitHeight * 0.88
                            // aparece recién cuando le toca sonar
                            readonly property bool landed: crt.reveal >= crt.dueFrac(index)
                            opacity: landed ? 1 : 0

                            // T3.5, estilo "type": la palabra no aparece, se
                            // escribe — un caracter cada 28 ms, con el cursor
                            // pegado atrás mientras dura. Se cuenta por code
                            // point y no por unidad UTF-16, si no un caracter
                            // japonés se escribe en dos mitades rotas.
                            readonly property int chars: Array.from(modelData).length
                            property int typed: 0
                            Timer {
                                interval: 28
                                repeat: true
                                running: crt.entryStyle === "type" && slot.landed
                                    && slot.typed < slot.chars
                                onTriggered: slot.typed++
                            }

                            transform: [
                                Scale { id: sc; origin.x: slot.width / 2; origin.y: slot.height / 2 },
                                Translate { id: tr }
                            ]

                            Text {
                                id: label
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: crt.entryStyle !== "type"
                                    ? slot.modelData.toUpperCase()
                                    : Array.from(slot.modelData.toUpperCase())
                                        .slice(0, slot.typed).join("")
                                        + (slot.typed < slot.chars ? "▮" : "")
                                color: crt.pal.ink
                                // la letra acompaña al fondo: si el fondo se
                                // lava en un segundo y la tinta salta de golpe,
                                // el salto de la tinta es el flash. (Las
                                // animaciones de entrada no pasan por acá: un
                                // Behavior no intercepta lo que anima otro.)
                                Behavior on color { ColorAnimation { duration: 900; easing.type: Easing.InOutQuad } }
                                font.family: crt.fontFamily
                                font.bold: true
                                font.letterSpacing: 3
                                font.pixelSize: measure.fontInfo.pixelSize
                            }

                            // fantasmas de canal desalineado: sólo mientras entra
                            Text {
                                x: label.x - slot.ghostOff
                                text: label.text
                                font: label.font
                                color: "#ff2d00"
                                opacity: slot.ghostFade * 0.55
                            }
                            Text {
                                x: label.x + slot.ghostOff
                                text: label.text
                                font: label.font
                                color: "#00c8ff"
                                opacity: slot.ghostFade * 0.55
                            }
                            property real ghostOff: 0
                            property real ghostFade: 0

                            onLandedChanged: {
                                if (landed) {
                                    typed = 0;
                                    entry.restart();
                                }
                            }

                            // La entrada: la palabra llega como si el televisor
                            // recién la sintonizara. El destello de color tiene su
                            // propia perilla (`word_flash`) porque pasa en CADA
                            // palabra — con el destello a full se lee como que la
                            // letra titila todo el tiempo, y no es lo mismo que el
                            // latido del tubo.
                            readonly property color entryTint: crt.ctl.crtWordFlash <= 0.01
                                ? crt.pal.ink
                                // proporción directa: el piso de 0.25 que tenía
                                // hacía que hasta en el mínimo la palabra entrara
                                // clarita, y el mínimo tiene que ser "nada"
                                : Qt.tint(crt.pal.ink, Qt.rgba(1, 1, 1, crt.ctl.crtWordFlash))
                            SequentialAnimation {
                                id: entry
                                PropertyAction { target: label; property: "color"; value: slot.entryTint }
                                // TODO el sacudón de entrada va por la misma
                                // perilla, no sólo el color: los fantasmas de
                                // canal y el tirón de tamaño pasan igual en cada
                                // palabra, así que con el destello apagado
                                // seguían leyéndose como que la letra vibra.
                                // `word_flash = 0` es la palabra entrando quieta.
                                PropertyAction { target: slot; property: "ghostOff"; value: measure.fontInfo.pixelSize * (crt.entryStyle === "roll" ? 0.34 : 0.22) * crt.ctl.crtWordFlash }
                                PropertyAction { target: slot; property: "ghostFade"; value: 0.85 * crt.ctl.crtWordFlash }
                                PropertyAction { target: sc; property: "xScale"; value: 1 + (crt.entryStyle === "slam" ? 0.35 : 0.06) * crt.ctl.crtWordFlash }
                                PropertyAction { target: sc; property: "yScale"; value: 1 + (crt.entryStyle === "slam" ? 0.35 : -0.18) * crt.ctl.crtWordFlash }
                                PropertyAction { target: tr; property: "y"; value: crt.entryStyle === "roll" ? -measure.fontInfo.pixelSize * 0.55 * crt.ctl.crtWordFlash : 0 }
                                PauseAnimation { duration: 28 }
                                ParallelAnimation {
                                    ColorAnimation { target: label; property: "color"; to: crt.pal.ink; duration: 70; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: sc; property: "xScale"; to: 1; duration: crt.entryStyle === "slam" ? 150 : 90; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: sc; property: "yScale"; to: 1; duration: crt.entryStyle === "slam" ? 150 : 90; easing.type: Easing.OutBack }
                                    NumberAnimation { target: tr; property: "y"; to: 0; duration: 140; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: slot; property: "ghostOff"; to: 0; duration: 110; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: slot; property: "ghostFade"; to: 0; duration: 120; easing.type: Easing.InQuad }
                                    SequentialAnimation {
                                        NumberAnimation { target: tr; property: "x"; from: -measure.fontInfo.pixelSize * 0.07 * crt.ctl.crtWordFlash; to: measure.fontInfo.pixelSize * 0.03 * crt.ctl.crtWordFlash; duration: 34 }
                                        NumberAnimation { target: tr; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
                                    }
                                }
                                // la animación de color rompe el binding; hay que
                                // devolvérselo o la palabra se queda con el color
                                // viejo cuando la pantalla se contagia otro
                                ScriptAction {
                                    script: label.color = Qt.binding(() => crt.pal.ink);
                                }
                            }
                        }
                    }
                }
            }

            // ---- pantalla sin letra: la animación que la mantiene viva
            Motif {
                anchors.fill: parent
                // en el instrumental corren TODAS: es la pared entera moviéndose
                // con el tema, que es justo lo que "NO SIGNAL" mataba
                visible: crt.idle || crt.instrumental
                kind: crt.ctl.crtMotifFor(crt.idx)
                // el destino acelera (×1.6 al final de la línea), las otras
                // apagadas se aquietan (×0.7) y bajan a 0.75 de opacidad
                energy: crt.ctl.sectionEnergy
                    * (crt.foreTarget ? 1 + 0.6 * crt.foreRamp : 1)
                    * (crt.foreOther ? 1 - 0.3 * crt.foreRamp : 1)
                dim: crt.foreOther ? 1 - 0.25 * crt.foreRamp : 1
                waterAmp: crt.ctl.crtWaterAmp
                // el registro de lo que suena: con el tubo apagado no hay
                // captura, y el laguito tiembla en un tono medio
                pitch: crt.live ? crt.ctl.audCentroid : 0.5
                colour: crt.motifColour
                hot: crt.pal.hot
                level: crt.pump
                low: crt.live ? crt.ctl.audLo : 0.4
                high: crt.live ? crt.ctl.audHi : 0.3
                beat: crt.ctl.audBeat
                beatAmt: crt.ctl.crtFlicker
                // cuando el tubo parpadea, la animación acompaña: se acelera y
                // crece un instante, así el golpe se ve en todas las pantallas.
                // Va por contador y no por magnitud: aunque el parpadeo esté
                // bajito, cuando pasa se tiene que ver acompañado.
                kick: crt.surgeGen
                clock: crt.tubeTime
                spinning: crt.visible && (crt.idle || crt.instrumental)
            }

            // ---- instrumental: no hay letra pero SÍ hay música. La pantalla
            // enfocada dice qué suena, en chico y abajo, como una consola; las
            // demás se quedan con su animación. "NO SIGNAL" es sólo para el
            // silencio.
            Text {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: Math.round(crt.shortSide * 0.08)
                }
                width: parent.width * 0.8
                visible: crt.instrumental && crt.idx === crt.ctl.crtShot.focus
                    && crt.ctl.npTitle !== ""
                text: (crt.ctl.npTitle + "  ·  " + crt.ctl.npInfo).toUpperCase()
                color: crt.pal.dim
                font.family: crt.fontFamily
                font.bold: true
                font.letterSpacing: 3
                font.pixelSize: Math.max(11, Math.round(crt.shortSide * 0.022))
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            // ---- sin señal: barras de ajuste y estática
            Item {
                id: standbyLayer
                anchors.fill: parent
                visible: crt.standby

                Row {
                    anchors.fill: parent
                    opacity: 0.18

                    Repeater {
                        model: ["#c0c0c0", "#c0c000", "#00c0c0", "#00c000", "#c000c0", "#c00000", "#0000c0", "#101010"]

                        Rectangle {
                            required property string modelData
                            width: standbyLayer.width / 8
                            height: standbyLayer.height
                            color: modelData
                        }
                    }
                }

                Text {
                    id: noSignal
                    anchors.centerIn: parent
                    width: parent.width * 0.7
                    // en el setup el número gigante va en el mismo lugar
                    visible: !crt.ctl.crtSetupOn
                    text: "NO SIGNAL"
                    color: crt.pal.hot
                    font.family: crt.fontFamily
                    font.bold: true
                    font.letterSpacing: 8
                    font.pixelSize: Math.round(crt.shortSide * 0.16)
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    opacity: blink ? 1 : 0.25
                    property bool blink: true

                    Timer {
                        interval: 900
                        repeat: true
                        running: crt.visible && crt.standby
                        onTriggered: noSignal.blink = !noSignal.blink
                    }
                }
            }

            // ---- `fatal crt setup`: qué número es esta pantalla. Se miran de
            // izquierda a derecha y ése es el orden de `[crt] order`; abajo va
            // el nombre del output, que es lo que se escribe en la lista.
            Item {
                anchors.fill: parent
                visible: crt.ctl.crtSetupOn

                Text {
                    anchors.centerIn: parent
                    text: crt.idx + 1
                    color: crt.pal.ink
                    font.family: crt.fontFamily
                    font.bold: true
                    font.pixelSize: Math.round(crt.shortSide * 0.8)
                }

                Text {
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        bottom: parent.bottom
                        bottomMargin: crt.pad * 2
                    }
                    text: (crt.scr.name || "?").toUpperCase()
                    color: crt.pal.dim
                    font.family: crt.fontFamily
                    font.bold: true
                    font.letterSpacing: 6
                    font.pixelSize: Math.round(crt.shortSide * 0.05)
                }
            }
        }

        // ---- fogonazo del golpe, sólo en la pantalla enfocada
        Rectangle {
            id: flash
            anchors.fill: parent
            color: crt.pal.hot
            opacity: 0
            function pulse() {
                flashAnim.restart();
            }
            NumberAnimation {
                id: flashAnim
                target: flash
                property: "opacity"
                from: 0.05 * crt.ctl.flickerAmt
                to: 0
                duration: 220
                easing.type: Easing.OutQuad
            }
        }

        // ---- chrome de consola industrial: rec, tema, timecode, barra
        Item {
            id: chrome
            anchors { fill: parent; margins: Math.round(crt.pad * 0.5) }
            visible: crt.ctl.crtChrome
            opacity: crt.focused || crt.standby ? 0.85 : 0.4

            readonly property int fs: Math.max(11, Math.round(crt.shortSide * 0.019))

            Row {
                anchors { left: parent.left; top: parent.top }
                spacing: Math.round(chrome.fs * 0.7)

                Rectangle {
                    id: recDot
                    width: chrome.fs * 0.7
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: crt.alarmLine ? "#ff3b30" : crt.pal.ink
                    opacity: on ? 1 : 0.15
                    property bool on: true

                    Timer {
                        interval: 700
                        repeat: true
                        running: crt.visible
                        onTriggered: recDot.on = !recDot.on
                    }
                }

                Text {
                    text: (crt.alarmLine ? "CRITICAL" : (crt.focused ? "REC" : "STBY"))
                        + "  //  CH0" + (crt.idx + 1) + "  " + crt.ctl.crtSchemeKey().toUpperCase()
                    color: crt.pal.ink
                    font.family: crt.fontFamily
                    font.pixelSize: chrome.fs
                    font.letterSpacing: 2
                    font.bold: true
                }
            }

            Text {
                anchors { right: parent.right; top: parent.top }
                text: crt.ctl.crtClock()
                color: crt.pal.ink
                font.family: crt.fontFamily
                font.pixelSize: chrome.fs
                font.letterSpacing: 2
                font.bold: true
            }

            Text {
                anchors { left: parent.left; right: parent.right; bottom: bar.top; bottomMargin: chrome.fs }
                text: crt.ctl.npTitle === "" ? "FATAL LYRICS"
                    : (crt.ctl.npTitle + "  ·  " + crt.ctl.npInfo).toUpperCase()
                color: crt.pal.dim
                font.family: crt.fontFamily
                font.pixelSize: chrome.fs
                font.letterSpacing: 2
                font.bold: true
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            // barra de progreso en bloques, como un medidor de consola
            Row {
                id: bar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Math.round(chrome.fs * 0.8)
                spacing: 3

                readonly property int cells: 48

                Repeater {
                    model: bar.cells

                    Rectangle {
                        required property int index
                        width: (bar.width - bar.spacing * (bar.cells - 1)) / bar.cells
                        height: bar.height
                        color: index / bar.cells <= crt.ctl.npProgress ? crt.pal.ink : crt.pal.dim
                        opacity: index / bar.cells <= crt.ctl.npProgress ? 0.9 : 0.25
                    }
                }
            }

            // esquineros de encuadre
            Repeater {
                model: [[0, 0], [1, 0], [0, 1], [1, 1]]

                Item {
                    required property var modelData
                    readonly property int arm: Math.round(chrome.fs * 2.2)
                    x: modelData[0] === 0 ? 0 : chrome.width - arm
                    y: modelData[1] === 0 ? chrome.height * 0.08 : chrome.height * 0.92 - arm
                    width: arm
                    height: arm

                    Rectangle {
                        width: parent.arm
                        height: 2
                        y: parent.modelData[1] === 0 ? 0 : parent.arm - 2
                        color: crt.pal.dim
                    }
                    Rectangle {
                        width: 2
                        height: parent.arm
                        x: parent.modelData[0] === 0 ? 0 : parent.arm - 2
                        color: crt.pal.dim
                    }
                }
            }
        }

        // La salida, escrita chiquita: se lee un rato cuando el tubo arranca y
        // después se apaga casi del todo. Queda ahí para el que la busque, sin
        // arruinar la pantalla — pero nadie queda encerrado sin saber cómo salir.
        Text {
            id: hint
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: Math.round(crt.pad * 0.75)
            }
            text: crt.grabKeyboard ? "ANY KEY RETURNS" : "MOVE THE MOUSE TO RETURN"
            color: crt.pal.ink
            font.family: crt.fontFamily
            font.pixelSize: Math.max(9, Math.round(crt.shortSide * 0.013))
            font.letterSpacing: 5
            opacity: 0.08

            // al prenderse se muestra un momento y se va desvaneciendo
            SequentialAnimation {
                id: hintIntro
                running: crt.visible
                NumberAnimation { target: hint; property: "opacity"; to: 0.6; duration: 250 }
                PauseAnimation { duration: 3200 }
                NumberAnimation { target: hint; property: "opacity"; to: 0.08; duration: 2500 }
            }
        }

        // El punto blanco en el que termina el colapso. Va acá adentro, no
        // encima del shader: el punto tiene que quedar detrás del mismo vidrio
        // que todo lo demás, si no se ve como un pixel dibujado sobre el tubo.
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(3, Math.round(crt.shortSide * 0.014))
            height: width
            radius: width / 2
            color: "#ffffff"
            opacity: crt.dotOpacity
            visible: crt.dotOpacity > 0.01
        }
    }

    // El mouse: puntero escondido mientras dura el tubo, y moverlo (o un click, o
    // la rueda) devuelve el escritorio. La ventana SÍ se come el input — es una
    // toma de la pantalla, no un adorno: si dejara pasar los clicks, la ventana
    // de abajo se comería uno que era para salir. Va último: el cursor lo decide
    // el ítem más alto abajo del puntero.
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        acceptedButtons: Qt.AllButtons
        onPressed: crt.ctl.crtExit()
        onWheel: crt.ctl.crtExit()

        // mover el mouse también saca del tubo. Con un margen: se arma medio
        // segundo después de prender (si no, el mismo click que lo prendió o el
        // cursor acomodándose lo apagan al instante) y pide unos píxeles de
        // recorrido, para que un temblor de la mano no tire todo abajo.
        property bool armed: false
        property real ax: -1
        property real ay: -1
        onPositionChanged: mouse => {
            if (!armed)
                return;
            if (ax < 0) {
                ax = mouse.x;
                ay = mouse.y;
                return;
            }
            if (Math.abs(mouse.x - ax) + Math.abs(mouse.y - ay) > 24)
                crt.ctl.crtExit();
        }

        Timer {
            interval: 600
            running: crt.visible
            onTriggered: {
                pointer.ax = -1;
                pointer.armed = true;
            }
        }
        Connections {
            target: crt
            function onVisibleChanged() {
                if (!crt.visible)
                    pointer.armed = false;
            }
        }
    }
}
