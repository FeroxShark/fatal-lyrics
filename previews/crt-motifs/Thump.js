// fatal-lyrics motivos CRT (testeo 2026-10-19) — el golpe del bombo con física, y
// el CARÁCTER del tema que decide cómo es esa física.
//
// Ferox, 2026-10-19: cada golpe del bajo SE VE, pero adaptado al tema: uno lento y
// calmo reacciona suave y lento, uno rápido y agitado reacciona fuerte y seco; nunca
// el mismo "default de dubstep" para todo. Carácter = BPM + mood (energy, valence).
//
// El golpe es un IMPULSO sobre una masa con resorte: la respuesta es la de un
// oscilador amortiguado (sube, se pasa, vuelve, se apaga), evaluada en forma
// CERRADA desde la edad del golpe. No hay integrador por cuadro: el resultado no
// depende de los cuadros por segundo, ni del techo de 30/60 Hz de `stepMin`, y
// varios golpes seguidos se SUMAN (cola del anterior + el nuevo), que es lo que
// hace una membrana de verdad.
//
//   temper   0 (calmo: lento, amplio, blando) .. 1 (agitado: rápido, seco, fuerte)
//   valence  0..1 del daemon (`mood`): no acelera; decide la ELASTICIDAD — un tema
//            luminoso rebota (poco amortiguado), uno oscuro pesa (se apaga antes)
.pragma library

function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }
function mix(a, b, k) { return a + (b - a) * k; }

// BPM 70 → 0, 150 → 1; la energía del tema (`mood.energy`, perfil + bpm) pesa casi igual
function temper(bpm, energy, valence) {
    const b = clamp01((bpm - 70) / 80);
    return clamp01(0.55 * b + 0.45 * clamp01(energy));
}

// La física de un tema. La frecuencia del resorte se ata al tempo (un calmo hace UNA
// ola por tiempo; un agitado, dos sacudidas secas por tiempo): así el rebote nunca
// pelea con el compás.
function params(temper, valence, bpm) {
    const T = clamp01(temper);
    const beatHz = Math.max(40, Math.min(200, bpm || 120)) / 60;
    const f = beatHz * mix(0.62, 1.9, T);
    const zeta = Math.min(0.7, mix(0.16, 0.38, T) * mix(1.3, 0.8, clamp01(valence)));
    const w = 2 * Math.PI * f;
    const wd = w * Math.sqrt(1 - zeta * zeta);
    // ataque: el calmo EMPUJA (180 ms), el agitado PEGA (10 ms)
    const rise = mix(0.18, 0.010, T);
    const p = { f: f, zeta: zeta, w: w, wd: wd, rise: rise,
                gain: mix(0.55, 1.0, T),
                // la deriva de fondo (lo que se mueve aunque no suene nada): calmo lento y ancho
                drift: mix(0.30, 0.95, T),
                // cuánto tarda en apagarse un golpe a 1/20 (para el buffer de golpes)
                life: 3.0 / (zeta * w), norm: 1 };
    // normalizado a pico 1 (el pico del seno amortiguado, con el ataque incluido)
    let peak = 1e-3;
    for (let i = 1; i <= 64; i++)
        peak = Math.max(peak, Math.abs(raw(p, i / 64 * Math.PI / wd * 1.2)));
    p.norm = 1 / peak;
    return p;
}

function raw(p, age) {
    if (!(age > 0))
        return 0;
    return (1 - Math.exp(-age / p.rise)) * Math.exp(-p.zeta * p.w * age) * Math.sin(p.wd * age);
}

// desplazamiento de la masa a `age` s del golpe: 0 → +1 → rebote negativo → 0
function resp(p, age) { return raw(p, age) * p.norm; }

// la envolvente sin oscilar (para brillos): sube con el ataque y se apaga con la misma masa
function env(p, age) {
    if (!(age > 0))
        return 0;
    return (1 - Math.exp(-age / p.rise)) * Math.exp(-p.zeta * p.w * age);
}

// Una masa más pesada (`mass` > 1) responde más lento y más tarde: el overlap y el
// follow-through de los motivos salen de evaluar el MISMO golpe en masas distintas.
function heavy(p, mass) {
    const q = Object.assign({}, p);
    q.w = p.w / Math.sqrt(mass);
    q.wd = q.w * Math.sqrt(1 - p.zeta * p.zeta);
    q.rise = p.rise * Math.sqrt(mass);
    q.norm = 1;
    let peak = 1e-3;
    for (let i = 1; i <= 64; i++)
        peak = Math.max(peak, Math.abs(raw(q, i / 64 * Math.PI / q.wd * 1.2)));
    q.norm = 1 / peak;
    return q;
}

// suma de los golpes vivos sobre una masa
function sum(p, now, hitT, hitA, delay) {
    let s = 0;
    for (let i = 0; i < hitT.length; i++)
        s += hitA[i] * resp(p, now - hitT[i] - (delay || 0));
    return s;
}
function envSum(p, now, hitT, hitA) {
    let s = 0;
    for (let i = 0; i < hitT.length; i++)
        s += hitA[i] * env(p, now - hitT[i]);
    return s;
}

// seguidor de primer orden con tiempos distintos de subida y bajada (s)
function follow(cur, target, dt, up, down) {
    if (!(dt > 0) || dt > 0.5)
        return cur;
    const tau = target > cur ? up : down;
    return cur + (target - cur) * (1 - Math.exp(-dt / Math.max(tau, 1e-3)));
}
