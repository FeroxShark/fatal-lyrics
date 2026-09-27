// fatal-lyrics showreel — el montaje: 6 módulos en la grilla de 128 BPM,
// el HUD del reel y el vidrio (post.frag) encima de todo.
//
// `t` es la ÚNICA entrada. render.py la avanza cuadro a cuadro; no hay ni
// un Timer ni una Animation en todo el árbol.
import QtQuick
import "Ease.js" as E
import "Timeline.js" as TL

Item {
    id: reel
    width: 1920
    height: 1080

    property real t: 0
    property string solo: ""          // key de un segmento: los demás no se dibujan
    property bool hud: true
    property bool glass: true
    readonly property string eventsJson: JSON.stringify(TL.allEvents())
    readonly property string segmentsJson: JSON.stringify(TL.SEGMENTS)

    FontLoader { id: fVt; source: "../../shell/fonts/VT323-Regular.ttf" }
    FontLoader { id: fPress; source: "../../shell/fonts/PressStart2P-Regular.ttf" }
    FontLoader { id: fShare; source: "../../shell/fonts/ShareTechMono-Regular.ttf" }

    SyntheticAudio { id: aud; t: reel.t }

    Item {
        id: content
        anchors.fill: parent

        Rectangle { anchors.fill: parent; color: "#000000" }

        Repeater {
            model: TL.SEGMENTS
            Loader {
                id: ld
                required property var modelData
                readonly property bool inside: reel.t >= modelData.t0 && reel.t < modelData.t1
                anchors.fill: parent
                active: (reel.solo === "" || reel.solo === modelData.key)
                        && reel.t > modelData.t0 - 0.25 && reel.t < modelData.t1 + 0.05
                visible: inside
                source: "modules/" + modelData.mod + ".qml"
                onLoaded: {
                    item.audio = aud;
                    item.t = Qt.binding(() => reel.t);
                    if (item.hasOwnProperty("mono")) item.mono = fVt.name;
                    if (item.hasOwnProperty("pixel")) item.pixel = fPress.name;
                    if (item.hasOwnProperty("tech")) item.tech = fShare.name;
                }
            }
        }

        Hud {
            anchors.fill: parent
            visible: reel.hud
            t: reel.t
            audio: aud
            mono: fShare.name
        }
    }

    // ---- el vidrio --------------------------------------------------------
    ShaderEffectSource {
        id: src
        sourceItem: content
        hideSource: reel.glass
        live: true
        visible: false
    }

    // puentes: 2 cuadros antes y 5 después de cada corte, el glitch pega fuerte
    function bridge(tt) {
        let g = 0;
        // el "Aceptar" del final también es un corte: suelta el botón y rompe
        const rel = 14.44;
        if (tt >= rel && tt < rel + 6 / 60) g = 1 - E.prog(tt, rel, 6 / 60) * 0.5;
        for (let i = 1; i < TL.SEGMENTS.length; i++) {
            const c = TL.SEGMENTS[i].t0;
            if (tt >= c - 2 / 60 && tt < c + 5 / 60) g = Math.max(g, 1 - E.prog(tt, c, 5 / 60) * 0.6);
        }
        return g;
    }
    // tubo: prende en el boot (punto → raya → imagen), se apaga al final
    readonly property var tube: {
        const tt = reel.t;
        if (tt < 0.36) {
            const dot = E.prog(tt, 0.0, 0.08);
            const hx = E.outExpo(E.prog(tt, 0.08, 0.12));
            const hy = E.outExpo(E.prog(tt, 0.2, 0.16));
            return { x: E.mix(0.002, 1, hx), y: E.mix(0.0025, 1, hy), glow: dot * (1 - hy) * 1.4 };
        }
        const off0 = TL.LENGTH - 0.42;
        if (tt >= off0) {
            const vy = E.inQuad(E.prog(tt, off0, 0.13));
            const hx = E.inQuad(E.prog(tt, off0 + 0.13, 0.14));
            const fade = E.prog(tt, off0 + 0.27, 0.13);
            return { x: E.mix(1, 0.002, hx), y: E.mix(1, 0.0025, vy), glow: Math.min(1, vy * 3) * (1 - fade) * 1.3 };
        }
        return { x: 1, y: 1, glow: 0 };
    }
    readonly property real buildGlitch: {
        const b = TL.segment("build");
        if (reel.t < TL.ROLL_AT || reel.t >= TL.GAP_AT) return 0;
        return 0.05 + 0.45 * E.inCubic(E.prog(reel.t, TL.ROLL_AT, TL.GAP_AT - TL.ROLL_AT)) * (0.4 + 0.6 * aud.snareEnv);
    }

    ShaderEffect {
        anchors.fill: parent
        visible: reel.glass
        property variant source: src
        property real time: reel.t
        property real seed: Math.floor(reel.t * 60) % 97 / 97
        property real glitch: Math.max(reel.bridge(reel.t), reel.buildGlitch)
        property real chroma: 1.2 + 5 * aud.snareEnv + 12 * aud.impactEnv * (reel.t > 11 ? 1 : 0.3)
        property real flash: {
            const tt = reel.t;
            if (tt >= TL.DROP_AT && tt < TL.DROP_AT + 2 / 60) return 1;
            if (tt >= TL.b(29) && tt < TL.b(29) + 1 / 60) return 0.85;
            return 0;
        }
        property real invert: {
            const tt = reel.t;
            if (tt >= TL.DROP_AT + 2 / 60 && tt < TL.DROP_AT + 5 / 60) return 1;
            for (const bb of [26, 28]) if (tt >= TL.b(bb) && tt < TL.b(bb) + 1 / 60) return 1;
            return 0;
        }
        property real curve: 0.07 + (reel.t >= TL.DROP_AT && reel.t < TL.b(29) ? 0.08 * aud.kickEnv : 0)
        property real scan: 0.14
        property real grain: 0.045
        property real tubeX: reel.tube.x
        property real tubeY: reel.tube.y
        property real glow: reel.tube.glow
        property size res: Qt.size(width, height)
        fragmentShader: "post.frag.qsb"
    }
}
