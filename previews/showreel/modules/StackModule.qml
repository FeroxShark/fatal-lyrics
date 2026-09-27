// 02 STACK — 1.875–4.688
// Un cartel por bombo, en la escalera clásica de Win95. El que nace entra con
// el snap de Motion (OutExpo 320 ms) + destello de 60 ms + reflejo en la
// barra; los de atrás pierden el foco (barra gris, como Windows con la ventana
// inactiva). La cámara sigue al grupo y se asienta; el bombo le da un latido.
// Los dos últimos tiempos: el cursor agarra el último cartel y lo arrastra en
// un rulo hasta el centro dejando la ESTELA del bug de Win95 (una copia por
// cuadro), creciendo hasta el tamaño del cartel del próximo módulo.
//
// Integrable: (1) foco activo/inactivo por edad, (2) estela al arrastrar
// (`dragBy` de shell.qml ya existe: la estela son copias congeladas).
import QtQuick
import ".."
import "../Ease.js" as E
import "../Timeline.js" as TL

Item {
    id: m
    property real t: 0
    property QtObject audio

    readonly property var seg: TL.segment("stack")
    readonly property var specs: TL.STACK
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real dragT0: TL.b(8)
    readonly property real dragT1: TL.b(9.6)
    readonly property real kFinal: 2.25

    function spawnAt(i) { return TL.b(4 + i); }
    function count(tt) { let n = 0; for (let i = 0; i < specs.length; i++) if (tt >= spawnAt(i)) n++; return n; }

    // foco de cámara: promedio de los carteles vivos, con el snap de cameraMs
    function focusAt(tt) {
        let fx = 0, fy = 0;
        let prevX = 0, prevY = 0;
        for (let i = 0; i < specs.length; i++) {
            const t0 = spawnAt(i);
            if (tt < t0) break;
            // objetivo con i+1 carteles
            let sx = 0, sy = 0;
            for (let j = 0; j <= i; j++) { sx += specs[j].dx; sy += specs[j].dy; }
            const tx = sx / (i + 1), ty = sy / (i + 1);
            const k = E.outExpo(E.prog(tt, t0, 0.52));
            fx = E.mix(prevX, tx, k); fy = E.mix(prevY, ty, k);
            prevX = fx; prevY = fy;
        }
        return Qt.point(fx, fy);
    }
    readonly property point camFocus: focusAt(t)
    readonly property real beatEnv: audio ? Math.exp(-Math.max(0, t - audio.lastBeatAt) / 0.14) : 0
    readonly property real zoom: (1 - 0.03 * (count(t) - 1)) * (1 + 0.018 * beatEnv)
                                 * (1 - 0.05 * E.inOutCubic(E.prog(t, dragT0, dragT1 - dragT0)))
    function toScreen(dx, dy) {
        return Qt.point(cx + (dx - camFocus.x) * zoom, cy + (dy - camFocus.y) * zoom);
    }

    // recorrido del arrastre (centro del cartel, en pantalla)
    readonly property point dragFrom: {
        const s = specs[3];
        const f0 = focusAt(dragT0);
        const z0 = (1 - 0.03 * 3);
        return Qt.point(cx + (s.dx - f0.x) * z0, cy + (s.dy - f0.y) * z0);
    }
    function dragE(tt) { return E.inOutCubic(E.prog(tt, dragT0, dragT1 - dragT0)); }
    function dragPos(tt) {
        const e = dragE(tt);
        const x = E.mix(dragFrom.x, cx, e) - 560 * Math.sin(Math.PI * e) * (1 - 0.35 * e);
        const y = E.mix(dragFrom.y, cy, e) - 250 * Math.sin(Math.PI * e) + 90 * Math.sin(2 * Math.PI * e);
        return Qt.point(x, y);
    }
    function dragK(tt) { return E.mix(TL.STACK_K * (1 - 0.03 * 3), kFinal, dragE(tt)); }

    // ---- fondo: el escritorio teal abre como iris desde el cartel --------
    Rectangle { anchors.fill: parent; color: "#000000" }
    Rectangle {
        readonly property real r: E.outExpo(E.prog(m.t, m.seg.t0, 0.5)) * 1250
        x: m.cx - r; y: m.cy - r
        width: 2 * r; height: 2 * r
        radius: r
        color: "#008080"
    }
    // anillo del iris
    Rectangle {
        readonly property real k: E.prog(m.t, m.seg.t0, 0.5)
        readonly property real r: E.outExpo(k) * 1250
        visible: k > 0 && k < 1
        x: m.cx - r; y: m.cy - r
        width: 2 * r; height: 2 * r
        radius: r
        color: "transparent"
        border.color: "#bff5f5"
        border.width: 10 * (1 - k)
        opacity: 1 - k
    }

    // ---- los carteles de la escalera --------------------------------------
    Repeater {
        model: m.specs.length
        Win95Dialog {
            id: dlg
            required property int index
            readonly property var spec: m.specs[index]
            readonly property real t0: m.spawnAt(index)
            readonly property real e: E.prog(m.t, t0, 0.32)
            readonly property bool dragged: index === 3 && m.t >= m.dragT0
            readonly property point p: m.toScreen(spec.dx, spec.dy)
            // el 0 ya viene nacido del boot: no repite la entrada
            readonly property real inK: index === 0 ? 1 : E.outExpo(e)
            visible: m.t >= t0 && !dragged
            k: TL.STACK_K * m.zoom
            baseW: TL.DIALOG_W
            bodyH: TL.DIALOG_BODY
            title: spec.title
            text: spec.text
            icon: spec.icon
            buttons: spec.buttons
            inactive: m.count(m.t) - 1 > index  // no es el de adelante: pierde el foco
            x: p.x - width / 2 + (1 - inK) * 46
            y: p.y - height / 2 + (1 - inK) * 36
            flash: index === 0 ? 0 : 1 - E.prog(m.t, t0, 0.06)
            sweep: index === 0 ? -1 : E.prog(m.t, t0 + 0.02, 0.22)
            shadow: 8
            opacity: index === 0 ? 1 : E.clamp01(e * 6)
            transform: Scale {
                origin.x: dlg.width / 2; origin.y: dlg.height / 2
                xScale: E.mix(0.9, 1, dlg.inK); yScale: xScale
            }
        }
    }

    // ---- la estela del arrastre: una copia congelada por cuadro ----------
    Repeater {
        model: 44
        Win95Dialog {
            required property int index
            readonly property real ts: m.dragT0 + index * (m.dragT1 - m.dragT0) / 44
            readonly property point p: m.dragPos(ts)
            visible: m.t >= m.dragT0 && ts < m.t - 1 / 120
            k: m.dragK(ts)
            baseW: TL.DIALOG_W
            bodyH: TL.DIALOG_BODY
            title: m.specs[3].title
            text: m.specs[3].text
            icon: m.specs[3].icon
            buttons: m.specs[3].buttons
            x: p.x - width / 2
            y: p.y - height / 2
        }
    }

    // el que se arrastra
    Win95Dialog {
        id: live
        readonly property point p: m.dragPos(m.t)
        visible: m.t >= m.dragT0
        k: m.dragK(m.t)
        baseW: TL.DIALOG_W
        bodyH: TL.DIALOG_BODY
        title: m.specs[3].title
        text: m.specs[3].text
        icon: m.specs[3].icon
        buttons: m.specs[3].buttons
        x: p.x - width / 2
        y: p.y - height / 2
        shadow: 10
    }

    // ---- el cursor: entra, agarra la barra, arrastra, suelta -------------
    Cursor95 {
        k: 2.2
        readonly property real inE: E.inOutCubic(E.prog(m.t, TL.b(7) + 0.1, m.dragT0 - TL.b(7) - 0.14))
        // el agarre: 80 px dentro de la barra del cartel 3
        readonly property point grab: {
            const kk = m.t >= m.dragT0 ? live.k : TL.STACK_K * (1 - 0.03 * 3);
            const c = m.t >= m.dragT0 ? live.p : m.dragFrom;
            return Qt.point(c.x - TL.DIALOG_W * kk / 2 + 90 * kk, c.y - (2 + 26 + TL.DIALOG_BODY + 24 + 14) * kk / 2 + 14 * kk);
        }
        readonly property real outE: E.inCubic(E.prog(m.t, m.dragT1 + 0.04, 0.2))
        visible: m.t >= TL.b(7) + 0.1
        x: E.mix(m.width + 40, grab.x, inE) + outE * 160
        y: E.mix(m.height + 60, grab.y, inE) + outE * 220
    }
}
