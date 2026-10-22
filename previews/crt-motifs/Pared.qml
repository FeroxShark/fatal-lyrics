// fatal-lyrics motivos CRT — banco de la PARED (`docs/PARED.md`): varias pantallas en sus
// posiciones reales, cada una con SU instancia del motivo (como un Crt.qml por pantalla), el
// mismo `share` y el mismo feed. `ref` dibuja el lienzo entero con UNA instancia: lo que se ve
// en cada pantalla tiene que ser el recorte de esa referencia (`pared.py` lo mide).
//
// Sin vidrio: lo que se mide es el dibujo. La cámara del tubo (`camS`) y el tirón del motivo
// (`zoom`) se aplican como en Crt.qml (Scale sobre `camOrigin`) para que la cuenta de
// `Wall.view` quede a prueba.
import QtQuick
import "Wall.js" as Wall
import "Ease.js" as E

Rectangle {
    id: pared
    color: "#000000"
    property real t: 0
    property string kind: "truchet"
    property string scheme: "ado"
    property var rects: [{ x: 0, y: 0, w: 1920, h: 1080 }]
    property int textIdx: -1          // la pantalla de la letra (-1: instrumental)
    property bool ref: false
    property real sc: 0.4             // px de la imagen por px lógico
    property real camS: 1
    property real zoom: 1
    readonly property var cv: Wall.canvas(rects)
    readonly property var pv: Wall.pivot(rects)
    width: Math.round(cv.w * sc)
    height: Math.round(cv.h * sc)
    // el estado compartido de la pared (en el overlay: `crtWallShare` del root)
    readonly property var share: ({})
    readonly property var schemes: ({
        dragons: { bg: "#170604", ink: "#ff8a2b", hot: "#ffe0b0" },
        ado: { bg: "#04162e", ink: "#7fe4ff", hot: "#ffffff" },
        poison: { bg: "#04120a", ink: "#9dff3d", hot: "#e8ffc4" },
        bloodline: { bg: "#12030a", ink: "#ff5c7a", hot: "#ffd6de" },
    })
    readonly property var pal: schemes[scheme] || schemes.ado
    // el foco en px de lienzo: la pantalla de la letra, o el medio del lienzo (`crtWallFocusTo`)
    readonly property point foco: textIdx >= 0 && textIdx < rects.length
        ? Qt.point(rects[textIdx].x - cv.x + rects[textIdx].w / 2, rects[textIdx].y - cv.y + rects[textIdx].h / 2)
        : Qt.point(cv.w / 2, cv.h / 2)

    LoopFeed { id: feed; t: pared.t }

    readonly property var contract: ["clock", "level", "low", "high", "pitch", "energy", "drop",
        "section", "tick", "beat", "kick", "beatMs", "bpmLive", "surge", "nextWord", "lineNo",
        "lines", "linesSynced", "waveL", "waveR", "cut", "hf",
        "thump", "thumpAmt", "mov", "valence", "moodEnergy"]

    Repeater {
        model: pared.ref ? 1 : pared.rects.length
        delegate: Item {
            id: slot
            required property int index
            readonly property var r: pared.ref ? { x: pared.cv.x, y: pared.cv.y, w: pared.cv.w, h: pared.cv.h }
                                               : pared.rects[index]
            readonly property bool isText: !pared.ref && index === pared.textIdx
            readonly property var o: Wall.local(r, pared.pv)
            // sin redondear: la referencia cae en el mismo medio píxel que la pantalla
            x: (r.x - pared.cv.x) * pared.sc
            y: (r.y - pared.cv.y) * pared.sc
            width: r.w * pared.sc
            height: r.h * pared.sc
            clip: true
            Item {
                width: slot.r.w
                height: slot.r.h
                transformOrigin: Item.TopLeft
                scale: pared.sc
                Rectangle { anchors.fill: parent; color: slot.isText ? "#000000" : pared.pal.bg }
                Item {
                    anchors.fill: parent
                    transform: Scale {
                        origin.x: slot.o.x
                        origin.y: slot.o.y
                        xScale: pared.camS
                        yScale: pared.camS
                    }
                    Loader {
                        anchors.fill: parent
                        active: !slot.isText
                        source: "motifs/" + pared.kind.charAt(0).toUpperCase() + pared.kind.slice(1) + ".qml"
                        onLoaded: {
                            const it = item;
                            for (const k of pared.contract)
                                if (k in it)
                                    it[k] = Qt.binding(() => feed[k]);
                            it.colour = Qt.binding(() => pared.pal.ink);
                            if ("hot" in it) it.hot = Qt.binding(() => pared.pal.hot);
                            if ("bg" in it) it.bg = Qt.binding(() => pared.pal.bg);
                            if ("seed" in it) it.seed = 0.37;
                            it.wallCam = Qt.binding(() => Qt.vector4d(pared.zoom, pared.camS, pared.foco.x, pared.foco.y));
                            it.wall = {
                                x: slot.r.x - pared.cv.x, y: slot.r.y - pared.cv.y,
                                cw: pared.cv.w, ch: pared.cv.h, span: pared.cv.span,
                                px: pared.pv.x - pared.cv.x, py: pared.pv.y - pared.cv.y,
                                ox: slot.o.x, oy: slot.o.y, epoch: 0, share: pared.share, now: () => pared.t
                            };
                            if ("wallT" in it) it.wallT = Qt.binding(() => pared.t);
                        }
                    }
                }
                // la pantalla de la letra: el motivo apagado y una línea, como en el overlay
                Text {
                    visible: slot.isText
                    anchors.centerIn: parent
                    text: "LA LETRA VA ACÁ"
                    color: "#7a7a7a"
                    font.pixelSize: 96
                    font.family: "monospace"
                }
            }
        }
    }
}
