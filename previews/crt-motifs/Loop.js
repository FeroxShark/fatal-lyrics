// fatal-lyrics motivos CRT — la partitura del loop de prueba.
//
// 8 compases a 128 BPM = 15.000 s exactos = 32 tiempos = 900 cuadros a 60 fps.
// Estrofa (compases 1-4), subida (5-6, redoble que acelera), drop (7-8).
// El loop vuelve del drop a la estrofa: es un tema, no un zumbido parejo, y así
// cada preview muestra cómo reacciona el motivo a las TRES partes.
//
// SÓLO para el preview. En el overlay nada de esto existe: el motivo recibe
// `tick`, `level`, `section`… del root, igual que lo recibe acá de LoopFeed.
.pragma library

const BPM = 128;
const BEAT = 60 / BPM;          // 0.46875
const BAR = 4 * BEAT;           // 1.875
const BEATS = 32;
const LOOP = BEATS * BEAT;      // 15.0
const FPS = 60;
// el reloj del tubo arranca lejos del cero a propósito: en el overlay vale
// miles de segundos, y un motivo que se rompe con eso tiene que romperse acá
const CLOCK0 = 3000;            // múltiplo de LOOP y de BEAT

function b(n) { return n * BEAT; }

function sectionAt(t) {
    const bt = t / BEAT;
    return bt < 16 ? "verse" : bt < 24 ? "build" : "drop";
}
function energyAt(t) {
    const bt = t / BEAT;
    if (bt < 16) return 0.9;
    if (bt < 24) return 0.9 + 0.5 * (bt - 16) / 8;
    return 1.6;
}

function kicks() { const o = []; for (let i = 0; i < 32; i++) o.push(b(i)); return o; }
function snares() {
    const o = [];
    for (let i = 4; i < 16; i++) if (i % 2 === 1) o.push(b(i));          // 2 y 4
    for (let i = 16; i < 20; i += 0.5) o.push(b(i));                      // corcheas
    for (let i = 20; i < 23; i += 0.25) o.push(b(i));                     // semis
    for (let i = 23; i < 24; i += 0.125) o.push(b(i));                    // fusas
    for (let i = 24; i < 32; i++) if (i % 2 === 1) o.push(b(i));
    return o;
}
function hats() {
    const o = [];
    for (let i = 0; i < 24; i++) o.push(b(i + 0.5));
    for (let i = 24; i < 32; i += 0.25) if ((i * 4) % 4 !== 0) o.push(b(i));
    return o;
}
function crashes() { return [b(0), b(24)]; }
function riser() { return { t0: b(16), t1: b(24) }; }
function drop() { return { t0: b(24), t1: LOOP }; }

// una palabra por compás: la "primera palabra de la línea que viene"
const WORDS = ["ERROR", "FATAL", "EN", "TU", "VOZ", "NO", "RESPONDE", "MEMORIA"];
const LINES = ["error fatal en tu voz", "no responde la memoria",
               "aceptar o cancelar", "letras que no responden"];

function events() {
    return { kicks: kicks(), snares: snares(), hats: hats(), crashes: crashes(),
             riser: riser(), drop: drop(), loop: LOOP, bpm: BPM };
}
