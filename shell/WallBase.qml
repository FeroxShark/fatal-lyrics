// fatal-lyrics — la PARED para los motivos de reloj propio (`dunes`, `ocean`, `pond`).
//
// Lo mismo que MotifBase le da a los motivos de loop (`docs/PARED.md`), pero para los tres que
// llevan su propio FrameAnimation y no heredan de MotifBase: el recorte del lienzo común de ESTA
// pantalla (`wallView`, el foco), el reloj compartido (`wallTime`) y un azar que sale de la
// semilla de la pared (`wallHash`), igual en todas las pantallas. Sin `wall` (una pantalla sola)
// nada de esto se usa y el motivo queda como siempre.
//
// En el banco (`tubeClock` -1) el reloj llega de afuera, el mismo para todas las rebanadas: el
// hijo no corre su FrameAnimation.
import QtQuick
import "Wall.js" as Wall

Item {
    id: wb

    property var wall: null
    property vector4d wallCam: Qt.vector4d(1, 1, 0, 0)
    // cómo reparte la pared cuando una pantalla tiene la letra (`Wall.fit`, `docs/PARED.md`):
    // "behind" (el mundo sigue por detrás) o "mirror" (alas espejadas). Cada motivo de pared
    // declara el suyo. `wallEcho` (0..1): un eco tenue y desenfocado detrás de la letra; 0 = sin eco.
    property string wallFit: "behind"
    property real wallEcho: 0
    property real tubeClock: -1
    property real seed: 0              // 0..1; en pared, la de la pared (igual en todas)
    readonly property bool walled: !!wall
    readonly property bool wallShared: walled && !!wall.share
    // reloj de pared: `wall.epoch` (ms) + acumulado compartido
    readonly property bool wallClocked: walled && tubeClock >= 0
    // el reloj lo mueve otro (el banco): el FrameAnimation del hijo se queda quieto
    readonly property bool clockExternal: walled && tubeClock < 0

    readonly property real span: walled ? wall.span : Math.min(width, height)
    readonly property var wallWin: walled
        ? Wall.view({ x: wall.x, y: wall.y }, { w: width, h: height }, { x: wall.px, y: wall.py },
                    { x: wall.ox, y: wall.oy }, wallCam.y, wallCam.x)
        : ({ x: 0, y: 0, w: width, h: height })
    readonly property vector2d wallArea: walled ? Qt.vector2d(wall.cw, wall.ch) : Qt.vector2d(width, height)
    // uv = wallView.xy + qt_TexCoord0 · wallView.zw, en unidades de `span` desde el centro del lienzo
    readonly property vector4d wallView: Qt.vector4d((wallWin.x - wallArea.x / 2) / span,
        (wallWin.y - wallArea.y / 2) / span, wallWin.w / span, wallWin.h / span)
    // el foco (la pantalla con la letra, o el medio del lienzo), en las mismas unidades
    readonly property vector2d wallFocusU: walled
        ? Qt.vector2d((wallCam.z - wallArea.x / 2) / span, (wallCam.w - wallArea.y / 2) / span)
        : Qt.vector2d(0, 0)
    // hasta dónde llega el agua desde el foco: la esquina más lejana del lienzo
    readonly property real wallReach: {
        const hx = wallArea.x / 2 / span, hy = wallArea.y / 2 / span;
        return Math.hypot(hx + Math.abs(wallFocusU.x), hy + Math.abs(wallFocusU.y));
    }
    // lo que el shader necesita de la pared: (1, px por unidad, tope del lienzo en unidades, 0)
    readonly property vector4d wallCfg: walled
        ? Qt.vector4d(1, span, -wallArea.y / 2 / span, 0) : Qt.vector4d(0, Math.max(height, 1), 0, 0)

    // segundos acumulados (con `rate`) desde que apareció la pared: UNA cuenta para todas las
    // instancias, la primera que llega en el cuadro la avanza y las demás la leen
    function wallTime(rate) {
        const S = wall.share, t = (Date.now() - wall.epoch) / 1000;
        if (S.cAt === undefined) {
            S.cAt = t;
            S.cV = 0;
        }
        if (t > S.cAt) {
            S.cV += (t - S.cAt) * rate;
            S.cAt = t;
        }
        return S.cV;
    }
    // azar determinista (0..1) de la semilla de la pared: igual en todas las pantallas
    function wallHash(n) {
        const s = Math.sin(n * 12.9898 + seed * 78.233) * 43758.5453;
        return s - Math.floor(s);
    }
    // el instante en que cayó el golpe `n`: el primero que lo ve lo fija y las demás lo leen
    function wallStamp(n, now) {
        const S = wall.share;
        if (S.sN !== n) {
            S.sN = n;
            S.sT = now;
        }
        return S.sT;
    }
}
