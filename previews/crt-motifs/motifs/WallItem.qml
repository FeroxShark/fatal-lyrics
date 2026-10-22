// fatal-lyrics — la pared para los motivos que NO son de MotifBase (túnel, estrellas).
//
// `MotifBase` ya trae la ventana del lienzo (`wallWin`), el foco y el reloj de pared para los
// motivos que cuelgan de él. Los que son un `Item` suelto (`Tunnel`, `Stars`) heredan de acá lo
// mismo, mínimo: el lienzo común (`docs/PARED.md`), la ventana de ESTA pantalla y el estado
// compartido (`wall.share`). Sin pared (`wall` null) todo vale lo de una pantalla sola:
// la ventana es la pantalla entera, el foco su centro y `span` su lado corto.
//
// Los motivos sacan lo mutable (distancia viajada, luz que corre) de `wallShared`/`wall.share`:
// la primera instancia que corre en un cuadro lo avanza y las demás lo leen. Cada una
// integrando lo suyo, la pantalla que entra tarde arrancaría de cero y el dibujo se partiría
// en la costura.
import QtQuick
import "../Wall.js" as Wall

Item {
    id: wi

    // el lienzo que arma Crt.qml (ver MotifBase: x, y, cw, ch, span, px, py, ox, oy, epoch,
    // share) y `wallCam` = (tirón propio, factor de la cámara del tubo, foco x, foco y)
    property var wall: null
    property vector4d wallCam: Qt.vector4d(1, 1, 0, 0)
    readonly property bool walled: !!wall
    readonly property bool wallShared: walled && !!wall.share
    // en el banco el reloj llega de afuera (`wall.now()`): las instancias de la pared y la
    // referencia ven la misma historia, sin animaciones de tiempo real de por medio
    readonly property bool wallExternal: walled && !!wall.now
    function wallNow() {
        return wallExternal ? wall.now() : (Date.now() - wall.epoch) / 1000;
    }
    // el banco avanza el reloj de a un cuadro simulado y lo publica acá; un `FrameAnimation` ahí
    // dispara a tiempo real, a un ritmo que cambia de una corrida a otra
    property real wallT: 0

    readonly property real span: walled ? wall.span : Math.min(width, height)
    readonly property var wallWin: walled
        ? Wall.view({ x: wall.x, y: wall.y }, { w: width, h: height }, { x: wall.px, y: wall.py },
                    { x: wall.ox, y: wall.oy }, wallCam.y, wallCam.x)
        : ({ x: 0, y: 0, w: width, h: height })
    readonly property vector2d wallArea: walled ? Qt.vector2d(wall.cw, wall.ch) : Qt.vector2d(width, height)
    // para un shader: p = wallPx.xy + qt_TexCoord0 · wallPx.zw, en px de lienzo
    readonly property vector4d wallPx: Qt.vector4d(wallWin.x, wallWin.y, wallWin.w, wallWin.h)
    // el foco (la pantalla con la letra, o el medio del lienzo), en px de lienzo
    readonly property vector2d wallFocus: walled ? Qt.vector2d(wallCam.z, wallCam.w)
                                                 : Qt.vector2d(width / 2, height / 2)
}
