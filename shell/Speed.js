// fatal-lyrics — la velocidad de los dibujos sigue cómo se mueve la música AHORA
// (tanda 8, slice "movimiento", parte visual).
//
// `pace` (`crtPaceTable`) sigue siendo la base del tema; `mov` (evento `aud`, 0..1,
// ya suavizado del lado del daemon: sube en ~1 s, baja en ~3 s) empuja el RITMO de
// los dibujos alrededor de 1: más lento en un pasaje quieto, más rápido en uno
// nervioso, dentro de un rango acotado por fila (`movMin`/`movMax`).
//
// La velocidad NO se aplica como `t · velocidad`: con `t` en cientos de segundos
// cualquier cambio de velocidad teletransporta el dibujo (TRAMPAS, tanda 8: el grano
// de `dirt`). Se ACUMULA un desplazamiento, `off += dt · (rate - 1)`, y el reloj de
// dibujo es `clock + off`. Con rate = 1 el desplazamiento no se mueve y todo queda
// bit a bit como antes; el reloj real (`clock`) no se toca, así que lo que mide
// tiempo de verdad (compás, golpes, entradas, el re-anclaje de `MotifBase`) no se
// entera.
//
// `Crt.qml`, `MotifBase.qml` y el banco offscreen (`previews/movimiento/`) llaman a
// ESTAS funciones: la hoja muestra el mapeo que corre en el overlay, no una copia.
.pragma library

// Dónde `mov` deja el ritmo en 1 (el de siempre). No es 0.5: un tema fuerte y
// PAREJO da `mov` ≈ 0.2 (el techo de la energía sola, docs/tanda8-estado/movimiento.md)
// y uno ocupado ≈ 0.75-0.8. Con el pivote al medio, cualquier tema sin mucho
// movimiento correría más lento que hoy de punta a punta.
var PIVOT = 0.35;

function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }

// El multiplicador de ritmo, lineal a trozos:
//   mov 0      → lo  (`movMin` de la fila de `pace`)
//   mov PIVOT  → 1
//   mov 1      → hi  (`movMax`)
// `amount` (perilla `crt.mov_speed`, 0..1) escala la desviación desde 1: 0 = apagado.
function rate(mov, lo, hi, amount) {
    const m = clamp01(mov);
    const r = m < PIVOT
        ? lo + (1 - lo) * (m / PIVOT)
        : 1 + (hi - 1) * ((m - PIVOT) / (1 - PIVOT));
    const a = amount > 0 ? amount : 0;
    return 1 + (r - 1) * a;
}

// Un paso del integrador: lo que se suma al desplazamiento en `dt` segundos reales.
// Un `dt` raro (negativo, o más de medio segundo: pausa, pantalla dormida, reinicio
// del reloj) no suma nada — mismo criterio que `React.grainAdvance`: si el reloj
// saltó, el dibujo no tiene por qué saltar además.
function advance(off, dt, r) {
    if (!(dt > 0) || dt > 0.5)
        return off;
    return off + dt * (r - 1);
}
