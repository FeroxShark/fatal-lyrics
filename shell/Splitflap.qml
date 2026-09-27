// splitflap — un cartel de paletas de aeropuerto (Solari) con la letra.
//
// Arriba el número de verso, en el medio el verso que suena partido en
// renglones, abajo "SIGUE:" y la primera palabra de la línea que viene. Cuando
// algo cambia, cada paleta GIRA por el abecedario desde la letra que tenía
// hasta la nueva (una media paleta cae, la otra sube), escalonadas de izquierda
// a derecha y de arriba abajo: el cartel entero se reescribe en cascada. Los
// cambios caen en el tiempo porque el verso y la palabra cambian en el golpe.
// Lo que suena:
//   · `lines` / `lineNo`: el verso que se muestra
//   · `nextWord`: el renglón de abajo, que cambia una vez por compás
//   · `tick`: cada paleta que termina de girar da un destello; en el drop las
//     letras del verso se prenden en `hot` en cada tiempo
//
// Costo en el overlay: ≤ 96 paletas de Text/Rectangle (3 textos y 3 recortes
// cada una); quieto no re-evalúa nada.
import QtQuick
import "Ease.js" as E
import "Dots.js" as D

MotifBase {
    id: m

    readonly property string abc: " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-?!/"
    readonly property int cols: portrait ? 9 : 16
    readonly property int rowsN: portrait ? 10 : 6
    readonly property real step: 0.018         // segundos por paleta
    readonly property real cw: Math.min(width * 0.92 / cols, height * 0.88 / rowsN / 1.34)
    readonly property real ch: cw * 1.34
    readonly property real bx: (width - cols * cw) / 2
    readonly property real by: (height - rowsN * ch) / 2

    function pad(s, n, center) {
        s = s.slice(0, n);
        if (!center) return s + " ".repeat(n - s.length);
        const l = Math.floor((n - s.length) / 2);
        return " ".repeat(l) + s + " ".repeat(n - s.length - l);
    }
    // el cartel entero, renglón por renglón
    readonly property var board: {
        const out = [];
        const nl = lines ? lines.length : 0;
        out.push(pad(nl > 0 && lineNo >= 0 ? "VERSO " + (lineNo + 1) + "/" + nl : "FATAL LYRICS", cols, false));
        const text = nl > 0 && lineNo >= 0 ? D.clean(lines[lineNo % nl]) : "";
        const words = text.split(" ").filter(w => w.length > 0);
        const body = [];
        let cur = "";
        for (const w of words) {
            const ww = w.slice(0, cols);
            if (cur.length === 0) cur = ww;
            else if (cur.length + 1 + ww.length <= cols) cur += " " + ww;
            else { body.push(cur); cur = ww; }
        }
        if (cur.length) body.push(cur);
        const inner = rowsN - 3;          // título, un renglón de aire, SIGUE
        const top = Math.max(0, Math.floor((inner - body.length) / 2));
        for (let r = 0; r < inner; r++)
            out.push(pad(body[r - top] || "", cols, true));
        out.push(pad("", cols, false));
        out.push(pad("SIGUE: " + D.clean(nextWord), cols, false));
        return out;
    }

    // lo que había antes del último cambio y cuándo cambió. Si en el mismo
    // cuadro cambian dos cosas (verso y palabra), el "antes" es el del primer
    // aviso: el segundo no puede pisarlo con un cartel a medio escribir.
    property var from: []
    property var shown: []
    property real changeAt: -1e6
    onBoardChanged: {
        if (changeAt !== clock)
            from = shown.length ? shown : board;
        shown = board;
        changeAt = clock;
    }

    // Paletas de Text y Rectangle comunes (placa de video), no un Canvas: la
    // palabra de abajo cambia en cada compás, así que el cartel está girando
    // casi siempre, y el Canvas costaba ~30 ms por cuadro. Y sin bindings por
    // paleta: con 96 paletas × 25 bindings colgados del reloj se iban ~15 ms
    // en re-evaluarlos. Un solo recorrido en JS (`advance()`) calcula el estado
    // y escribe sólo en las paletas que se mueven.
    readonly property color face: Qt.darker(bg, 1.6)
    readonly property real gap: Math.max(2, cw * 0.06)
    readonly property real fontPx: Math.max(1, Math.round(ch * 0.92))
    readonly property int nCells: rowsN * cols
    property real lastDropHot: 0
    property bool dirtyAll: true
    onFromChanged: dirtyAll = true
    onShownChanged: dirtyAll = true
    onColourChanged: dirtyAll = true
    onHotChanged: dirtyAll = true
    onWidthChanged: dirtyAll = true
    onHeightChanged: dirtyAll = true

    function advance() {
        const since = clock - changeAt;
        const dropHot = drop ? 1 - E.outQuad(bp) : 0;
        if (since >= 3 && !dirtyAll && dropHot === 0 && lastDropHot === 0)
            return;
        const all = dirtyAll;
        dirtyAll = false;
        lastDropHot = dropHot;
        const L = abc.length;
        for (let i = 0; i < nCells; i++) {
            const it = cells.itemAt(i);
            if (!it) continue;
            const r = Math.floor(i / cols), c = i % cols;
            const t0 = c * 0.015 + r * 0.04;
            const a = (from[r] || "").charAt(c) || " ";
            const b = (shown[r] || "").charAt(c) || " ";
            const ia = Math.max(0, abc.indexOf(a)), ib = Math.max(0, abc.indexOf(b));
            const n = (ib - ia + L) % L;
            const f = (since - t0) / step;          // paletas caídas
            // quieta y ya asentada: no hay nada que escribir (salvo el drop)
            const settled = n === 0 || since - t0 - n * step > 0.6;
            const lit = r > 0 && r < rowsN - 2 ? dropHot : 0;
            if (!all && settled && lit === 0 && it.wasLit === 0)
                continue;
            it.wasLit = lit;
            const done = n === 0 || f >= n;
            const flipping = !done && f >= 0;
            const landed = done && n > 0 ? Math.exp(-(since - t0 - n * step) / 0.12) : 0;
            const k = Math.floor(Math.max(0, f)), ph = f - k;
            it.ink = E.col(lit > 0.3 || landed > 0.5 ? hot : colour, 0.92);
            it.edge = E.col(colour, 0.18 + 0.4 * landed);
            it.flipping = flipping;
            if (flipping) {
                const cOld = abc.charAt((ia + k) % L), cNew = abc.charAt((ia + k + 1) % L);
                it.topText = cNew;
                it.botText = cOld;
                it.ph = ph;
                it.flapText = ph < 0.5 ? cOld : cNew;
            } else {
                const still = done ? b : a;
                it.topText = still;
                it.botText = still;
            }
        }
    }
    onFrame: advance()

    // una letra centrada en la paleta entera (las mitades la recortan)
    component Glyph: Text {
        property real cellW
        property real cellH
        width: cellW; height: cellH
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        topPadding: cellH * 0.06
        font.family: m.fontFamily
        font.pixelSize: m.fontPx
    }

    Repeater {
        id: cells
        model: m.nCells
        Item {
            id: cell
            required property int index
            x: m.bx + (index % m.cols) * m.cw + m.gap / 2
            y: m.by + Math.floor(index / m.cols) * m.ch + m.gap / 2
            width: m.cw - m.gap
            height: m.ch - m.gap
            // lo escribe `advance()`
            property string topText: " "
            property string botText: " "
            property string flapText: " "
            property bool flipping: false
            property real ph: 0
            property color ink: "transparent"
            property color edge: "transparent"
            property real wasLit: 0
            readonly property real flapS: ph < 0.5 ? 1 - ph * 2 : (ph - 0.5) * 2

            Rectangle {
                anchors.fill: parent
                color: m.face
                border.color: cell.edge
                border.width: Math.max(1, cell.width * 0.03)
            }
            // quieta: una letra entera, sin recortes (cada recorte corta el
            // lote de dibujo de la placa: 96 paletas × 3 recortes pesaban)
            Glyph { visible: !cell.flipping; cellW: cell.width; cellH: cell.height; color: cell.ink; text: cell.topText }
            // girando: mitad de arriba la nueva, abajo la vieja
            Item {
                visible: cell.flipping
                width: cell.width; height: cell.height / 2
                clip: true
                Glyph { cellW: cell.width; cellH: cell.height; color: cell.ink; text: cell.topText }
            }
            Item {
                visible: cell.flipping
                y: cell.height / 2
                width: cell.width; height: cell.height / 2
                clip: true
                Glyph { y: -cell.height / 2; cellW: cell.width; cellH: cell.height; color: cell.ink; text: cell.botText }
            }
            // la paleta que cae: primero la mitad de arriba vieja se aplasta
            // contra la bisagra, después la de abajo nueva baja
            Item {
                visible: cell.flipping
                y: cell.ph < 0.5 ? 0 : cell.height / 2
                width: cell.width; height: cell.height / 2
                clip: true
                transform: Scale { origin.y: cell.ph < 0.5 ? cell.height / 2 : 0; yScale: cell.flapS }
                Rectangle { anchors.fill: parent; color: m.face }
                Glyph {
                    y: cell.ph < 0.5 ? 0 : -cell.height / 2
                    cellW: cell.width; cellH: cell.height
                    text: cell.flapText
                    color: E.col(m.colour, 0.92 * (0.5 + 0.5 * cell.flapS))
                }
            }
            // la bisagra
            Rectangle {
                y: cell.height / 2 - Math.max(1, cell.height * 0.012)
                width: cell.width; height: Math.max(2, cell.height * 0.024)
                color: E.col(m.bg, 0.9)
            }
        }
    }
}
