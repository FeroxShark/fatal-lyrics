// swarm — una bandada de punteros de Windows 95 que ARMA la palabra que viene.
//
// Tres bandadas de flechitas viajan cada una en formación (un centro que
// pasea, las flechas en un óvalo que respira alrededor, todo periódico en
// 15 s), con profundidad (las chicas van atrás y más tenues) y una estela
// corta. En el primer tiempo de cada
// compás las que hacen falta se clavan en su lugar y escriben `nextWord` en
// matriz de puntos 5×7 (Dots.js): snap OutExpo de 320 ms con un escalonado
// chico, así se lee la bandada llegando, no una palabra que aparece. Tres
// tiempos quietas (el hold largo de Motion) y en el cuarto revientan hacia
// afuera y vuelven a la bandada. Lo que suena:
//   · `tick`: el compás entero es la frase — formar, sostener, soltar
//   · `nextWord`: lo que escriben (la primera palabra de la línea que viene;
//     sin ella, la palabra más larga del verso que suena, y si no, FATAL)
//   · `tick`: en cada tiempo un puñado de la bandada hace CLIC (un anillo que
//     se abre en la punta); `level` decide cuántas
//   · `high` en la subida: la palabra tiembla, cada puntero por su lado
//   · `drop`: la palabra late en cada tiempo (se abre desde su centro y se
//     prende en `hot`) y la bandada de fondo se enciende
//
// El dibujo vive en `swarm.vert` + `swarm.frag` (una instancia por flecha, en la placa;
// el puntero de Win95 con borde analítico). Acá sólo se reparten los números del cuadro y la
// palabra, empaquetada en 18 matrices (un punto = x * 8 + y).
// Costo en el overlay: UN ShaderEffect con 4 × 260 instancias y cero geometría por cuadro
// (antes: un `MShape` de hasta 260 flechas × 3 reconstruidas en JS, 14,9 ms en el banco).
// `quality` baja la cuenta.
import QtQuick
import "../Ease.js" as E
import "../Dots.js" as D

MotifBase {
    id: m

    readonly property int count: Math.min(260, Math.round(260 * quality))
    function lineText(entry) {
        if (entry === undefined || entry === null) return "";
        return typeof entry === "string" ? entry : (entry.text || "");
    }
    // la palabra: la que viene; si no hay, la más larga del verso que suena
    readonly property string wordText: {
        if (D.clean(nextWord).length > 0)
            return nextWord;
        const ln = lines && lines.length > 0 && lineNo >= 0 ? D.clean(lineText(lines[lineNo % lines.length])) : "";
        let best = "";
        for (const w of ln.split(" "))
            if (w.length > best.length && w.length <= 8) best = w;
        return best.length > 0 ? best : "FATAL";
    }
    readonly property var word: D.cells(wordText, 8)
    readonly property int need: word.pts.length
    // cuántas flechas escriben: dos por punto, así la letra sale gorda
    readonly property int writers: Math.min(count, need * 2)
    readonly property real cell: Math.min(width * 0.84 / word.cols, height * 0.40 / 7)
    readonly property real ox: (width - word.cols * cell) / 2
    readonly property real oy: (height - 7 * cell) / 2
    // dónde va del compás, en tiempos (0..4)
    readonly property real q: E.wrap(beatN, 4) + bp
    readonly property real arrow: Math.max(span * 0.0016, cell * 0.042)

    // de 2 a 4 bandadas (según la aparición); cada flecha en su lugar de un
    // óvalo que respira
    readonly property int flocks: 2 + Math.floor(E.hash(seed * 3.9 + 0.6) * 3)
    readonly property real spread: 0.8 + 0.45 * E.hash(seed * 8.3 + 0.2)
    // la semilla, chica, para el hash del shader (en float32 un seed de millones no sirve)
    readonly property real seedS: 12 * E.hash(seed * 0.91 + 0.17)

    readonly property real beatHot: drop ? 1 - E.outQuad(bp) : 0
    readonly property real swell: drop && q >= 1 && q < 3 ? 0.07 * (1 - E.outExpo(bp)) : 0

    // La palabra para el shader: 16 puntos por matriz (x * 8 + y), 18 matrices = 288 ≥ 8 letras
    // de 35 puntos. `Qt.matrix4x4` recibe las filas; el shader lee columnas.
    function packed(n) {
        const a = [];
        for (let t = 0; t < 16; t++) {
            const p = word.pts[n * 16 + t];
            a.push(p ? p.x * 8 + p.y : 0);
        }
        return Qt.matrix4x4(...a);
    }

    ShaderEffect {
        anchors.fill: parent
        // 4 bloques × 260 instancias × 4 columnas = 4160 columnas = 4159 celdas (ver swarm.vert)
        mesh: GridMesh { resolution: Qt.size(4159, 1) }
        property variant p0: m.packed(0)
        property variant p1: m.packed(1)
        property variant p2: m.packed(2)
        property variant p3: m.packed(3)
        property variant p4: m.packed(4)
        property variant p5: m.packed(5)
        property variant p6: m.packed(6)
        property variant p7: m.packed(7)
        property variant p8: m.packed(8)
        property variant p9: m.packed(9)
        property variant p10: m.packed(10)
        property variant p11: m.packed(11)
        property variant p12: m.packed(12)
        property variant p13: m.packed(13)
        property variant p14: m.packed(14)
        property variant p15: m.packed(15)
        property variant p16: m.packed(16)
        property variant p17: m.packed(17)
        property color ink: m.colour
        property color hot: m.hot
        property color dark: Qt.darker(m.bg, 1.4)
        property variant res: Qt.vector2d(width, height)
        property real span: m.span
        property real lt: m.lt
        property real sd: m.seedS
        property real flocks: m.flocks
        property real spread: m.spread
        property real count: m.count
        property real writers: m.writers
        property real need: m.need
        property real cols: m.word.cols
        property real cell: m.cell
        property real ox: m.ox
        property real oy: m.oy
        property real arrow: m.arrow
        property real q: m.q
        property real bs: m.beatS
        property real bp: m.bp
        property real beatHot: m.beatHot
        property real swell: m.swell
        property real dropAmt: m.dropAmt
        property real dropOn: m.drop ? 1 : 0
        // la subida: cada una tiembla por su lado
        property real shake: m.cell * 0.45 * m.high * (m.section === "build" ? 1 : 0.15)
        property real clickN: Math.round((0.04 + 0.12 * m.level + (m.drop ? 0.1 : 0)) * m.count)
        property real clickSeed: m.beatN % 97
        vertexShader: Qt.resolvedUrl("swarm.vert.qsb")
        fragmentShader: Qt.resolvedUrl("swarm.frag.qsb")
    }
}
