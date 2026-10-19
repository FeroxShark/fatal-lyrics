// fatal-lyrics motivos CRT (testeo 2026-10-19) — lo que suman los tres motivos
// del testeo (`membrana`, `cintas`, `giroscopio`) sobre MotifBase.
//
// MotifBase es copia de shell/ (lo pisa `sync-shell.sh`): lo nuevo vive acá.
//   · `thump`/`thumpAmt` — contador de golpes del BOMBO (cada vez que sube, un
//     golpe) y su fuerza 0..1. En el overlay todavía no existe con ese nombre: al
//     integrar se ata al detector de bombo que salga del frente "golpe de bajo".
//   · `mov` (0..1, el `audMov` del daemon), `valence`/`moodEnergy` (evento `mood`)
//     y el tempo (`beatMs`) arman el CARÁCTER (`temper`) y la física (`phys`).
//   · `hitT/hitA/hitS` — los últimos 4 golpes (reloj, fuerza, semilla): los
//     shaders los reciben como vec4 y evalúan la respuesta del resorte por píxel
//     (ondas que viajan: la edad cambia con la distancia).
//   · `dens` — la canción llena (energía + movimiento), suavizada: sube en 0.7 s,
//     baja en 2.5 s (llenarse es un evento, vaciarse es un desvanecer).
//   · `drift` — fase ACUMULADA de la deriva de fondo (nunca `clock × velocidad`:
//     la trampa del hiperespacio). Avanza siempre, también en silencio: ninguna
//     pantalla queda quieta.
import QtQuick
import "../Ease.js" as E
import "../Thump.js" as T
import "../React.js" as React

MotifBase {
    id: tb

    property int thump: 0
    property real thumpAmt: 1
    property real mov: 0.35
    property real valence: 0.5
    property real moodEnergy: 0.5

    readonly property real bpm: 60000 / Math.max(beatMs, 1)
    readonly property real temper: T.temper(bpm, moodEnergy, valence)
    readonly property var phys: T.params(temper, valence, bpm)
    // agudos con la curva del vidrio (sólo lo que ENTRA arriba, no el hi-hat parejo)
    readonly property real fizz: Math.max(React.fizz(hf, 1), 0.8 * E.clamp01((high - 0.15) / 0.6))

    property var hitT: [-1e6, -1e6, -1e6, -1e6]
    property var hitA: [0, 0, 0, 0]
    property var hitS: [0, 0, 0, 0]
    property int hitN: 0
    // el primer cambio es el binding que llega con el valor acumulado: no es un golpe
    property bool armed: false
    onThumpChanged: {
        if (!armed) {
            armed = true;
            return;
        }
        const t = hitT.slice(1), a = hitA.slice(1), s = hitS.slice(1);
        t.push(clock);
        a.push(E.clamp01(thumpAmt) * phys.gain);
        s.push(E.hash(hitN * 7.31 + seed * 13.0));
        hitT = t; hitA = a; hitS = s;
        hitN++;
    }
    // edades de los 4 golpes (el más viejo primero), para los shaders
    readonly property vector4d hitAge: Qt.vector4d(clock - hitT[0], clock - hitT[1], clock - hitT[2], clock - hitT[3])
    readonly property vector4d hitAmp: Qt.vector4d(hitA[0], hitA[1], hitA[2], hitA[3])
    readonly property vector4d hitSeed: Qt.vector4d(hitS[0], hitS[1], hitS[2], hitS[3])
    // la física para el shader: (w, wd, zeta·w, 1/rise) y la normalización
    readonly property vector4d physV: Qt.vector4d(phys.w, phys.wd, phys.zeta * phys.w, 1 / phys.rise)
    readonly property real physN: phys.norm

    property real dens: 0
    property real drift: 0
    property real lastClock: -1e9
    readonly property real densTarget: E.clamp01(0.55 * E.clamp01((energy - 0.9) / 0.7) + 0.45 * mov
                                                 + (drop ? 0.15 : 0))
    Connections {
        target: tb
        function onClockChanged() {
            const dt = tb.clock - tb.lastClock;
            tb.lastClock = tb.clock;
            if (!(dt > 0) || dt > 0.5)
                return;
            tb.dens = T.follow(tb.dens, tb.densTarget, dt, 0.7, 2.5);
            tb.drift += dt * tb.phys.drift * (0.75 + 0.6 * tb.dens);
        }
    }
}
