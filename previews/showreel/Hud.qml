// fatal-lyrics showreel — el marco del reel: timecode, capítulo, medidor.
// Entra en el primer bombo (1.875) con stagger y se va con el tubo.
import QtQuick
import "Ease.js" as E
import "Timeline.js" as TL

Item {
    id: h
    property real t: 0
    property QtObject audio
    property string mono: "monospace"

    readonly property real t0: TL.b(4)
    readonly property int segIdx: {
        for (let i = 0; i < TL.SEGMENTS.length; i++)
            if (t >= TL.SEGMENTS[i].t0 && t < TL.SEGMENTS[i].t1) return i;
        return TL.SEGMENTS.length - 1;
    }
    readonly property var seg: TL.SEGMENTS[segIdx]
    readonly property color ink: "#e8fbff"
    readonly property real m: 44
    // la letra desaparece en el vacío antes del drop (todo se congela)
    opacity: audio && audio.gap ? 0 : 0.8
    visible: t >= t0

    function inE(delay) { return E.outExpo(E.prog(t, t0 + delay, 0.32)); }
    function pad(n, w) { let s = "" + n; while (s.length < w) s = "0" + s; return s; }

    // marcas de registro en las cuatro esquinas
    Repeater {
        model: 4
        Item {
            required property int index
            readonly property bool r: index % 2 === 1
            readonly property bool b: index >= 2
            readonly property real e: h.inE(index * 0.03)
            x: r ? h.width - h.m - 26 : h.m
            y: b ? h.height - h.m - 26 : h.m
            width: 26; height: 26
            opacity: e
            transform: Translate { x: (r ? 1 : -1) * (1 - parent.e) * 30; y: (b ? 1 : -1) * (1 - parent.e) * 30 }
            Rectangle { x: parent.r ? 24 : 0; y: 0; width: 2; height: 26; color: h.ink }
            Rectangle { x: 0; y: parent.b ? 24 : 0; width: 26; height: 2; color: h.ink }
        }
    }

    Text {
        x: h.m + 40; y: h.m + 2
        opacity: h.inE(0.05)
        text: "FATAL LYRICS  //  MOTION REEL  //  2026"
        color: h.ink
        font.family: h.mono
        font.pixelSize: 20
        font.letterSpacing: 3
    }

    // timecode ss:ff
    Text {
        anchors.right: parent.right
        anchors.rightMargin: h.m + 40
        y: h.m + 2
        opacity: h.inE(0.09)
        readonly property int f: Math.floor(h.t * TL.FPS + 1e-6)
        text: "TC 00:" + h.pad(Math.floor(f / TL.FPS), 2) + ":" + h.pad(f % TL.FPS, 2)
              + "   BAR " + (Math.floor(h.t / TL.BAR) + 1) + "." + (Math.floor(h.t / TL.BEAT) % 4 + 1)
        color: h.ink
        font.family: h.mono
        font.pixelSize: 20
        font.letterSpacing: 2
    }

    // capítulo + barra del segmento
    Item {
        x: h.m + 40
        y: h.height - h.m - 34
        opacity: h.inE(0.12)
        Text {
            id: chap
            text: h.pad(h.segIdx + 1, 2) + " / " + h.seg.name.toUpperCase()
            color: h.ink
            font.family: h.mono
            font.pixelSize: 22
            font.letterSpacing: 3
        }
        Rectangle { y: 34; width: 260; height: 2; color: h.ink; opacity: 0.25 }
        Rectangle {
            y: 34; height: 2; color: h.ink
            width: 260 * E.prog(h.t, h.seg.t0, h.seg.t1 - h.seg.t0)
        }
    }

    // medidor: lo / mid / hi + nivel, y el punto del tiempo
    Row {
        anchors.right: parent.right
        anchors.rightMargin: h.m + 40
        y: h.height - h.m - 60
        spacing: 6
        opacity: h.inE(0.15)
        Repeater {
            model: 4
            Item {
                required property int index
                width: 10; height: 56
                readonly property real v: !h.audio ? 0
                    : index === 0 ? h.audio.audLo : index === 1 ? h.audio.audMid
                    : index === 2 ? h.audio.audHi : h.audio.audLevel
                Rectangle { anchors.bottom: parent.bottom; width: 10; height: 56; color: h.ink; opacity: 0.15 }
                Rectangle { anchors.bottom: parent.bottom; width: 10; height: 56 * E.clamp01(parent.v * (index === 3 ? 1 : 1.6)); color: index === 3 ? "#ff4a3d" : h.ink }
            }
        }
        Item { width: 14; height: 1 }
        Column {
            anchors.bottom: parent.bottom
            spacing: 4
            Rectangle {
                width: 14; height: 14; radius: 7
                color: "#ff4a3d"
                opacity: h.audio ? Math.exp(-Math.max(0, h.t - h.audio.lastBeatAt) / 0.12) : 0
            }
            Text {
                text: "128 BPM"
                color: h.ink
                font.family: h.mono
                font.pixelSize: 20
                font.letterSpacing: 2
            }
        }
    }
}
