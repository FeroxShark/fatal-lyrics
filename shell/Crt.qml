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
    Component.onCompleted: {
        tubeOn = ctl.crtOn;
        // el dibujo de arranque no pasa por el puente: no hay de qué venir
        motifShown = motifKind;
    }

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

    // ---- qué dibujo le toca a esta pantalla
    // Sale por una property y no directo en el `kind` del Motif para poder
    // CONTARLO: cuántas veces cambia de dibujo una pantalla por minuto es el
    // número que Ferox describió como "las animaciones cambian y no llegás a
    // entender qué ves", y sin marca en el log no se mide ni antes ni después.
    readonly property string motifKind: ctl.crtMotifFor(idx)
    onMotifKindChanged: {
        if (ctl.crtOn)
            console.log("crt: motif s" + idx + " " + motifKind);
        // T4.3: el cambio lleva PUENTE. Hasta acá el Loader cortaba seco y un
        // dibujo se convertía en otro en un cuadro, que es lo que hace que la
        // pared se lea como ruido aunque cada dibujo esté bien. Se va rápido
        // (`exitMs`, InQuad), se cambia con la pantalla apagada y entra con
        // snap (`enterMs`, OutExpo) — el corte del video de referencia.
        //
        // El puente NO va por `dim`: esa property tiene un Behavior de 220 ms,
        // así que el ScriptAction del cambio caería con el dibujo viejo todavía
        // a media luz. `swap` no tiene Behavior: lo que se ve es exactamente
        // la curva de acá.
        if (motifShown === "")
            motifShown = motifKind;      // el primero no tiene de qué venir
        else
            motifBridge.restart();
    }
    property string motifShown: ""
    property real motifSwap: 1
    SequentialAnimation {
        id: motifBridge
        NumberAnimation {
            target: crt; property: "motifSwap"; to: 0
            duration: Motion.exitMs; easing.type: Easing.InQuad
        }
        ScriptAction { script: crt.motifShown = crt.motifKind; }
        NumberAnimation {
            target: crt; property: "motifSwap"; to: 1
            duration: Motion.enterMs; easing.type: Easing.OutExpo
        }
    }

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

    // A dónde mira la pared: a la pantalla enfocada, y durante el aviso del
    // salto (el último 40% del verso) a la que va a recibir la frase. -1 en
    // cualquiera de las dos puntas es mirar al frente.
    readonly property int gazeAt: (foreOn && foreRamp > 0.15) ? ctl.crtNextFocus
                                                              : ctl.crtShot.focus
    readonly property real motifGaze: gazeAt < 0 || gazeAt === idx
        ? 0 : (gazeAt > idx ? 1 : -1)

    // ------------------------------------------------- el aro que cuenta (T2.2)
    // Va en la pantalla DONDE VA A CAER la próxima línea, y sólo si esa
    // pantalla no tiene nada de la que suena: encima del texto sería un
    // adorno, no un aviso.
    //
    // TANDA 4: la decisión NO se toma acá. Prenderlo y apagarlo tiene memoria
    // (aparece con más de 1.4 s por delante y con la voz de la línea que suena
    // ya terminada, y se queda hasta después de la hora), y eso es estado del
    // root, no un binding por pantalla — `show()` además le pregunta al root
    // dónde ESTABA el aro para elegir la entrada de esta pantalla. Acá sólo se
    // lee en qué pantalla está.
    readonly property bool ringShows: ctl.crtRingLive === idx

    // ------------------------------------------------ el salto de pantalla (T2.3)
    // La frase saltó a una pantalla que NO es la de al lado. Lo que se ve es el
    // viaje: una franja de scanlines cruza cada pantalla del medio en su tramo
    // del reloj, la del medio glitchea justo cuando le pasa por encima, y la de
    // origen pega un tirón hacia donde se fue. El texto del medio no se toca:
    // la franja pasa por arriba, no lo reemplaza.
    //
    // El reloj (0→1 en `crtHopMs`, más la cola) sale de `ctl.crtHopStart`, que
    // es del root: acá se LEE por cuadro. Cada pantalla anotándose su propio
    // arranque hacía que la cabeza entrara en la segunda antes de salir de la
    // primera.
    //
    // El reparto del reloj: la pantalla de origen se lleva el 22 % (las hebras
    // saliendo de la letra), las del medio el 56 % entre todas, y el destino el
    // 22 % final. Después de eso quedan 150 ms de cola apagándose ENCIMA de la
    // línea que ya entró, que es lo que ata el viaje con la frase.
    readonly property real hopTailFrac: 150 / Math.max(ctl.crtHopMs, 1)
    property real hopClock: 2
    readonly property bool hopLive: ctl.crtHopStart > 0 && ctl.crtHop.from >= 0
    readonly property bool hopCorridor: ctl.crtHopMode === "corridor"
        || ctl.crtHopMode === "both"
    readonly property bool hopInterf: ctl.crtHopMode === "interference"
        || ctl.crtHopMode === "both"
    readonly property bool hopFrom: hopLive && ctl.crtHop.from === idx
    readonly property bool hopTo: hopLive && ctl.crtHop.to === idx
    // ¿esta pantalla queda EN EL MEDIO del salto?
    readonly property bool hopMid: hopLive
        && idx > Math.min(ctl.crtHop.from, ctl.crtHop.to)
        && idx < Math.max(ctl.crtHop.from, ctl.crtHop.to)
    // cuántas pantallas hay en el medio y cuál es ésta, contadas en el sentido
    // del viaje: cada una recibe un tramo igual del reloj (con dos, [0,0.5] y
    // [0.5,1]), así la franja se pasa de una a la otra sin superponerse
    readonly property int hopMids: Math.max(
        Math.abs(ctl.crtHop.to - ctl.crtHop.from) - 1, 1)
    readonly property int hopPos: ctl.crtHop.dir > 0
        ? idx - ctl.crtHop.from - 1 : ctl.crtHop.from - idx - 1
    // Cuánto avanzó el rayo DENTRO de esta pantalla. En la de origen y en las
    // del medio se lo deja pasar de 1 (hasta que la cola termina de salir por
    // el borde); en la de destino se clava en 1, que es el centro, y lo que
    // sigue es la cola apagándose.
    readonly property real hopRayP: {
        if (!hopLive || !hopCorridor)
            return 0;
        if (hopFrom)
            return Math.min(Math.max(hopClock / 0.22, 0), 1.45);
        if (hopMid)
            return Math.min(Math.max(
                (hopClock - 0.22) / 0.56 * hopMids - hopPos, 0), 1.45);
        if (hopTo)
            return Math.min(Math.max((hopClock - 0.78) / 0.22, 0), 1);
        return 0;
    }
    readonly property real hopRayFade: hopTo
        ? Math.min(Math.max(1 - (hopClock - 1) / hopTailFrac, 0), 1) : 1
    // el tramo del degradado que le toca a esta pantalla: el color va del de la
    // letra que se va al de la que llega a lo largo de TODO el viaje
    readonly property real hopRayG0: hopFrom ? 0
        : (hopMid ? 0.22 + 0.56 * hopPos / hopMids : 0.78)
    readonly property real hopRayG1: hopFrom ? 0.22
        : (hopMid ? 0.22 + 0.56 * (hopPos + 1) / hopMids : 1)

    // La crominancia por cuatro mientras el rayo pasa por encima. Duraba TRES
    // CUADROS, contados en cuadros: a 60 Hz son 50 ms y a 200 Hz son 15, y en
    // los dos casos pasa sin que nadie lo registre (T3.B6). Ahora dura por
    // reloj, mínimo 120 ms, y termina con UN cuadro al doble: el ojo necesita
    // un final para saber que hubo algo, si no lee un parpadeo del monitor.
    readonly property int glitchMinMs: 120
    property real hopChroma: 1
    property double hopChromaUntil: 0
    property bool hopChromaPunch: false
    FrameAnimation {
        // corre sólo durante el salto (y los tres cuadros del glitch): el resto
        // del tiempo la pantalla del medio sigue a sus 20 fps de siempre
        running: crt.visible
            && (crt.hopClock < 1 + crt.hopTailFrac || crt.hopChromaUntil > 0)
        onTriggered: {
            const now = Date.now();
            const end = 1 + crt.hopTailFrac;
            crt.hopClock = crt.ctl.crtHopStart > 0
                ? Math.min((now - crt.ctl.crtHopStart) / crt.ctl.crtHopMs, end)
                : end;
            if (crt.hopChromaUntil > 0 && now >= crt.hopChromaUntil) {
                if (!crt.hopChromaPunch) {
                    // el cuadro de más, al doble: el remate del glitch
                    crt.hopChromaPunch = true;
                    crt.hopChroma = 8;
                } else {
                    crt.hopChromaPunch = false;
                    crt.hopChromaUntil = 0;
                    crt.hopChroma = 1;
                }
            }
        }
    }
    Timer {
        // se dispara cuando la franja está sobre ESTA pantalla: el medio de su
        // tramo, medido contra el mismo arranque que publicó el root
        id: hopGlitch
        onTriggered: {
            crt.hopChroma = 4;
            crt.hopChromaPunch = false;
            crt.hopChromaUntil = Date.now() + crt.glitchMinMs;
            // por el portero de siempre: si esta pantalla acaba de romperse,
            // que se descarte es lo correcto
            crt.hit(0.25);
        }
    }
    // la pantalla que se quedó vacía acusa el golpe: el verso se corre hacia
    // donde saltó la frase y vuelve
    property real hopShift: 0
    SequentialAnimation {
        id: hopKick
        ScriptAction { script: crt.hit(0.4) }
        NumberAnimation {
            target: crt; property: "hopShift"
            to: crt.ctl.crtHop.dir * 16
            duration: 60; easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: crt; property: "hopShift"; to: 0
            duration: 140; easing.type: Easing.OutQuad
        }
    }
    Connections {
        target: crt.ctl
        function onCrtHopStartChanged() {
            if (crt.ctl.crtHopStart <= 0) {
                // cancelado a mitad de camino (hotplug, config, otro tema)
                hopGlitch.stop();
                crt.hopClock = 1 + crt.hopTailFrac;
                crt.hopChroma = 1;
                crt.hopChromaUntil = 0;
                crt.hopChromaPunch = false;
                return;
            }
            crt.hopClock = 0;
            if (crt.hopFrom) {
                hopKick.restart();
                return;
            }
            if (!crt.hopMid || !crt.hopInterf)
                return;
            // cuándo le pasa el rayo por encima a ESTA pantalla: el tramo del
            // medio arranca al 22 % del reloj y se reparte entre las
            // intermedias
            hopGlitch.interval = Math.max(Math.round(
                (0.22 + 0.56 * (crt.hopPos + 0.5) / crt.hopMids)
                * crt.ctl.crtHopMs
                - (Date.now() - crt.ctl.crtHopStart)), 1);
            hopGlitch.restart();
        }
    }

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
    // el estilo de entrada lo reparte el root al llegar la línea (un estilo por
    // pantalla, pesado por lo que está sonando): acá sólo se lee el que tocó
    readonly property string entryStyle: ctl.crtEntryStyles[idx] || "snap"
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
            // el mismo acercamiento, un poco más largo cuando lo que viene es
            // el drop que el zoom por sección va a abrir: la anticipación es
            // ÉSTA, no una rampa nueva al lado
            cueAnim.to = crt.sectionZoomOn && crt.ctl.audComing === "drop"
                ? 1.09 : 1.055;
            cueAnim.restart();
        }
        function onSectionGenChanged() {
            // T4.1: el ÚNICO cambio de parte que mueve la cámara es el drop, y
            // la mueve un momento. El resto de las secciones no tienen plano
            // propio: el tubo se queda donde estaba.
            if (crt.sectionZoomOn && crt.ctl.audSection === "drop") {
                sectionKick.restart();
                crt.hit(1);
            }
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
        duration: Motion.levelMs
        easing.type: Easing.OutQuad
    }
    // Un solo portero para TODOS los glitches. Había cinco cosas distintas
    // pidiéndolo — cada palabra, cada golpe, el cambio de línea, el contagio de
    // color y la interferencia sola — y sumadas dejaban la pantalla vibrando sin
    // parar. Ahora entra uno cada tanto: el que llega tarde se descarta, salvo
    // que venga mucho más fuerte que el que está sonando.
    property double lastHitAt: 0
    // con el compás medido la espera se redondea a un número entero de tiempos:
    // el glitch entra en el pulso del tema, no en el medio.
    //
    // T4.3: el número sale de la tabla de `pace` y está escrito en SEGUNDOS DE
    // VERDAD — el 0.45 es el `intensity` de fábrica, así que con la perilla
    // como viene, `normal` son exactamente los 4 s del presupuesto. Sin ese
    // factor la tabla diría 4000 y la pared esperaría 8.9 s.
    readonly property int hitGap: Math.round(
        ctl.quantize(ctl.pace.hitGapMs * 0.45 / Math.max(ctl.crtIntensity, 0.25)))
    function hit(amount) {
        const now = Date.now();
        if (now - lastHitAt < hitGap && amount < glitchAmt * 1.5)
            return;
        lastHitAt = now;
        // el presupuesto de eventos se MIDE, no se estima: cada glitch que
        // pasa el portero deja su marca, y con eso se cuentan las roturas por
        // minuto antes y después de tocar cualquier número (tanda 4, corrida 3)
        console.log("crt: hit s" + idx + " " + amount.toFixed(2));
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
        // 60 ms de ruido no se leen como un cambio de canal: se leen como que
        // el monitor parpadeó (T3.B6, el mínimo de 120 ms)
        PauseAnimation { duration: 130 }
        PropertyAction { target: crt; property: "chanFlash"; value: true }
        PauseAnimation { duration: 16 }
        PropertyAction { target: crt; property: "chanFlash"; value: false }
        PropertyAction { target: crt; property: "chanNoise"; value: 0 }
        // el texto ya está puesto: la rotura es la del emisor de siempre, no
        // una segunda fuente de glitch compitiendo con hit()
        ScriptAction { script: { console.log("crt: chan s" + crt.idx); crt.hit(1.0); } }
    }

    // -------------------------------------------- entradas del verso (T3.1)
    // Tres formas nuevas de que la línea aparezca, elegidas por el director del
    // root (ctl.crtEntryStyles). Las animaciones se declaran ACÁ ARRIBA, antes
    // del handler que las dispara: no por gusto — el `id` de una animación
    // declarada más abajo no resuelve desde el cuerpo de un handler.
    //
    // interlace: el tubo recibe medio cuadro. Aparecen las scanlines pares,
    // un cuadro después las impares, parpadea dos veces entre los dos campos
    // y recién ahí se asienta. Es un uniform del shader (interlacePhase), no
    // dos capas de texto: la mitad que falta es de la SEÑAL, no de la letra.
    property real interlacePhase: 0
    SequentialAnimation {
        id: interlaceAnim
        PropertyAction { target: crt; property: "interlacePhase"; value: 1 }
        PauseAnimation { duration: 40 }
        PropertyAction { target: crt; property: "interlacePhase"; value: 2 }
        PauseAnimation { duration: 40 }
        PropertyAction { target: crt; property: "interlacePhase"; value: 1 }
        PauseAnimation { duration: 40 }
        PropertyAction { target: crt; property: "interlacePhase"; value: 2 }
        PauseAnimation { duration: 40 }
        PropertyAction { target: crt; property: "interlacePhase"; value: 0 }
    }

    // tubeon: el apagado de tubo al revés — punto, raya, imagen, 220 ms. El
    // punto y la raya son el haz (beam, más abajo); la imagen es el texto
    // abriéndose en vertical desde la raya. Es la entrada obligatoria cuando la
    // línea cae donde estaba el aro: el aro colapsa en un punto, y ese punto es
    // éste abriéndose.
    property real tubeOnY: 1
    property real beamW: 0
    property real beamFade: 0
    SequentialAnimation {
        id: tubeOnAnim
        ScriptAction { script: crt.hit(0.35) }
        PropertyAction { target: crt; property: "tubeOnY"; value: 0.02 }
        PropertyAction { target: crt; property: "beamFade"; value: 1 }
        // el punto se estira hasta ser una raya de lado a lado
        NumberAnimation {
            target: crt; property: "beamW"; from: 0.015; to: 1
            duration: 90; easing.type: Easing.OutQuad
        }
        // y la raya se abre en la imagen mientras se apaga
        ParallelAnimation {
            NumberAnimation {
                target: crt; property: "tubeOnY"; to: 1
                duration: 130; easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: crt; property: "beamFade"; to: 0
                duration: 130; easing.type: Easing.InQuad
            }
        }
    }

    // overburn: cada palabra entra sobrequemada (blanco puro y el fósforo por
    // tres) y baja al color de la paleta en 200 ms. El fogonazo del fósforo es
    // uno solo por palabra y va acá, no en el delegate: el bloom es del tubo.
    property real burnGlow: 0
    NumberAnimation {
        id: burnAnim
        target: crt
        property: "burnGlow"
        from: 1
        to: 0
        duration: 200
        easing.type: Easing.OutQuad
    }
    function burnFlash() {
        burnAnim.restart();
    }
    // Sin `words` (LRC "enhanced") el overburn no tiene reloj propio de palabra:
    // va UNA POR TIEMPO, contando los golpes del compás. `burnStep` arranca en
    // 0 y no en 1 a propósito: onLandedChanged no se dispara con el valor
    // inicial del delegate, así que la palabra 0 naciendo ya encendida nunca se
    // quemaría — el primer beat es el que la trae.
    property int burnStep: 0
    property int burnStride: 1
    // y se pone en cero cuando aparece EL TEXTO DE ESTA PANTALLA, no sólo con
    // el verso: en un relay el segundo pedazo arranca tiempos después de la
    // línea, y con el contador ya corriendo sus primeras palabras nacen puestas
    // (sin onLandedChanged, o sea sin quemadura)
    onMyTextChanged: burnStep = 0
    readonly property bool burnMode: entryStyle === "overburn" && !lineWords
    Connections {
        target: crt.ctl
        enabled: crt.visible && crt.burnMode
        function onBeatTickChanged() {
            crt.burnStep += crt.burnStride;
        }
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
                // T4.3: la patada de señal del verso sólo cuando el foco se
                // MUDÓ de pantalla y pasó el hold. Un verso más en la misma
                // pantalla no es un cambio de escena: romper ahí es lo que
                // hacía que la pared pegara un golpe cada tres segundos.
                // Y si el aro estaba contando ACÁ, el que rompe es el aro
                // (`onCollapsed`, ~100 ms después): dos roturas en la misma
                // pantalla con 100 ms de diferencia se leen como una falla.
                const moved = crt.ctl.crtHop.from >= 0;
                const wasRing = crt.ctl.crtRingWas === crt.idx;
                const held = Date.now() - crt.lastHitAt >= Motion.holdMs;
                if (moved && held && !wasRing)
                    crt.hit(0.35 + Math.random() * 0.3);
                // las entradas que son de la PANTALLA (no de cada palabra)
                // arrancan acá, con la línea ya puesta
                if (crt.entryStyle === "interlace")
                    interlaceAnim.restart();
                else if (crt.entryStyle === "tubeon")
                    tubeOnAnim.restart();
            }
            crt.reveal = 0;
            // el reloj del overburn sin `words`: una palabra por tiempo, de a
            // dos si la línea no entra en los tiempos que quedan hasta la que
            // viene (si no, la última palabra suena cuando ya cambió el verso)
            crt.burnStep = 0;
            const beats = crt.ctl.beatMs > 0
                ? ((crt.ctl.crtLine.t1 || 0) - (crt.ctl.crtLine.t0 || 0)) * 1000 / crt.ctl.beatMs
                : 0;
            crt.burnStride = (beats > 0 && crt.myWords.length > beats) ? 2 : 1;

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

    // El cambio de canal lo dispara el ROOT (T4.3): la pared entera cambia de
    // canal junta — que es lo que hace un televisor — y el portero de cuántas
    // veces por minuto vive en un solo lugar. Hasta la tanda 3 colgaba del
    // serial de la línea, y entonces cada pantalla decidía por su cuenta con
    // un dato (`shot.chan`) que ya venía sorteado.
    Connections {
        target: crt.ctl
        enabled: crt.visible
        function onCrtChanGenChanged() { chanAnim.restart(); }
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
    // ---- IOWN (T3.B5): la palabra se ancla, no se desliza
    // En qué pantalla está la palabra ahora mismo, refrescado por cuadro; y el
    // "punto → raya → palabra" con el que entra en cada una, que es el mismo
    // encendido de tubo de la entrada `tubeon`.
    property int iownAt: -1
    readonly property bool iownHere: iownMode && showsText && iownAt === idx
    property real iownOpen: 0
    property real iownBeam: 0
    onIownHereChanged: {
        iownOut.stop();
        iownIn.stop();
        if (iownHere)
            iownIn.restart();
        else if (iownOpen > 0.01)
            iownOut.restart();
    }
    SequentialAnimation {
        id: iownIn
        PropertyAction { target: crt; property: "iownOpen"; value: 0 }
        NumberAnimation { target: crt; property: "iownBeam"; from: 0; to: 1;
                          duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: crt; property: "iownOpen"; from: 0; to: 1;
                          duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { target: crt; property: "iownBeam"; to: 0;
                          duration: 130; easing.type: Easing.OutQuad }
    }
    SequentialAnimation {
        id: iownOut
        // el apagado del tubo, al revés que la entrada: la palabra se cierra a
        // una raya y la raya se va
        NumberAnimation { target: crt; property: "iownOpen"; to: 0.02;
                          duration: 120; easing.type: Easing.InQuad }
        PropertyAction { target: crt; property: "iownOpen"; value: 0 }
    }
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
            if (crt.iownMode)
                crt.iownAt = crt.ctl.crtIownScreen();
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
    //
    // T3.A3: son DOS sumandos y no un número solo, porque tienen tiempos
    // distintos. El plano (cerca si esta pantalla tiene la frase, lejos si no)
    // cambia de una: la línea nueva nace ya con su tamaño, y el corte lo tapa
    // la patada de señal que llega con ella. El latido es el sumando de abajo.
    // Viajando los dos juntos por un Behavior de 520 ms, cada muestra de audio
    // (una cada 70 ms) reiniciaba el tween del plano: la pantalla que acababa
    // de recibir la línea tardaba como un tercio de segundo en llegar a su
    // encuadre y la frase se veía NACER CHICA y crecer.
    readonly property real camFocus: 1 + cam * (focused ? 0.030 : 0.004)
    // El latido SÍ lleva su propio filtro, sólo que corto: `pump` ya viene
    // suavizado a 90 ms, pero el tween que se reinicia con cada muestra es el
    // que hacía que el acercamiento se leyera continuo y no como que sigue la
    // onda. Reiniciar un tween con cada valor está bien para una señal chica
    // como ésta — lo que estaba mal era hacerlo con el PLANO, que es un salto
    // grande y se quedaba a mitad de camino.
    property real camBreath: focused ? cam * 0.022 * pump * ctl.crtFlicker : 0
    Behavior on camBreath { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
    readonly property real camZoom: camFocus + camBreath

    // T4.1: el plano de la LETRA, y sólo de la letra.
    //
    // Hasta la tanda 3 el tamaño del verso salía del plano de la sección: en la
    // estrofa la cámara se iba a 0.85 y la frase con ella. Sacar ese plano
    // (ahora la cámara descansa en 1) dejaría la letra un 18 % más grande que
    // en `a85fefc`, que es justo lo contrario de lo que pidió Ferox. Así que el
    // 0.85 de la estrofa se le queda a la letra, como una constante: el verso
    // mide exactamente lo que medía antes, y la cámara no tiene que alejarse
    // para conseguirlo — que es lo que dejaba el marco alrededor del motivo.
    readonly property real textPlane: sectionZoomOn
        ? Math.max(1 - 0.15 * cam, 0.5) : 1

    // T4.1: la cámara sigue la PARTE del tema, pero como un GOLPE y no como un
    // estado. Hasta la tanda 3 cada sección tenía su plano sostenido (estrofa
    // 0.85, drop 1.30): el tubo pasaba la canción entera con un zoom puesto y
    // eso es lo que Ferox leyó como "está todo agrandado por default". Ahora el
    // plano DESCANSA en 1 y sólo el drop pega un empujón que se va solo.
    //
    // Que nunca baje de 1 no es un detalle estético: los otros tres factores
    // del Scale (`camZoom`, `cueZoom`, el tirón del latido) tampoco bajan, así
    // que el encuadre es SIEMPRE >= 1 y ningún dibujo a sangre puede dejar un
    // marco de fondo plano alrededor. Ésa era toda la razón del overscan de la
    // tanda 3 (`motifFrame` agrandado por 1/zoomMin), que ya no existe. Si
    // algún día un plano vuelve a bajar de 1, vuelve el marco.
    readonly property bool sectionZoomOn: ctl.crtSectionZoom && cam > 0.01
    // El empujón del drop. Entra en 350 ms, se sostiene medio segundo y afloja
    // en 1.4 s: se ve el cambio de parte, no queda un zoom puesto.
    property real sectionZoom: 1
    SequentialAnimation {
        id: sectionKick
        NumberAnimation {
            target: crt; property: "sectionZoom"
            to: 1 + 0.12 * crt.cam; duration: 350; easing.type: Easing.OutCubic
        }
        PauseAnimation { duration: 500 }
        NumberAnimation {
            target: crt; property: "sectionZoom"
            to: 1; duration: 1400; easing.type: Easing.InOutQuad
        }
    }
    // la perilla apagada (o un hotplug a mitad de golpe) tiene que dejar el
    // plano donde descansa, no donde lo agarró la animación
    onSectionZoomOnChanged: {
        if (!sectionZoomOn) {
            sectionKick.stop();
            sectionZoom = 1;
        }
    }

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
            // x4 los tres cuadros en que la franja del salto pasa por acá
            property real chroma: crt.ctl.crtChroma * (0.45 + 0.55 * crt.rest)
                * crt.hopChroma
            // el fósforo late con la música; en la pantalla apagada se va a cero
            // y el shader se saltea las ocho muestras del bloom
            // el overburn multiplica el fósforo por tres mientras la palabra
            // está blanca: es lo que hace que se lea como quemada y no como
            // una palabra clara
            property real bloom: crt.showsText
                ? crt.ctl.crtBloom * (0.72 + 0.55 * crt.pump * crt.ctl.flickerAmt)
                    * (1 + 2 * crt.burnGlow) : 0
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
            // 0 = nada, 1 = sólo las pares, 2 = sólo las impares
            property real interlacePhase: crt.interlacePhase
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
                    xScale: crt.camZoom * crt.cueZoom * crt.sectionZoom
                        * (1 + 0.035 * crt.beatPulse
                           + 0.02 * crt.gridPulse * crt.ctl.crtFlicker)
                    yScale: crt.camZoom * crt.cueZoom * crt.sectionZoom
                        * (1 + 0.035 * crt.beatPulse
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
                id: ghost
                anchors { fill: parent; margins: crt.pad }
                // el tirón del salto: en la pantalla de origen esto es lo único
                // que queda de la frase, así que es lo que se tiene que ir
                transform: [
                    // el plano de la letra (T4.1): el quemado tiene que medir
                    // lo mismo que el verso del que salió
                    Scale {
                        origin.x: ghost.width / 2
                        origin.y: ghost.height / 2
                        xScale: crt.textPlane
                        yScale: crt.textPlane
                    },
                    Translate { x: crt.hopShift }
                ]
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
            // ---- IOWN: una palabra sola, del alto de la pantalla, que golpea
            // una pantalla por vez de derecha a izquierda. Entra con el
            // encendido del tubo (punto → raya → palabra), se queda, y se
            // cierra a una raya al pasar a la siguiente: tres golpes, no un
            // deslizamiento (T3.B5).
            Item {
                anchors.fill: parent
                visible: crt.iownMode && crt.showsText && crt.iownOpen > 0.005

                Text {
                    id: iownWord
                    anchors.centerIn: parent
                    // La palabra entra ENTERA aunque la cámara esté encima. El
                    // IOWN cae en el drop, que es justo el plano más cerca
                    // (1.6): midiendo contra la pantalla pelada, la palabra
                    // salía cortada por los dos lados y una palabra cortada no
                    // se lee, que era la mitad de la queja.
                    width: (parent.width - crt.pad * 2)
                        / Math.max(crt.sectionZoom * crt.camZoom * crt.cueZoom, 1)
                    horizontalAlignment: Text.AlignHCenter
                    text: crt.myText.toUpperCase()
                    color: crt.pal.ink
                    font.family: crt.fontFamily
                    font.bold: true
                    font.letterSpacing: 6
                    font.pixelSize: Math.round(crt.shortSide * 0.7)
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 10
                    transform: Scale {
                        origin.x: iownWord.width / 2
                        origin.y: iownWord.height / 2
                        yScale: crt.iownOpen
                    }
                }

                // la raya del haz: lo único que hay antes de que la palabra se
                // abra, y lo último que queda cuando se cierra
                Rectangle {
                    anchors.centerIn: parent
                    visible: crt.iownBeam > 0.01
                    width: Math.max(parent.width * (0.15 + 0.75 * crt.iownBeam), 3)
                    height: 3
                    radius: 1.5
                    color: crt.pal.hot
                    opacity: crt.iownBeam
                }
            }

            Item {
                id: lyric
                anchors { fill: parent; margins: crt.pad }
                transform: [
                    // el plano de la letra (T4.1). Es un Scale y no un factor
                    // sobre `font.pixelSize` porque el tamaño del verso lo
                    // deciden DOS cosas — el tope en píxeles y la caja del
                    // `Text.Fit` —, y con el plano de la cámara las dos se
                    // achicaban juntas. Tocando sólo el tope, una línea larga
                    // (limitada por la caja) no cambiaría de tamaño.
                    Scale {
                        origin.x: lyric.width / 2
                        origin.y: lyric.height / 2
                        xScale: crt.textPlane
                        yScale: crt.textPlane
                    },
                    // el tubo prendiéndose: la imagen se abre en vertical desde
                    // la raya del haz (tubeon). El resto del tiempo vale 1.
                    Scale {
                        origin.x: lyric.width / 2
                        origin.y: lyric.height / 2
                        yScale: crt.tubeOnY
                    },
                    Translate { x: crt.hopShift }
                ]
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
                            // aparece recién cuando le toca sonar. Con
                            // `overburn` sin tiempos por palabra el reloj es el
                            // compás (una por tiempo); el `reveal >= 1` de
                            // atrás es el paracaídas: si el compás se pierde a
                            // mitad de línea, las que faltan aparecen igual en
                            // vez de no llegar nunca.
                            readonly property bool landed: crt.burnMode
                                ? (index < crt.burnStep || crt.reveal >= 1)
                                : crt.reveal >= crt.dueFrac(index)
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
                            readonly property color entryTint: crt.entryStyle === "overburn"
                                // sobrequemada: blanco puro, pase lo que pase
                                // con `word_flash` — es lo que define la entrada
                                ? "#ffffff"
                                : crt.ctl.crtWordFlash <= 0.01
                                ? crt.pal.ink
                                // proporción directa: el piso de 0.25 que tenía
                                // hacía que hasta en el mínimo la palabra entrara
                                // clarita, y el mínimo tiene que ser "nada"
                                : Qt.tint(crt.pal.ink, Qt.rgba(1, 1, 1, crt.ctl.crtWordFlash))
                            SequentialAnimation {
                                id: entry
                                ScriptAction {
                                    script: if (crt.entryStyle === "overburn")
                                        crt.burnFlash();
                                }
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
                                    // el blanco del overburn baja despacio (200 ms):
                                    // es una quemadura del fósforo, no un destello
                                    ColorAnimation { target: label; property: "color"; to: crt.pal.ink; duration: crt.entryStyle === "overburn" ? 200 : 70; easing.type: Easing.OutQuad }
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

            // ---- el haz del tubo prendiéndose (entrada `tubeon`)
            // Punto y raya: lo único que hay antes de que aparezca la imagen.
            // Va encima del texto porque es el haz, no el texto.
            Rectangle {
                anchors.centerIn: parent
                visible: crt.beamFade > 0.01
                width: Math.max(parent.width * crt.beamW, 3)
                height: 3
                radius: 1.5
                color: crt.pal.hot
                opacity: crt.beamFade
            }

            // ---- pantalla sin letra: la animación que la mantiene viva
            //
            // T4.1: el motivo se dibuja al TAMAÑO DE LA PANTALLA, y nada más.
            // El marco venía agrandado por el overscan de la tanda 3, que era
            // el parche para el marco de fondo que dejaba el plano de la
            // estrofa (0.85). Ese plano ya no existe — la cámara nunca baja de
            // 1 —, así que agrandar sólo servía para que cada dibujo saliera un
            // 22 % más grande y recortado, que es exactamente lo que Ferox vio.
            // El `clip` se queda: es lo que garantiza que ningún motivo pinte
            // fuera de su caja.
            Item {
                id: motifFrame
                anchors.fill: parent
                clip: true
                // en el instrumental corren TODAS: es la pared entera moviéndose
                // con el tema, que es justo lo que "NO SIGNAL" mataba
                visible: crt.idle || crt.instrumental

                Motif {
                    anchors.fill: parent
                    // lo que se ve es el dibujo YA cambiado, que va un puente
                    // atrás de lo que el root asignó (ver motifBridge)
                    kind: crt.motifShown
                    // el destino acelera (×1.6 al final de la línea), las otras
                    // apagadas se aquietan (×0.7) y bajan a 0.75 de opacidad
                    energy: crt.ctl.sectionEnergy
                        * (crt.foreTarget ? 1 + 0.6 * crt.foreRamp : 1)
                        * (crt.foreOther ? 1 - 0.3 * crt.foreRamp : 1)
                    // A5: con el aro contando en esta pantalla el motivo se
                    // apaga entero. Dos animaciones a la vez en la misma
                    // pantalla no se leen como una cosa esperando la frase:
                    // se leen como ruido encima de un dibujo.
                    // Y lo mismo con el rótulo del sync (tanda 3, C): cae en
                    // la pantalla enfocada, que con letra no dibuja ningún
                    // motivo — pero en un instrumental sí, y ahí el número
                    // quedaba encima del dibujo y sin contraste contra él.
                    dim: (crt.ringShows || syncHint.opacity > 0.01) ? 0
                        : (crt.foreOther ? 1 - 0.25 * crt.foreRamp : 1)
                    waterAmp: crt.ctl.crtWaterAmp
                    // la semilla de esta aparición: el reloj de los motivos cruzado
                    // con el número de pantalla, así dos pantallas con el mismo
                    // dibujo no arman el mismo paisaje
                    // la semilla de esta aparición. Se siembra al ASIGNAR el
                    // dibujo y no con el reloj de los motivos: con el hold
                    // puesto, ese reloj sigue corriendo debajo de un dibujo que
                    // se queda, y el paisaje se re-sembraba solo cada 25 s
                    seed: crt.ctl.crtMotifSeeds[crt.idx] || 0
                    quality: crt.ctl.crtQuality
                    // el compás y el verso: la estática forma algo una vez por
                    // compás, y lo que forma sale de la línea que viene
                    tick: crt.ctl.beatTick
                    beatMs: crt.ctl.beatMs > 0 ? crt.ctl.beatMs : 500
                    bpmLive: crt.ctl.bpmLive
                    lineNo: crt.ctl.crtLineNo
                    nextWord: crt.ctl.crtNextWord
                    lines: crt.ctl.crtLines
                    linesSynced: crt.ctl.crtLinesSynced
                    fontFamily: crt.fontFamily
                    // hacia dónde miran los ojos: a la pantalla que tiene la frase,
                    // y en el último tramo del verso, a la que la va a recibir
                    gaze: crt.motifGaze
                    // el drop viaja como booleano: los motivos no pueden sacarlo de
                    // `energy`, que acá arriba ya viene multiplicada por el aviso
                    drop: crt.ctl.audSection === "drop"
                    // la parte del tema: el osciloscopio elige con ella la relación
                    // entre sus dos ejes, que es lo que hace que la figura cambie
                    // al entrar el estribillo
                    section: crt.ctl.audSection
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
            }

            // ---- el aro de la línea que viene, encima del motif
            Ring {
                anchors.fill: parent
                // `armed` y no `visible`: el aro se va con la raya encima de la
                // letra que entra, así que decide él cuándo deja de dibujarse
                armed: crt.ringShows
                gen: crt.ctl.crtNextGen
                colour: crt.pal.ink
                hot: crt.pal.hot
                fontFamily: crt.fontFamily
                level: crt.pump
                dueAt: crt.ctl.crtNextAt
                // el ritmo ya no decide cuánto se comió (eso lo dice el reloj):
                // decide dónde cae el mordisco. Con compás, en el tiempo.
                stepped: crt.ctl.bpmLive
                beatMs: crt.ctl.beatMs > 0 ? crt.ctl.beatMs : 500
                beat: crt.ctl.beatTick
                // sin compás, en el grave: el golpe CRUDO (`audBeat`), no el
                // pico del tubo, que va uno cada cuatro segundos
                kick: crt.ctl.audBeat
                low: crt.live ? crt.ctl.audLo : 0.4
                screen: crt.idx
                cue: crt.ctl.cueGen
                // el aro entrega la línea: la rotura sale con la RAYA, que es
                // cuando la frase llega de verdad — no cuando vence el reloj.
                // El `show` cae 0–300 ms después (el poll del daemon) y una
                // rotura en la hora se gastaba el portero justo antes.
                onCollapsed: crt.hit(0.5)
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
            // Misma regla que el motivo (T4.1): a tamaño de pantalla. Las ocho
            // barras van a sangre y no dejan marco porque la cámara nunca se
            // aleja por debajo de 1.
            Item {
                id: standbyLayer
                anchors.fill: parent
                clip: true
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

        // ---- el rayo del salto (T3.B4)
        // Va en `stage` y NO adentro de `camera`: el recorrido se mide contra
        // los bordes del tubo, y con el plano de la sección encima terminaría
        // agarrando por un borde que no es el borde. Sigue pasando por el
        // vidrio, que es lo que importa.
        HopRay {
            anchors.fill: parent
            visible: crt.hopRayP > 0 && crt.hopRayFade > 0.01
            role: crt.hopFrom ? "from" : (crt.hopMid ? "mid" : "to")
            dir: crt.ctl.crtHop.dir
            progress: crt.hopRayP
            fade: crt.hopRayFade
            globalFrom: crt.hopRayG0
            globalTo: crt.hopRayG1
            edgeTop: crt.ctl.crtHopEdge
            colFrom: crt.ctl.crtFace(crt.ctl.crtHop.from, false).ink
            colTo: crt.ctl.crtFace(crt.ctl.crtHop.to, false).ink
            textH: Math.min(0.45, crt.shortSide * 0.34 / Math.max(crt.height, 1))
        }

        // ---- el ajuste de sync a ojo (tanda 3, C)
        // El rótulo va SÓLO en la pantalla enfocada, que es la que tiene la
        // línea: encima de una apagada caería sobre su motif y la regla es una
        // animación por pantalla. Encima del texto no la rompe — el texto no es
        // una animación en curso, y es justo lo que se está tratando de
        // sincronizar, así que el número tiene que leerse al lado.
        // Vive en `stage` y FUERA de `camera`, por lo mismo que el rayo del
        // salto: es un rótulo del tubo, no parte del plano que la cámara
        // acerca y aleja.
        Text {
            id: syncHint
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Math.round(crt.pad * 1.4)
            }
            property string full: ""
            property int typed: 0
            // entrada `type`, la misma que las palabras de la línea: no
            // aparece, se ESCRIBE, un caracter cada 28 ms con el cursor pegado
            // atrás. Contado por code point (Array.from) y no por unidad
            // UTF-16: un nombre de artista con un caracter fuera del BMP se
            // escribiría en dos mitades rotas.
            readonly property int chars: Array.from(full).length
            text: Array.from(full).slice(0, typed).join("") + (typed < chars ? "▮" : "")
            color: crt.pal.ink
            font.family: crt.fontFamily
            font.bold: true
            font.letterSpacing: 3
            font.pixelSize: Math.max(12, Math.round(crt.shortSide * 0.030))
            opacity: 0
            visible: opacity > 0.01

            Timer {
                interval: 28
                repeat: true
                running: syncHint.opacity > 0.01 && syncHint.typed < syncHint.chars
                onTriggered: syncHint.typed++
            }

            // El segundo y medio se mide por RELOJ, no por cuadros: la pantalla
            // del medio corre a 20 fps y uno de los monitores va a 200.
            SequentialAnimation {
                id: syncShowAnim
                PropertyAction { target: syncHint; property: "typed"; value: 0 }
                NumberAnimation { target: syncHint; property: "opacity"; to: 1; duration: 120 }
                PauseAnimation { duration: 1120 }
                NumberAnimation {
                    target: syncHint; property: "opacity"; to: 0
                    duration: 260; easing.type: Easing.InQuad
                }
            }

            // Se cuelga del timbre (`syncGen`) y no del número: dos ajustes
            // opuestos dejan el mismo offset acumulado, y el segundo no se
            // vería si el rearme dependiera de que el valor cambie.
            Connections {
                target: crt.ctl
                function onSyncGenChanged() {
                    if (crt.idx !== crt.ctl.crtSyncScreen())
                        return;
                    syncHint.full = crt.ctl.syncLabel().toUpperCase();
                    syncShowAnim.restart();
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
