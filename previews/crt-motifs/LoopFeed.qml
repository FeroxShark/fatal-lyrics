// fatal-lyrics motivos CRT — lo que el root le pasaría a un Motif, sacado de `t`.
//
// Publica EXACTAMENTE los nombres que Crt.qml le asigna a `Motif` (y Motif a
// cada dibujo): un motivo que lee esto se integra copiándolo, sin renombrar
// nada. Todo es función de `t` (el tiempo del loop, 0..15, negativo durante el
// precalentamiento) y los envolventes miran los golpes del loop ANTERIOR y el
// SIGUIENTE, así el cuadro 0 lleva la cola del último golpe y el loop no pega
// un salto en la costura.
import QtQuick
import "Loop.js" as L
import "Ease.js" as E

QtObject {
    id: f
    property real t: 0

    readonly property real lt: E.wrap(t, L.LOOP)
    readonly property int lap: Math.floor(t / L.LOOP)
    // el reloj del tubo (tubeTime): lejos del cero, como en el overlay
    readonly property real clock: L.CLOCK0 + t

    readonly property var ev: L.events()

    // el último evento de `list` antes de `tt`, mirando también el loop anterior
    function since(list, tt) {
        let best = 1e9;
        for (let k = -1; k <= 0; k++)
            for (let i = 0; i < list.length; i++) {
                const d = tt - (list[i] + k * L.LOOP);
                if (d >= 0 && d < best) best = d;
            }
        return best;
    }
    function env(list, tau) { return Math.exp(-since(list, lt) / tau); }

    readonly property real kickEnv: env(ev.kicks, 0.11)
    readonly property real snareEnv: env(ev.snares, 0.07)
    readonly property real hatEnv: env(ev.hats, 0.03)
    readonly property real crashEnv: env(ev.crashes, 0.9)
    readonly property real riserAmt: lt >= ev.riser.t0 && lt < ev.riser.t1
        ? Math.pow((lt - ev.riser.t0) / (ev.riser.t1 - ev.riser.t0), 2) : 0
    readonly property bool dropOn: lt >= ev.drop.t0
    readonly property real bass: dropOn ? 1 - Math.exp(-since(ev.kicks, lt) / 0.09) : 0

    // ---- el contrato de Motif ---------------------------------------------
    readonly property string section: L.sectionAt(lt)
    readonly property bool drop: dropOn
    readonly property real energy: L.energyAt(lt)
    readonly property real level: E.clamp01(0.28 + 0.34 * kickEnv + 0.22 * snareEnv
        + 0.25 * riserAmt + 0.3 * bass * 0.6 + (dropOn ? 0.12 : 0))
    readonly property real low: E.clamp01(0.2 + 0.7 * kickEnv + 0.35 * bass)
    readonly property real high: E.clamp01(0.12 + 0.5 * hatEnv + 0.45 * snareEnv + 0.4 * riserAmt)
    readonly property real pitch: E.clamp01(0.35 + 0.4 * riserAmt + (dropOn ? 0.1 : 0))
    // contadores: suben en cada tiempo (tick, beat) y en cada compás (kick, el
    // golpe del tubo, que en el overlay pasa como mucho cada `hitGapMs`)
    readonly property int tick: Math.floor((clock + 1e-6) / L.BEAT)
    readonly property int beat: tick
    readonly property int kick: Math.floor((clock + 1e-6) / L.BAR)
    readonly property real beatMs: L.BEAT * 1000
    readonly property bool bpmLive: true
    // el empujón del golpe del tubo (Motif: 1 → 0 en 460 ms, OutQuad)
    readonly property real surge: {
        const p = E.wrap(clock, L.BAR) / 0.46;
        return p < 1 ? (1 - p) * (1 - p) : 0;
    }
    // el fogonazo del tubo (Crt.qml beatPulse: 40 % del tiempo, OutQuad)
    readonly property real beatPulse: {
        const p = E.wrap(clock, L.BEAT) / (0.4 * L.BEAT);
        return p < 1 ? (1 - p) * (1 - p) : 0;
    }
    readonly property int barNo: Math.floor(lt / L.BAR)
    readonly property string nextWord: L.WORDS[(barNo + 1) % L.WORDS.length]
    readonly property int lineNo: Math.floor(barNo / 2)
    readonly property var lines: L.LINES
    readonly property bool linesSynced: true

    // la forma de onda (64 + 64 en ±127): el bajo y el bombo por el izquierdo,
    // el mismo bajo corrido de fase por el derecho → una figura, no una diagonal
    readonly property var waveL: wave(0)
    readonly property var waveR: wave(1)
    function wave(ch) {
        const out = [];
        const f0 = dropOn ? 2 : 1;
        const ph = lt * 2 * Math.PI * (ch ? 0.5 : 0.25);
        const a = 40 + 70 * low;
        for (let i = 0; i < 64; i++) {
            const u = i / 64 * 2 * Math.PI;
            let v = a * Math.sin(u * f0 * (ch ? 3 : 2) + ph)
                + 25 * kickEnv * Math.sin(u * 5 + ch)
                + 14 * high * (E.hash(i * 3 + ch + Math.floor(lt * 60)) - 0.5);
            out.push(Math.round(E.clamp(v, -127, 127)));
        }
        return out;
    }
}
