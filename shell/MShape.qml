// El lienzo de los motivos de líneas: un Shape de Qt Quick (lo dibuja la placa
// de video) en vez de un Canvas (lo rasteriza el procesador: 50–110 ms por
// cuadro a 1080p en el banco del 2026-09-27; así, 1–3 ms).
//
// El motivo no declara ShapePaths: llena dos listas paralelas y el lienzo arma
// un ShapePath por estilo.
//   · `styles[i]` = { w: grosor (0 = sin trazo), c: color del trazo,
//                     f: color de relleno (opcional) }   — colores de QML
//                     (`E.col`), no texto CSS
//   · `geo[i]`    = lista de polilíneas, cada una una lista de `Qt.point`;
//                   todas las del mismo estilo viajan en UN ShapePath
// Cada estilo es una tanda, igual que los `stroke()` agrupados del Canvas: la
// cantidad de estilos tiene que ser fija por motivo (cambiarla recrea todo).
//
// GeometryRenderer + una capa con MSAA 4× y no CurveRenderer: el CurveRenderer
// hace más trabajo de CPU por trazo, y en una ventana sin exponer (el banco de
// CPU) deja de dibujar desde la segunda captura, así que no se puede medir. Con
// la capa lo que se mide es lo mismo que corre.
import QtQuick
import QtQuick.Shapes

Shape {
    id: sh
    anchors.fill: parent
    preferredRendererType: Shape.GeometryRenderer
    layer.enabled: visible
    layer.samples: 4
    layer.smooth: true

    property var styles: []
    property var geo: []
    readonly property var none: []

    Instantiator {
        model: sh.styles.length
        delegate: ShapePath {
            required property int index
            readonly property var st: sh.styles[index] || ({})
            strokeWidth: st.w > 0 ? st.w : -1
            strokeColor: st.w > 0 ? st.c : "transparent"
            fillColor: st.f !== undefined ? st.f : "transparent"
            fillRule: ShapePath.WindingFill
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: sh.geo[index] || sh.none }
        }
        onObjectAdded: (i, o) => sh.data.push(o)
    }
}
