// fatal-lyrics showreel — el audio de mentira.
//
// Publica EXACTAMENTE los nombres que `root` tiene en shell/shell.qml
// (audLevel, audLo/Mid/Hi, audBeat, audPeak, bpm, lastBeatAt, wave) con la
// misma forma, pero calculados de la partitura de Timeline.js en vez de venir
// del socket. Por eso los módulos, al integrarse, se bindean a `root` sin
// cambiar una línea: `audio: root`.
//
// Unidades: acá lastBeatAt está en SEGUNDOS del reel. En shell.qml es ms de
// reloj; los módulos sólo usan la diferencia (now - lastBeatAt), así que al
// integrar alcanza con pasarles `now` en la misma unidad.
import QtQuick
import "Ease.js" as E
import "Timeline.js" as TL

QtObject {
    id: a

    property real t: 0

    readonly property var ev: TL.allEvents()

    // ---- lo que publica, con los nombres de root -----------------------
    readonly property real bpm: TL.BPM
    readonly property real lastBeatAt: lastOf(beats, t)
    readonly property int audBeat: countUpTo(beats, t)
    readonly property int audPeak: countUpTo(ev.impacts, t)
    readonly property real lastPeakAt: lastOf(ev.impacts, t)
    readonly property real audLo: bands[0]
    readonly property real audMid: bands[1]
    readonly property real audHi: bands[2]
    readonly property real audLevel: level
    readonly property var wave: waveAt(t)

    // extras que el daemon real NO manda (sólo para el preview): se derivan
    // de lo de arriba, nunca los usa un módulo que se vaya a integrar
    readonly property real riser: E.smoothstep(TL.ROLL_AT, TL.GAP_AT, t) * (t < TL.GAP_AT ? 1 : 0)
    readonly property bool gap: t >= TL.GAP_AT && t < TL.DROP_AT

    // ---- internos -------------------------------------------------------
    readonly property var beats: mergeSorted(ev.kicks, ev.snares)

    readonly property real kickEnv: env(ev.kicks, t, 0.16)
    readonly property real snareEnv: env(ev.snares, t, 0.09)
    readonly property real hatEnv: env(ev.hats, t, 0.04)
    readonly property real impactEnv: env(ev.impacts, t, 0.6)
    readonly property real keyEnv: env(ev.keys, t, 0.03)

    // la cama: sube con el cascade, se abre con el build, explota en el drop
    readonly property real bed: {
        if (t < TL.b(4)) return 0.05 + 0.1 * E.smoothstep(0.3, TL.b(4), t);
        if (t < TL.GAP_AT) return 0.28 + 0.2 * E.smoothstep(TL.b(16), TL.GAP_AT, t);
        if (t < TL.DROP_AT) return 0.02;
        if (t < TL.b(29)) return 0.55;
        return 0.35 * E.decay(t, TL.b(29), 0.5);
    }

    readonly property real level: E.clamp01(bed + 0.55 * kickEnv + 0.35 * snareEnv + 0.1 * hatEnv
                                           + 0.4 * impactEnv + 0.25 * riser + 0.15 * keyEnv)

    // fracción de energía por banda (suman ~1, como las 6 bandas del daemon)
    readonly property var bands: {
        const lo = 0.15 + 1.2 * kickEnv + 0.5 * impactEnv + (t >= TL.DROP_AT && t < TL.b(29) ? 0.4 : 0);
        const mid = 0.2 + 0.9 * snareEnv + 0.3 * riser + 0.2 * keyEnv;
        const hi = 0.1 + 0.8 * hatEnv + 0.9 * riser + 0.4 * snareEnv + 0.5 * keyEnv;
        const s = lo + mid + hi;
        return [lo / s, mid / s, hi / s];
    }

    function mergeSorted(x, y) {
        const out = x.concat(y);
        out.sort((p, q) => p - q);
        return out;
    }
    // último evento <= tt (o -1e9 si no hubo)
    function lastOf(arr, tt) {
        let lo = 0, hi = arr.length - 1, best = -1e9;
        while (lo <= hi) {
            const m = (lo + hi) >> 1;
            if (arr[m] <= tt) { best = arr[m]; lo = m + 1; } else hi = m - 1;
        }
        return best;
    }
    function countUpTo(arr, tt) {
        let n = 0;
        for (let i = 0; i < arr.length; i++) if (arr[i] <= tt) n++;
        return n;
    }
    function env(arr, tt, tau) {
        const l = lastOf(arr, tt);
        return l < -1e8 ? 0 : Math.exp(-(tt - l) / tau);
    }

    // 64+64 enteros en [-127,127], como el evento `wave`: una fundamental que
    // sigue al bombo (baja de tono en el golpe, como un 808) + armónicos que
    // abre el redoble. L y R se desfasan: el scope dibuja Lissajous.
    function waveAt(tt) {
        const l = [], r = [];
        const amp = 127 * E.clamp01(0.15 + level * 0.9);
        const kAge = tt - lastOf(ev.kicks, tt);
        const f0 = 2 + 5 * Math.exp(-kAge / 0.05);
        const harm = 0.25 + riser * 0.8 + snareEnv * 0.5;
        const ph = tt * 9;
        for (let i = 0; i < 64; i++) {
            const x = i / 64 * Math.PI * 2;
            const v1 = Math.sin(x * f0 + ph) + harm * Math.sin(x * f0 * 3.01 + ph * 1.7) * 0.5
                     + snareEnv * (E.hash2(i, Math.floor(tt * 60)) * 2 - 1) * 0.6;
            const v2 = Math.sin(x * f0 * 1.5 + ph + 1.3) + harm * Math.cos(x * f0 * 2.02 + ph) * 0.5
                     + snareEnv * (E.hash2(i + 99, Math.floor(tt * 60)) * 2 - 1) * 0.6;
            l.push(Math.round(E.clamp(v1 * amp * 0.6, -127, 127)));
            r.push(Math.round(E.clamp(v2 * amp * 0.6, -127, 127)));
        }
        return { l: l, r: r };
    }
}
