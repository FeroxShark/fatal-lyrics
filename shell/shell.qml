// fatal-lyrics — letras de Spotify como diálogos de error Win95 glitcheados.
// - El cartel de la línea que suena AHORA es más grande y (por default) sin efectos.
// - Los viejos vibran como holograma, quedan con la ventana PARTIDA (tearing) y
//   mueren glitcheando con colapso CRT.
// - Config: ~/.config/cartelitos/config.toml (el daemon la manda por el socket).
// - Viejos: click = cerrar, barra de título = arrastrar. Actual: botones completos.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

ShellRoot {
    id: root

    // config (defaults; el daemon los pisa con el evento "config")
    // screen: "auto" | "all" | nombre | lista de nombres
    property var targetScreen: "auto"
    property int maxDialogs: 12
    property real cfgScale: 1.0
    property real cfgCurrentScale: 1.3
    property string spawnArea: "full"
    property string glitchLevel: "normal"
    property bool effectsOnCurrent: false
    property bool tearingOn: true
    property int deathAgeMin: 3
    property int deathAgeMax: 7
    property int maxLifetime: 60
    property bool clickThrough: false
    property bool trollNo: true
    // T4.4: el cartel de la línea que suena se para sobre su propio reflejo
    property bool mirrorOn: false
    property bool burnIn: true
    property bool cascadeDeath: true
    property string cascadeStyle: "random"
    // resuelto al disparar cada cascada: age | top | center (nunca "random"
    // en sí, eso sólo elige entre estos tres)
    property string cascadeMode: "age"
    property bool karaokeOn: false
    property string npCorner: "top-right"
    property int npMargin: 14
    property bool npVinyl: true
    // T5: modo karaoke. Es una perilla del daemon (`[behavior] sing`), no un
    // archivo: acá sólo cambia lo que se dibuja, y el que escucha el micrófono
    // es el daemon, que manda `sing` cuando el estado cambia (no el nivel del
    // micrófono: la decisión es suya, porque es el único que sabe si hay letra).
    property bool singMode: false
    property bool singing: false
    // Con el karaoke puesto, la pared no está apagada ni prendida: está
    // esperando. Se prende rápido (300 ms: tiene que llegar con la primera
    // palabra) y se apaga lento (800 ms), porque cortar en seco entre dos
    // versos se lee como un parpadeo y no como que dejaste de cantar.
    readonly property real singTarget: (!singMode || singing) ? 1 : 0
    property real singGlow: 1
    onSingTargetChanged: {
        // asignado a mano y no con bindings: `to` y `duration` dependen del
        // mismo cambio que dispara este handler, y el orden entre un binding y
        // un handler de la misma señal no está garantizado
        singFade.stop();
        singFade.to = singTarget;
        singFade.duration = singTarget > 0 ? 300 : 800;
        singFade.start();
    }
    NumberAnimation {
        id: singFade
        target: root
        property: "singGlow"
        easing.type: Easing.InOutQuad
    }

    // ---- modo CRT: el tubo full-bleed que tapa cada monitor (opt-in)
    property bool crtOn: false
    property string crtScreens: "all"    // igual que `screen`, pero para el tubo ("same" = el mismo)
    property var crtOrder: "auto"        // "auto" (por posición) o lista de izquierda a derecha
    property string crtExitOn: "mouse"   // mouse (cursor oculto + click) | keyboard (cualquier tecla)
    property string crtPalette: "album"  // album | auto | dragons | ado | poison | bloodline | vapor | bone
    property string crtSplit: "mixed"    // mixed | whole | fragment
    property string crtFont: ""
    property real crtCurvature: 1.0
    property real crtScanlines: 0.75
    property real crtChroma: 1.0
    property real crtBloom: 1.0
    property real crtNoise: 0.5
    property real crtRoll: 1.0
    property real crtVignette: 0.9
    property real crtIntensity: 1.0
    property bool crtChrome: true
    property bool crtDirector: true
    property string crtFocusMode: "roam"     // roam | all
    property bool crtColorFromPitch: true
    property int crtColorHold: 10
    // segundos de anticipación con que el color infecta la pantalla siguiente
    // (ver updateInfection más abajo)
    property real crtInfectLead: 0.35
    // probabilidad de que un verso entre como un cambio de canal (T3.1)
    property real crtChannelSwitch: 0.25
    // T3.2: la palabra gigante que cruza la pared en el drop
    property bool crtIown: true
    // T2.1: la pantalla a la que va a saltar la frase lo delata antes de que
    // llegue (ver foreRamp en Crt.qml)
    property bool crtForeshadow: true
    // T2.2: el aro que se consume en la pantalla destino (ver Ring.qml)
    property bool crtRing: true
    // T2.3: cómo se muestra un salto a una pantalla que NO es la de al lado:
    // "corridor" (la franja que cruza las del medio), "interference" (el
    // glitch al pasar), "both", "off". Cualquier otra cosa se lee como "off".
    property string crtHopMode: "both"
    // qué tan seguido una línea sale "critical" (pantalla roja): umbral del
    // sorteo determinístico en crtPlanFor, más alto = más raro
    property real crtAlarmThreshold: 0.87
    property bool crtMotifs: true
    property real crtCamera: 1.0
    // T3.4: la cámara sigue también la PARTE del tema (lejos en la estrofa,
    // encima en el drop). Cuelga de `camera`: con la cámara quieta esto
    // tampoco se mueve.
    property bool crtSectionZoom: true
    property real crtQuality: 1.0
    property real crtFlicker: 0.25
    // La perilla mueve el brillo al CUADRADO: medido, la respuesta lineal daba
    // saltos de 5% de brillo ya en 0.25, y la zona donde uno quiere estar es
    // justo la de abajo. Así 0.25 son 6 puntos de latido y no 25.
    readonly property real flickerAmt: crtFlicker * crtFlicker
    // cuánto destella cada palabra al aparecer (0 = entra directo en su color).
    // Va aparte del latido del tubo: pasa en CADA palabra, así que es lo que se
    // percibe como "la letra titila todo el tiempo".
    property real crtWordFlash: 0.3
    // Los dos motivos de agua (el mar y el laguito que vibra con la música):
    // entran al sorteo como cualquier otro, y `water_amp` dice cuánta agua se
    // mueve
    property bool crtWater: true
    property real crtWaterAmp: 0.55

    // ---- lo que está sonando de verdad (eventos "aud" del daemon)
    property real audLevel: 0
    // el mismo nivel, promediado ~2 s (los eventos llegan a 10 Hz). Un golpe no
    // dice si el tema está fuerte: lo dice el rato. Es lo que pesa el director
    // de entradas (crtEntryTable).
    property real audLevel2s: 0.35
    property real audLo: 0
    property real audMid: 0
    property real audHi: 0
    property real audCentroid: 0.5
    property int audBeat: 0
    // los picos: no cada golpe, sino los pocos momentos más altos del tema
    property int audPeak: 0
    property double lastPeakAt: 0
    property double audAt: 0
    // en qué parte de la canción estamos (lo decide el daemon comparando este
    // momento contra el tema entero, no contra un volumen fijo)
    property string audSection: "verse"
    property real audPct: 0.5
    property string audComing: ""      // lo que se viene, si el tema ya se escuchó
    property double audComingAt: 0
    // T4.2: cuántos segundos faltan para lo que se viene, y el pulso que arranca
    // el acercamiento lento de la cámara. `motifPreCued` evita el doble cambio
    // de dibujo (uno al avisar, otro al llegar el `sec` dos segundos después).
    property real cueIn: 2.0
    property int cueGen: 0
    property bool motifPreCued: false
    property int sectionGen: 0
    // si la captura se cae o está apagada, todo vuelve a moverse con la letra
    readonly property bool audLive: crtOn && (Date.now() - audAt) < 1500

    // ---- el compás (T4.1: eventos "bpm" del daemon)
    // `bpmPhase` NO es una marca de tiempo del daemon: es la EDAD del último
    // golpe cuando se mandó el evento. El reloj del daemon (time.monotonic) y
    // el de acá (Date.now) no son el mismo, así que lo único que significa algo
    // de este lado es "hace tanto fue el último golpe" — con eso se ancla.
    property real bpm: 0
    property real bpmConf: 0
    property double lastBeatAt: 0
    property double bpmAt: 0
    readonly property real beatMs: bpm > 0 ? 60000 / bpm : 0
    // debajo de 0.6 el número es una adivinanza: todo sigue moviéndose con la
    // letra, como antes de que existiera esto
    readonly property bool bpmLive: crtOn && bpm > 0 && bpmConf > 0.6
        && (liveTick, Date.now() - bpmAt < 15000)
    // Cuantizar = redondear a un número ENTERO de tiempos, no reemplazar por un
    // tiempo: el compás acomoda lo que ya pasaba, no lo hace pasar más seguido.
    function quantize(ms) {
        if (!bpmLive)
            return ms;
        return Math.max(1, Math.round(ms / beatMs)) * beatMs;
    }
    // El pulso del compás. Es un poll de 25 ms y no un Timer con el intervalo
    // del tiempo: un Timer hay que restart()earlo en cada re-anclaje de fase, y
    // eso le rompe el binding de `running` (queda prendido con el tubo apagado).
    // Acá el reloj es la resta contra `lastBeatAt`, así que re-anclar es asignar
    // una property y listo.
    property int beatTick: 0
    property int lastBeatIndex: -1
    Timer {
        interval: 25
        repeat: true
        running: root.crtOn && root.bpmLive
        onTriggered: {
            const n = Math.floor((Date.now() - root.lastBeatAt) / root.beatMs);
            if (n !== root.lastBeatIndex) {
                root.lastBeatIndex = n;
                root.beatTick++;
            }
        }
    }

    // T3.8: ¿suena algo AHORA? No es lo mismo que haya letra: en un
    // instrumental la pantalla tiene que estar viva, no decir "NO SIGNAL".
    // Los `pos` llegan 1/s con el tema andando (y paran en pausa) y los `aud`
    // varias veces por segundo si la captura está prendida; alcanza con
    // cualquiera de los dos.
    // liveTick existe sólo para que esto se vuelva a evaluar: Date.now() no es
    // una propiedad, así que sin un empujón por segundo el binding se quedaría
    // en "sí, suena" para siempre después del último evento (mismo truco que
    // screensGen con las pantallas).
    property int liveTick: 0
    Timer {
        interval: 1000
        repeat: true
        running: root.crtOn
        onTriggered: root.liveTick++
    }
    readonly property bool musicLive: {
        liveTick;
        return Date.now() - Math.max(posAt, audAt) < 3500;
    }

    // Cuánto empuja la parte en la que está el tema. Es el número que hace que
    // las animaciones estén "sintonizadas": en el silencio todo se aquieta, en
    // el estribillo todo aprieta, sin que nadie toque una perilla.
    readonly property real sectionEnergy: audSection === "quiet" ? 0.45
        : audSection === "build" ? 1.25
        : audSection === "drop" ? 1.6 : 1.0
    // true mientras se sabe que en un par de segundos cambia la parte: el tubo
    // empieza a apretar ANTES, que es lo que hace que el golpe caiga en tiempo
    readonly property bool building: audComing !== "" && (Date.now() - audComingAt) < 2200

    // estado del Now Playing (ventana propia, no es un diálogo);
    // compartido entre pantallas para que la animación vaya sincronizada
    property bool npShown: false
    property string npTitle: ""
    property string npInfo: ""
    property string npArt: ""
    property real npProgress: 0
    property bool npDocked: false
    property int npSerial: 0

    Timer {
        id: npDockTimer
        interval: 4000
        onTriggered: root.npDocked = true
    }

    // multiplicadores según nivel de glitch
    readonly property real gProb: glitchLevel === "off" ? 0 : glitchLevel === "soft" ? 0.5 : glitchLevel === "aggressive" ? 1.6 : 1
    readonly property real gStr: glitchLevel === "off" ? 0 : glitchLevel === "soft" ? 0.6 : glitchLevel === "aggressive" ? 1.5 : 1

    property int serial: 0
    property int currentLyricSerial: -1
    property var dialogList: []
    // T0.3: cuando max_dialogs se pasa, el sobrante muere con su animación en
    // vez de un splice directo — pushDialog manda el serial acá, y cada
    // instancia (una por pantalla) lo ve y se manda a morir sola
    property int dyingSerial: -1

    // generación de líneas de letra: los carteles envejecen por líneas NUEVAS,
    // no por duplicados del botón "No" (spamear No no mata a los demás)
    property int lyricGen: 0

    // cascada: cada incremento dispara la muerte en cadena de los carteles vivos
    property int clearGen: 0

    // posición de la canción (eventos "pos" a 1 Hz) para el karaoke;
    // se extrapola con el reloj local, con tope por si el player se pausó
    property real posAbs: 0
    property real posLen: 0
    property double posAt: 0
    function songPos() {
        return posAbs + Math.min((Date.now() - posAt) / 1000, 1.5);
    }

    function htmlEscape(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // ------------------------------------------------- estado del modo CRT
    // La línea que suena, sin diálogos de por medio: el tubo la dibuja entera.
    property var crtLine: ({ text: "", t0: 0, t1: 0, serial: 0, segs: [], words: [] })
    property int crtSerial: 0
    property int crtTrackSeed: 0
    // true mientras la línea que suena es la primera del tema (ver show())
    property bool crtTrackStart: false

    // ---- la línea que VIENE (T2.0)
    // El daemon manda una línea por vez: hasta acá el tubo no sabía nada de la
    // próxima, y sin eso no hay forma de avisar a dónde va a saltar la frase.
    // `crtNext` es lo que mandó el daemon con el `show` ({text, t0, t1, segs});
    // null cuando la letra se terminó. NO se infiere de crtLines: en un
    // rebobinado el daemon vuelve a mandar el `show` con el `next` correcto y
    // acá sólo se consume.
    property var crtNext: null
    // la letra entera del tema (evento `lyrics`), para lo que necesita mirar
    // más allá del verso que suena
    property var crtLines: []
    // ...y si esa letra tiene tiempos. Sin sincronizar viaja igual (el bloque
    // de texto suelto), pero entonces no hay ninguna línea "actual": lo que la
    // mire tiene que correr sin resaltar nada.
    property bool crtLinesSynced: true
    // Cuándo arranca la próxima línea, en reloj local, y cuánto faltaba cuando
    // llegó la actual. Se fija al llegar la línea (un `show` nuevo es también
    // lo que llega después de un ajuste de sync o de un salto, así que no hace
    // falta recalcularlo por fuera).
    property double crtNextAt: 0
    property real crtNextIn: -1

    // Ruido determinístico: todas las pantallas tienen que elegir el MISMO
    // layout para la misma línea, y sin hablar entre ellas.
    // Semilla de una línea: el tema y el número de línea, NADA vivo. Es lo que
    // hace que el reparto de la línea k+1 se pueda calcular mientras suena la
    // k y dé exactamente lo mismo cuando llegue de verdad.
    function crtSeed(serial) {
        return crtTrackSeed * 1009 + (serial || 0);
    }

    function crtHash(n) {
        let x = Math.imul(n ^ 0x9e3779b9, 2654435761);
        x ^= x >>> 15;
        x = Math.imul(x, 2246822507);
        x ^= x >>> 13;
        return (x >>> 0) / 4294967296;
    }

    // Cómo se muestra esta línea. "mixed" (default): casi siempre la frase
    // entera en cada monitor y de vez en cuando partida entre las pantallas.
    function crtPlanFor(line) {
        const words = (line.text || "").split(/\s+/).filter(w => w.length > 0);
        if (words.length === 0)
            return { layout: "plain", alarm: false };
        const n = line.serial || 0;
        const r = crtHash(n * 7 + words.length);
        // La línea "critical" pinta la pantalla entera de rojo. Salía por sorteo
        // — una de cada ocho, o sea un par por minuto — y el rojo dejaba de
        // querer decir nada: era un color más que aparecía solo. Ahora sólo
        // puede caer sobre un pico, así que el rojo ES el pico.
        const alarm = crtHash(n * 13 + 5) > crtAlarmThreshold && Date.now() - lastPeakAt < 9000;
        // el corte se reparte entre las pantallas DEL TUBO, que no son las
        // mismas donde salen los carteles
        const canSplit = activeCrtScreens.length > 1 && words.length <= 3;
        if (crtSplit === "fragment" && canSplit)
            return { layout: "split", alarm: alarm };
        if (crtSplit === "mixed" && canSplit && r < 0.45)
            return { layout: "split", alarm: alarm };
        if (words.length <= 4 && r < 0.60)
            return { layout: "stack", alarm: alarm };
        if (words.length <= 3 && r < 0.72)
            return { layout: "tile", alarm: alarm };
        if (r > 0.86)
            return { layout: "type", alarm: alarm };
        return { layout: "plain", alarm: alarm };
    }
    readonly property var crtPlan: crtPlanFor(crtLine)

    // Pedazo de la línea que le toca a la pantalla i de n: se corta por
    // posición, no por palabra — que "TAKE" quede como "TA" + "KE" es el efecto.
    function crtSlice(text, i, n) {
        const s = (text || "").trim();
        if (n <= 1 || s.length === 0)
            return s;
        // Array.from() corta por code point, no por unidad UTF-16: substring()
        // partía un caracter japonés/coreano por la mitad y dejaba un � a cada
        // lado del corte.
        const cps = Array.from(s);
        const a = Math.round(cps.length * i / n);
        const b = Math.round(cps.length * (i + 1) / n);
        return cps.slice(a, b).join("").trim();
    }

    // Avance de la línea actual (0..1) para el pintado palabra por palabra;
    // mismo cálculo que el karaoke de los carteles.
    // karaokeFracAt() es lo mismo para un instante cualquiera, no sólo para
    // "ahora": con los tiempos por palabra del LRC "enhanced" hay que poder
    // preguntar en qué punto de la barra cae una palabra que todavía no sonó.
    function karaokeFracAt(t0, t1, t) {
        const dur = t1 - t0;
        if (dur <= 0)
            return 1;
        // termina de pintar ~1 s antes de la próxima línea
        const lead = Math.min(1.0, dur * 0.35);
        return Math.max(0, Math.min((t - t0) / Math.max(dur - lead, 0.5), 1));
    }
    function karaokeFraction(t0, t1) {
        return karaokeFracAt(t0, t1, songPos());
    }
    function crtProgress() {
        const e = crtLine;
        if (!e || (e.t1 || 0) <= (e.t0 || 0))
            return 1;
        return karaokeFraction(e.t0, e.t1);
    }

    function fmtTime(s) {
        const v = Math.max(0, Math.floor(s));
        const m = Math.floor(v / 60);
        const ss = v % 60;
        return (m < 10 ? "0" : "") + m + ":" + (ss < 10 ? "0" : "") + ss;
    }
    // depende de posAbs (1 evento por segundo del daemon) → el binding se refresca solo
    function crtClock() {
        return fmtTime(posAbs) + " / " + fmtTime(posLen);
    }



    // --------------------------------------------------------------- paletas
    // Una paleta = DOS caras que combinan entre sí: una pantalla prendida (fondo
    // quemado, letra oscura) y una de tubo apagado (fondo hondo, letra encendida).
    // Las pantallas alternan entre esas dos y nunca hay tres colores peleándose.
    readonly property var schemes: [
        { key: "dragons",
          a: { bg: "#f7d21f", ink: "#a51405", hot: "#5e0700", dim: "#c05010" },
          b: { bg: "#170604", ink: "#ff8a2b", hot: "#ffe0b0", dim: "#8a4110" } },
        { key: "ado",
          a: { bg: "#68d6f2", ink: "#062247", hot: "#010d24", dim: "#1f5c8a" },
          b: { bg: "#04162e", ink: "#7fe4ff", hot: "#ffffff", dim: "#2d6f96" } },
        { key: "poison",
          a: { bg: "#c8f224", ink: "#123a06", hot: "#061c02", dim: "#3f7a1a" },
          b: { bg: "#04120a", ink: "#9dff3d", hot: "#e8ffc4", dim: "#3f7a1a" } },
        { key: "bloodline",
          a: { bg: "#ff2f14", ink: "#2b0600", hot: "#5e0f00", dim: "#8a2c14" },
          b: { bg: "#12030a", ink: "#ff5c7a", hot: "#ffd6de", dim: "#8a2540" } },
        { key: "vapor",
          a: { bg: "#f74fc3", ink: "#2b0126", hot: "#12000f", dim: "#8a1670" },
          b: { bg: "#0d0a2b", ink: "#6ff2ff", hot: "#e6ffff", dim: "#2f5a8a" } },
        { key: "bone",
          a: { bg: "#f2e2bc", ink: "#7a2a05", hot: "#3d1302", dim: "#a8642a" },
          b: { bg: "#150c05", ink: "#ffb457", hot: "#ffe6c2", dim: "#8a5a20" } },
    ]
    readonly property var criticalFace: ({ bg: "#ff2a0a", ink: "#26030a", hot: "#5e0500", dim: "#7d1a08" })

    // colores de la tapa del disco (evento "art" del daemon)
    property var artColors: []

    function faceFromColor(hex, lit) {
        const c = Qt.color(hex);
        const h = c.hslHue;
        const sat = Math.min(Math.max(c.hslSaturation, 0.6), 1);
        if (lit)
            return {
                bg: Qt.hsla(h, sat, 0.58, 1),
                ink: Qt.hsla(h, Math.min(sat + 0.15, 1), 0.15, 1),
                hot: Qt.hsla(h, 1, 0.07, 1),
                dim: Qt.hsla(h, sat, 0.34, 1),
            };
        return {
            bg: Qt.hsla(h, sat * 0.9, 0.07, 1),
            ink: Qt.hsla(h, sat, 0.66, 1),
            hot: Qt.hsla(h, 0.4, 0.92, 1),
            dim: Qt.hsla(h, sat, 0.40, 1),
        };
    }

    // La paleta del tema sale de su tapa: el color más presente manda la pantalla
    // prendida y el segundo la oscura. Si los dos son casi el mismo tono, al
    // segundo se lo manda al otro lado de la rueda — dos caras del mismo color no
    // son una paleta, son una pantalla lavada.
    readonly property var albumScheme: {
        if (!artColors || artColors.length === 0)
            return null;
        // Los grises NO sirven como color de pantalla: no tienen tono propio y
        // Qt les devuelve uno cualquiera — una tapa en blanco y negro terminaba
        // pintando el tubo de verde, que no pintaba nada con el resto.
        let usable = [];
        for (let i = 0; i < artColors.length; i++)
            if (Qt.color(artColors[i]).hslSaturation > 0.18)
                usable.push(artColors[i]);
        if (usable.length === 0)
            return null;     // tapa sin color: mejor una paleta de fábrica
        const first = usable[0];
        const h1 = Qt.color(first).hslHue;
        let second = usable.length > 1 ? usable[1] : null;
        if (second !== null) {
            const h2 = Qt.color(second).hslHue;
            const gap = Math.abs(h1 - h2);
            if (gap < 0.06 || gap > 0.94)
                second = null;    // casi el mismo tono: no son dos colores
        }
        if (second === null)
            second = Qt.hsla((h1 + 0.45) % 1, 0.75, 0.5, 1).toString();
        return { key: "album", a: faceFromColor(first, true), b: faceFromColor(second, false) };
    }

    function currentScheme() {
        if (crtPalette === "album" && albumScheme)
            return albumScheme;
        for (let i = 0; i < schemes.length; i++)
            if (schemes[i].key === crtPalette)
                return schemes[i];
        if (crtPalette === "album" || crtPalette === "auto") {
            // sin tapa: la elige el registro de lo que suena, o el tema
            const base = crtColorFromPitch && pitchPal >= 0 ? pitchPal : crtTrackSeed;
            return schemes[base % schemes.length];
        }
        return schemes[0];
    }

    // Cómo se reparten las dos caras entre las pantallas. Alternar (0,1,0) deja
    // SIEMPRE la del medio distinta y se nota enseguida; acá el reparto cambia
    // por tema y cada varias líneas, y sólo se garantiza que estén las dos caras.
    function crtFacePattern() {
        const n = Math.max(activeCrtScreens.length, 1);
        if (n === 1)
            return [0];
        const seed = crtTrackSeed * 31 + sectionGen * 13 + Math.floor(crtSerial / 6) * 7;
        // 1..2^n-2 deja afuera "todas iguales" en las dos puntas
        const combos = Math.pow(2, n) - 2;
        const bits = 1 + Math.floor(crtHash(seed) * combos);
        let out = [];
        for (let i = 0; i < n; i++)
            out.push((bits >> i) & 1);
        return out;
    }

    // Qué cara tiene cada pantalla AHORA. Empieza en el reparto de arriba, pero
    // se contagia: cuando la frase está por saltar a la pantalla de al lado, esa
    // pantalla toma el color de la que la trae, un instante ANTES de que llegue
    // el texto. La letra no cambia de pantalla, infecta la siguiente.
    property var faceIdx: []

    function resetFaces() {
        faceIdx = crtFacePattern();
    }
    // Repartir de nuevo las caras da vuelta pantallas ENTERAS: la que estaba
    // clara se va a negra y al revés. Eso no es un cambio de color, es un
    // fogonazo del tamaño del monitor. Iba en cada cambio de parte — o sea,
    // cada vez que el tema subía — y era lo que se veía como "flashea todo el
    // tiempo cuando sube la música". Ahora la pared se repinta en los picos y
    // al cambiar de tema: un par de veces por canción, que es cuando significa
    // algo.
    onCrtTrackSeedChanged: resetFaces()
    onActiveCrtScreensChanged: {
        resetFaces();
        // el reparto guardado habla de pantallas que ya no son las mismas
        crtForget();
    }

    function updateInfection() {
        const sh = crtShot;
        // el IOWN no reparte la frase: las pantallas muestran LA MISMA palabra
        // a la vez, así que no hay quién le pase el color a quién
        if (!crtOn || sh.mode === "all" || sh.mode === "iown" || sh.chunks.length < 2)
            return;
        if (faceIdx.length !== activeCrtScreens.length) {
            resetFaces();
            return;
        }
        const p = songPos();
        let next = faceIdx.slice();
        let touched = false;
        for (let k = 1; k < sh.chunks.length; k++) {
            const c = sh.chunks[k];
            if (p < c.from - crtInfectLead)
                break;                       // todavía no le toca a esta pantalla
            const donor = sh.chunks[k - 1].screen;
            if (c.screen === donor || next[c.screen] === next[donor])
                continue;
            // El color se MUDA, no se copia: la que recibe toma el color de la
            // que traía la frase, y la que lo entregó se queda con el otro. Si
            // sólo se copiara, en tres pasos las tres pantallas terminan del
            // mismo color y se pierde la pared de dos tonos.
            const moving = next[donor];
            next[donor] = next[c.screen];
            next[c.screen] = moving;
            touched = true;
        }
        if (touched)
            faceIdx = next;                  // array nuevo: dispara los bindings
    }

    Timer {
        interval: 60
        repeat: true
        running: root.crtOn
        onTriggered: root.updateInfection()
    }

    function crtFace(i, alarm) {
        if (alarm)
            return criticalFace;
        const sc = currentScheme();
        const idx = (faceIdx.length > i ? faceIdx[i] : crtFacePattern()[i]) || 0;
        return idx === 0 ? sc.a : sc.b;
    }
    function crtSchemeKey() {
        return currentScheme().key;
    }

    // ------------------------------------------------- dirección de cámara
    // El videoclip no muestra la misma frase en todas las pantallas: enfoca una,
    // la frase sigue en la de al lado, y el resto queda apagado. Eso es esto.
    //
    // El QUÉ se ve y DÓNDE lo manda siempre el reloj de la letra, nunca el audio:
    // si los saltos siguieran los golpes, una palabra terminaría cayendo en una
    // pantalla que ya se apagó. El audio mueve la intensidad (brillo, glitch,
    // animaciones, encuadre), no el contenido.
    property real pitchAvg: 0.5
    // referencia lenta (~20 s) del mismo centroide: el color no sale del valor
    // absoluto sino de cuánto se separó de su propio promedio. La música real
    // vive apretada en la zona grave del espectro, así que un mapeo absoluto
    // pintaría todo del mismo color; contra su propia referencia, en cambio, el
    // estribillo se despega del verso y ahí sí se ve el cambio.
    property real pitchRef: 0.5
    readonly property real pitchRel: Math.max(0, Math.min(0.5 + (pitchAvg - pitchRef) * 3.5, 1))
    property int pitchPal: -1
    property real pitchAtPal: 0.5
    property double pitchChangedAt: 0

    // fósforo según el registro: grave → amarillo/rojo (dragons), agudo →
    // celeste (ado). El rojo "critical" queda reservado para los golpes de línea.
    function palForPitch(p) {
        if (p < 0.22) return 0;        // dragons
        if (p < 0.42) return 3;        // bloodline
        if (p < 0.60) return 5;        // bone
        if (p < 0.78) return 2;        // poison
        return 1;                      // ado
    }

    // Se evalúa sólo al empezar una línea, con salto mínimo de tono y un mínimo
    // de segundos entre cambios: si no, el tubo es una calesita de colores.
    //
    // Y aun con esos dos frenos era una calesita: el registro de una voz sube en
    // cada estribillo, así que el permiso de cambiar cada `color_hold` segundos
    // se usaba casi siempre, y la pantalla entera —fondo y letra— se pintaba de
    // otro color cada diez segundos. Un tema tiene DOS o TRES momentos, no
    // dieciocho: el color ahora sólo puede moverse encima de un pico.
    function updatePitchPalette() {
        if (!crtColorFromPitch || !audLive)
            return;
        const now = Date.now();
        const cand = palForPitch(pitchRel);
        if (pitchPal < 0) {
            // la primera vez no es un cambio de color, es el color de arranque
            pitchPal = cand;
            pitchAtPal = pitchRel;
            pitchChangedAt = now;
            return;
        }
        if (cand === pitchPal)
            return;
        if (now - pitchChangedAt < crtColorHold * 1000)
            return;
        if (Math.abs(pitchRel - pitchAtPal) < 0.06)
            return;
        if (now - lastPeakAt > 9000)
            return;      // el registro cambió, pero no es un momento del tema
        pitchPal = cand;
        pitchAtPal = pitchRel;
        pitchChangedAt = now;
    }

    // Reparte una línea en pedazos con su pantalla y su ventana de tiempo.
    // mode: "all" (todas muestran todo, comportamiento viejo) | "relay" (la frase
    // viaja) | "jump" (la frase corta salta) | "single" (una sola pantalla).
    // Pedazos "naturales" de una línea: las barras la cortan, y una palabra
    // repetida arranca uno nuevo. "Take, take, take" no es una frase de tres
    // palabras: son tres golpes, y cada uno se merece su propia pantalla.
    function crtShotFor(line) {
        const text = (line.text || "").trim();
        const words = text.split(/\s+/).filter(w => w.length > 0);
        const n = activeCrtScreens.length;
        const serial = line.serial || 0;
        // Todo el sorteo cuelga de la semilla de la línea, y la semilla no mira
        // nada vivo: por eso esta función se puede evaluar para la línea que
        // TODAVÍA no llegó y da el mismo resultado cuando llega. Lo único que
        // sigue saliendo del `serial` pelado es la rotación del foco, que es
        // lo que hace que dos líneas seguidas no caigan en la misma pantalla.
        const seed = crtSeed(serial);
        const focus = n > 0 ? (serial + Math.floor(crtHash(seed * 17 + 3) * n)) % n : 0;
        // T3.1: el verso llega como un cambio de canal (estática, un cuadro
        // rojo, y ahí el texto). El sorteo es determinístico a propósito:
        // crtShot es un binding y se recalcula por cosas que no son la línea
        // (config, monitores), así que con Math.random() el mismo verso
        // cambiaría de canal a mitad de camino.
        // `trackStart` viaja en la LÍNEA y no se lee del root: preguntándoselo
        // al vivo, la predicción de la línea siguiente hecha durante la primera
        // del tema le daría el cambio de canal a la que viene, que no lo tiene.
        const chan = (line.trackStart === true) || crtHash(seed * 41 + 9) < crtChannelSwitch;
        if (!crtDirector || crtFocusMode === "all" || n <= 1 || words.length === 0)
            return { mode: "all", focus: focus, chunks: [], chan: chan };

        const t0 = line.t0 || 0;
        // Termina antes que la línea (el último pedazo tiene que llegar a leerse)
        // Y ADEMÁS se acota al tiempo de lectura: lrclib da como final de la línea
        // el comienzo de la siguiente, así que entre estrofas eso puede ser medio
        // minuto — sin el tope, un pedazo se quedaba solo en pantalla eternidades.
        const words_n = words.length;
        const span = Math.max((line.t1 || 0) - t0, 0.8) * 0.92;
        const dur = Math.min(span, 1.2 + words_n * 0.55);
        const h = crtHash(seed * 31 + words.length);
        const dir = crtHash(seed * 11 + 7) < 0.5 ? 1 : -1;

        // T3.2 — IOWN: la línea corta no se reparte, se vuelve UNA palabra del
        // tamaño de la pantalla que cruza la pared entera de derecha a
        // izquierda. Va en el drop (que es cuando el tema se abre y una
        // palabra sola aguanta tres monitores) y, muy de vez en cuando, por
        // sorteo. La parte del tema sale de la línea, congelada al mostrarla.
        if (crtIown && words.length <= 3
                && ((line.section || "verse") === "drop"
                    || crtHash(seed * 53 + 17) < 0.10)) {
            // La ventana del pedazo es la LÍNEA ENTERA, no el `dur` de los
            // otros modos: la palabra viaja con crtProgress(), que se reparte
            // sobre toda la línea. Con `dur` (dos segundos) la palabra se
            // apagaba a un tercio de camino y la pared quedaba vacía.
            const iownTo = Math.max(t0 + dur, line.t1 || 0);
            let chunks = [];
            for (let i = 0; i < n; i++)
                chunks.push({ text: text, screen: i, from: t0, to: iownTo });
            return { mode: "iown", focus: focus, chunks: chunks, chan: chan };
        }

        // Golpes repetidos: cada uno a una pantalla distinta. El corte viene
        // hecho del daemon (`segs`), que es donde se puede probar de verdad
        // contra todas las formas en que una letra escribe una repetición.
        const segs = line.segs || [];
        if (segs.length > 1) {
            let total = 0;
            const weights = segs.map(sg => { const w = sg.length + 2; total += w; return w; });
            let chunks = [], acc = 0;
            for (let i = 0; i < segs.length; i++) {
                const from = t0 + dur * acc / total;
                acc += weights[i];
                chunks.push({
                    text: segs[i],
                    screen: ((focus + dir * i) % n + n) % n,
                    from: from,
                    to: t0 + dur * acc / total,
                });
            }
            return { mode: "relay", focus: focus, chunks: chunks, chan: chan };
        }

        // frase corta y sorteo a favor: salta de pantalla en pantalla, entera
        if (words.length <= 3 && h < 0.45) {
            const hops = Math.min(n, 3);
            let chunks = [];
            for (let i = 0; i < hops; i++)
                chunks.push({
                    text: text,
                    screen: ((focus + dir * i) % n + n) % n,
                    from: t0 + dur * i / hops,
                    to: t0 + dur * (i + 1) / hops,
                });
            return { mode: "jump", focus: focus, chunks: chunks, chan: chan };
        }

        // frase larga: se reparte en pedazos que se encienden uno atrás del otro
        if (words.length >= 4) {
            const parts = Math.min(n, Math.max(2, Math.ceil(words.length / 3)));
            const per = Math.ceil(words.length / parts);
            let groups = [];
            for (let i = 0; i < words.length; i += per)
                groups.push(words.slice(i, i + per));
            let total = 0;
            const weights = groups.map(g => { const w = g.join(" ").length + 1; total += w; return w; });
            let chunks = [], acc = 0;
            for (let i = 0; i < groups.length; i++) {
                const from = t0 + dur * acc / total;
                acc += weights[i];
                chunks.push({
                    text: groups[i].join(" "),
                    screen: ((focus + dir * i) % n + n) % n,
                    from: from,
                    to: t0 + dur * acc / total,
                });
            }
            return { mode: "relay", focus: focus, chunks: chunks, chan: chan };
        }

        return { mode: "single", focus: focus, chan: chan,
                 chunks: [{ text: text, screen: focus, from: t0, to: t0 + dur }] };
    }
    // El reparto de la línea que SUENA. Normalmente sale de crtShotFor, pero si
    // al llegar había una predicción para este serial se usa ESA: la predicción
    // es la fuente de verdad, no un pronóstico que después se comprueba. Si el
    // aro apuntó a la pantalla 2, la frase cae en la pantalla 2.
    property var crtShotOverride: null
    readonly property var crtShot: (crtShotOverride
        && crtShotOverride.serial === (crtLine.serial || 0))
        ? crtShotOverride : crtShotFor(crtLine)

    // ---------------------------------------------- anticipar la línea que viene
    // El reparto de la línea k+1, calculado UNA vez al llegar la k y consumido
    // cuando la k+1 llega de verdad. No se recalcula: recalcularlo sería volver
    // a sortear, y entonces el aviso y el destino podrían no coincidir.
    property var crtPendingShot: null
    // pantalla (índice en `order`) donde va a caer la próxima línea; -1 = no se sabe
    readonly property int crtNextFocus: crtPendingShot ? crtPendingShot.focus : -1
    // el salto de esta línea: de qué pantalla viene la frase y a cuál fue
    property var crtHop: ({ from: -1, to: -1, dir: 0 })
    // T2.3: el reloj del salto. Lo publica el root — el Date.now() en que
    // arrancó — y cada monitor lo LEE; ninguno se lo anota solo. Con un reloj
    // por pantalla la franja entraría en la segunda antes de salir de la
    // primera, que es justo lo que rompe la ilusión de que es una sola.
    // 0 = no hay salto en curso (también es la forma de cancelarlo).
    property double crtHopStart: 0
    readonly property int crtHopMs: 180
    // a qué altura cruza la franja, sorteada una vez por salto: es UNA franja
    // atravesando la pared, no una por pantalla
    property real crtHopY: 0.5

    function crtPredict() {
        crtPendingShot = null;
        crtNextAt = 0;
        crtNextIn = -1;
        const nx = crtNext;
        if (!nx || !nx.text || activeCrtScreens.length === 0)
            return;
        // el `section` de la línea que viene no se puede saber (los eventos
        // `sec` llegan cuando quieren): se predice con la parte de ahora y, si
        // al llegar resultó ser un drop, el consumo la vuelve IOWN — que cruza
        // la pared entera, así que el foco que se anticipó sigue valiendo
        crtPendingShot = crtShotFor({ text: nx.text, t0: nx.t0 || 0, t1: nx.t1 || 0,
                                      serial: (crtLine.serial || 0) + 1,
                                      segs: nx.segs || [], words: [],
                                      section: audSection, trackStart: false });
        crtPendingShot.serial = (crtLine.serial || 0) + 1;
        crtNextAt = Date.now() + Math.max((nx.t0 || 0) - songPos(), 0) * 1000;
        crtNextIn = crtNextAt - Date.now();
    }

    // En qué verso va el tema: el índice de la línea que suena adentro de la
    // letra entera, o -1 si no se sabe. NO sale del `serial`, que es un contador
    // de la sesión y no dice nada después de un rebobinado ni entrando a mitad
    // de tema: se busca por `t0` (el daemon lo manda redondeado a dos decimales,
    // de ahí la tolerancia).
    readonly property int crtLineNo: {
        const ls = crtLines;
        const t0 = crtLine.t0 || 0;
        // sin tiempos no hay línea "actual": todas arrancan en cero y la
        // primera matchearía siempre
        if (!ls || ls.length === 0 || !crtLinesSynced || (crtLine.text || "") === "")
            return -1;
        for (let i = 0; i < ls.length; i++)
            if (Math.abs((ls[i].t0 || 0) - t0) < 0.05)
                return i;
        return -1;
    }

    // la primera palabra de la línea que viene ("" si no hay próxima)
    readonly property string crtNextWord: {
        const nx = crtNext;
        if (!nx || !nx.text)
            return "";
        const w = nx.text.trim().split(/\s+/).filter(x => x.length > 0);
        return w.length > 0 ? w[0] : "";
    }

    // ms que faltan para la próxima línea, ahora mismo (-1 si no se sabe)
    function crtNextLeft() {
        return crtNextAt > 0 ? crtNextAt - Date.now() : -1;
    }

    // Toda predicción se tira cuando el mundo cambió abajo: otro tema, otras
    // pantallas, otra config. Un shot guardado contra un mundo que ya no existe
    // manda la frase a una pantalla que puede no estar.
    function crtForget() {
        crtPendingShot = null;
        crtShotOverride = null;
        crtNextAt = 0;
        crtNextIn = -1;
        crtHop = { from: -1, to: -1, dir: 0 };
        // un salto a mitad de camino con otras pantallas (o con otra config)
        // es una franja cruzando una pared que ya no es ésa: se corta
        crtHopStart = 0;
    }

    // Se ve el viaje sólo cuando hay algo que cruzar: entre pantallas pegadas
    // la frase ya aparece al lado y no hay nada en el medio. El IOWN no
    // dispara (cruza la pared él solo) ni `all` (la línea está en todas).
    function crtHopFire(shot) {
        crtHopStart = 0;
        if (crtHopMode !== "corridor" && crtHopMode !== "interference"
            && crtHopMode !== "both")
            return;
        if (crtHop.from < 0 || Math.abs(crtHop.to - crtHop.from) < 2)
            return;
        if (shot.mode === "iown" || shot.mode === "all")
            return;
        crtHopY = 0.25 + Math.random() * 0.5;
        crtHopStart = Date.now();
        console.log("crt: hop sweep " + crtHop.from + "->" + crtHop.to
            + " mids=" + (Math.abs(crtHop.to - crtHop.from) - 1)
            + " y=" + crtHopY.toFixed(2));
    }

    // Dónde cae la palabra del IOWN en la pantalla i, medido sobre la PARED y
    // no sobre el monitor: el pedazo que sale por el borde de uno tiene que
    // entrar por el del otro, así que el offset descuenta el ancho de todas las
    // pantallas anteriores. Respeta `crt.order` porque activeCrtScreens ya
    // viene ordenado de izquierda a derecha.
    function crtIownX(i) {
        const scrs = activeCrtScreens;
        let total = 0;
        let before = 0;
        for (let k = 0; k < scrs.length; k++) {
            const w = (scrs[k] && scrs[k].width) || 1920;
            if (k < i)
                before += w;
            total += w;
        }
        return (1 - crtProgress()) * total - before;
    }

    // Qué le toca a la pantalla i AHORA: su pedazo encendido, el que ya pasó
    // (queda quemado, apagándose) o nada.
    function crtChunkState(i) {
        const sh = crtShot;
        if (sh.mode === "all")
            return { text: crtLine.text || "", active: true, past: false, reveal: crtProgress() };
        const p = songPos();
        let out = { text: "", active: false, past: false, reveal: 0 };
        // el quemado dura un rato después del último pedazo y se apaga: en el
        // instrumental las pantallas tienen que quedar libres, no con restos
        const ends = sh.chunks.length > 0 ? sh.chunks[sh.chunks.length - 1].to : 0;
        if (p > ends + 2.5)
            return out;
        for (let k = 0; k < sh.chunks.length; k++) {
            const c = sh.chunks[k];
            if (c.screen !== i || p < c.from)
                continue;
            const span = Math.max(c.to - c.from, 0.35);
            out = {
                text: c.text,
                active: p <= c.to,
                past: p > c.to,
                reveal: Math.max(0, Math.min((p - c.from) / span, 1)),
            };
        }
        return out;
    }

    // ---------------------------------------------- cómo entra la palabra (T3.3)
    // Que la palabra entre siempre igual cansa. Hasta acá los cuatro estilos
    // salían por sorteo parejo, así que el teletipo aparecía tanto en el
    // silencio como en el estribillo — y un teletipo en el estribillo llega
    // tarde. Ahora los pesa el contexto: cuánto está sonando (RMS de los
    // últimos ~2 s) y en qué parte del tema está la línea.
    //
    // Cómo tunear: cada fila es un contexto y cada número el peso RELATIVO
    // dentro de esa fila — no hace falta que sumen 1. Un 0 saca el estilo de
    // ese contexto. Lo que se reparte es lo que quede después de dos filtros:
    // `overburn` tiene su propio portero (compás confiable + drop) y el estilo
    // de la línea anterior EN ESA PANTALLA se descarta, salvo que sea el único
    // que quedó con peso.
    readonly property var crtEntryTable: ({
        calm:   { type: 0.35, tubeon: 0.30, snap: 0.15, interlace: 0.10,
                  slam: 0.05, roll: 0.05, overburn: 0.00 },
        strong: { interlace: 0.35, snap: 0.25, overburn: 0.25, tubeon: 0.10,
                  type: 0.05, slam: 0.00, roll: 0.00 },
    })
    // Arriba de esto la fila es "fuerte". `audLevel` no son decibeles: es el rms
    // dividido por el pico del propio tema, así que 0.55 quiere decir "más de la
    // mitad de lo más fuerte que sonó", y eso viaja igual en un tema bajito.
    readonly property real crtEntryLoud: 0.55

    // Sorteo con pesos, puro: no mira nada del root, todo entra por argumento.
    // `r` es 0..1.
    function crtPickEntry(ctx, burnOk, last, r) {
        const w = crtEntryTable[ctx] || crtEntryTable.calm;
        let keys = [];
        let total = 0;
        for (const k in w) {
            const v = (k === "overburn" && !burnOk) ? 0 : w[k];
            if (v <= 0)
                continue;
            keys.push({ k: k, v: v });
            total += v;
        }
        const kept = keys.filter(e => e.k !== last);
        if (kept.length > 0) {
            keys = kept;
            total = 0;
            for (let i = 0; i < keys.length; i++)
                total += keys[i].v;
        }
        if (keys.length === 0)
            return "snap";
        const x = r * total;
        let acc = 0;
        for (let i = 0; i < keys.length; i++) {
            acc += keys[i].v;
            if (x <= acc)
                return keys[i].k;
        }
        return keys[keys.length - 1].k;
    }

    // El estilo de entrada de cada pantalla en la línea que está llegando. Se
    // calcula UNA vez, al consumir (acá sí se lee el estado vivo: esto es la
    // línea que llega, no la que se anticipa — dentro de crtShotFor no podría).
    // `ringScreen` es la pantalla donde estaba el aro: ahí la entrada es
    // `tubeon` sí o sí, porque el aro colapsa en un punto y el punto tiene que
    // abrirse en la imagen. Sería el aro entregando la línea a otra animación.
    property var crtEntryStyles: ({})
    // el último estilo POR PANTALLA, y sólo de las pantallas que mostraron la
    // línea: anotando también las que se quedaron vacías, "el anterior" deja de
    // ser el que se vio y la regla de no repetir no dice nada
    property var crtLastEntry: ({})

    function crtEntriesFor(shot, ringScreen) {
        const out = {};
        const n = activeCrtScreens.length;
        const strong = audSection === "drop" || audLevel2s >= crtEntryLoud;
        // overburn: sólo con el compás medido (cada palabra se quema en un
        // tiempo) y en un drop. Fuera de eso no sale nunca.
        const burnOk = bpmLive && (crtLine.section || "verse") === "drop";
        const seed = crtSeed(crtLine.serial || 0);
        for (let i = 0; i < n; i++) {
            if (shot.mode !== "all") {
                let mine = false;
                for (let k = 0; k < shot.chunks.length; k++)
                    if (shot.chunks[k].screen === i)
                        mine = true;
                if (!mine)
                    continue;
            }
            out[i] = (i === ringScreen && i === shot.focus)
                ? "tubeon"
                : crtPickEntry(strong ? "strong" : "calm", burnOk,
                               crtLastEntry[i], crtHash(seed * 97 + i * 7 + 5));
        }
        return out;
    }

    // Dónde estaba el aro cuando llegó esta línea, mirando la línea VIEJA (por
    // eso se llama antes de pisar crtLine). Son las condiciones de `ringShows`
    // en Crt.qml: la pantalla que iba a recibir la próxima, sin nada de la que
    // sonaba encima. -1 = no había aro.
    function crtRingScreen() {
        const t = crtNextFocus;
        const sh = crtShot;
        if (!crtRing || t < 0 || (crtLine.text || "") === "")
            return -1;
        if (sh.mode === "all" || sh.mode === "iown" || t === sh.focus)
            return -1;
        if (crtNextIn <= 1500)
            return -1;
        for (let k = 0; k < sh.chunks.length; k++)
            if (sh.chunks[k].screen === t)
                return -1;
        return t;
    }

    // Animación de la pantalla sin letra. Alguna palabra la elige a propósito
    // (el ojo cuando la letra habla de mirar o de silencio), el resto es sorteo.
    readonly property var motifWords: [
        { re: /\b(eye|eyes|see|seen|look|watch|silence|silent|quiet|blind)\b/i, kind: "eye" },
        { re: /\b(ojo|ojos|mir[ao]|mirar|ver|silencio|callar|ciego)\b/i, kind: "eye" },
        // el mar: agua grande, hundirse, la marea
        { re: /\b(sea|ocean|wave|waves|drown|drowning|deep|tide|swim|sink|sinking|beach|shore)\b/i, kind: "ocean" },
        { re: /\b(mar|ola|olas|ahog[oa]|marea|nad[ao]|hundi?[ro]|fondo|orilla|playa)\b/i, kind: "ocean" },
        // el laguito: agua quieta que tiembla — temblar, vibrar, la lluvia
        { re: /\b(water|shake|shaking|shiver|tremble|vibrate|ripple|still|rain)\b/i, kind: "pond" },
        { re: /\b(agua|tiembl[oa]|temblar|vibra|vibrar|quiet[oa]|lluvia|llover|calma)\b/i, kind: "pond" },
        // OJO: "rings" y "tunnel" existían hasta la 4ª pasada; hoy Motif.qml no
        // los conoce y estas palabras dejaban la pantalla en blanco. Van a los
        // motivos que quedaron con el mismo sentido.
        // la estática: el ruido y la señal
        { re: /\b(static|noise|signal|snow|channel)\b/i, kind: "static" },
        { re: /\b(ruido|se[ñn]al|est[aá]tica|canal)\b/i, kind: "static" },
        // el desierto: arena, dunas, sed
        { re: /\b(sand|desert|dune|dunes|dust|thirst)\b/i, kind: "dunes" },
        { re: /\b(arena|desierto|duna|dunas|polvo|sed)\b/i, kind: "dunes" },
        { re: /\b(fire|burn|heart|beat|blood|fuego|arde|coraz[oó]n|late)\b/i, kind: "radar" },
        { re: /\b(run|road|drive|fall|corr[eo]|camino|caigo)\b/i, kind: "stars" },
    ]
    // Cada cuánto se cambia de animación. Antes se sorteaba por LÍNEA: las
    // pantallas laterales cambiaban de dibujo cada dos segundos y parecían un
    // salvapantallas nervioso. Ahora dura una sección entera (o ~25 s).
    property int motifGen: 0
    Timer {
        interval: 25000
        repeat: true
        running: root.crtOn
        onTriggered: root.motifGen++
    }

    readonly property var motifKinds: ["eye", "scope", "radar", "stars", "testcard",
                                       "rain", "ocean", "pond", "dunes", "static",
                                       "textsea"]

    // Un motivo puede no tener con qué dibujarse. El filtro NO mira la pantalla
    // a propósito: `crtMotifFor` garantiza que dos pantallas apagadas nunca
    // muestren el mismo dibujo repartiendo UNA lista entre todas, y una lista
    // distinta por pantalla rompe justo eso.
    function motifAllowed(kind) {
        if (kind === "textsea")
            return crtLines.length > 0;
        return true;
    }

    // Los dos de agua se pueden apagar juntos (`water = false`) sin tocar el
    // resto de las animaciones, y de paso se caen los que ahora mismo no tienen
    // con qué dibujarse.
    function motifPool(list) {
        const out = [];
        for (let k = 0; k < list.length; k++) {
            const kind = list[k];
            if (!crtWater && (kind === "ocean" || kind === "pond"))
                continue;
            if (!motifAllowed(kind))
                continue;
            out.push(kind);
        }
        return out.length > 0 ? out : ["eye"];
    }

    function crtMotifFor(i) {
        if (!crtMotifs)
            return "none";
        const n = Math.max(activeCrtScreens.length, 1);
        // la palabra clave se lleva UNA sola pantalla, no todas: si el ojo
        // aparece en las tres a la vez deja de ser un guiño y es un cartel
        const chosen = (crtLine.serial || 0) % n;
        if (i === chosen) {
            const text = crtLine.text || "";
            for (let k = 0; k < motifWords.length; k++)
                if (motifWords[k].re.test(text)) {
                    const kind = motifWords[k].kind;
                    if ((crtWater || (kind !== "ocean" && kind !== "pond"))
                            && motifAllowed(kind))
                        return kind;
                }
        }
        // dos pantallas apagadas nunca muestran el mismo dibujo
        // en el silencio el ojo, la carta de ajuste o el mar quieto; en el pico,
        // lo que se mueve
        const calm = audSection === "quiet";
        const pool = motifPool(calm ? ["eye", "testcard", "scope", "pond"] : motifKinds);
        const pick = Math.floor(crtHash(motifGen * 17 + crtTrackSeed * 3) * pool.length);
        const offset = Math.floor(crtHash(motifGen * 29 + i * 11) * (pool.length - 1)) + 1;
        return pool[(pick + (i === chosen ? 0 : offset)) % pool.length];
    }

    // El latido del tubo: lo decide el root UNA vez para toda la pared, no cada
    // pantalla por su cuenta. Antes el fogonazo lo disparaba la pantalla enfocada
    // en su propia instancia, así que las demás nunca se enteraban y las
    // animaciones no acompañaban nada.
    property int flickerGen: 0
    property double lastFlickerAt: 0
    property bool flickerHard: false     // true = además apagón corto
    // El tubo late en los PICOS, no en los golpes. El golpe es cada bombo que
    // sobresale: hay cientos por tema, y latir en todos es latir siempre — se
    // lee como una pantalla rota, no como que el tema pegó. El pico lo elige el
    // daemon contra la canción entera (percentil, separación mínima y tope por
    // tema), así que acá sólo queda un seguro por si llegan dos juntos.
    function tubeBeat() {
        if (!crtOn || crtFlicker <= 0.01)
            return;
        const now = Date.now();
        // el seguro contra dos picos juntos también se cuantiza: si el tubo va
        // a esperar, que espere un número entero de tiempos
        if (now - lastFlickerAt < quantize(4000))
            return;
        lastFlickerAt = now;
        flickerHard = sectionEnergy > 1.45 && Math.random() < 0.35 && crtFlicker > 0.5;
        flickerGen++;
    }
    // Todo lo grande cuelga del mismo clavo: el latido del tubo y el reparto de
    // colores de la pared pasan en el pico, juntos. Dos cosas fuertes en el
    // mismo instante se leen como UN golpe; repartidas, se leen como una
    // pantalla que hace cosas raras cada tanto.
    onAudPeakChanged: {
        tubeBeat();
        if (crtOn)
            resetFaces();
    }

    // Interferencia espontánea: la programa el root y le toca a UNA pantalla por
    // vez. Con un temporizador propio por pantalla, aunque cada una se rompiera
    // cada 20 s, en la pared se veía una rotura cada 6 — y eso es lo que se
    // siente como "vibra en momentos random".
    property int interfGen: 0
    property int interfScreen: 0
    Timer {
        interval: 9000
        repeat: true
        running: root.crtOn && root.crtIntensity > 0
        onTriggered: {
            const calm = 1 / Math.max(sectionEnergy, 0.35);
            interval = (7000 + Math.random() * 11000 * calm)
                / Math.max(crtIntensity + 0.55, 0.3);
            interfScreen = Math.floor(Math.random() * Math.max(activeCrtScreens.length, 1));
            interfGen++;
        }
    }

    // Interruptor del modo: un archivo en XDG_RUNTIME_DIR, no el socket. Así
    // `fatal crt off` apaga el tubo aunque el daemon esté colgado o muerto —
    // con la pantalla tapada esa es la única salida que no depende de nada.
    FileView {
        id: crtSwitch
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/cartelitos-crt`
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.crtOn = text().trim() === "1"
        onLoadFailed: root.crtOn = false
    }

    // T3.3: modo setup. Cada pantalla dibuja su número y el nombre de su output,
    // que es lo que hay que escribir en `[crt] order`. Otro archivo, mismo
    // mecanismo que el interruptor — `fatal crt setup` es un proceso corto y no
    // tiene forma de hablarle al overlay que no sea ésta.
    property bool crtSetupOn: false
    FileView {
        id: crtSetupSwitch
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/cartelitos-crt-setup`
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.crtSetupOn = text().trim() === "1"
        onLoadFailed: root.crtSetupOn = false
    }

    // Al prender el tubo se barren los carteles: si no, los que ya estaban vivos
    // quedan esperando abajo y reaparecen enteros al salir (se veía como si el
    // modo viejo hubiera estado corriendo todo el tiempo).
    onCrtOnChanged: {
        if (crtOn) {
            dialogList = [];
            currentLyricSerial = -1;
        }
    }

    // Salida del tubo: cualquier tecla o click vuelve al escritorio. Se escribe
    // el mismo interruptor que usa `fatal crt`, así que el daemon y la bandeja
    // quedan enterados — no hay dos verdades sobre si el tubo está prendido.
    function crtExit() {
        if (!crtOn)
            return;
        crtOn = false;
        crtSwitch.setText("0");
        // salir con el mouse también tiene que apagar los números del setup: si
        // no, quedan puestos y el próximo `fatal crt on` arranca en modo setup
        if (crtSetupOn) {
            crtSetupOn = false;
            crtSetupSwitch.setText("0");
        }
    }

    // el watcher no alcanza si el archivo todavía no existe cuando arranca el
    // overlay (pasa siempre: el daemon lo escribe un segundo después), así que
    // además se relee solo. Es un byte: sale más barato que perdérselo.
    Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            crtSwitch.reload();
            crtSetupSwitch.reload();
        }
    }

    // T0.11: hotplug de monitores. matchScreens/orderScreens leen
    // Quickshell.screens dentro de una función, y esa lectura no siempre basta
    // para que el binding se marque sucio con un hotplug real — por eso el
    // recálculo se fuerza a mano leyendo screensGen, que Connections empuja
    // cada vez que la lista de pantallas cambia.
    property int screensGen: 0
    Connections {
        target: Quickshell
        function onScreensChanged() {
            root.screensGen++;
        }
    }

    // pantallas donde corre el overlay según la config
    function matchScreens(v) {
        const _dep = root.screensGen;   // dependencia: ver el comentario de arriba
        const ss = Quickshell.screens;
        if (v === "all")
            return [...ss];
        if (Array.isArray(v)) {
            const r = ss.filter(s => v.indexOf(s.name) >= 0);
            return r.length > 0 ? r : [ss[0]];
        }
        for (let i = 0; i < ss.length; i++)
            if (ss[i].name === v)
                return [ss[i]];
        return [ss[0]];
    }
    readonly property var activeScreens: matchScreens(targetScreen)

    // Orden de las pantallas del tubo: de izquierda a derecha. Importa cuando la
    // línea se parte entre monitores — "TA" tiene que caer en el de la izquierda.
    // "auto" usa la posición real que les dio el compositor; también se puede
    // dar la lista a mano (sirve para cualquier cantidad de monitores).
    function orderScreens(list) {
        if (Array.isArray(crtOrder) && crtOrder.length > 0) {
            let out = [];
            for (let i = 0; i < crtOrder.length; i++) {
                const s = list.find(x => x.name === crtOrder[i]);
                if (s && out.indexOf(s) < 0)
                    out.push(s);
            }
            // las que no estén en la lista van al final, sin perderse
            for (let i = 0; i < list.length; i++)
                if (out.indexOf(list[i]) < 0)
                    out.push(list[i]);
            return out;
        }
        return [...list].sort((a, b) => (a.x - b.x) || (a.y - b.y));
    }

    // el tubo se toma todas las pantallas por default, aunque los carteles
    // estén limitados a una sola: el modo CRT es una toma de la máquina entera
    readonly property var activeCrtScreens: orderScreens(
        crtScreens === "same" ? activeScreens : matchScreens(crtScreens))

    function randomIcon() {
        const r = Math.random();
        if (r < 0.40) return "warning";
        if (r < 0.65) return "error";
        if (r < 0.85) return "question";
        return "info";
    }

    function _randomSpawnPos() {
        let rx = 0.02 + Math.random() * 0.90;
        let ry = 0.02 + Math.random() * 0.84;
        const a = root.spawnArea;
        if (a === "top")
            ry = 0.02 + Math.random() * 0.23;
        else if (a === "bottom")
            ry = 0.60 + Math.random() * 0.26;
        else if (a === "left")
            rx = 0.02 + Math.random() * 0.28;
        else if (a === "right")
            rx = 0.64 + Math.random() * 0.28;
        else if (a === "edges") {
            if (Math.random() < 0.5)
                rx = Math.random() < 0.5 ? 0.02 + Math.random() * 0.12 : 0.78 + Math.random() * 0.14;
            else
                ry = Math.random() < 0.5 ? 0.02 + Math.random() * 0.12 : 0.72 + Math.random() * 0.14;
        }
        return { rx: rx, ry: ry };
    }

    // T0.4: hasta 6 intentos rechazando una posición que se pisaría con un
    // cartel vivo (no muriendo). No hay tamaño real de pantalla acá todavía
    // (el cartel ni se creó), así que el rect se estima en fracción de una
    // referencia 1920x1080 — no hace falta exacto, sólo evitar que nazcan
    // pegados uno encima del otro.
    function spawnPos() {
        const w = (320 * root.cfgScale) / 1920;
        const h = (110 * root.cfgScale) / 1080;
        let candidate = _randomSpawnPos();
        for (let attempt = 0; attempt < 6; attempt++) {
            candidate = _randomSpawnPos();
            const collides = root.dialogList.some(d => {
                if (d.dying)
                    return false;
                return candidate.rx < d.rx + w && candidate.rx + w > d.rx
                    && candidate.ry < d.ry + h && candidate.ry + h > d.ry;
            });
            if (!collides)
                return candidate;
        }
        return candidate;
    }

    // orden de muerte de la cascada: dónde cae este cartel en la coreografía
    // elegida (cascadeMode). "age" es el índice de aparición (el orden de
    // siempre); "top"/"center" reordenan por posición normalizada (rx, ry).
    function cascadeRank(d) {
        const arr = root.dialogList;
        if (root.cascadeMode === "top") {
            const sorted = arr.slice().sort((a, b) => a.ry - b.ry);
            return sorted.findIndex(x => x.serial === d.serial);
        }
        if (root.cascadeMode === "center") {
            const dist = e => Math.abs(e.rx - 0.5) + Math.abs(e.ry - 0.5);
            const sorted = arr.slice().sort((a, b) => dist(a) - dist(b));
            return sorted.findIndex(x => x.serial === d.serial);
        }
        return arr.findIndex(x => x.serial === d.serial);
    }

    function pushDialog(entry, markCurrent) {
        const pos = spawnPos();
        entry.serial = root.serial++;
        entry.rx = pos.rx;
        entry.ry = pos.ry;
        entry.deathAge = root.deathAgeMin + Math.floor(Math.random() * (root.deathAgeMax - root.deathAgeMin + 1));
        if (markCurrent) {
            root.lyricGen++;
            root.currentLyricSerial = entry.serial;
        }
        entry.gen = root.lyricGen;
        let arr = root.dialogList.slice();
        arr.push(entry);
        root.dialogList = arr;
        // max_dialogs = 0: sin límite (igual los carteles mueren por edad/TTL).
        // Nunca splice directo: el sobrante se manda a morir con su animación,
        // igual que cualquier otro cartel — el más viejo (menor serial), nunca
        // el actual.
        if (root.maxDialogs > 0 && arr.length > root.maxDialogs) {
            const oldest = arr.filter(d => d.serial !== root.currentLyricSerial)
                              .reduce((a, b) => (a === null || b.serial < a.serial) ? b : a, null);
            if (oldest)
                root.dyingSerial = oldest.serial;
        }
    }

    function show(text, title, icon, t0, t1, segs, words, kind, nxt) {
        // T4.5: "fatal-lyrics no responde". No es un verso: no toca el tubo, no
        // envejece a nadie y no pasa a ser la línea actual. Muere solo cuando
        // llegue la próxima línea de verdad (ver shouldDie).
        if (kind === "hang") {
            if (crtOn || (singMode && !singing))
                return;      // en el tubo no hay carteles: no hay dónde ponerlo
            pushDialog({ text: text, title: title || "fatal-lyrics",
                         icon: "warning", kind: "hang" }, false);
            return;
        }
        // el tubo dibuja la línea entera; los carteles son el otro modo
        // el serial viaja adentro del objeto: una sola señal de cambio lleva
        // texto y sorteo juntos, y el layout no parpadea al aparecer la línea
        // `words`: tiempo real de cada palabra (LRC "enhanced"). Vacío = no lo
        // manda el daemon y el karaoke lo estima por largo, como siempre.
        // primer verso después de un clear = tema nuevo: ahí el cambio de canal
        // va siempre, no por sorteo. Se mira ANTES de pisar la línea vieja.
        crtTrackStart = (crtLine.text || "") === "";
        const serial = crtSerial + 1;
        // dónde estaba el aro: se mira ANTES de pisar la línea vieja, porque
        // sale de lo que se estaba mostrando hasta recién
        const ringScreen = crtRingScreen();
        // Se CONSUME el reparto que se calculó al llegar la línea anterior. No
        // se vuelve a sortear: volver a sortear sería admitir que lo que se
        // anticipó (el aro, el motif que huye) puede no cumplirse.
        let taken = (crtPendingShot && crtPendingShot.serial === serial)
            ? crtPendingShot : null;
        crtPendingShot = null;
        const prevFocus = (crtLine.text || "") !== "" ? crtShot.focus : -1;
        // `section`: la parte del tema QUEDA CONGELADA en la línea. Leerla del
        // vivo desde crtShotFor haría que el modo cambie a mitad de verso (los
        // eventos `sec` llegan cuando quieren) y la palabra saltaría de lugar.
        crtLine = { text: text, t0: t0 ?? 0, t1: t1 ?? 0, serial: serial,
                    segs: segs || [], words: words || [], section: audSection,
                    trackStart: crtTrackStart };
        // Lo ÚNICO que la predicción no podía saber es en qué parte del tema
        // iba a caer la línea. Si cayó en un drop y eso la vuelve IOWN, se
        // rehace encima: el foco no cambia (sale de la semilla y de cuántas
        // pantallas hay) y el IOWN cruza la pared entera igual, así que lo que
        // se anticipó sigue siendo cierto.
        const fresh = crtShotFor(crtLine);
        if (taken && fresh.mode === "iown" && taken.mode !== "iown") {
            fresh.serial = serial;
            taken = fresh;
        }
        crtShotOverride = taken;
        const shot = taken || fresh;
        crtHop = (prevFocus >= 0 && prevFocus !== shot.focus)
            ? { from: prevFocus, to: shot.focus, dir: shot.focus > prevFocus ? 1 : -1 }
            : { from: -1, to: -1, dir: 0 };
        // el salto arranca ACÁ, antes del serial: cuando Crt.qml reciba la
        // línea nueva el reloj de la franja ya tiene que estar corriendo
        crtHopFire(shot);
        // y el estilo de entrada de cada pantalla, también antes del serial:
        // Crt.qml lo lee al recibir la línea, así que para entonces ya tiene
        // que estar puesto
        crtEntryStyles = crtEntriesFor(shot, ringScreen);
        // el registro del "anterior" se acumula: una pantalla que esta vez no
        // mostró nada conserva el estilo con el que entró la última vez que sí
        const seen = {};
        for (const k in crtLastEntry)
            seen[k] = crtLastEntry[k];
        for (const k in crtEntryStyles)
            seen[k] = crtEntryStyles[k];
        crtLastEntry = seen;
        // último: Crt.qml cuelga de esta señal, y para cuando la reciba tiene
        // que ver la línea, el reparto y el salto ya puestos
        crtSerial++;
        crtNext = nxt || null;
        crtPredict();
        if (crtOn)
            console.log("crt: next focus=" + crtNextFocus
                + " in=" + Math.round(crtNextIn)
                + " hop=" + crtHop.from + "->" + crtHop.to
                + " ring=" + ringScreen
                + " entry=" + JSON.stringify(crtEntryStyles));
        updatePitchPalette();
        if (crtOn)
            return;
        // T5.3: con el karaoke puesto un cartel sólo nace mientras se canta. La
        // línea igual se guarda arriba (crtLine): si arrancás a cantar en la
        // mitad del verso, el tubo ya tiene qué mostrar sin esperar al próximo.
        if (singMode && !singing)
            return;
        pushDialog({
            text: text, title: title || "Spotify", icon: icon || randomIcon(),
            t0: t0 ?? 0, t1: t1 ?? 0, words: words || null,
        }, true);
    }

    // El daemon manda `np` también cuando el tubo está prendido y la funda
    // apagada (el instrumental necesita saber qué suena), así que prender la
    // funda acá se decide con el tubo a la vista: si no, al salir del CRT
    // aparecería una funda que nadie pidió.
    function nowPlaying(title, artist, album, art) {
        npTitle = title || "Now Playing";
        npInfo = artist + (album ? " — " + album : "");
        npArt = art || "";
        npProgress = 0;
        npShown = !crtOn;
        npDocked = false;
        npSerial++;
        npDockTimer.restart();
    }

    // botón "No" (si troll_no): duplica el cartel, el original queda
    function duplicate(d) {
        pushDialog({ text: d.text, title: d.title, icon: d.icon }, false);
    }

    function dismiss(serial) {
        root.dialogList = root.dialogList.filter(d => d.serial !== serial);
    }

    // evento -> propiedad. Es sólo una tabla de datos leída por applyConfig
    // (abajo): asignaciones planas `x = ev.k ?? x`, sin lógica ni orden que
    // importe entre ellas (ninguna de estas propiedades tiene un
    // onXxxChanged que dependa de las demás), así que iterarla en vez de
    // repetirla a mano no cambia nada de lo que se ve ni de cuándo dispara.
    readonly property var _configEventMap: ({
        screen: "targetScreen", max_dialogs: "maxDialogs", scale: "cfgScale",
        current_scale: "cfgCurrentScale", spawn_area: "spawnArea", glitch: "glitchLevel",
        effects_on_current: "effectsOnCurrent", tearing: "tearingOn",
        death_age_min: "deathAgeMin", death_age_max: "deathAgeMax", max_lifetime: "maxLifetime",
        click_through: "clickThrough", troll_no: "trollNo", burn_in: "burnIn",
        cascade: "cascadeDeath", cascade_style: "cascadeStyle", karaoke: "karaokeOn",
        mirror: "mirrorOn",
        np_corner: "npCorner", np_margin: "npMargin", np_vinyl: "npVinyl",
        sing: "singMode",
        crt_screens: "crtScreens", crt_order: "crtOrder", crt_exit_on: "crtExitOn",
        crt_palette: "crtPalette", crt_split: "crtSplit", crt_font: "crtFont",
        crt_curvature: "crtCurvature", crt_scanlines: "crtScanlines", crt_chroma: "crtChroma",
        crt_bloom: "crtBloom", crt_noise: "crtNoise", crt_roll: "crtRoll",
        crt_vignette: "crtVignette", crt_intensity: "crtIntensity", crt_chrome: "crtChrome",
        crt_director: "crtDirector", crt_focus: "crtFocusMode",
        crt_color_from_pitch: "crtColorFromPitch", crt_color_hold: "crtColorHold",
        crt_infect_lead: "crtInfectLead", crt_alarm_threshold: "crtAlarmThreshold",
        crt_channel_switch: "crtChannelSwitch", crt_iown: "crtIown",
        crt_foreshadow: "crtForeshadow", crt_ring: "crtRing",
        crt_hop: "crtHopMode",
        crt_motifs: "crtMotifs", crt_camera: "crtCamera",
        crt_section_zoom: "crtSectionZoom", crt_quality: "crtQuality",
        crt_flicker: "crtFlicker", crt_word_flash: "crtWordFlash",
        crt_water: "crtWater", crt_water_amp: "crtWaterAmp",
    })

    function applyConfig(ev) {
        const map = root._configEventMap;
        for (const key in map) {
            const prop = map[key];
            root[prop] = ev[key] ?? root[prop];
        }
        // la config decide cómo se reparte una línea (director, focus, split,
        // iown): lo que se anticipó con la config vieja ya no es lo que va a
        // pasar. Se tira y la línea que suena se vuelve a repartir sola.
        crtForget();
    }

    // El daemon manda eventos JSON por línea: config / show / np / clear
    SocketServer {
        active: true
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/cartelitos.sock`
        handler: Socket {
            parser: SplitParser {
                onRead: message => {
                    try {
                        const ev = JSON.parse(message);
                        if (ev.cmd === "show")
                            root.show(ev.text, ev.title, ev.icon, ev.t0, ev.t1, ev.segs,
                                      ev.words, ev.kind, ev.next);
                        else if (ev.cmd === "lyrics") {
                            root.crtLines = ev.lines || [];
                            root.crtLinesSynced = ev.synced !== false;
                        }
                        else if (ev.cmd === "np")
                            root.nowPlaying(ev.title, ev.artist, ev.album, ev.art);
                        else if (ev.cmd === "pos") {
                            root.npProgress = ev.l > 0 ? Math.min(ev.p / ev.l, 1) : 0;
                            root.posAbs = ev.p;
                            root.posLen = ev.l;
                            root.posAt = Date.now();
                        } else if (ev.cmd === "sec") {
                            root.audSection = ev.kind;
                            root.audPct = ev.p;
                            // cambiar de parte cambia el dibujo y el reparto de
                            // colores: es el momento en el que el tema respira
                            root.sectionGen++;
                            // el aviso (T4.2) ya cambió el dibujo hace dos
                            // segundos: cambiarlo otra vez ahora sería un
                            // parpadeo, no una anticipación
                            if (root.motifPreCued)
                                root.motifPreCued = false;
                            else
                                root.motifGen++;
                        } else if (ev.cmd === "bpm") {
                            root.bpm = ev.v;
                            root.bpmConf = ev.conf;
                            root.bpmAt = Date.now();
                            // ver bpmPhase: llega la EDAD del último golpe
                            root.lastBeatAt = Date.now() - (ev.phase || 0) * 1000;
                        } else if (ev.cmd === "cue") {
                            root.audComing = ev.kind;
                            root.audComingAt = Date.now();
                            root.cueIn = ev.in || 2.0;
                            // T4.2: el aviso sólo llega en la SEGUNDA escucha
                            // del tema (el mapa tiene que existir). Es lo único
                            // que puede prepararse para un golpe en vez de
                            // reaccionar tarde: la pantalla de al lado ya cambia
                            // de dibujo y la cámara empieza a acercarse ANTES.
                            if (ev.kind === "drop") {
                                root.motifGen++;
                                root.motifPreCued = true;
                                root.cueGen++;
                            }
                        } else if (ev.cmd === "art") {
                            root.artColors = ev.colors || [];
                        } else if (ev.cmd === "aud") {
                            root.audLevel = ev.l;
                            root.audLevel2s = root.audLevel2s * 0.95 + ev.l * 0.05;
                            root.audLo = ev.lo;
                            root.audMid = ev.mid;
                            root.audHi = ev.hi;
                            root.audCentroid = ev.c;
                            root.audAt = Date.now();
                            // el centroide se promedia largo: el color tiene que
                            // seguir el registro del tema, no cada sílaba
                            root.pitchAvg = root.pitchAvg * 0.96 + ev.c * 0.04;
                            root.pitchRef = root.pitchRef * 0.998 + ev.c * 0.002;
                            if (ev.b)
                                root.audBeat++;
                            // el pico lo elige el daemon (es el que sabe dónde
                            // cae este momento dentro de la canción entera)
                            if (ev.pk) {
                                root.lastPeakAt = Date.now();
                                root.audPeak++;
                            }
                        } else if (ev.cmd === "sing") {
                            // T5.3: sólo llegan los cambios, no un nivel por
                            // bloque — el que decide es el daemon
                            root.singing = ev.on === true;
                        } else if (ev.cmd === "clear") {
                            root.npShown = false;
                            root.bpm = 0;      // otro tema, otro compás
                            root.bpmConf = 0;
                            root.audComing = "";
                            root.motifPreCued = false;
                            // el tubo se queda sin señal y rota el fósforo
                            root.crtLine = { text: "", t0: 0, t1: 0, serial: root.crtSerial, segs: [], words: [] };
                            root.crtTrackSeed++;
                            // otro tema: la letra y todo lo anticipado sobre la
                            // anterior no valen nada. Sin esto los pedazos del
                            // reparto viejo sobreviven al cambio de tema.
                            root.crtNext = null;
                            root.crtLines = [];
                            root.crtLinesSynced = true;
                            root.crtForget();
                            // cascada: en vez de esfumarse, mueren en cadena (dominó CRT)
                            if (root.cascadeDeath && root.dialogList.length > 0) {
                                root.cascadeMode = root.cascadeStyle === "random"
                                    ? ["age", "top", "center"][Math.floor(Math.random() * 3)]
                                    : root.cascadeStyle;
                                root.clearGen++;
                            }
                            else
                                root.dialogList = [];
                        } else if (ev.cmd === "config")
                            root.applyConfig(ev);
                    } catch (e) {
                        console.log("cartelitos: evento inválido:", message);
                    }
                }
            }
        }
    }

    // modo CRT: un tubo full-bleed por pantalla, con su propio fósforo.
    // Va aparte de los carteles porque suele tomar más monitores que ellos.
    Variants {
        model: root.activeCrtScreens

        Scope {
            id: crtScope
            required property var modelData

            Crt {
                ctl: root
                scr: crtScope.modelData
                idx: Math.max(0, root.activeCrtScreens.indexOf(crtScope.modelData))
                total: root.activeCrtScreens.length
            }
        }
    }

    // una instancia del overlay por pantalla activa ("all"/lista = varias);
    // cada monitor spawnea los carteles en posiciones propias
    Variants {
        model: root.activeScreens

        Scope {
            id: perScreen
            required property var modelData
            readonly property var scr: modelData

            Variants {
                model: root.crtOn ? [] : root.dialogList

                PanelWindow {
                    id: win
                    required property var modelData

                    // edad = cuántas líneas de letra aparecieron después de éste
                    // (los duplicados del "No" no envejecen a nadie)
                    readonly property int age: root.lyricGen - modelData.gen
                    readonly property bool current: modelData.serial === root.currentLyricSerial
                    readonly property real glitchiness: Math.min(age / 5, 1)
                    // signo determinístico por serial: mitad de los carteles se
                    // inclina para un lado, la otra mitad para el otro
                    readonly property int rotSign: modelData.serial % 2 === 0 ? 1 : -1
                    property bool dying: false
                    property bool ghosting: false

                    // nacimiento: el cartel crece desde un punto y un flash blanco
                    // recorre el bevel, como si el monitor recién lo encendiera.
                    // Declarado antes de Component.onCompleted: en un delegate con
                    // required property (ComponentBehavior: Bound implícito), un id
                    // referenciado directo en un signal handler no resuelve si su
                    // objeto se declara más abajo en el archivo.
                    property real spawnFlash: 0
                    ParallelAnimation {
                        id: spawnAnim
                        NumberAnimation { target: win; property: "deathScale"; from: 0.04; to: 1; duration: 140; easing.type: Easing.OutQuad }
                        NumberAnimation { target: win; property: "deathOpacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutQuad }
                        SequentialAnimation {
                            PropertyAction { target: win; property: "spawnFlash"; value: 1 }
                            NumberAnimation { target: win; property: "spawnFlash"; to: 0; duration: 60 }
                        }
                    }

                    // factor de tamaño: config global + extra del cartel actual
                    readonly property real k: root.cfgScale * (current ? root.cfgCurrentScale : 1.0)
                    readonly property real iconW: 32
                    readonly property bool fx: !current || root.effectsOnCurrent

                    // karaoke: la línea actual se pinta palabra por palabra; el timing
                    // por palabra se estima proporcional al largo (lrclib solo da líneas)
                    readonly property bool karaokeActive: root.karaokeOn && current
                        && (modelData.t1 || 0) > (modelData.t0 || 0)
                    property string karaokeText: ""
                    function htmlEsc(s) {
                        return root.htmlEscape(s);
                    }
                    function updateKaraoke() {
                        const words = modelData.text.split(" ").filter(w => w.length > 0);
                        if (words.length === 0)
                            return;
                        let cut = 0;
                        // LRC "enhanced": cada palabra trae su segundo, no hay
                        // nada que estimar. El daemon garantiza un tiempo por
                        // palabra del texto, pero el largo se chequea igual: si
                        // no coincide, los índices no son los mismos y pintar
                        // por índice pintaría cualquier cosa.
                        const timed = modelData.words || null;
                        if (timed && timed.length === words.length) {
                            const p = root.songPos();
                            while (cut < timed.length && timed[cut][0] <= p)
                                cut++;
                            karaokeText = win.karaokeHtml(words, cut);
                            return;
                        }
                        // mismo avance que usa el tubo del modo CRT: una sola cuenta
                        // (termina de pintar ~1 s antes del próximo cartel; si no, la
                        // última palabra nunca llega a verse pintada)
                        const f = root.karaokeFraction(modelData.t0, modelData.t1);
                        let total = 0;
                        const weights = words.map(w => { const n = w.length + 1; total += n; return n; });
                        let acc = 0;
                        for (let i = 0; i < words.length; i++) {
                            acc += weights[i];
                            if (acc <= f * total + 0.001)
                                cut = i + 1;
                        }
                        karaokeText = win.karaokeHtml(words, cut);
                    }
                    // las primeras `cut` palabras pintadas, el resto crudo
                    function karaokeHtml(words, cut) {
                        let out = "";
                        if (cut > 0)
                            out = '<font color="#000080">' + htmlEsc(words.slice(0, cut).join(" ")) + "</font>";
                        if (cut > 0 && cut < words.length)
                            out += " ";
                        if (cut < words.length)
                            out += htmlEsc(words.slice(cut).join(" "));
                        return out;
                    }
                    Timer {
                        interval: 120
                        repeat: true
                        running: win.karaokeActive
                        triggeredOnStart: true
                        onTriggered: win.updateKaraoke()
                    }

                    // tearing: la ventana partida en franjas desplazadas (solo viejos)
                    readonly property int tearPad: 22
                    property var tearSeed: []
                    readonly property bool torn: root.tearingOn && !current && tearSeed.length > 0

                    // offset de arrastre manual
                    property real dx: 0
                    property real dy: 0

                    // estado del glitch
                    property bool burst: false
                    property real jx: 0
                    property real jy: 0
                    property real burstOpacity: 1
                    property real holoOpacity: 1
                    property color burstTint: "#ff00ff"
                    property var burstSeed: []

                    screen: perScreen.scr
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "cartelitos"
                    exclusionMode: ExclusionMode.Ignore
                    color: "transparent"

                    // click_through: región de input vacía, el mouse pasa de largo
                    Region { id: emptyMask }
                    mask: root.clickThrough ? emptyMask : null

                    TextMetrics {
                        id: tm
                        text: win.modelData.text
                        font.pixelSize: Math.round(13 * win.k)
                    }

                    readonly property int dlgW: Math.max(300 * k, Math.min(tm.width, 360 * k) + (iconW + 78) * k)

                    // El reflejo vive DENTRO de la ventana del cartel (así se
                    // arrastra con él sin plumbing extra), pero cae por debajo:
                    // la ventana tiene que crecer o queda recortado.
                    // muriendo no: el colapso encoge el cartel y el reflejo no lo
                    // acompaña, así que quedaría una copia flotando abajo
                    readonly property bool mirrored: root.mirrorOn && current && !ghosting && !dying
                    readonly property int mirrorH: mirrored ? Math.round(content.height * 0.5) : 0

                    implicitWidth: dlgW + tearPad * 2
                    implicitHeight: content.height + mirrorH

                    // en multi-pantalla cada monitor randomiza su propia posición
                    // (mismo cartel, lugar distinto en cada una)
                    property real prx: modelData.rx
                    property real pry: modelData.ry
                    Component.onCompleted: {
                        if (root.activeScreens.length > 1) {
                            const p = root.spawnPos();
                            prx = p.rx;
                            pry = p.ry;
                        }
                        if (win.shouldDie)
                            win.die();
                        else
                            spawnAnim.start();
                    }

                    // max_dialogs: pushDialog avisa por acá cuál es el más viejo que
                    // sobra; cada pantalla tiene su propia instancia de este cartel y
                    // todas lo ven, así que todas se mandan a morir juntas
                    // el cartel colgado (T4.5) se va solo cuando aparece la línea
                    // siguiente: `gen` quedó en el lyricGen del momento en que
                    // nació, y lyricGen sólo sube con un verso de verdad
                    readonly property bool hung: modelData.kind === "hang"
                    readonly property bool shouldDie: modelData.serial === root.dyingSerial
                        || (hung && modelData.gen < root.lyricGen)
                    onShouldDieChanged: {
                        if (shouldDie && !dying)
                            die();
                    }

                    readonly property real baseX: prx * (screen.width - implicitWidth)
                    readonly property real baseY: pry * (screen.height - 200)

                    // arrastre: delta clampeado contra la base (si no, en los bordes el acumulado
                    // se dispara) y jitter fuera de los márgenes mientras se arrastra — el jitter
                    // metido en la posición realimentaba el delta y la ventana "salía volando"
                    property bool dragHeld: false
                    function dragBy(ddx, ddy) {
                        dx = Math.max(-baseX, Math.min(dx + ddx, screen.width - 80 - baseX));
                        dy = Math.max(-baseY, Math.min(dy + ddy, screen.height - 60 - baseY));
                    }

                    // click derecho en la titlebar: minimiza hacia la esquina de la
                    // funda en vez de morir en el lugar. Sin burn-in: no queda
                    // sombra quemada de algo que el usuario cerró a propósito.
                    readonly property real minimizeDx: (root.npCorner === "center" ? (screen.width - implicitWidth) / 2
                        : root.npCorner.indexOf("left") >= 0 ? root.npMargin
                        : screen.width - implicitWidth - root.npMargin) - baseX
                    readonly property real minimizeDy: (root.npCorner === "center" ? (screen.height - content.height) / 2
                        : root.npCorner.indexOf("top") === 0 ? root.npMargin
                        : screen.height - content.height - root.npMargin) - baseY

                    function minimize() {
                        if (dying)
                            return;
                        dying = true;
                        modelData.dying = true;
                        minimizeAnim.start();
                    }

                    SequentialAnimation {
                        id: minimizeAnim
                        ParallelAnimation {
                            NumberAnimation { target: win; property: "dx"; to: win.minimizeDx; duration: 260; easing.type: Easing.InQuad }
                            NumberAnimation { target: win; property: "dy"; to: win.minimizeDy; duration: 260; easing.type: Easing.InQuad }
                            NumberAnimation { target: win; property: "deathScale"; to: 0.08; duration: 260; easing.type: Easing.InQuad }
                            NumberAnimation { target: win; property: "deathOpacity"; to: 0; duration: 260; easing.type: Easing.InQuad }
                        }
                        ScriptAction { script: root.dismiss(win.modelData.serial) }
                    }

                    anchors { left: true; top: true }
                    margins {
                        left: Math.round(Math.min(Math.max(0, win.baseX + win.dx + (win.dragHeld ? 0 : win.jx)), win.screen.width - 80))
                        top: Math.round(Math.min(Math.max(0, win.baseY + win.dy + (win.dragHeld ? 0 : win.jy)), win.screen.height - 60))
                    }

                    // paleta tipo GPU muriéndose: magenta, verde, morado, cyan, rosa
                    readonly property var gpuPalette: ["#ff00ff", "#00ff00", "#7b2bff", "#00ffff", "#ff0080", "#39ff14", "#000000", "#ffffff"]

                    function scramble(strength) {
                        jx = (Math.random() - 0.5) * 26 * strength;
                        jy = (Math.random() - 0.5) * 16 * strength;
                        burstOpacity = 1 - Math.random() * 0.5 * Math.min(strength, 1.2);
                        burstTint = gpuPalette[Math.floor(Math.random() * 5)];
                        let seed = [];
                        const n = 3 + Math.floor(Math.random() * (4 + 6 * strength));
                        for (let i = 0; i < n; i++) {
                            const block = Math.random() < 0.5; // bloque de corrupción vs scanline
                            seed.push({
                                x: block ? Math.random() * 0.75 : -0.1,
                                y: Math.random() * 0.92,
                                w: block ? 0.12 + Math.random() * 0.45 : 1.2,
                                h: block ? 8 + Math.random() * 34 * strength : 2 + Math.random() * 5,
                                c: gpuPalette[Math.floor(Math.random() * gpuPalette.length)],
                                o: 0.5 + Math.random() * 0.45,
                            });
                        }
                        burstSeed = seed;
                    }

                    // genera los cortes de tearing; dxAmp = desplazamiento máximo de cada franja
                    function genTear(dxAmp) {
                        if (!root.tearingOn || current)
                            return;
                        const H = content.height;
                        if (H <= 4)
                            return;
                        const cuts = 2 + Math.floor(Math.random() * (2 + 3 * glitchiness));
                        let ys = [0, H];
                        for (let i = 0; i < cuts; i++)
                            ys.push(Math.random() * H);
                        ys.sort((a, b) => a - b);
                        let seed = [];
                        for (let i = 0; i < ys.length - 1; i++) {
                            const h = ys[i + 1] - ys[i];
                            if (h < 2)
                                continue;
                            seed.push({ y0: ys[i], h: h, dx: (Math.random() - 0.5) * 2 * dxAmp });
                        }
                        tearSeed = seed;
                    }

                    readonly property real tearBase: 3 + 6 * glitchiness

                    function doBurst(strength) {
                        scramble(strength);
                        genTear(10 + 16 * strength);
                        burst = true;
                        burstEnd.interval = 60 + Math.random() * 90;
                        burstEnd.restart();
                    }

                    Timer {
                        id: burstEnd
                        onTriggered: {
                            if (win.dying)
                                return;
                            win.burst = false;
                            win.jx = 0;
                            win.jy = 0;
                            win.burstOpacity = 1;
                            win.genTear(win.tearBase);
                        }
                    }

                    // vibración de holograma: micro-jitter permanente
                    Timer {
                        interval: 90
                        repeat: true
                        running: !win.dying && win.fx && root.gStr > 0
                        onTriggered: {
                            if (win.burst)
                                return;
                            const amp = (1.8 + 1.4 * win.glitchiness) * root.gStr;
                            win.jx = (Math.random() - 0.5) * 2 * amp;
                            win.jy = (Math.random() - 0.5) * 2 * amp;
                        }
                    }

                    // flicker de holograma en la opacidad
                    Timer {
                        interval: 140
                        repeat: true
                        running: !win.dying && win.fx && root.gStr > 0
                        onTriggered: win.holoOpacity = 1 - Math.random() * (0.16 + 0.1 * win.glitchiness) * root.gStr
                    }

                    // bursts de glitch espontáneos y frecuentes
                    Timer {
                        running: !win.dying && win.fx && root.gProb > 0
                        repeat: true
                        interval: 400
                        onTriggered: {
                            interval = 160 + Math.random() * (550 - 380 * win.glitchiness);
                            if (Math.random() < (0.55 + 0.4 * win.glitchiness) * root.gProb)
                                win.doBurst((0.6 + win.glitchiness) * root.gStr);
                        }
                    }

                    // vida máxima: que no queden flotando infinito si la música se paró
                    Timer {
                        interval: Math.max(1000, root.maxLifetime * 1000)
                        running: root.maxLifetime > 0 && !win.dying
                        onTriggered: win.die()
                    }

                    // cascada: al limpiar mueren en cadena, con la coreografía sorteada
                    // en root.cascadeMode (age | top | center) para este disparo
                    Connections {
                        target: root
                        enabled: !win.dying
                        function onClearGenChanged() {
                            const rank = root.cascadeRank(win.modelData);
                            cascadeTimer.interval = 60 + Math.max(0, rank) * 110;
                            cascadeTimer.restart();
                        }
                    }
                    Timer {
                        id: cascadeTimer
                        onTriggered: {
                            if (!win.dying)
                                win.die();
                        }
                    }

                    // sacudida al pico de audio: sólo el cartel actual, un empujón corto
                    // sobre el jitter existente. Respeta glitch = "off" igual que el resto.
                    Connections {
                        target: root
                        enabled: win.current && !win.dying
                        function onAudPeakChanged() {
                            if (root.gStr <= 0)
                                return;
                            peakShake.restart();
                        }
                    }
                    SequentialAnimation {
                        id: peakShake
                        NumberAnimation { target: win; property: "jx"; to: 6 * root.flickerAmt; duration: 45; easing.type: Easing.OutQuad }
                        NumberAnimation { target: win; property: "jx"; to: 0; duration: 45; easing.type: Easing.InQuad }
                    }

                    // al dejar de ser el actual: burst que tapa el achique + tearing permanente
                    onCurrentChanged: {
                        if (!current && !dying) {
                            if (root.gStr > 0)
                                doBurst(1.2);
                            else
                                genTear(tearBase);
                        }
                    }

                    onAgeChanged: {
                        if (age >= modelData.deathAge && !dying)
                            die();
                        else if (age > 0 && !dying)
                            genTear(tearBase); // más viejo → cortes nuevos, nunca queda sana
                    }

                    function die() {
                        dying = true;
                        modelData.dying = true;   // spawnPos() no lo cuenta como ocupado
                        burst = true;
                        // la foto del burn-in se saca ACÁ, con el cartel entero
                        // todavía en pantalla: 370 ms más tarde, cuando el
                        // fantasma se prende, el colapso ya lo dejó en una raya
                        ghostShot.scheduleUpdate();
                        deathAnim.start();
                        deathEnd.start();
                    }

                    // muerte: jitter violento continuo + colapso vertical CRT
                    Timer {
                        interval: 45
                        repeat: true
                        running: win.dying && !win.ghosting
                        onTriggered: win.scramble(1.6)
                    }
                    Timer {
                        id: deathEnd
                        interval: root.burnIn ? 2900 : 380
                        onTriggered: root.dismiss(win.modelData.serial)
                    }

                    // burn-in: tras el colapso queda una sombra quemada estática que se apaga
                    Timer {
                        interval: 370
                        running: win.dying && root.burnIn
                        onTriggered: {
                            win.ghosting = true;
                            win.burst = false;
                            win.jx = 0;
                            win.jy = 0;
                            ghostFade.start();
                        }
                    }

                    property real deathScale: 1
                    property real deathOpacity: 1
                    SequentialAnimation {
                        id: deathAnim
                        PauseAnimation { duration: 140 }
                        ParallelAnimation {
                            NumberAnimation { target: win; property: "deathScale"; to: 0.04; duration: 200; easing.type: Easing.InQuad }
                            NumberAnimation { target: win; property: "deathOpacity"; to: 0; duration: 230 }
                        }
                    }

                    // contenido real del cartel; cuando está "torn" se oculta y se
                    // renderiza vía franjas ShaderEffectSource desplazadas
                    Item {
                        id: content
                        x: win.tearPad
                        y: 0
                        width: win.dlgW
                        height: frame.implicitHeight
                        visible: !win.ghosting

                        // sombra proyectada, para que el cartel no flote sobre el fondo
                        Rectangle {
                            id: shadow
                            x: 4
                            y: 4
                            width: frame.width
                            height: frame.height
                            color: "#000000"
                            opacity: 0.25 * win.deathOpacity
                            transform: Scale {
                                origin.y: shadow.height / 2
                                yScale: win.deathScale
                            }
                        }

                        // marco con bevel clásico
                        Rectangle {
                            id: frame
                            anchors.fill: parent
                            implicitHeight: column.implicitHeight + 4
                            color: "#c0c0c0"
                            clip: true
                            opacity: win.burstOpacity * win.deathOpacity * win.holoOpacity
                            transform: [
                                Scale {
                                    origin.y: frame.height / 2
                                    yScale: win.deathScale
                                },
                                // micro-rotación por edad: cero con glitch = "off"
                                Rotation {
                                    origin.x: frame.width / 2
                                    origin.y: frame.height / 2
                                    angle: root.gStr > 0 ? win.glitchiness * 0.6 * win.rotSign : 0
                                }
                            ]

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 2; color: "#ffffff" }
                            Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 2; color: "#ffffff" }
                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 2; color: "#404040" }
                            Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 2; color: "#404040" }

                            Column {
                                id: column
                                anchors { fill: parent; margins: 2 }

                                // barra de título (arrastrable)
                                Rectangle {
                                    id: titlebar
                                    width: parent.width
                                    height: Math.round(26 * win.k)
                                    clip: true
                                    // el colgado no tiene el azul del cartel activo:
                                    // Windows le pintaba la barra gris a la ventana
                                    // que no respondía
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: win.hung ? "#5a5a5a" : "#000080" }
                                        GradientStop { position: 1.0; color: win.hung ? "#9a9a9a" : "#1084d0" }
                                    }

                                    // barrido blanco al nacer, como un reflejo cruzando el vidrio
                                    Rectangle {
                                        width: Math.round(40 * win.k)
                                        height: titlebar.height
                                        color: "#ffffff"
                                        opacity: 0.5
                                        NumberAnimation on x {
                                            from: -Math.round(40 * win.k)
                                            to: titlebar.width
                                            duration: 220
                                            running: true
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        property real px: 0
                                        property real py: 0
                                        onPressed: m => {
                                            if (m.button === Qt.LeftButton) { px = m.x; py = m.y; win.dragHeld = true; }
                                        }
                                        onReleased: win.dragHeld = false
                                        onCanceled: win.dragHeld = false
                                        onPositionChanged: m => {
                                            if (pressed && win.dragHeld)
                                                win.dragBy(m.x - px, m.y - py);
                                        }
                                        onClicked: m => {
                                            if (m.button === Qt.RightButton)
                                                win.minimize();
                                        }
                                    }

                                    Text {
                                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter; right: closeBtn.left; rightMargin: 6 }
                                        text: win.modelData.title
                                        color: "#ffffff"
                                        font.pixelSize: Math.round(12 * win.k)
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        id: closeBtn
                                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                        width: Math.round(18 * win.k)
                                        height: Math.round(16 * win.k)
                                        color: closeMa.pressed ? "#a8a8a8" : "#c0c0c0"

                                        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 1; color: "#ffffff" }
                                        Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 1; color: "#ffffff" }
                                        Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 1; color: "#404040" }
                                        Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 1; color: "#404040" }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            color: "#000000"
                                            font.pixelSize: Math.round(10 * win.k)
                                            font.bold: true
                                        }
                                        MouseArea {
                                            id: closeMa
                                            anchors.fill: parent
                                            onClicked: root.dismiss(win.modelData.serial)
                                        }
                                    }
                                }

                                // cuerpo: ícono + texto
                                Row {
                                    width: parent.width
                                    padding: Math.round(14 * win.k)
                                    spacing: Math.round(14 * win.k)

                                    // ícono estilo Windows (error/advertencia/pregunta/info)
                                    Canvas {
                                        width: Math.round(32 * win.k)
                                        height: Math.round(32 * win.k)
                                        onWidthChanged: requestPaint()
                                        onPaint: {
                                            const c = getContext("2d");
                                            c.reset();
                                            c.scale(width / 32, height / 32);
                                            const icon = win.modelData.icon;
                                            if (icon === "warning") {
                                                c.beginPath();
                                                c.moveTo(16, 2);
                                                c.lineTo(30, 29);
                                                c.lineTo(2, 29);
                                                c.closePath();
                                                c.fillStyle = "#ffd800";
                                                c.fill();
                                                c.lineWidth = 1.5;
                                                c.strokeStyle = "#000000";
                                                c.stroke();
                                                c.fillStyle = "#000000";
                                                c.fillRect(14.6, 11, 2.8, 10);
                                                c.fillRect(14.6, 23.5, 2.8, 2.8);
                                            } else if (icon === "error") {
                                                c.beginPath();
                                                c.arc(16, 16, 14, 0, Math.PI * 2);
                                                c.fillStyle = "#d32f2f";
                                                c.fill();
                                                c.strokeStyle = "#7a0000";
                                                c.lineWidth = 1;
                                                c.stroke();
                                                c.strokeStyle = "#ffffff";
                                                c.lineWidth = 3.2;
                                                c.lineCap = "round";
                                                c.beginPath();
                                                c.moveTo(10.5, 10.5); c.lineTo(21.5, 21.5);
                                                c.moveTo(21.5, 10.5); c.lineTo(10.5, 21.5);
                                                c.stroke();
                                            } else if (icon === "question") {
                                                c.beginPath();
                                                c.arc(16, 16, 14, 0, Math.PI * 2);
                                                c.fillStyle = "#2458c8";
                                                c.fill();
                                                c.strokeStyle = "#0a1f66";
                                                c.lineWidth = 1;
                                                c.stroke();
                                                c.fillStyle = "#ffffff";
                                                c.textAlign = "center";
                                                c.textBaseline = "middle";
                                                c.font = "bold 20px sans-serif";
                                                c.fillText("?", 16, 17);
                                            } else {
                                                // info: círculo azul, "i" dibujada (punto + palo, bien centrada)
                                                c.beginPath();
                                                c.arc(16, 16, 14, 0, Math.PI * 2);
                                                c.fillStyle = "#2458c8";
                                                c.fill();
                                                c.strokeStyle = "#0a1f66";
                                                c.lineWidth = 1;
                                                c.stroke();
                                                c.fillStyle = "#ffffff";
                                                c.beginPath();
                                                c.arc(16, 10.2, 2.3, 0, Math.PI * 2);
                                                c.fill();
                                                c.fillRect(14.6, 14.2, 2.8, 9.4);
                                            }
                                        }
                                    }

                                    Text {
                                        width: parent.width - (win.iconW + 14 + 28) * win.k
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: win.karaokeActive ? win.karaokeText : win.modelData.text
                                        textFormat: win.karaokeActive ? Text.StyledText : Text.PlainText
                                        color: "#000000"
                                        font.pixelSize: Math.round(13 * win.k)
                                        wrapMode: Text.Wrap
                                    }
                                }

                                // botones: Yes/Cancel cierran, "No" duplica (si troll_no)
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: Math.round(8 * win.k)
                                    bottomPadding: Math.round(12 * win.k)

                                    Repeater {
                                        model: win.hung ? ["Esperar", "Finalizar ahora"]
                                                        : ["Yes", "No", "Cancel"]

                                        Rectangle {
                                            required property string modelData
                                            required property int index
                                            // "Finalizar ahora" no entra en los 76 px
                                            // de siempre: el botón se mide con su texto
                                            width: Math.max(Math.round(76 * win.k),
                                                            btnText.implicitWidth + Math.round(20 * win.k))
                                            height: Math.round(24 * win.k)
                                            color: btnMa.pressed ? "#a8a8a8" : "#c0c0c0"
                                            border.width: index === 0 ? 1 : 0
                                            border.color: "#000000"

                                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right; margins: index === 0 ? 1 : 0 } height: 1; color: "#ffffff" }
                                            Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom; margins: index === 0 ? 1 : 0 } width: 1; color: "#ffffff" }
                                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: index === 0 ? 1 : 0 } height: 1; color: "#404040" }
                                            Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom; margins: index === 0 ? 1 : 0 } width: 1; color: "#404040" }

                                            Text {
                                                id: btnText
                                                anchors.centerIn: parent
                                                text: parent.modelData
                                                color: "#000000"
                                                font.pixelSize: Math.round(12 * win.k)
                                            }

                                            // rectángulo punteado de foco en el botón default
                                            Rectangle {
                                                visible: parent.index === 0
                                                anchors { fill: parent; margins: 4 }
                                                color: "transparent"
                                                border.width: 1
                                                border.color: "#000000"
                                                opacity: 0.55
                                            }

                                            MouseArea {
                                                id: btnMa
                                                anchors.fill: parent
                                                onClicked: {
                                                    // en el colgado los dos botones cierran:
                                                    // "Esperar" tampoco sirve de nada, que es
                                                    // exactamente el chiste
                                                    if (!win.hung && parent.modelData === "No" && root.trollNo)
                                                        root.duplicate(win.modelData);
                                                    else
                                                        root.dismiss(win.modelData.serial);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // fringe cromático (aberración RGB de holograma), solo viejos
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: 2
                                color: "#ff00ff"
                                opacity: win.current ? 0 : 0.40
                            }
                            Rectangle {
                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                width: 2
                                color: "#00ffff"
                                opacity: win.current ? 0 : 0.40
                            }

                            // banda de escaneo que recorre el cartel (holograma), solo viejos
                            Rectangle {
                                x: 0
                                visible: !win.current && root.gStr > 0
                                width: frame.width
                                height: Math.round(10 * win.k)
                                color: "#ffffff"
                                opacity: 0.11
                                NumberAnimation on y {
                                    from: -12
                                    to: 400
                                    duration: 1800 + (win.modelData.serial % 5) * 300
                                    loops: Animation.Infinite
                                }
                            }

                            // tinte de corrupción durante el burst
                            Rectangle {
                                anchors.fill: parent
                                visible: win.burst
                                color: win.burstTint
                                opacity: win.dying ? 0.35 : 0.18
                            }

                            // bloques y scanlines de corrupción tipo artefactos de GPU
                            Repeater {
                                model: win.burst ? win.burstSeed : []
                                Rectangle {
                                    required property var modelData
                                    x: modelData.x * frame.width
                                    y: modelData.y * frame.height
                                    width: modelData.w * frame.width
                                    height: modelData.h
                                    color: modelData.c
                                    opacity: modelData.o
                                }
                            }

                            // flash blanco al nacer, como si el monitor se acabara de encender
                            Rectangle {
                                anchors.fill: parent
                                color: "#ffffff"
                                opacity: win.spawnFlash
                            }
                        }
                    }

                    // franjas de tearing: la ventana partida de verdad
                    Repeater {
                        model: win.torn ? win.tearSeed : []
                        ShaderEffectSource {
                            required property var modelData
                            sourceItem: content
                            hideSource: true
                            live: true
                            sourceRect: Qt.rect(0, modelData.y0, content.width, modelData.h)
                            x: win.tearPad + modelData.dx
                            y: modelData.y0
                            width: content.width
                            height: modelData.h
                        }
                    }

                    // ---- el reflejo (T4.4)
                    // Ocho tajadas en vez de una sola imagen con degradado: el
                    // degradado necesitaría OpacityMask (Qt5Compat.GraphicalEffects),
                    // que este shell no importa en ningún lado. Cada tajada copia
                    // su franja del cartel y baja de opacidad — el corte no se ve
                    // porque el salto entre una y la siguiente es de 3 puntos.
                    Item {
                        id: mirror
                        x: win.tearPad
                        y: content.height
                        width: win.dlgW
                        height: win.mirrorH
                        visible: win.mirrored
                        opacity: win.deathOpacity

                        Repeater {
                            model: win.mirrored ? 8 : 0

                            ShaderEffectSource {
                                required property int index
                                readonly property real bandH: mirror.height / 8
                                // la franja de ABAJO del cartel es la de ARRIBA
                                // del reflejo: el espejo da vuelta el orden
                                sourceItem: content
                                hideSource: false
                                live: true
                                sourceRect: Qt.rect(0, content.height - (index + 1) * bandH,
                                                    content.width, bandH)
                                x: 0
                                y: index * bandH
                                width: mirror.width
                                height: bandH
                                opacity: 0.25 * (1 - index / 8)
                                transform: Scale {
                                    origin.y: bandH / 2
                                    yScale: -1
                                }
                            }
                        }
                    }

                    // burn-in: silueta quemada del cartel, estática, que se desvanece
                    Item {
                        id: ghost
                        x: win.tearPad
                        width: win.dlgW
                        height: content.height
                        // Se suma a la escena en cuanto el cartel empieza a
                        // morir, con opacidad 0: un ShaderEffectSource adentro
                        // de un item invisible no dibuja, y entonces la captura
                        // de die() saldría vacía.
                        visible: win.dying || win.ghosting
                        opacity: 0

                        // el fósforo tiñe lo quemado; va DEBAJO de la foto para
                        // que el color se lea a través de ella
                        Rectangle { anchors.fill: parent; color: "#e8d5ff"; opacity: 0.06 }

                        // Lo quemado es el cartel, no un rectángulo del tamaño
                        // del cartel: el título, el ícono y los botones quedan
                        // marcados donde estaban. Es la foto que sacó die(),
                        // congelada (`live: false`) — el contenido de abajo ya
                        // no existe cuando esto se prende.
                        ShaderEffectSource {
                            id: ghostShot
                            anchors.fill: parent
                            sourceItem: content
                            live: false
                            opacity: 0.35
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: 1
                            border.color: "#d9c9ff"
                            opacity: 0.35
                        }
                        // resto de la línea del colapso CRT
                        Rectangle {
                            y: parent.height / 2 - 1
                            width: parent.width
                            height: 2
                            color: "#ffffff"
                            opacity: 0.5
                        }
                    }
                    NumberAnimation {
                        id: ghostFade
                        target: ghost
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: 2400
                        easing.type: Easing.OutQuad
                    }

                    // input de carteles viejos (torn): click = cerrar, título = arrastrar
                    MouseArea {
                        anchors.fill: parent
                        enabled: win.torn && !win.ghosting
                        property real px: 0
                        property real py: 0
                        property bool dragging: false
                        onPressed: m => {
                            dragging = m.y < Math.round(26 * win.k) + 6;
                            px = m.x;
                            py = m.y;
                            if (dragging)
                                win.dragHeld = true;
                        }
                        onReleased: win.dragHeld = false
                        onCanceled: win.dragHeld = false
                        onPositionChanged: m => {
                            if (dragging && pressed)
                                win.dragBy(m.x - px, m.y - py);
                        }
                        onClicked: {
                            if (!dragging)
                                root.dismiss(win.modelData.serial);
                        }
                    }
                }
            }

            // Now Playing: funda de vinilo — aparece grande en el centro al cambiar de
            // canción y a los segundos se estaciona chiquita en una esquina, con barra
            // de progreso Win95. Ventana propia full-screen con máscara solo en la funda.
            PanelWindow {
                id: npWin
                visible: root.npShown && !root.crtOn
                screen: perScreen.scr
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "cartelitos-np"
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                anchors { left: true; right: true; top: true; bottom: true }

                Region { id: npCardMask; item: npCard }
                Region { id: npEmptyMask }
                mask: root.clickThrough ? npEmptyMask : npCardMask

                readonly property real bigW: Math.round(300 * root.cfgScale * root.cfgCurrentScale)
                readonly property real smallW: Math.round(170 * root.cfgScale)

                // un solo parámetro anima posición y tamaño juntos → trayectoria recta
                property real dockT: root.npDocked ? 1 : 0
                Behavior on dockT { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }

                // disco de vinilo que asoma girando por el costado de la funda
                // (np_vinyl); declarado antes de npCard para quedar DETRÁS
                Item {
                    id: npDisc
                    // asoma hacia el centro de la pantalla: esquinas derechas → izquierda
                    readonly property real dir: root.npCorner.indexOf("right") >= 0 ? -1 : 1
                    property real out: 0
                    Behavior on out { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

                    visible: root.npVinyl && out > 0.01
                    width: (npCard.width - npCard.pad * 2) * 0.96
                    height: width
                    x: npCard.x + (npCard.width - width) / 2 + dir * out * width * 0.42
                    y: npCard.y + npCard.pad + (npCard.width - npCard.pad * 2 - height) / 2

                    // al cambiar de tema el disco arranca guardado y sale a los ~900 ms
                    Connections {
                        target: root
                        function onNpSerialChanged() {
                            npDisc.out = 0;
                            discDelay.restart();
                        }
                    }
                    Timer {
                        id: discDelay
                        interval: 900
                        onTriggered: npDisc.out = 1
                    }

                    Item {
                        anchors.fill: parent
                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1800 // ~33 rpm
                            loops: Animation.Infinite
                            running: npDisc.visible && root.npShown
                        }

                        // vinilo: disco negro con surcos y un brillo que gira con él
                        Canvas {
                            anchors.fill: parent
                            onWidthChanged: requestPaint()
                            onPaint: {
                                const c = getContext("2d");
                                c.reset();
                                c.scale(width / 200, height / 200);
                                c.beginPath();
                                c.arc(100, 100, 99, 0, Math.PI * 2);
                                c.fillStyle = "#101010";
                                c.fill();
                                c.strokeStyle = "rgba(255,255,255,0.05)";
                                c.lineWidth = 1;
                                for (let r = 44; r < 96; r += 4.5) {
                                    c.beginPath();
                                    c.arc(100, 100, r, 0, Math.PI * 2);
                                    c.stroke();
                                }
                                // brillo asimétrico: hace visible la rotación
                                c.strokeStyle = "rgba(255,255,255,0.09)";
                                c.lineWidth = 26;
                                c.beginPath();
                                c.arc(100, 100, 68, -0.5, 0.55);
                                c.stroke();
                                c.beginPath();
                                c.arc(100, 100, 68, Math.PI - 0.5, Math.PI + 0.55);
                                c.stroke();
                                c.strokeStyle = "rgba(255,255,255,0.14)";
                                c.lineWidth = 1.5;
                                c.beginPath();
                                c.arc(100, 100, 98, 0, Math.PI * 2);
                                c.stroke();
                            }
                        }

                        // etiqueta central con la portada, recortada en círculo
                        ClippingRectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.37
                            height: width
                            radius: width / 2
                            color: "#2a2a2a"

                            Image {
                                anchors.fill: parent
                                visible: root.npArt !== ""
                                source: root.npArt
                                fillMode: Image.PreserveAspectCrop
                            }
                        }

                        // agujero del eje
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.045
                            height: width
                            radius: width / 2
                            color: "#000000"
                        }
                    }
                }

                Rectangle {
                    id: npCard
                    readonly property real f: width / 300
                    readonly property int pad: Math.round(8 * f)
                    readonly property int barH: Math.round(16 * f)

                    // extremos del recorrido calculados con el tamaño de cada punta;
                    // x/y/width interpolan con el mismo t → va directo, sin curva
                    function hFor(w) {
                        const g = w / 300;
                        return w + Math.round(4 * g) + Math.round(16 * g) + Math.round(8 * g);
                    }
                    readonly property real cx0: (npWin.width - npWin.bigW) / 2
                    readonly property real cy0: (npWin.height - hFor(npWin.bigW)) / 2
                    // "center": se achica en el lugar, sin viajar a ninguna esquina
                    readonly property real cx1: root.npCorner === "center" ? (npWin.width - npWin.smallW) / 2
                        : root.npCorner.indexOf("left") >= 0 ? root.npMargin
                        : npWin.width - npWin.smallW - root.npMargin
                    readonly property real cy1: root.npCorner === "center" ? (npWin.height - hFor(npWin.smallW)) / 2
                        : root.npCorner.indexOf("top") === 0 ? root.npMargin
                        : npWin.height - hFor(npWin.smallW) - root.npMargin

                    // offset de arrastre manual; se resetea al cambiar de tema
                    property real ox: 0
                    property real oy: 0

                    width: npWin.bigW + (npWin.smallW - npWin.bigW) * npWin.dockT
                    height: width + Math.round(4 * f) + barH + pad
                    x: cx0 + (cx1 - cx0) * npWin.dockT + ox
                    y: cy0 + (cy1 - cy0) * npWin.dockT + oy
                    color: "#c0c0c0"

                    Connections {
                        target: root
                        function onNpSerialChanged() {
                            npCard.ox = 0;
                            npCard.oy = 0;
                        }
                    }

                    // bevel exterior clásico
                    Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 2; color: "#ffffff" }
                    Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 2; color: "#ffffff" }
                    Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 2; color: "#404040" }
                    Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 2; color: "#404040" }

                    // portada con bevel hundido
                    Item {
                        id: npArtBox
                        x: npCard.pad
                        y: npCard.pad
                        width: npCard.width - npCard.pad * 2
                        height: width

                        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 2; color: "#404040" }
                        Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 2; color: "#404040" }
                        Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 2; color: "#ffffff" }
                        Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 2; color: "#ffffff" }

                        Rectangle {
                            anchors { fill: parent; margins: 2 }
                            color: "#3a3a3a"
                            clip: true

                            Image {
                                anchors.fill: parent
                                visible: root.npArt !== ""
                                source: root.npArt
                                fillMode: Image.PreserveAspectCrop
                            }

                            // sin portada: nota sobre gris oscuro
                            Text {
                                visible: root.npArt === ""
                                anchors.centerIn: parent
                                text: "♪"
                                color: "#c0c0c0"
                                font.pixelSize: Math.round(96 * npCard.f)
                            }

                            // banda inferior: tema — artista
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: npText.implicitHeight + Math.round(14 * npCard.f)
                                color: "#000000"
                                opacity: 0.62
                            }
                            Column {
                                id: npText
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                    leftMargin: Math.round(10 * npCard.f)
                                    rightMargin: Math.round(10 * npCard.f)
                                    bottomMargin: Math.round(8 * npCard.f)
                                }
                                spacing: Math.round(2 * npCard.f)

                                Text {
                                    width: parent.width
                                    text: root.npTitle
                                    color: "#ffffff"
                                    font.pixelSize: Math.max(9, Math.round(15 * npCard.f))
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: root.npInfo
                                    color: "#d8d8d8"
                                    font.pixelSize: Math.max(8, Math.round(12 * npCard.f))
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // barra de progreso Win95: bloques azules en canaleta hundida
                    Rectangle {
                        id: npBar
                        x: npCard.pad
                        y: npArtBox.y + npArtBox.height + Math.round(4 * npCard.f)
                        width: npArtBox.width
                        height: npCard.barH
                        color: "#c0c0c0"

                        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 1; color: "#404040" }
                        Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 1; color: "#404040" }
                        Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 1; color: "#ffffff" }
                        Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 1; color: "#ffffff" }

                        Row {
                            id: npBlocks
                            x: 3
                            y: 3
                            spacing: 2
                            readonly property int blockW: Math.max(4, Math.round(9 * npCard.f))
                            readonly property int total: Math.max(1, Math.floor((npBar.width - 4) / (blockW + 2)))

                            Repeater {
                                model: Math.round(root.npProgress * npBlocks.total)
                                Rectangle {
                                    width: npBlocks.blockW
                                    height: npBar.height - 6
                                    color: "#000080"
                                }
                            }
                        }
                    }

                    // arrastrar = moverla donde quieras; click seco = esconder hasta
                    // la próxima canción (umbral de 5 px para distinguirlos)
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: pressed && moved ? Qt.ClosedHandCursor : Qt.ArrowCursor
                        property real px: 0
                        property real py: 0
                        property bool moved: false
                        onPressed: m => {
                            px = m.x;
                            py = m.y;
                            moved = false;
                        }
                        onPositionChanged: m => {
                            if (!pressed)
                                return;
                            const ddx = m.x - px;
                            const ddy = m.y - py;
                            if (!moved && Math.abs(ddx) + Math.abs(ddy) < 5)
                                return;
                            moved = true;
                            const bx = npCard.cx0 + (npCard.cx1 - npCard.cx0) * npWin.dockT;
                            const by = npCard.cy0 + (npCard.cy1 - npCard.cy0) * npWin.dockT;
                            npCard.ox = Math.max(-bx, Math.min(npCard.ox + ddx, npWin.width - npCard.width - bx));
                            npCard.oy = Math.max(-by, Math.min(npCard.oy + ddy, npWin.height - npCard.height - by));
                        }
                        onClicked: {
                            if (!moved)
                                root.npShown = false;
                        }
                    }
                }
            }
        }
    }
}
