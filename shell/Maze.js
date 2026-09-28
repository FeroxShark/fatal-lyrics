// fatal-lyrics — el laberinto: la ruta, el reparto de pasos y los huevos de pascua.
//
// Todo función PURA (sin reloj, sin estado): `Maze.qml` guarda el estado (cuántos
// pasos lleva, cuándo empezó cada cosa) y llama a estas cuentas; los tests las
// corren con node. Nada de esto usa `t · velocidad`: la marcha es un CONTADOR de
// pasos (`walked`) al que la música le da o le quita créditos por tiempo.
.pragma library

var LOOP_STEPS = 32;     // 32 acciones = la vuelta entera del anillo
var LEG_ENDS = [8, 15, 24, 31];       // acciones "doblar a la derecha" (fin de cada tramo)

function clamp(x, a, b) { return x < a ? a : (x > b ? b : x); }
function wrap(x, n) { return x - Math.floor(x / n) * n; }
function hash(n) {
    const s = Math.sin(n * 127.1 + 311.7) * 43758.5453123;
    return s - Math.floor(s);
}
function hash2(a, b) { return hash(a * 57.0 + b * 131.0); }

// las 33 posiciones de la vuelta: [x, y, ángulo]. 8 adelante, doblar, 6, doblar…
function states() {
    const acts = [];
    const legs = [8, 6, 8, 6];
    for (const n of legs) {
        for (let i = 0; i < n; i++) acts.push("F");
        acts.push("R");
    }
    let x = 1.5, y = 1.5, a = 0;
    const out = [[x, y, a]];
    for (const c of acts) {
        if (c === "F") { x += Math.round(Math.cos(a)); y += Math.round(Math.sin(a)); }
        else a += Math.PI / 2;
        out.push([x, y, a]);
    }
    return out;
}
var STATES = states();

// Cuántos pasos da la marcha en `d` tiempos con el ritmo `rate` (1 = un paso por
// tiempo, como siempre). `acc` es el crédito fraccionario que sobró: con ritmo
// 0.6 salen 1,0,1,1,0…; con 1.6, algún tiempo da dos. Devuelve {steps, acc}.
// A ritmo 1 EXACTO son `d` pasos y `acc` no se mueve (la marcha vieja, bit a bit).
function credit(acc, d, rate) {
    const r = clamp(rate, 0.25, 2.6);
    const t = acc + d * r;
    const steps = Math.floor(t + 1e-9);
    return { steps: steps, acc: t - steps };
}

// La pose (x, y, ángulo) en el paso continuo `s` (fracción = avance dentro de la acción).
function pose(s) {
    const w = wrap(s, LOOP_STEPS);
    const i = Math.min(Math.floor(w), LOOP_STEPS - 1);
    const f = w - i;
    const a = STATES[i], b = STATES[i + 1];
    return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
}

// la dirección de avance (entera) de la acción `k`
function heading(k) {
    const a = STATES[Math.floor(wrap(k, LOOP_STEPS))][2];
    return [Math.round(Math.cos(a)), Math.round(Math.sin(a))];
}

// acciones "adelante" con al menos 4 más adelante en el mismo tramo: por ahí cruza
// una rata / hay una roca
var OPEN_ACTIONS = [0, 1, 2, 3, 4, 9, 10, 11, 16, 17, 18, 19, 20, 25, 26, 27];

// el reparto de los huevos (suma 1): cuál toca cuando le toca a uno
var KINDS = [["smiley", 0.24], ["dialog", 0.24], ["exit", 0.14], ["rat", 0.20], ["rock", 0.18]];
var EGG_KIND = { smiley: 1, dialog: 2, exit: 3, rat: 4, rock: 5 };
// probabilidad de que una vuelta (32 tiempos, ~15 s a 128 BPM) traiga un huevo: raros
var CHANCE = 0.22;

function pickKind(h) {
    let acc = 0;
    for (const k of KINDS) {
        acc += k[1];
        if (h < acc) return k[0];
    }
    return KINDS[KINDS.length - 1][0];
}

// El plan de la vuelta `lap` para la semilla `seed`, o null si no toca huevo.
// `force` (el banco / `fatal`…): un tipo fijo, SIEMPRE, y en la misma acción todas
// las vueltas (así el loop del banco cierra). Sin `force` decide el sorteo sembrado.
//   {kind, act, cell:[cx,cy], dir:[dx,dy], lead, tail}
// `act` es la acción ABSOLUTA en que la cámara está frente al huevo; el huevo vive
// mientras `walked` esté entre act-lead y act+tail.
function plan(seed, lap, force) {
    let kind = force || "";
    let base = lap;
    if (!kind) {
        if (hash2(seed + 3.1, lap) >= CHANCE) return null;
        kind = pickKind(hash2(seed + 7.7, lap));
    } else {
        base = 0;
    }
    const pick = hash2(seed + 11.3, base);
    let r, lead, tail;
    if (kind === "rat" || kind === "rock") {
        r = force ? 2 : OPEN_ACTIONS[Math.floor(pick * OPEN_ACTIONS.length)];
        lead = kind === "rat" ? 1 : 3;
        tail = kind === "rat" ? 1 : 3;
    } else {
        // el cartel va en la pared del fondo de un tramo: se lo ve venir de frente
        r = force ? LEG_ENDS[0] : LEG_ENDS[Math.floor(pick * LEG_ENDS.length)];
        lead = 5;
        tail = 2;
    }
    const st = STATES[r];
    const d = heading(r);
    let ahead = kind === "rat" ? 2 : (kind === "rock" ? 3 : 1);
    const cell = [Math.floor(st[0]) + d[0] * ahead, Math.floor(st[1]) + d[1] * ahead];
    return { kind: kind, act: (force ? 0 : lap) * LOOP_STEPS + r, cell: cell, dir: d, lead: lead, tail: tail };
}

// ¿el plan está en ventana con `walked` pasos dados?
function inWindow(p, walked) {
    return !!p && walked >= p.act - p.lead && walked <= p.act + p.tail;
}

// La ventana de un plan forzado se repite en cada vuelta: el plan es el de la vuelta 0
// corrido `lap` vueltas.
function shifted(p, lap) {
    return p ? { kind: p.kind, act: p.act + lap * LOOP_STEPS, cell: p.cell, dir: p.dir, lead: p.lead, tail: p.tail } : null;
}

// el plan que vale con `walked` pasos: el de esta vuelta (un cartel del fondo del último
// tramo cruza a la vuelta siguiente, por eso también se mira la anterior)
function active(seed, walked, force) {
    const lap = Math.floor(walked / LOOP_STEPS);
    for (const l of [lap, lap - 1]) {
        const p = force ? shifted(plan(seed, 0, force), l) : plan(seed, l, "");
        if (inWindow(p, walked)) return p;
    }
    return null;
}

// La mirada al costado: 1 o -1, sembrada. `slot` cambia cada 4 pasos.
function side(seed, slot) { return hash2(seed + 5.9, slot) < 0.5 ? -1 : 1; }
