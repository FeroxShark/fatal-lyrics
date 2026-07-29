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
    visible: ctl.crtOn
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

    readonly property string lineText: ctl.crtLine.text
    readonly property bool standby: lineText === ""
    readonly property bool showsText: !standby && (allMode || shot.active || shot.past)
    readonly property bool focused: !standby && (allMode || shot.active)
    readonly property bool burned: !allMode && shot.past && !shot.active
    readonly property bool idle: !standby && !showsText

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
    function dueFrac(i) {
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
        running: crt.visible && !crt.standby
        triggeredOnStart: true
        onTriggered: {
            const st = crt.ctl.crtChunkState(crt.idx);
            crt.shot = st;
            crt.reveal = st.reveal;
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

    // golpe: chispazo de señal y fogonazo, más fuerte en la pantalla enfocada
    Connections {
        target: crt.ctl
        enabled: crt.visible && crt.live
        function onAudBeatChanged() {
            // El golpe NO rompe la señal (eso era la mitad de la vibración): lo
            // que hace es prender el tubo. El titileo va con la canción.
            beatAnim.restart();
            // El apagón es para el pico del tema, no para cada golpe: pedía poco
            // (energía > 1.1 y una de cada tres) y terminaba pareciendo una luz
            // rota. Ahora sólo en la parte más fuerte, una de cada ocho, y con
            // tres segundos de descanso mínimo entre uno y otro.
            const now = Date.now();
            if (crt.ctl.sectionEnergy > 1.35 && Math.random() < 0.12
                    && now - crt.lastBlinkAt > 3000) {
                crt.lastBlinkAt = now;
                blinkAnim.restart();
            }
            if (crt.focused)
                flash.pulse();
        }
    }

    // El latido del tubo con cada golpe: sube de un saque y baja con curva, que
    // es lo que se lee como "está sincronizado" en vez de "parpadea".
    property real beatPulse: 0
    property real beatBlink: 0
    property double lastBlinkAt: 0
    NumberAnimation {
        id: beatAnim
        target: crt
        property: "beatPulse"
        from: 1
        to: 0
        duration: 190
        easing.type: Easing.OutQuad
    }
    SequentialAnimation {
        id: blinkAnim
        NumberAnimation { target: crt; property: "beatBlink"; from: 0.55; to: 0; duration: 90; easing.type: Easing.OutQuad }
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
    readonly property int hitGap: Math.round(1200 / Math.max(ctl.crtIntensity, 0.25))
    function hit(amount) {
        const now = Date.now();
        if (now - lastHitAt < hitGap && amount < glitchAmt * 1.5)
            return;
        lastHitAt = now;
        glitchDecay.stop();
        glitchAmt = Math.min(amount, 1);
        glitchDecay.start();
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
    FrameAnimation {
        running: crt.visible && (crt.showsText || crt.standby)
        onTriggered: crt.tubeTime += frameTime
    }
    Timer {
        interval: 50
        repeat: true
        running: crt.visible && !crt.showsText && !crt.standby
        onTriggered: crt.tubeTime += 0.05
    }

    // Encuadre: la pantalla con la letra se acerca y abre el cuadro; la que no,
    // queda lejos y con las bandas más gruesas. Eso es la "cámara" moviéndose.
    // Encuadre: nada de barras ni marcos — pantalla llena, cero distracción. Lo
    // único que se mueve es un acercamiento lento y continuo, que es de dónde
    // sale la sensación de fluidez: transformación sobre algo quieto, no
    // redibujo. La pantalla enfocada se acerca; la apagada queda un poco atrás.
    readonly property real cam: ctl.crtCamera
    property real camZoom: 1 + cam * (focused ? 0.030 + 0.022 * pump : 0.004)
    Behavior on camZoom { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

    Item {
        id: stage
        anchors.fill: parent

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
                ? crt.ctl.crtBloom * (0.72 + 0.55 * crt.pump) : 0
            property real noiseAmt: crt.ctl.crtNoise * (0.35 + 0.65 * crt.rest)
                * (crt.standby ? 3.5 : (crt.idle ? 1.6 : 1))
            property real glitch: Math.min(crt.glitchAmt, 1)
            property real roll: crt.ctl.crtRoll * (0.25 + 0.75 * crt.rest)
            property real alarm: crt.alarmLine ? 1 : 0
            property real vignette: crt.ctl.crtVignette
            // el titileo llega desde el audio, no del reloj del shader
            // el latido también lo gradúa la perilla única: en intensity baja
            // late apenas, en alta pega como antes
            property real pulse: crt.beatPulse * (0.55 + 0.45 * crt.ctl.sectionEnergy)
                * (crt.focused ? 1 : 0.6) * (0.45 + 0.55 * crt.ctl.crtIntensity)
            property real blink: crt.beatBlink
            property variant res: Qt.vector2d(Math.max(crt.width, 1), Math.max(crt.height, 1))
            property variant tint: crt.pal.tint
            fragmentShader: Qt.resolvedUrl("crt.frag.qsb")
        }

        Rectangle {
            anchors.fill: parent
            color: crt.pal.bg
            // el contagio se ve: el color entra rápido, pero entra, no aparece
            Behavior on color { ColorAnimation { duration: 190; easing.type: Easing.OutQuad } }
        }

        // ---- todo lo que la cámara mueve va acá adentro
        Item {
            id: camera
            anchors.fill: parent
            transform: Scale {
                origin.x: camera.width / 2
                origin.y: camera.height / 2
                xScale: crt.camZoom
                yScale: crt.camZoom
            }

            // la pantalla prendida respira: el fondo sube y baja con la música,
            // no hay un "resplandor" separado porque el fondo YA es la luz
            Rectangle {
                anchors.fill: parent
                color: crt.pal.bg
                opacity: crt.showsText ? 0.10 + 0.16 * crt.pump : 0.05
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
            Item {
                id: lyric
                anchors { fill: parent; margins: crt.pad }
                visible: crt.showsText
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

                            transform: [
                                Scale { id: sc; origin.x: slot.width / 2; origin.y: slot.height / 2 },
                                Translate { id: tr }
                            ]

                            Text {
                                id: label
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: slot.modelData.toUpperCase()
                                color: crt.pal.ink
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
                                if (landed)
                                    entry.restart();
                            }

                            // La entrada: blanco de un frame largo (≈40 ms, se ve
                            // igual en el monitor de 60 que en el de 200) y se va
                            // al color con easing, con un tirón lateral y los
                            // canales separados que se juntan. Todo interpolado
                            // por frame — nada de timers manejando el movimiento.
                            // La entrada tiene que leerse como que la palabra YA
                            // ESTABA y el televisor recién la sintonizó: golpe de
                            // estática, blanco, y en menos de un cuarto de segundo
                            // ya está quieta. Nada de rebotes largos.
                            SequentialAnimation {
                                id: entry
                                PropertyAction { target: label; property: "color"; value: "#ffffff" }
                                PropertyAction { target: slot; property: "ghostOff"; value: measure.fontInfo.pixelSize * (crt.entryStyle === "roll" ? 0.34 : 0.22) }
                                PropertyAction { target: slot; property: "ghostFade"; value: 1 }
                                PropertyAction { target: sc; property: "xScale"; value: crt.entryStyle === "slam" ? 1.35 : 1.06 }
                                PropertyAction { target: sc; property: "yScale"; value: crt.entryStyle === "slam" ? 1.35 : 0.82 }
                                PropertyAction { target: tr; property: "y"; value: crt.entryStyle === "roll" ? -measure.fontInfo.pixelSize * 0.55 : 0 }
                                PauseAnimation { duration: 28 }
                                ParallelAnimation {
                                    ColorAnimation { target: label; property: "color"; to: crt.pal.ink; duration: 70; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: sc; property: "xScale"; to: 1; duration: crt.entryStyle === "slam" ? 150 : 90; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: sc; property: "yScale"; to: 1; duration: crt.entryStyle === "slam" ? 150 : 90; easing.type: Easing.OutBack }
                                    NumberAnimation { target: tr; property: "y"; to: 0; duration: 140; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: slot; property: "ghostOff"; to: 0; duration: 110; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: slot; property: "ghostFade"; to: 0; duration: 120; easing.type: Easing.InQuad }
                                    SequentialAnimation {
                                        NumberAnimation { target: tr; property: "x"; from: -measure.fontInfo.pixelSize * 0.07; to: measure.fontInfo.pixelSize * 0.03; duration: 34 }
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
                visible: crt.idle
                kind: crt.ctl.crtMotifFor(crt.idx)
                energy: crt.ctl.sectionEnergy
                colour: crt.pal.ink
                hot: crt.pal.hot
                level: crt.pump
                low: crt.live ? crt.ctl.audLo : 0.4
                high: crt.live ? crt.ctl.audHi : 0.3
                beat: crt.ctl.audBeat
                clock: crt.tubeTime
                spinning: crt.visible && crt.idle
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
                from: 0.055
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
