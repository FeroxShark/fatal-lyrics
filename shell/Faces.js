// fatal-lyrics — las caras del fondo del CRT y cómo se reparten (tanda 8, slice "colores").
//
// Una paleta son TRES caras que combinan, separadas por LUZ antes que por tono:
//   a — la prendida: fondo quemado claro, letra oscura (la "invertida" de TRAMPAS)
//   b — el tubo apagado: fondo hondo, letra encendida
//   c — la media: fondo saturado de luz intermedia, letra casi blanca (la del BSOD)
// Así las tres se distinguen aunque el tono se parezca, y el texto se lee en las
// tres (contraste WCAG ≥ 4.5 en las tres, lo mide `tests/test_colores.py`).
//
// El reparto sigue la parte del tema (`crt.face_mode = song`):
//   verse  — estrofa: dos caras, 2-1 (lo de siempre)
//   chorus — el drop: la pared entera de UNA cara, el golpe
//   wild   — puente / subida / evento raro: las tres distintas
// `classic` es lo de antes: sólo a/b, 2-1 al azar, nunca las tres iguales.
//
// Todo PURO y en hex, sin Qt: lo llaman `shell.qml` y el banco offscreen
// (`previews/colores/`), y los tests lo corren con node.
.pragma library

// ------------------------------------------------------------------ color
function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }

function hexToRgb(hex) {
    let h = String(hex).replace("#", "");
    if (h.length === 3)
        h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    if (h.length === 8)
        h = h.slice(2);          // #aarrggbb (así imprime Qt un color con alfa)
    const v = parseInt(h, 16);
    return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
}
function rgbToHex(rgb) {
    let s = "#";
    for (let i = 0; i < 3; i++) {
        const v = Math.round(clamp01(rgb[i]) * 255);
        s += (v < 16 ? "0" : "") + v.toString(16);
    }
    return s;
}
function rgbToHsl(rgb) {
    const r = rgb[0], g = rgb[1], b = rgb[2];
    const hi = Math.max(r, g, b), lo = Math.min(r, g, b);
    const l = (hi + lo) / 2;
    if (hi === lo)
        return [0, 0, l];
    const d = hi - lo;
    const s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo);
    let h;
    if (hi === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (hi === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    return [h / 6, s, l];
}
function hslToHex(h, s, l) {
    h = ((h % 1) + 1) % 1;
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    function ch(t) {
        t = ((t % 1) + 1) % 1;
        if (t < 1 / 6) return p + (q - p) * 6 * t;
        if (t < 1 / 2) return q;
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
        return p;
    }
    return rgbToHex([ch(h + 1 / 3), ch(h), ch(h - 1 / 3)]);
}
// luminancia relativa y contraste, los de WCAG 2
function luminance(hex) {
    const c = hexToRgb(hex).map(v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
function contrast(x, y) {
    const a = luminance(x), b = luminance(y);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}
function hueGap(h1, h2) {
    const d = Math.abs(h1 - h2) % 1;
    return Math.min(d, 1 - d);
}
// La luz (HSL) que le da a ese tono y saturación la luminancia pedida. El mismo
// L=0.58 es casi blanco en amarillo y casi negro en azul: fijar L era lo que
// dejaba las tapas azules con la letra ilegible.
function lightFor(h, s, target, lo, hi) {
    lo = lo === undefined ? 0 : lo;
    hi = hi === undefined ? 1 : hi;
    for (let i = 0; i < 24; i++) {
        const m = (lo + hi) / 2;
        if (luminance(hslToHex(h, s, m)) < target) lo = m; else hi = m;
    }
    return (lo + hi) / 2;
}

// ------------------------------------------------------------ el tono
// El color también sigue a la CANCIÓN, no sólo a la tapa (`cartelitos/tone.py`
// mide, esto aplica). `warm` -1..1 es el registro: agudo y brillante tira a
// ámbar y a más luz, grave y oscuro tira a azul hondo y a menos luz. `shift`
// -1..1 es el mood: una sección que sube o baja corre el tono de la tapa.
// La tapa sigue siendo la base: el tono se TIRA hacia el polo (una fracción del
// arco más corto, `TONE_PULL_MAX`), no se reemplaza. El polo cálido es ámbar —
// nunca violeta — y el frío un azul profundo entre el índigo y el petróleo.
// La luz de cada cara se corre dentro de un margen donde el contraste de la
// letra sigue valiendo (lo mide `tests/test_tono.py` en toda la rueda).
const TONE_POLE_WARM = 0.105;       // ámbar
const TONE_POLE_COOL = 0.58;        // azul profundo
const TONE_PULL_MAX = 0.55;         // cuánto del camino al polo, a ±1
const TONE_SHIFT_MAX = 0.09;        // vuelta de la rueda a ±1 de mood (32°)
const TONE_LUM_DOWN = 0.5;          // cuánta luz pierde una cara a -1 (la prendida, de 0.5 a 0.25)
const TONE_LUM_UP = 0.3;            // y cuánta gana a +1
const TONE_LUM_MID = 0.25;          // la media, a +1; a -1 baja casi tanto como la prendida (0.45): vive entre las otras dos y la prendida ya no baja de LIT_Y_MIN
const LIT_Y_MIN = 0.2;              // la prendida no baja de acá: más oscura y la letra negra no llega a 4.5
const INK_Y_MIN = 0.2;              // ni la letra encendida de la oscura
// la luminancia `y0` corrida por el registro `t`; nunca por debajo de `floor`
// (si ya estaba abajo, se queda) ni por encima de 0.9
function toneY(y0, t, floor) {
    if (!t)
        return y0;
    if (t < 0)
        return Math.min(y0, Math.max(floor, y0 * (1 + TONE_LUM_DOWN * t)));
    return Math.min(0.9, Math.max(y0, y0 * (1 + TONE_LUM_UP * t)));
}

// El tono `h` (0..1) después del mood y del registro.
function toneHue(h, warm, shift) {
    warm = clamp01((warm + 1) / 2) * 2 - 1;
    shift = clamp01((shift + 1) / 2) * 2 - 1;
    const rot = h + shift * TONE_SHIFT_MAX;
    const pole = warm >= 0 ? TONE_POLE_WARM : TONE_POLE_COOL;
    const d = ((pole - rot + 1.5) % 1 + 1) % 1 - 0.5;      // el arco corto hacia el polo, -0.5..0.5
    return ((rot + d * Math.abs(warm) * TONE_PULL_MAX) % 1 + 1) % 1;
}
// Un color suelto (la barra de título del modo normal): el tono corre, la
// LUMINANCIA se queda — es lo que la mantiene legible con letra blanca encima.
// `yMul` (opcional) la sube o baja: el texto karaoke del modo normal, que es
// casi negro, necesita un poco de luz para que el color se note.
function toneHex(hex, warm, shift, yMul) {
    const hsl = rgbToHsl(hexToRgb(hex));
    if (hsl[1] < 0.05 || (!warm && !shift))
        return hex;
    const y = luminance(hex) * (yMul || 1);
    const h = toneHue(hsl[0], warm, shift);
    return hslToHex(h, hsl[1], lightFor(h, hsl[1], y));
}

// ------------------------------------------------------------ las caras
// Cada cara: { bg, ink, hot, dim, tint } en hex. `tint` es el color del
// fósforo (halo del bloom, barra que rueda, rotura); `shell.qml` lo pasa a vec3.
// Los L de base son los de la cara de siempre (`faceFromColor`, tanda 2); sólo
// se corren cuando ese tono no llega al contraste. `t` (-1..1) es el registro:
// sin él (0) las caras son las de siempre, byte por byte.
const LIT_Y = 0.27;
const INK_MIN_C = 5.0;     // contraste que se le exige a la letra de la prendida (la regla del test es 4.5)
// la letra más clara de L0 hacia abajo que llegue a `minC` contra `bg`
function inkOn(h, s, bg, l0, minC) {
    let l = l0;
    while (l > 0 && contrast(hslToHex(h, s, l), bg) < minC)
        l = Math.max(0, l - 0.01);
    return hslToHex(h, s, l);
}
function faceLit(h, s, t) {
    t = t || 0;
    const l0 = Math.max(0.58, lightFor(h, s, LIT_Y));
    const l = t ? lightFor(h, s, toneY(luminance(hslToHex(h, s, l0)), t, LIT_Y_MIN)) : l0;
    const dim = hslToHex(h, s, 0.34);
    const bg = hslToHex(h, s, l);
    const inkS = Math.min(s + 0.15, 1);
    return {
        bg: bg,
        ink: t < 0 ? inkOn(h, inkS, bg, 0.15, INK_MIN_C) : hslToHex(h, inkS, 0.15),
        hot: t < 0 ? inkOn(h, 1, bg, 0.07, 3.5) : hslToHex(h, 1, 0.07),
        dim: dim,
        tint: dim,
    };
}
function faceDark(h, s, t) {
    t = t || 0;
    const ink0 = hslToHex(h, s, Math.max(0.66, lightFor(h, s, 0.30)));
    const ink = t ? hslToHex(h, s, lightFor(h, s, toneY(luminance(ink0), t, INK_Y_MIN))) : ink0;
    return {
        bg: hslToHex(h, s * 0.9, 0.07 + 0.015 * t),
        ink: ink,
        hot: hslToHex(h, 0.4, 0.92),
        dim: hslToHex(h, s, Math.max(0.40, lightFor(h, s, 0.09))),
        tint: ink,
    };
}
// La media: el fondo apunta a una luminancia entre las otras dos (lejos del
// blanco de `a` y del negro de `b`), la letra casi blanca del mismo tono.
const MID_Y = 0.11;
function faceMid(h, s, t) {
    t = t || 0;
    const sat = Math.max(s, 0.55);
    const dim = hslToHex(h, sat, lightFor(h, sat, 0.30, 0.3, 0.97));
    return {
        bg: hslToHex(h, sat, lightFor(h, sat, MID_Y * (1 + (t < 0 ? 0.45 : TONE_LUM_MID) * t), 0.05, 0.6)),
        ink: hslToHex(h, 0.9, 0.94),
        hot: "#ffffff",
        dim: dim,
        tint: dim,
    };
}

const ALBUM_SAT_CALM = 0.35;
const ALBUM_SAT_HARD = 0.6;

// La paleta de la tapa: hasta cuatro colores del daemon (evento `art`, ya
// ordenados por presencia pesada por saturación). El primero manda la prendida,
// el segundo la oscura y el tercero la media. Un color que repite el tono de
// uno que ya está no cuenta como otro: se busca el siguiente y, si no hay, se
// DERIVA del arco más grande que dejan los que hay (split-complementario), no
// se sortea. null si la tapa no tiene color (gris, blanco y negro).
function albumFaces(colors, energy, tone) {
    let usable = [];
    for (let i = 0; i < (colors || []).length; i++) {
        const hsl = rgbToHsl(hexToRgb(colors[i]));
        if (hsl[1] > 0.18)
            usable.push(hsl);
    }
    if (usable.length === 0)
        return null;
    let picked = [usable[0]];
    for (let i = 1; i < usable.length && picked.length < 3; i++) {
        let far = true;
        for (let k = 0; k < picked.length; k++)
            if (hueGap(usable[i][0], picked[k][0]) < 0.06)
                far = false;
        if (far)
            picked.push(usable[i]);
    }
    if (picked.length === 1)          // lo de siempre: el segundo, al otro lado de la rueda
        picked.push([(picked[0][0] + 0.45) % 1, 0.75, 0.5]);
    if (picked.length === 2) {
        // el medio del arco más grande entre los dos tonos
        const h1 = picked[0][0], h2 = picked[1][0];
        const d = ((h2 - h1) % 1 + 1) % 1;            // de h1 a h2 hacia adelante
        const mid = d > 0.5 ? h1 + d / 2 : h2 + (1 - d) / 2;
        picked.push([mid % 1, 0.7, 0.5]);
    }
    // La tapa manda el TONO; la energía del tema, cuánto se le deja de su apagado. Piso de
    // saturación: ALBUM_SAT_CALM (tema quieto: una tapa sepia sale sepia) hasta ALBUM_SAT_HARD
    // (tema de golpe: plena, como siempre). `energy` ausente = 1, el piso de antes.
    const e = Math.min(Math.max(energy === undefined || energy === null ? 1 : energy, 0), 1);
    const floor = ALBUM_SAT_CALM + (ALBUM_SAT_HARD - ALBUM_SAT_CALM) * e;
    function sat(p) { return Math.min(Math.max(p[1], floor), 1); }
    // El tono se aplica DESPUÉS de elegir: quién es la prendida, la oscura y la
    // media sale de la tapa pelada y no salta cuando el registro se mueve.
    const warm = tone && tone.warm ? tone.warm : 0;
    const shift = tone && tone.shift ? tone.shift : 0;
    function hue(p) { return warm || shift ? toneHue(p[0], warm, shift) : p[0]; }
    return {
        a: faceLit(hue(picked[0]), sat(picked[0]), warm),
        b: faceDark(hue(picked[1]), sat(picked[1]), warm),
        c: faceMid(hue(picked[2]), sat(picked[2]), warm),
    };
}

// Validador de una paleta: el texto se lee en las tres caras y los tres fondos
// se distinguen entre sí. Lo usan los tests para las fijas y las de la tapa.
function checkScheme(sc) {
    const faces = [sc.a, sc.b, sc.c];
    let out = { inkMin: 99, hotMin: 99, bgMin: 99 };
    for (let i = 0; i < 3; i++) {
        out.inkMin = Math.min(out.inkMin, contrast(faces[i].ink, faces[i].bg));
        out.hotMin = Math.min(out.hotMin, contrast(faces[i].hot, faces[i].bg));
        for (let k = i + 1; k < 3; k++)
            out.bgMin = Math.min(out.bgMin, contrast(faces[i].bg, faces[k].bg));
    }
    return out;
}

// ----------------------------------------------------------- el reparto
// Qué parte del tema es, para los colores. `section` es la del daemon
// (`quiet|verse|build|drop`, ya sin rebotes: sólo llega cuando cambia).
// Un `quiet` antes del primer drop es la intro o una estrofa floja; después,
// es el puente.
function faceMode(section, rare, dropSeen) {
    if (rare)
        return "wild";
    if (section === "drop")
        return "chorus";
    if (section === "build")
        return "wild";
    if (section === "quiet" && dropSeen)
        return "wild";
    return "verse";
}

// Un tema sin build ni drop detectable (clásica, ambient, un drone) es `verse`
// todo el rato, y la pared se quedaba en 2-1 para siempre. Si la parte lleva
// `VARIETY_AFTER_MS` sin repartirse, la estrofa se turna con un momento de tres
// caras distintas y uno de las tres iguales (`turn` cuenta cuántas van). Sólo
// toca `verse`: las partes con evento propio ya reparten distinto.
const VARIETY_AFTER_MS = 24000;
const VARIETY_KINDS = ["wild", "chorus"];
function varietyMode(mode, sinceMs, turn) {
    if (mode !== "verse" || sinceMs < VARIETY_AFTER_MS)
        return mode;
    return VARIETY_KINDS[((turn % 2) + 2) % 2];
}

// El portero. Entrar a un EVENTO (el drop, el puente, un raro) pasa: el golpe
// no puede esperar diez segundos, y un raro dura menos que eso. Volver a la
// estrofa espera el `color_hold` entero. Y ningún cambio antes de `floorMs`
// desde el anterior: dos secciones pegadas no son dos repartos.
const MODE_FLOOR_MS = 2500;
function gateOk(now, lastAt, holdMs, from, to) {
    if (from === to)
        return false;
    const since = now - lastAt;
    if (since < MODE_FLOOR_MS)
        return false;
    if (to !== "verse")
        return true;
    return since >= holdMs;
}

// 2-1 al azar (`r` en [0,1)): nunca las n iguales. El de siempre.
function twoTone(n, r) {
    if (n <= 1)
        return [0];
    const combos = Math.pow(2, n) - 2;
    const bits = 1 + Math.floor(r * combos);
    let out = [];
    for (let i = 0; i < n; i++)
        out.push((bits >> i) & 1);
    return out;
}

// Qué cara va en cada pantalla. `prev` es el reparto de ahora (puede venir
// vacío o de otro largo), `focus` la pantalla con la letra: en todos los modos
// la pantalla con la letra CONSERVA su cara cuando hay un reparto válido que lo
// permite — el cambio pasa en las de al lado, no debajo de la frase.
// Degradado con menos pantallas:
//   1 — verse [0]; chorus su cara; wild [2] (la tercera marca el momento raro)
//   2 — verse 1-1 de a/b; chorus las dos iguales; wild la del foco + la otra
//       con la media (o una de a/b si el foco ya tiene la media)
//   ≥3 — verse 2-1 de a/b; chorus todas iguales; wild las tres presentes y dos
//       vecinas nunca iguales
function facePattern(mode, n, prev, focus, r) {
    n = Math.max(n, 1);
    const f = (focus >= 0 && focus < n) ? focus : Math.floor((n - 1) / 2);
    const had = (prev && prev.length === n) ? prev[f] : -1;
    if (mode === "chorus") {
        const face = had >= 0 ? had : 0;
        let out = [];
        for (let i = 0; i < n; i++) out.push(face);
        return out;
    }
    if (mode === "wild") {
        if (n === 1)
            return [2];
        const keep = had >= 0 ? had : 2;
        let rest = [0, 1, 2].filter(v => v !== keep);
        if (r >= 0.5)
            rest = [rest[1], rest[0]];
        if (n === 2) {
            // con dos pantallas entra la media, si el foco no la tiene ya
            let out = [0, 0];
            out[f] = keep;
            out[1 - f] = keep === 2 ? rest[0] : 2;
            return out;
        }
        const perm = [keep, rest[0], rest[1]];
        let out = [];
        for (let i = 0; i < n; i++)
            out.push(perm[((i - f) % 3 + 3) % 3]);
        return out;
    }
    // verse: 2-1 de a/b; si la del foco queda distinta de la que tenía, el
    // complemento es otro 2-1 igual de válido y la deja quieta
    let out = twoTone(n, r);
    if (n > 1 && (had === 0 || had === 1) && out[f] !== had)
        out = out.map(v => 1 - v);
    return out;
}

// El orden en que cambia cada pantalla: desde la de la letra hacia afuera, así
// el cambio se ve salir de donde está la voz. Sólo las que cambian.
function stepOrder(prev, next, focus) {
    const n = next.length;
    const f = (focus >= 0 && focus < n) ? focus : Math.floor((n - 1) / 2);
    let idx = [];
    for (let i = 0; i < n; i++)
        if (!prev || prev.length !== n || prev[i] !== next[i])
            idx.push(i);
    idx.sort((x, y) => (Math.abs(x - f) - Math.abs(y - f)) || (x - y));
    return idx;
}
