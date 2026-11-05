// fatal-lyrics — motivo `radar`: una pantalla de radar (el dibujo está en `radar.frag`).
//
// Eran cuatro aros, una cuña girando y siete puntitos en un disco chico. Ahora es una costa que
// aparece bajo la aguja y se apaga, contactos que se mueven con su estela, un pulso con cada golpe
// del bombo y la consola al costado con los datos de lo que se ve.
//
// El barrido cuelga de la grilla (`beatN` + `bp`): una vuelta cada 8 tiempos, sin reloj propio.
// Sin compás, `beatN` sigue con los ticks. Los contactos salen de `drift`, acumulada.
import QtQuick
import "Ease.js" as E

ThumpBase {
    id: m

    readonly property real sweep: (m.beatN + m.bp) / 8 * Math.PI * 2
    readonly property int nContacts: 6
    readonly property real sd: E.hash(m.seed * 5.3 + 0.17)

    function contactAt(i, t) {
        const a = E.hash(sd * 3.1 + i * 1.73) * Math.PI * 2, b = E.hash(sd * 7.7 + i * 2.91) * Math.PI * 2;
        const w1 = 0.05 + 0.05 * E.hash(i * 4.13 + sd), w2 = 0.04 + 0.05 * E.hash(i * 6.37 + sd);
        const r = 0.34 + 0.52 * E.hash(i * 9.21 + sd);
        return { x: r * Math.sin(t * w1 + a), y: r * Math.cos(t * w2 + b) };
    }
    readonly property var cs: {
        const t = m.drift, out = [];
        for (let i = 0; i < nContacts; i++) {
            const p = contactAt(i, t), q = contactAt(i, t - 1);
            out.push({ x: p.x, y: p.y, vx: p.x - q.x, vy: p.y - q.y });
        }
        return out;
    }

    ShaderEffect {
        anchors.fill: parent
        property color ink: m.colour
        property color hot: m.hot
        property color bg: m.bg
        property vector4d hitAge: m.hitAge
        property vector4d hitAmp: m.hitAmp
        property vector4d c0: Qt.vector4d(m.cs[0].x, m.cs[0].y, m.cs[1].x, m.cs[1].y)
        property vector4d c1: Qt.vector4d(m.cs[2].x, m.cs[2].y, m.cs[3].x, m.cs[3].y)
        property vector4d c2: Qt.vector4d(m.cs[4].x, m.cs[4].y, m.cs[5].x, m.cs[5].y)
        property vector4d v0: Qt.vector4d(m.cs[0].vx, m.cs[0].vy, m.cs[1].vx, m.cs[1].vy)
        property vector4d v1: Qt.vector4d(m.cs[2].vx, m.cs[2].vy, m.cs[3].vx, m.cs[3].vy)
        property vector4d v2: Qt.vector4d(m.cs[4].vx, m.cs[4].vy, m.cs[5].vx, m.cs[5].vy)
        property variant res: Qt.vector2d(width, height)
        property real sweep: m.sweep
        property real dens: m.dens
        property real fizz: m.fizz
        property real dropAmt: m.dropAmt
        property real seed: m.sd
        property real flash: m.surge
        fragmentShader: Qt.resolvedUrl("radar.frag.qsb")
    }

    // la consola: lo que dice es lo que se ve. Se escribe una vez por tiempo, no por cuadro.
    readonly property bool wide: width > height * 1.25
    function pad(n, w) { return String(n).padStart(w, "0"); }
    function bearing(c) { return Math.round((Math.atan2(c.x, -c.y) * 180 / Math.PI + 360) % 360) % 360; }
    readonly property string leftText: {
        const n = m.beatN;
        const brg = Math.round((m.sweep * 180 / Math.PI + 90) % 360);
        return "SCAN  " + pad(Math.floor(n / 8) + 1, 4) + "\nRANGE 40 NM\nBRG   " + pad(brg, 3)
            + "\nTRK   " + m.nContacts + (m.drop ? "\n\nALERT" : "");
    }
    readonly property string rightText: {
        const n = m.beatN;   // se recalcula por tiempo
        let out = "";
        for (let i = 0; i < m.nContacts; i++) {
            const c = m.contactAt(i, m.drift);
            out += "T" + (i + 1) + (i === 0 ? ">" : " ") + pad(m.bearing(c), 3) + " "
                 + (Math.hypot(c.x, c.y) * 40).toFixed(1).padStart(4, "0") + (i < m.nContacts - 1 ? "\n" : "");
        }
        return out;
    }
    Text {
        visible: m.wide
        x: m.width * 0.035
        anchors.verticalCenter: parent.verticalCenter
        text: m.leftText
        color: m.colour
        opacity: 0.78
        font.family: m.fontFamily
        font.pixelSize: Math.round(m.span * 0.042)
        lineHeight: 1.1
    }
    Text {
        visible: m.wide
        anchors.right: parent.right
        anchors.rightMargin: m.width * 0.035
        anchors.verticalCenter: parent.verticalCenter
        text: m.rightText
        color: m.colour
        opacity: 0.78
        font.family: m.fontFamily
        font.pixelSize: Math.round(m.span * 0.042)
        lineHeight: 1.1
    }
    // vertical: arriba el estado, abajo los contactos
    Text {
        visible: !m.wide
        anchors.horizontalCenter: parent.horizontalCenter
        y: m.height * 0.06
        text: m.leftText
        color: m.colour
        opacity: 0.78
        font.family: m.fontFamily
        font.pixelSize: Math.round(m.span * 0.042)
        lineHeight: 1.1
    }
    Text {
        visible: !m.wide
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: m.height * 0.06
        text: m.rightText
        color: m.colour
        opacity: 0.78
        font.family: m.fontFamily
        font.pixelSize: Math.round(m.span * 0.042)
        lineHeight: 1.1
    }
}
