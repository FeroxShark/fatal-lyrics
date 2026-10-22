// fatal-lyrics — motivo `pixelsort` (2026-10-22; en el sorteo, grupo `hot` de `motifGroups`).
//
// Pixel-sort: una pila de ventanas de error se ORDENA por brillo, columna por columna, y se
// chorrea hacia abajo en rayas. Qué hace con cada señal:
//   · bombo (`thump`)  — el golpe ABRE el umbral de orden (`pulse`: la envolvente del resorte de
//     `Thump.js`): entra más ventana al orden y los chorros se alargan; vuelve con el mismo resorte.
//   · tiempo (`beatN`) — las ventanas de origen saltan de lugar con el snap de Motion (OutExpo
//     320 ms), una o dos por tiempo (escalonadas), no todas juntas.
//   · agudos (`fizz`)  — columnas sueltas que chispean.
//   · densidad (`dens`) — baja el umbral: más imagen entra al orden.
// La deriva (`drift`, acumulada) mueve las ventanas y el umbral aunque no suene nada.
//
// Costo: UN ShaderEffect de pantalla completa (`pixelsort.frag`): 12 celdas por columna y 144
// comparaciones por píxel, sin texturas. `quality` ensancha las columnas.
import QtQuick
import "../Ease.js" as E
import "../Thump.js" as T

ThumpBase {
    id: m

    readonly property var camPhys: T.heavy(phys, 2.5)
    // el umbral se abre con la envolvente del golpe (sube con el ataque, se apaga con la masa)
    readonly property real pulse: E.clamp01(T.envSum(camPhys, clock, hitT, hitA))

    ShaderEffect {
        anchors.fill: parent
        property color ink: m.colour
        property color hot: m.hot
        property color bg: m.bg
        property variant res: Qt.vector2d(width, height)
        property real drift: m.drift
        property real dens: m.dens
        property real fizz: m.fizz
        property real pulse: m.pulse
        property real bn: m.beatN
        property real since: Math.min(m.sinceTick, m.beatS * 1.5)
        property real beatS: m.beatS
        property real seed: E.hash(m.seed * 3.17 + 0.3)
        property real dropAmt: m.dropAmt
        property real quality: Math.max(0.5, Math.min(1, m.quality))
        fragmentShader: Qt.resolvedUrl("pixelsort.frag.qsb")
    }
}
