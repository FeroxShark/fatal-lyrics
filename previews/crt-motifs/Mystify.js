// fatal-lyrics — mystify: las dos cuentas del corte seco.
//
// Funciones PURAS de estampas de reloj (nada de Animation ni Behavior: el banco
// offscreen exige que cada cuadro salga del reloj y de las estampas). `Mystify.qml`
// guarda cuándo llegó el corte y cuándo volvió la música y llama acá; los tests las
// corren con node. Ambas terminan EXACTO en 0 (no en una cola exponencial), así el
// loop del banco cierra con costura 0.
.pragma library

function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }
function prog(t, t0, dur) { return dur <= 0 ? (t >= t0 ? 1 : 0) : clamp01((t - t0) / dur); }
// el snap de Motion.qml (OutExpo): llega rápido y se asienta a la vista
function outExpo(x) { return x >= 1 ? 1 : 1 - Math.pow(2, -10 * x); }

// Cuánto está "agarrado" el dibujo, 0..1. Sube con OutExpo en `inS` desde `cutAt` y, al
// volver la música (`backAt`), suelta con OutExpo en `outS`. Mientras el corte dura
// `backAt` vale 1e9 (todavía no volvió) y el factor de bajada es 1. Como es un
// producto, un corte más corto que `inS` suelta desde donde llegó, sin salto.
//   now, cutAt, backAt — el reloj del motivo (`clock`, s)
function hold(now, cutAt, backAt, inS, outS) {
    return outExpo(prog(now, cutAt, inS)) * (1 - outExpo(prog(now, backAt, outS)));
}

// Cuánto se atrasó la fase del dibujo mientras estuvo quieto, en segundos de fase, 0..cap.
// `phase` es la fase MONÓTONA (`clock + movOff`: no da la vuelta a los 15 s, así la
// resta nunca se va por el camino largo de la vuelta). `freezeAt`/`thawAt` son esa
// misma fase al llegar y al volver el corte (`thawAt` = 1e9 mientras dura). `cap`
// acota el atraso: un "corte" que en realidad es una pausa no puede dejar al
// polígono medio minuto atrás y hacerlo volar al volver.
function lag(phase, freezeAt, thawAt, cap) {
    return Math.min(Math.max(0, Math.min(phase, thawAt) - freezeAt), cap);
}
