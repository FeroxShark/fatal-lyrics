// fatal-lyrics — la reacción del vidrio a las señales finas del audio (tanda 8).
//
// Tres canales, cada uno en un EJE distinto del golpe del bajo (que es brillo:
// `pulse` levanta la pantalla entera):
//   - corte seco (`cut`/`cutf` del daemon): la luz del tubo baja mientras el tema
//     se calla y vuelve de un golpe, con la fuerza con que volvió la música;
//   - agudos (`hf`, flujo espectral 125-6000 Hz): el barrido de las filas tiembla
//     de costado, fino, y los claros se enfrían — POSICIÓN y COLOR, no brillo;
//   - suciedad (`dirt`): la estática deja de ser ruido blanco quieto y pasa a
//     tener bandas que corren, deriva de costado y rayas horizontales.
//
// Todo es función PURA del reloj del tubo (`tubeTime`, en segundos), sin
// Animation ni Behavior: `Crt.qml` y el banco offscreen (`previews/reaccion/`)
// llaman a ESTAS funciones, así la hoja comparativa muestra el mapeo que corre
// en el overlay y no una copia. Duraciones: las de `Motion.qml` (se pasan como
// argumento para no importar un singleton desde un `.pragma library`).
.pragma library

function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }

// Cuánto se apaga el tubo durante un corte, 0..depth.
//   now, cutAt — reloj del tubo y el momento en que llegó `cut=1` (s)
//   on         — el corte sigue (el daemon lo sostiene hasta que vuelve el nivel)
//   depth      — cuánto baja la luz (`crtPaceTable.cutDepth`)
//   outMs      — la bajada: es algo que se va, así que `Motion.exitMs` con InQuad
//   holdMs     — el tope: un "corte" más largo que esto es una pausa, no un corte
//                seco (los medidos son de 150-400 ms). Pasado el tope la luz
//                vuelve sola en `backMs`, y el tubo no queda a media luz toda la
//                pausa (de eso se ocupa `resting`, con su propio reloj).
//   backMs     — `Motion.levelMs`
function cutDim(now, cutAt, on, depth, outMs, holdMs, backMs) {
    if (!on || depth <= 0)
        return 0;
    const age = (now - cutAt) * 1000;
    if (age < 0)
        return 0;
    const down = clamp01(age / Math.max(outMs, 1));
    let v = depth * down * down;
    if (age > holdMs) {
        const up = clamp01((age - holdMs) / Math.max(backMs, 1));
        v *= (1 - up) * (1 - up);   // 1 - OutQuad: de vuelta a 0
    }
    return v;
}

// El golpe de vuelta: un fogonazo que arranca en `force * amt` y se apaga con
// OutQuad en `durMs`. Es el mismo molde que `beatAnim` (un golpe), pero dura lo
// que dura una ENTRADA (`Motion.enterMs`): lo que vuelve, entra.
function backFlash(now, backAt, force, amt, durMs) {
    if (force <= 0 || amt <= 0 || backAt < 0)
        return 0;
    const age = (now - backAt) * 1000;
    if (age < 0 || age >= durMs)
        return 0;
    const p = age / durMs;
    return force * amt * (1 - p) * (1 - p);   // 1 - OutQuad
}

// Los agudos: `hf` ya viene suavizado del daemon (sube en ~50 ms, baja en ~400),
// así que acá sólo se le da forma. Una curva que deja pasar poco de lo bajo: el
// flujo de agudos de fondo (hi-hats parejos) no tiene que tener el tubo
// temblando todo el tema — sólo lo que ENTRA arriba.
function fizz(hf, amt) {
    const x = clamp01((hf - 0.12) / 0.88);
    return amt * x * x * (3 - 2 * x);
}

// La suciedad que MUEVE el grano (estructura, no cantidad: la cantidad sigue
// siendo `noiseAmt` × `crtDirtMult`). `pump` es el nivel de los últimos 70 ms:
// con el mismo `dirt`, un pasaje fuerte hace correr el grano más que uno bajo,
// y eso es lo que el `dirt` solo (suavizado ~1.5 s en el daemon) no podía dar.
function grain(dirt, pump, move) {
    return clamp01(dirt) * move * (0.55 + 0.45 * clamp01(pump));
}

// La fase de las franjas del grano, ACUMULADA: la velocidad depende de `grain`, y
// `t·velocidad(grain)` en el shader salta cada vez que `grain` se mueve (con `t` en
// cientos de segundos, un cambio de 0.01 corre las franjas media pantalla de golpe:
// el banco lo mostró como un zigzag). Se suma de a `dt` y se envuelve en 64
// vueltas (el shader la usa entera para la deriva de las rayas).
function grainSpeed(g) { return 0.35 + 0.9 * g; }   // franjas por segundo
function grainAdvance(phase, dt, g) {
    if (dt <= 0 || dt > 0.5)
        return phase;          // un salto del reloj (pausa, reinicio) no corre las franjas
    const p = phase + dt * grainSpeed(g);
    return p >= 64 ? p - 64 : p;
}
