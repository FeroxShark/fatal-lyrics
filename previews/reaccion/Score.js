// fatal-lyrics — banco de la reacción (tanda 8): la partitura sintética de `aud`.
//
// Ocho segundos que tocan cada canal por separado, para que la hoja muestre qué
// mueve cada uno:
//   0.0–2.0  estrofa: golpes de bajo cada 0.5 s, agudos quietos, poco sucio
//   2.0–3.2  melodía sin bajo: tres entradas de agudos (hf) y ningún golpe
//   3.3–3.75 corte seco (el daemon lo marca a los 100 ms: cut=1 desde 3.40)
//   3.75     vuelve con fuerza (cutf 0.9) y un golpe
//   4.0–8.0  se ensucia: dirt sube hasta 0.9, golpes cada 0.5 s
// Los valores imitan lo que manda el daemon (docs/tanda8-estado/senales.md):
// hf sube en ~50 ms y baja en ~400, dirt ya viene suavizado.
.pragma library

var BEATS = [0.25, 0.75, 1.25, 1.75, 3.75, 4.25, 4.75, 5.25, 5.75, 6.25, 6.75, 7.25, 7.75];
var HF_ONSETS = [[2.10, 0.95], [2.50, 0.75], [2.90, 0.90]];
var CUT_ON = 3.40;          // cuándo llega cut=1 (el silencio empezó en 3.30)
var CUT_BACK = 3.75;        // cuándo vuelve (cutf)
var CUT_F = 0.9;

function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }

// el golpe del bajo, como `beatAnim` sin compás: 1 → 0 OutQuad en 190 ms
function beatPulse(t) {
    var v = 0;
    for (var i = 0; i < BEATS.length; i++) {
        var a = t - BEATS[i];
        if (a >= 0 && a < 0.19) {
            var p = a / 0.19;
            v = Math.max(v, (1 - p) * (1 - p));
        }
    }
    return v;
}

function hf(t) {
    var v = 0.08;
    for (var i = 0; i < HF_ONSETS.length; i++) {
        var a = t - HF_ONSETS[i][0];
        var pk = HF_ONSETS[i][1];
        if (a < 0)
            continue;
        var e = a < 0.05 ? pk * a / 0.05 : pk * Math.exp(-(a - 0.05) / 0.18);
        v = Math.max(v, e);
    }
    return v;
}

function cut(t) { return t >= CUT_ON && t < CUT_BACK; }

function dirt(t) {
    if (t < 4.0)
        return 0.15;
    var k = clamp01((t - 4.0) / 1.5);
    return 0.15 + 0.75 * k * k * (3 - 2 * k);
}

// el nivel de los últimos 70 ms (`pump` de Crt.qml, sin la sección)
function pump(t) {
    if (t >= 3.30 && t < CUT_BACK)
        return 0.03;
    return 0.55 + 0.35 * beatPulse(t);
}
