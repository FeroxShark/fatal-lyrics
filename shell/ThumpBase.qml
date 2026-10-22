// fatal-lyrics motivos CRT — lo que suman los tres motivos de golpe físico
// (`membrana`, `cintas`, `giroscopio`, integrados 2026-10-19) sobre MotifBase.
//   · `thump`/`thumpAmt` — contador de golpes del BOMBO (cada vez que sube, un
//     golpe) y su fuerza 0..1. En el overlay: `bassGen` de shell.qml (el `k` del
//     daemon, o `b` si no llega; un `rise` también lo sube, más flojo) y
//     `kickThump` × la perilla `flicker`.
//   · `mov` (0..1: la densidad, `crtDensity` = `audMov` + `audNov`) y el tempo
//     (`beatMs`) arman la densidad (`dens`) y la física (`phys`).
//   · CARÁCTER (`temper`): con `character` >= 0 (`crtCharacter` del overlay: `char`
//     del daemon o BPM + mood) es ése, suavizado 1.5 s (un cambio de tema o de
//     compás no cambia la física con un golpe en el aire). Con -1 (el banco de
//     previews, que no tiene `crtCharacter`) sale de BPM + `valence`/`moodEnergy`.
//   · `hat` (0..1, `hatLevel`: el hi-hat `ht`, o los agudos `audHf` si no llega)
//     son los agudos; con -1 se usa `hf`.
//   · `hitT/hitA/hitS` — los últimos 4 golpes (reloj, fuerza, semilla): los
//     shaders los reciben como vec4 y evalúan la respuesta del resorte por píxel
//     (ondas que viajan: la edad cambia con la distancia).
//   · `dens` — la canción llena (energía + movimiento), suavizada: sube en 0.7 s,
//     baja en 2.5 s (llenarse es un evento, vaciarse es un desvanecer).
//   · `drift` — fase ACUMULADA de la deriva de fondo (nunca `clock × velocidad`:
//     la trampa del hiperespacio). Avanza siempre, también en silencio: ninguna
//     pantalla queda quieta.
import QtQuick
import "Ease.js" as E
import "Thump.js" as T
import "React.js" as React

MotifBase {
    id: tb

    property int thump: 0
    property real thumpAmt: 1
    property real mov: 0.35
    property real valence: 0.5
    property real moodEnergy: 0.5
    property real character: -1
    property real hat: -1

    readonly property real bpm: 60000 / Math.max(beatMs, 1)
    readonly property real temperTarget: character >= 0 ? E.clamp01(character)
                                                         : T.temper(bpm, moodEnergy, valence)
    property real temperSmooth: -1
    readonly property real temper: (character < 0 || temperSmooth < 0) ? temperTarget : temperSmooth
    readonly property var phys: T.params(temper, valence, bpm)
    // agudos con la curva del vidrio (sólo lo que ENTRA arriba, no el hi-hat parejo)
    readonly property real fizz: Math.max(React.fizz(hat >= 0 ? hat : hf, 1), 0.8 * E.clamp01((high - 0.15) / 0.6))

    property var hitT: [-1e6, -1e6, -1e6, -1e6]
    property var hitA: [0, 0, 0, 0]
    property var hitS: [0, 0, 0, 0]
    property int hitN: 0
    // el valor con que nació el motivo (el contador del overlay ya viene acumulado): no es un golpe
    property int thumpSeen: -1
    Component.onCompleted: thumpSeen = thump
    onThumpChanged: {
        if (thumpSeen < 0)
            return;
        const t = hitT.slice(1), a = hitA.slice(1), s = hitS.slice(1);
        t.push(wallNow());
        a.push(E.clamp01(thumpAmt) * phys.gain);
        // en pared, la semilla sale del contador del overlay: `hitN` es de cada instancia, y
        // una pantalla que entró tarde lo tiene corrido
        s.push(E.hash((wallShared ? thump : hitN) * 7.31 + seed * 13.0));
        hitT = t; hitA = a; hitS = s;
        hitN++;
    }
    // edades de los 4 golpes (el más viejo primero), para los shaders
    // (en pared el golpe se anota con la hora de la pared, que puede ir un cuadro delante de `clock`)
    readonly property vector4d hitAge: Qt.vector4d(Math.max(0, clock - hitT[0]), Math.max(0, clock - hitT[1]),
                                                   Math.max(0, clock - hitT[2]), Math.max(0, clock - hitT[3]))
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
            if (tb.wallShared) {
                tb.wallThump();
                return;
            }
            const dt = tb.clock - tb.lastClock;
            tb.lastClock = tb.clock;
            if (!(dt > 0) || dt > 0.5)
                return;
            tb.dens = T.follow(tb.dens, tb.densTarget, dt, 0.7, 2.5);
            if (tb.character >= 0) {
                // se asienta y se queda: seguir aproximando para siempre recalcularía `phys` en cada cuadro
                const tt = tb.temperTarget, cur = tb.temperSmooth < 0 ? tt : tb.temperSmooth;
                tb.temperSmooth = Math.abs(tt - cur) < 0.003 ? tt : T.follow(cur, tt, dt, 1.5, 1.5);
            }
            tb.drift += dt * tb.phys.drift * (0.75 + 0.6 * tb.dens);
        }
    }
    // PARED (MotifBase): la misma cuenta de arriba, pero sobre el objeto que comparten todas las
    // instancias — la primera que corre en el cuadro avanza, las demás leen. Así la deriva y la
    // densidad son UNA para el lienzo entero, también en la pantalla que se suma tarde.
    function wallThump() {
        const S = wall.share;
        if (S.dAt === undefined) {
            S.dAt = clock;
            S.dens = 0;
            S.drift = 0;
            S.temper = -1;
        }
        const dt = clock - S.dAt;
        if (dt > 0) {
            S.dAt = clock;
            if (dt <= 0.5) {
                S.dens = T.follow(S.dens, densTarget, dt, 0.7, 2.5);
                if (character >= 0) {
                    const tt = temperTarget, cur = S.temper < 0 ? tt : S.temper;
                    S.temper = Math.abs(tt - cur) < 0.003 ? tt : T.follow(cur, tt, dt, 1.5, 1.5);
                }
                S.drift += dt * phys.drift * (0.75 + 0.6 * S.dens);
            }
        }
        dens = S.dens;
        drift = S.drift;
        if (character >= 0 && S.temper >= 0)
            temperSmooth = S.temper;
    }
}
