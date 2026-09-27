// fatal-lyrics motivos CRT — easing y utilidades de tiempo (copia del showreel
// con dos helpers de LOOP abajo). Al integrar un motivo, este archivo va a
// `shell/` tal cual: los motivos lo importan como `"Ease.js" as E`.
//
// Todo es función PURA del reloj: ningún motivo usa Animation ni Behavior,
// así el cuadro 437 siempre es el mismo y el loop cierra exacto.
.pragma library

function clamp(x, a, b) { return x < a ? a : (x > b ? b : x); }
function clamp01(x) { return clamp(x, 0, 1); }
function mix(a, b, k) { return a + (b - a) * k; }
// progreso lineal 0..1 de `t` dentro de [t0, t0+dur]
function prog(t, t0, dur) { return dur <= 0 ? (t >= t0 ? 1 : 0) : clamp01((t - t0) / dur); }

function inQuad(x) { return x * x; }
function outQuad(x) { return 1 - (1 - x) * (1 - x); }
function inCubic(x) { return x * x * x; }
function outCubic(x) { return 1 - Math.pow(1 - x, 3); }
function inOutCubic(x) { return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; }
function outQuart(x) { return 1 - Math.pow(1 - x, 4); }
function inExpo(x) { return x <= 0 ? 0 : Math.pow(2, 10 * x - 10); }
// el snap de Motion.qml (enterMs, OutExpo): llega rápido y se asienta a la vista
function outExpo(x) { return x >= 1 ? 1 : 1 - Math.pow(2, -10 * x); }
function inOutExpo(x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    return x < 0.5 ? Math.pow(2, 20 * x - 10) / 2 : (2 - Math.pow(2, -20 * x + 10)) / 2;
}
function outBack(x, s) {
    s = s === undefined ? 1.70158 : s;
    const c3 = s + 1;
    return 1 + c3 * Math.pow(x - 1, 3) + s * Math.pow(x - 1, 2);
}
function inBack(x, s) {
    s = s === undefined ? 1.70158 : s;
    return (s + 1) * x * x * x - s * x * x;
}
// resorte subamortiguado: 0 → 1 con rebote que se apaga (follow-through)
function spring(x, freq, damp) {
    if (x <= 0) return 0;
    freq = freq === undefined ? 4.5 : freq;
    damp = damp === undefined ? 6 : damp;
    return 1 - Math.exp(-damp * x) * Math.cos(freq * Math.PI * 2 * x);
}
// golpe que decae: 1 en t0 y se apaga con constante tau (s)
function decay(t, t0, tau) { return t < t0 ? 0 : Math.exp(-(t - t0) / tau); }
function smoothstep(a, b, x) { const k = clamp01((x - a) / (b - a)); return k * k * (3 - 2 * k); }

// hash estable 0..1 (mismo número para la misma semilla, en todos los cuadros)
function hash(n) {
    const s = Math.sin(n * 127.1 + 311.7) * 43758.5453123;
    return s - Math.floor(s);
}
function hash2(a, b) { return hash(a * 57.0 + b * 131.0); }

// ruido 1D suave (value noise), para derivas que nunca paran
function noise(x) {
    const i = Math.floor(x), f = x - i;
    const u = f * f * (3 - 2 * f);
    return mix(hash(i), hash(i + 1), u) * 2 - 1;
}

// cuadro de un glifo "descifrándose": mientras k < 1 el carácter es basura
const GLYPHS = "#%&$@!?*+=<>/\\|01░▒▓█";
function scramble(ch, t, seed, k) {
    if (k >= 1 || ch === " ") return ch;
    const n = Math.floor(t * 30 + seed * 17);
    return GLYPHS.charAt(Math.floor(hash2(n, seed) * GLYPHS.length));
}

// ---- loops -----------------------------------------------------------------
// onda triangular 0..1..0 con período 1: el rebote de un salvapantallas
function tri(u) { const f = u - Math.floor(u); return 1 - Math.abs(2 * f - 1); }
// ruido 1D que se REPITE cada `P` unidades (P entero): una deriva que nunca
// para y aun así cierra el loop. `s` separa canales.
function pnoise(x, P, s) {
    s = s || 0;
    const i = Math.floor(x), f = x - i;
    const u = f * f * (3 - 2 * f);
    const a = ((i % P) + P) % P, b = (((i + 1) % P) + P) % P;
    return mix(hash(a + s * 91.7), hash(b + s * 91.7), u) * 2 - 1;
}
// módulo que no se va a negativo
function wrap(x, m) { return ((x % m) + m) % m; }
// un color de QML como texto CSS para el Canvas, con alfa aparte
function css(c, a) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
        + Math.round(c.b * 255) + "," + (a === undefined ? 1 : clamp01(a)).toFixed(3) + ")";
}
// lo mismo como color de QML (Shapes, Rectangle): el texto rgba() de `css` no
// lo entiende una propiedad `color`
function col(c, a) {
    return Qt.rgba(c.r, c.g, c.b, a === undefined ? 1 : clamp01(a));
}
