// fatal-lyrics — la velocidad de los dibujos sigue cómo se mueve la música AHORA
// (tanda 8, slice "movimiento", parte visual).
//
// `pace` (`crtPaceTable`) sigue siendo la base del tema; `mov` (evento `aud`, 0..1,
// ya suavizado del lado del daemon: sube en ~0.25 s, baja en ~0.7 s) empuja el RITMO
// de los dibujos alrededor de 1: más lento en un pasaje quieto, más rápido en uno
// nervioso, dentro de un rango acotado por fila (`movMin`/`movMax`). Encima de eso el
// GOLPE fuerte da un empujón que decae en medio segundo (`kick*`, más abajo).
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

// Dónde `mov` deja el ritmo en 1 SIN historial del tema (los primeros segundos: con
// historial el pivote es la mediana, ver `fit`). No es 0.5: un tema fuerte y PAREJO da
// `mov` ≈ 0.2 (el techo de la energía sola, docs/tanda8-estado/movimiento.md), y desde
// la ronda 3 (densidad sin saturar) la música con pulso ronda 0.6-0.7 y un final que se
// calma 0.2-0.3.
var PIVOT = 0.45;

function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }

// El multiplicador de ritmo, lineal a trozos:
//   mov 0      → lo  (`movMin` de la fila de `pace`)
//   mov PIVOT  → 1
//   mov 1      → hi  (`movMax`)
// `amount` (perilla `crt.mov_speed`, 0..1) escala la desviación desde 1: 0 = apagado.
function rate(mov, lo, hi, amount, pivot) {
    const m = clamp01(mov);
    const pv = pivot > 0 && pivot < 1 ? pivot : PIVOT;
    const r = m < pv
        ? lo + (1 - lo) * (m / pv)
        : 1 + (hi - 1) * ((m - pv) / (1 - pv));
    const a = amount > 0 ? amount : 0;
    return 1 + (r - 1) * a;
}

// ---- percentiles del TEMA. `mov` real vive en una franja angosta y SESGADA: música con
// pulso 0.55-0.70 casi todo el tiempo y de golpe un final que se calma a 0.2-0.3
// (ronda 3, docs/NUMEROS-MEDIDOS.md). Un estirado lineal de p5..p95 deja la mediana bien
// arriba del medio: el tema "corre" todo el tiempo y sólo las caídas se notan. Por eso el
// mapa pasa por TRES percentiles: P_LO → 0, la MEDIANA → 0.5 (ritmo 1) y P_HI → 1, cada
// mitad estirada por su lado. Así un tema sesgado igual da ritmo 1 en su parte habitual, y
// P_LO/P_HI (10/90 y no 5/95) son el 10 % del tiempo pegado a `movMin`/`movMax`: los
// extremos SE USAN. Se guarda un histograma de `mov` del tema (decae con STAT_TAU_S).
var STAT_BINS = 40;
var STAT_TAU_S = 60;      // el tema "olvida" lento: la parte de hace 2 min pesa 13%
var STAT_WARM = 10;       // masa (s) para confiar del todo en los percentiles
var MIN_HALF = 0.10;      // cada mitad de la franja mide al menos esto: un tema parejo no amplifica ruido
var P_LO = 0.10;
var P_HI = 0.90;

function newStat() {
    const h = [];
    for (let i = 0; i < STAT_BINS; i++) h.push(0);
    return { h: h, mass: 0 };
}

// `dt` s reales con `mov` vigente. Un `dt` raro no suma (mismo criterio que `advance`).
function observe(st, mov, dt) {
    if (!(dt > 0) || dt > 0.5)
        return st;
    const k = Math.exp(-dt / STAT_TAU_S);
    for (let i = 0; i < STAT_BINS; i++) st.h[i] *= k;
    const b = Math.min(STAT_BINS - 1, Math.floor(clamp01(mov) * STAT_BINS));
    st.h[b] += dt;
    st.mass = st.mass * k + dt;
    return st;
}

function percentile(st, p) {
    if (!(st.mass > 0)) return 0.5;
    const target = st.mass * p;
    let acc = 0;
    for (let i = 0; i < STAT_BINS; i++) {
        const c = st.h[i];
        if (acc + c >= target)
            return (i + (c > 0 ? (target - acc) / c : 0.5)) / STAT_BINS;
        acc += c;
    }
    return 1;
}

// {lo, mid, hi, conf}: P_LO, la mediana y P_HI (cada mitad ya ensanchada a MIN_HALF) y
// cuánto confiar en ellos (0..1).
function span(st) {
    const mid = percentile(st, 0.5);
    return {
        lo: Math.min(percentile(st, P_LO), mid - MIN_HALF),
        mid: mid,
        hi: Math.max(percentile(st, P_HI), mid + MIN_HALF),
        conf: clamp01(st.mass / STAT_WARM)
    };
}

// `mov` reescalado al tema: 0.5 = su mediana. Con `conf` 0 vale `mov` tal cual (mapeo
// absoluto de siempre, pivote PIVOT); con 1 es el mapa por cuantiles con el pivote en 0.5.
function fit(mov, sp) {
    const m = clamp01(mov);
    const nm = m < sp.mid
        ? 0.5 * clamp01((m - sp.lo) / (sp.mid - sp.lo))
        : 0.5 + 0.5 * clamp01((m - sp.mid) / (sp.hi - sp.mid));
    return {
        mov: m + (nm - m) * sp.conf,
        pivot: PIVOT + (0.5 - PIVOT) * sp.conf
    };
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

// ---- el golpe empuja la velocidad (ronda 3: "más sensible al ritmo") ----
// Cada golpe (`b` del evento `aud`; `h`, el que sobresale mucho, pesa más) le suma al
// ritmo un empujón que decae en KICK_S. Sigue siendo VELOCIDAD, no posición: el empujón
// entra en el `rate` que después integra `advance`, así que un golpe acelera el dibujo un
// instante y nunca lo teletransporta. Multiplica (`push`): pesa igual sobre un pasaje
// quieto (0.4x) que sobre uno nervioso (2x). Con `amount` (crt.mov_speed) en 0 no queda
// nada. La amplitud (`movKick`) vive en `crtPaceTable`, por fila.
var KICK_S = 0.42;          // lo que dura el empujón (= Motion.levelMs, OutQuad)
var KICK_HARD = 1.0;        // fuerza de un golpe que sobresale (`h`)
var KICK_SOFT = 0.4;        // fuerza de un golpe común (`b`)
var KICK_CAP = 1.5;         // golpes encimados: el empujón nunca pasa de KICK_CAP · amp

// Cuánto pesa un golpe: `hard` (el `h` del evento `aud`, el que sobresale) o uno común.
function kickStrength(hard) { return hard ? KICK_HARD : KICK_SOFT; }

// El empujón `k0` que arrancó hace `elapsed` s: OutQuad hasta 0, como una
// NumberAnimation con Easing.OutQuad. La función de tiempo es pura: la llaman el overlay
// (`shell.qml`) y el banco offscreen.
function kickAt(k0, elapsed) {
    if (!(k0 > 0) || !(elapsed >= 0) || elapsed >= KICK_S)
        return 0;
    const r = 1 - elapsed / KICK_S;
    return k0 * r * r;
}

// Un golpe nuevo `strength` (KICK_HARD/KICK_SOFT) encima del empujón que todavía queda
// (`cur`), con la amplitud `amp` de la fila. Devuelve el empujón que arranca AHORA.
function kickAdd(cur, strength, amp) {
    if (!(amp > 0) || !(strength > 0))
        return cur > 0 ? cur : 0;
    return Math.min((cur > 0 ? cur : 0) + strength * amp, KICK_CAP * amp);
}

// `base` (el ritmo por `mov`) con el empujón encima. `amount` (perilla) 0 = ritmo 1.
function push(base, kick, amount) {
    const a = amount > 0 ? amount : 0;
    return base * (1 + (kick > 0 ? kick : 0) * a);
}
