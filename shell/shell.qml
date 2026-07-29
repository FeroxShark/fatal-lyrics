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
    property bool burnIn: true
    property bool cascadeDeath: true
    property bool karaokeOn: false
    property string npCorner: "top-right"
    property int npMargin: 14
    property bool npVinyl: true

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
    property bool crtMotifs: true
    property real crtCamera: 1.0
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

    // ---- lo que está sonando de verdad (eventos "aud" del daemon)
    property real audLevel: 0
    property real audLo: 0
    property real audMid: 0
    property real audHi: 0
    property real audCentroid: 0.5
    property int audBeat: 0
    property double audAt: 0
    // en qué parte de la canción estamos (lo decide el daemon comparando este
    // momento contra el tema entero, no contra un volumen fijo)
    property string audSection: "verse"
    property real audPct: 0.5
    property string audComing: ""      // lo que se viene, si el tema ya se escuchó
    property double audComingAt: 0
    property int sectionGen: 0
    // si la captura se cae o está apagada, todo vuelve a moverse con la letra
    readonly property bool audLive: crtOn && (Date.now() - audAt) < 1500

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
    property var crtLine: ({ text: "", t0: 0, t1: 0, serial: 0, segs: [] })
    property int crtSerial: 0
    property int crtTrackSeed: 0

    // Ruido determinístico: todas las pantallas tienen que elegir el MISMO
    // layout para la misma línea, y sin hablar entre ellas.
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
        const alarm = crtHash(n * 13 + 5) > 0.87;
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
        const a = Math.round(s.length * i / n);
        const b = Math.round(s.length * (i + 1) / n);
        return s.substring(a, b).trim();
    }

    // Avance de la línea actual (0..1) para el pintado palabra por palabra;
    // mismo cálculo que el karaoke de los carteles.
    function karaokeFraction(t0, t1) {
        const dur = t1 - t0;
        if (dur <= 0)
            return 1;
        // termina de pintar ~1 s antes de la próxima línea
        const lead = Math.min(1.0, dur * 0.35);
        return Math.max(0, Math.min((songPos() - t0) / Math.max(dur - lead, 0.5), 1));
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
    readonly property real infectLead: 0.35     // segundos de anticipación

    function resetFaces() {
        faceIdx = crtFacePattern();
    }
    onSectionGenChanged: resetFaces()
    onCrtTrackSeedChanged: resetFaces()
    onActiveCrtScreensChanged: resetFaces()

    function updateInfection() {
        const sh = crtShot;
        if (!crtOn || sh.mode === "all" || sh.chunks.length < 2)
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
            if (p < c.from - infectLead)
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
    function updatePitchPalette() {
        if (!crtColorFromPitch || !audLive)
            return;
        const now = Date.now();
        const cand = palForPitch(pitchRel);
        if (pitchPal < 0) {
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
        const focus = n > 0 ? (serial + Math.floor(crtHash(serial * 17 + 3) * n)) % n : 0;
        if (!crtDirector || crtFocusMode === "all" || n <= 1 || words.length === 0)
            return { mode: "all", focus: focus, chunks: [] };

        const t0 = line.t0 || 0;
        // Termina antes que la línea (el último pedazo tiene que llegar a leerse)
        // Y ADEMÁS se acota al tiempo de lectura: lrclib da como final de la línea
        // el comienzo de la siguiente, así que entre estrofas eso puede ser medio
        // minuto — sin el tope, un pedazo se quedaba solo en pantalla eternidades.
        const words_n = words.length;
        const span = Math.max((line.t1 || 0) - t0, 0.8) * 0.92;
        const dur = Math.min(span, 1.2 + words_n * 0.55);
        const h = crtHash(serial * 31 + words.length);
        const dir = crtHash(serial * 11 + 7) < 0.5 ? 1 : -1;

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
            return { mode: "relay", focus: focus, chunks: chunks };
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
            return { mode: "jump", focus: focus, chunks: chunks };
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
            return { mode: "relay", focus: focus, chunks: chunks };
        }

        return { mode: "single", focus: focus,
                 chunks: [{ text: text, screen: focus, from: t0, to: t0 + dur }] };
    }
    readonly property var crtShot: crtShotFor(crtLine)

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

    // Cómo entra la palabra en esta línea. Que sea siempre igual cansa: a veces
    // aparece seca, a veces entra de golpe grande, a veces baja rodando como un
    // tubo que recién agarra la sincronía.
    function crtEntryStyle() {
        const r = crtHash((crtLine.serial || 0) * 23 + 11);
        if (r < 0.18)
            return "slam";
        if (r < 0.34)
            return "roll";
        return "snap";
    }

    // Animación de la pantalla sin letra. Alguna palabra la elige a propósito
    // (el ojo cuando la letra habla de mirar o de silencio), el resto es sorteo.
    readonly property var motifWords: [
        { re: /\b(eye|eyes|see|seen|look|watch|silence|silent|quiet|blind)\b/i, kind: "eye" },
        { re: /\b(ojo|ojos|mir[ao]|mirar|ver|silencio|callar|ciego)\b/i, kind: "eye" },
        { re: /\b(fire|burn|heart|beat|blood|fuego|arde|coraz[oó]n|late)\b/i, kind: "rings" },
        { re: /\b(run|road|drive|fall|deep|corr[eo]|camino|caigo|fondo)\b/i, kind: "tunnel" },
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

    readonly property var motifKinds: ["eye", "scope", "radar", "stars", "testcard", "rain"]

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
                if (motifWords[k].re.test(text))
                    return motifWords[k].kind;
        }
        // dos pantallas apagadas nunca muestran el mismo dibujo
        // en el silencio el ojo o la carta de ajuste; en el pico, lo que se mueve
        const calm = audSection === "quiet";
        const pool = calm ? ["eye", "testcard", "scope"] : motifKinds;
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
    function tubeBeat() {
        if (!crtOn || crtFlicker <= 0.01)
            return;
        const now = Date.now();
        if (now - lastFlickerAt < 1400 / Math.max(crtFlicker, 0.05))
            return;
        lastFlickerAt = now;
        flickerHard = sectionEnergy > 1.45 && Math.random() < 0.35 && crtFlicker > 0.5;
        flickerGen++;
    }
    onAudBeatChanged: tubeBeat()

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
    }

    // el watcher no alcanza si el archivo todavía no existe cuando arranca el
    // overlay (pasa siempre: el daemon lo escribe un segundo después), así que
    // además se relee solo. Es un byte: sale más barato que perdérselo.
    Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: crtSwitch.reload()
    }

    // pantallas donde corre el overlay según la config
    function matchScreens(v) {
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

    function spawnPos() {
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
        // max_dialogs = 0: sin límite (igual los carteles mueren por edad/TTL)
        while (root.maxDialogs > 0 && arr.length > root.maxDialogs)
            arr.shift();
        root.dialogList = arr;
    }

    function show(text, title, icon, t0, t1, segs) {
        // el tubo dibuja la línea entera; los carteles son el otro modo
        // el serial viaja adentro del objeto: una sola señal de cambio lleva
        // texto y sorteo juntos, y el layout no parpadea al aparecer la línea
        crtLine = { text: text, t0: t0 ?? 0, t1: t1 ?? 0, serial: crtSerial + 1,
                    segs: segs || [] };
        crtSerial++;
        updatePitchPalette();
        if (crtOn)
            return;
        pushDialog({
            text: text, title: title || "Spotify", icon: icon || randomIcon(),
            t0: t0 ?? 0, t1: t1 ?? 0,
        }, true);
    }

    function nowPlaying(title, artist, album, art) {
        npTitle = title || "Now Playing";
        npInfo = artist + (album ? " — " + album : "");
        npArt = art || "";
        npProgress = 0;
        npShown = true;
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

    function applyConfig(ev) {
        targetScreen = ev.screen ?? targetScreen;
        maxDialogs = ev.max_dialogs ?? maxDialogs;
        cfgScale = ev.scale ?? cfgScale;
        cfgCurrentScale = ev.current_scale ?? cfgCurrentScale;
        spawnArea = ev.spawn_area ?? spawnArea;
        glitchLevel = ev.glitch ?? glitchLevel;
        effectsOnCurrent = ev.effects_on_current ?? effectsOnCurrent;
        tearingOn = ev.tearing ?? tearingOn;
        deathAgeMin = ev.death_age_min ?? deathAgeMin;
        deathAgeMax = ev.death_age_max ?? deathAgeMax;
        maxLifetime = ev.max_lifetime ?? maxLifetime;
        clickThrough = ev.click_through ?? clickThrough;
        trollNo = ev.troll_no ?? trollNo;
        burnIn = ev.burn_in ?? burnIn;
        cascadeDeath = ev.cascade ?? cascadeDeath;
        karaokeOn = ev.karaoke ?? karaokeOn;
        npCorner = ev.np_corner ?? npCorner;
        npMargin = ev.np_margin ?? npMargin;
        npVinyl = ev.np_vinyl ?? npVinyl;
        crtScreens = ev.crt_screens ?? crtScreens;
        crtOrder = ev.crt_order ?? crtOrder;
        crtExitOn = ev.crt_exit_on ?? crtExitOn;
        crtPalette = ev.crt_palette ?? crtPalette;
        crtSplit = ev.crt_split ?? crtSplit;
        crtFont = ev.crt_font ?? crtFont;
        crtCurvature = ev.crt_curvature ?? crtCurvature;
        crtScanlines = ev.crt_scanlines ?? crtScanlines;
        crtChroma = ev.crt_chroma ?? crtChroma;
        crtBloom = ev.crt_bloom ?? crtBloom;
        crtNoise = ev.crt_noise ?? crtNoise;
        crtRoll = ev.crt_roll ?? crtRoll;
        crtVignette = ev.crt_vignette ?? crtVignette;
        crtIntensity = ev.crt_intensity ?? crtIntensity;
        crtChrome = ev.crt_chrome ?? crtChrome;
        crtDirector = ev.crt_director ?? crtDirector;
        crtFocusMode = ev.crt_focus ?? crtFocusMode;
        crtColorFromPitch = ev.crt_color_from_pitch ?? crtColorFromPitch;
        crtColorHold = ev.crt_color_hold ?? crtColorHold;
        crtMotifs = ev.crt_motifs ?? crtMotifs;
        crtCamera = ev.crt_camera ?? crtCamera;
        crtQuality = ev.crt_quality ?? crtQuality;
        crtFlicker = ev.crt_flicker ?? crtFlicker;
        crtWordFlash = ev.crt_word_flash ?? crtWordFlash;
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
                            root.show(ev.text, ev.title, ev.icon, ev.t0, ev.t1, ev.segs);
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
                            root.motifGen++;
                        } else if (ev.cmd === "cue") {
                            root.audComing = ev.kind;
                            root.audComingAt = Date.now();
                        } else if (ev.cmd === "art") {
                            root.artColors = ev.colors || [];
                        } else if (ev.cmd === "aud") {
                            root.audLevel = ev.l;
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
                        } else if (ev.cmd === "clear") {
                            root.npShown = false;
                            // el tubo se queda sin señal y rota el fósforo
                            root.crtLine = { text: "", t0: 0, t1: 0, serial: root.crtSerial, segs: [] };
                            root.crtTrackSeed++;
                            // cascada: en vez de esfumarse, mueren en cadena (dominó CRT)
                            if (root.cascadeDeath && root.dialogList.length > 0)
                                root.clearGen++;
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
                    property bool dying: false
                    property bool ghosting: false

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
                        // mismo avance que usa el tubo del modo CRT: una sola cuenta
                        // (termina de pintar ~1 s antes del próximo cartel; si no, la
                        // última palabra nunca llega a verse pintada)
                        const f = root.karaokeFraction(modelData.t0, modelData.t1);
                        let total = 0;
                        const weights = words.map(w => { const n = w.length + 1; total += n; return n; });
                        let acc = 0, cut = 0;
                        for (let i = 0; i < words.length; i++) {
                            acc += weights[i];
                            if (acc <= f * total + 0.001)
                                cut = i + 1;
                        }
                        let out = "";
                        if (cut > 0)
                            out = '<font color="#000080">' + htmlEsc(words.slice(0, cut).join(" ")) + "</font>";
                        if (cut > 0 && cut < words.length)
                            out += " ";
                        if (cut < words.length)
                            out += htmlEsc(words.slice(cut).join(" "));
                        karaokeText = out;
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

                    implicitWidth: dlgW + tearPad * 2
                    implicitHeight: content.height

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

                    // cascada: al limpiar mueren en cadena, del más viejo al más nuevo
                    Connections {
                        target: root
                        enabled: !win.dying
                        function onClearGenChanged() {
                            const rank = root.dialogList.findIndex(d => d.serial === win.modelData.serial);
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
                        burst = true;
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

                        // marco con bevel clásico
                        Rectangle {
                            id: frame
                            anchors.fill: parent
                            implicitHeight: column.implicitHeight + 4
                            color: "#c0c0c0"
                            clip: true
                            opacity: win.burstOpacity * win.deathOpacity * win.holoOpacity
                            transform: Scale {
                                origin.y: frame.height / 2
                                yScale: win.deathScale
                            }

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 2; color: "#ffffff" }
                            Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 2; color: "#ffffff" }
                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 2; color: "#404040" }
                            Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 2; color: "#404040" }

                            Column {
                                id: column
                                anchors { fill: parent; margins: 2 }

                                // barra de título (arrastrable)
                                Rectangle {
                                    width: parent.width
                                    height: Math.round(26 * win.k)
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#000080" }
                                        GradientStop { position: 1.0; color: "#1084d0" }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        property real px: 0
                                        property real py: 0
                                        onPressed: m => { px = m.x; py = m.y; win.dragHeld = true; }
                                        onReleased: win.dragHeld = false
                                        onCanceled: win.dragHeld = false
                                        onPositionChanged: m => {
                                            if (pressed)
                                                win.dragBy(m.x - px, m.y - py);
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
                                        model: ["Yes", "No", "Cancel"]

                                        Rectangle {
                                            required property string modelData
                                            required property int index
                                            width: Math.round(76 * win.k)
                                            height: Math.round(24 * win.k)
                                            color: btnMa.pressed ? "#a8a8a8" : "#c0c0c0"
                                            border.width: index === 0 ? 1 : 0
                                            border.color: "#000000"

                                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right; margins: index === 0 ? 1 : 0 } height: 1; color: "#ffffff" }
                                            Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom; margins: index === 0 ? 1 : 0 } width: 1; color: "#ffffff" }
                                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: index === 0 ? 1 : 0 } height: 1; color: "#404040" }
                                            Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom; margins: index === 0 ? 1 : 0 } width: 1; color: "#404040" }

                                            Text {
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
                                                    if (parent.modelData === "No" && root.trollNo)
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

                    // burn-in: silueta quemada del cartel, estática, que se desvanece
                    Item {
                        id: ghost
                        x: win.tearPad
                        width: win.dlgW
                        height: content.height
                        visible: win.ghosting
                        opacity: 0

                        Rectangle { anchors.fill: parent; color: "#e8d5ff"; opacity: 0.10 }
                        Rectangle { width: parent.width; height: Math.round(26 * win.k) + 2; color: "#b9a4ff"; opacity: 0.16 }
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
                Behavior on dockT { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }

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
