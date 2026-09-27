// fatal-lyrics showreel — el guion. 128 BPM, 8 compases = 15.000 s justos.
//
// Todos los cortes caen en la grilla (compás o medio compás): el ojo los
// siente "a tempo" aunque no suene nada. SyntheticAudio, los módulos y la
// pista de audio del render leen ESTOS números; ninguno tiene su copia.
.pragma library

var BPM = 128;
var BEAT = 60 / BPM;          // 0.46875
var BAR = BEAT * 4;           // 1.875
var FPS = 60;
var LENGTH = BAR * 8;         // 15.0

function b(n) { return n * BEAT; }

var SEGMENTS = [
    { key: "boot",    mod: "BootModule",    name: "Boot",          t0: 0,       t1: b(4)  },  // 0.000 – 1.875
    { key: "stack",   mod: "StackModule",   name: "Stack",       t0: b(4),    t1: b(10) },  // 1.875 – 4.688
    { key: "kinetic", mod: "KineticModule", name: "Kinetic type",  t0: b(10),   t1: b(16) },  // 4.688 – 7.500
    { key: "build",   mod: "MitosisModule", name: "Mitosis build", t0: b(16),   t1: b(24) },  // 7.500 – 11.250
    { key: "drop",    mod: "DropModule",    name: "Drop zoom",     t0: b(24),   t1: b(29) },  // 11.250 – 13.594
    { key: "resolve", mod: "ResolveModule", name: "Resolve",       t0: b(29),   t1: LENGTH }  // 13.594 – 15.000
];

var DROP_AT = b(24);          // 11.25: el golpe
var GAP_AT = b(23.5);         // 11.015: el vacío antes del drop (todo se congela)
var ROLL_AT = b(20);          // 9.375: arranca el redoble

function segment(key) {
    for (var i = 0; i < SEGMENTS.length; i++)
        if (SEGMENTS[i].key === key) return SEGMENTS[i];
    return null;
}

// ---- la partitura -------------------------------------------------------

function kicks() {
    var out = [];
    for (var i = 4; i < 20; i++) out.push(b(i));         // stack, kinetic, 1er compás del build
    for (var j = 24; j <= 29; j++) out.push(b(j));        // drop + el impacto final
    return out;
}

function snares() {
    var out = [];
    for (var i = 4; i < 20; i++) if (i % 4 === 1 || i % 4 === 3) out.push(b(i));
    // redoble que acelera: corcheas, semicorcheas, fusas, y corta en el vacío
    for (var e = 20; e < 22; e += 0.5) out.push(b(e));
    for (var s = 22; s < 23; s += 0.25) out.push(b(s));
    for (var f = 23; f < 23.5; f += 0.125) out.push(b(f));
    out.push(b(25)); out.push(b(27));
    return out;
}

function hats() {
    var out = [];
    for (var i = 4; i < 16; i++) out.push(b(i + 0.5));
    for (var j = 24; j < 29; j++) out.push(b(j + 0.5));
    return out;
}

// golpes duros (crash / impacto): cuentan como pico (`audPeak`)
function impacts() { return [b(4), DROP_AT, b(29)]; }

// cada tecla del prompt del boot: cae en fusas, del 0.5 al 1.4
var PROMPT = "C:\\FATAL> lyrics.exe /sync";
function keystrokes() {
    var out = [];
    var t0 = 0.52, step = BEAT / 8 * 0.9;
    for (var i = 0; i < PROMPT.length; i++) out.push(t0 + i * step);
    return out;
}
var ENTER_AT = b(3);          // 1.406: Enter

// ---- la letra (original, no es de ningún tema) --------------------------
// misma forma que el `show` del daemon: {text, title, t0, t1, words:[[t, w]]}
var LYRIC = {
    title: "voz.dll",
    text: "error fatal en tu voz",
    t0: b(10.5),
    t1: b(16),
    words: [[b(10.5), "error"], [b(11.5), "fatal"], [b(13), "en"], [b(13.5), "tu"], [b(14), "voz"]]
};

// una palabra por nivel del zoom del drop
var DROP_WORDS = ["NO", "RESPONDE", "LA", "MEMORIA", "DE", "TU", "VOZ"];

function allEvents() {
    return {
        bpm: BPM, length: LENGTH,
        kicks: kicks(), snares: snares(), hats: hats(), impacts: impacts(),
        keys: keystrokes(), enter: ENTER_AT, rollAt: ROLL_AT, gapAt: GAP_AT, dropAt: DROP_AT
    };
}

// los carteles del stack (no confundir con `cascade` de shell.qml, la muerte en cadena) (el 0 es el que nace en el boot: mismo lugar,
// mismo tamaño, para que el corte no se vea)
var STACK_K = 1.55;
var STACK = [
    { title: "fatal.exe", icon: "error", text: "Esta letra realizó una operación no válida y será cerrada.", buttons: ["Aceptar"], dx: 0, dy: 0 },
    { title: "memoria.sys", icon: "warning", text: "La memoria no responde. ¿Reintentar?", buttons: ["Reintentar", "Cancelar"], dx: 74, dy: 58 },
    { title: "voz.dll", icon: "error", text: "No se encontró la voz en C:\\TU\\VOZ", buttons: ["Aceptar"], dx: 148, dy: 116 },
    { title: "estribillo.exe", icon: "question", text: "¿Querés repetir el estribillo?", buttons: ["Sí", "No"], dx: 222, dy: 174 }
];
var DIALOG_W = 440;
var DIALOG_BODY = 56;
