// fatal-lyrics — la ventana de Ajustes.
//
// `fatal ajustes` (o `fatal config`, o "Settings…" en la bandeja y en el
// lanzador) abre esto: TODAS las opciones de Fatal, en pestañas, en UNA ventana
// con la misma pinta que los carteles — un diálogo de Win95. No hay otra
// pantalla de opciones: el menú de terminal que había antes se fue, y esta
// ventana no abre ninguna terminal.
//
// Qué se dibuja no vive acá: lo dice cartelitos/settings.py (TABS y GROUPS), que
// esta ventana pide con `cartelitos.py --settings-json` al abrir y cada vez que
// el TOML cambia (la bandeja o un editor también lo tocan). Acá hay un widget
// por tipo de fila y nada más, así que una opción nueva no se agrega en este
// archivo.
//
// Lo que se toca se escribe en $XDG_RUNTIME_DIR/cartelitos-settings, una línea
// `<serie> <seccion.clave>=<json>` por perilla; el daemon la valida, la pasa a
// la config y la aplica — queda guardada igual que desde la bandeja. El archivo
// guarda las últimas varias: el daemon mira cada 250 ms, y dos clicks más
// rápidos que eso no se pueden pisar. La serie (la hora en ms al abrir, +1 por
// cambio) es lo que hace que cada una se aplique una sola vez.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    // los pone `fatal ajustes`: el launcher sabe dónde está instalado todo
    readonly property string fatalBin: Quickshell.env("FATAL_BIN") || "fatal"
    readonly property string daemonPy: Quickshell.env("FATAL_DAEMON") || ""
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR")

    property var tabs: []
    property var quick: []
    property var groups: []
    property var vals: ({})
    // la prosa larga de cada perilla (el comentario del TOML) y la fila que se
    // está apuntando: el panel de abajo de la hoja las muestra
    property var details: ({})
    property var sel: null
    property bool crtOn: false
    property var keys: ({})
    property var monitors: []
    property var players: []
    property bool daemonUp: true
    property string status: ""
    property int tab: 0

    // los valores con que abrió la ventana: "Undo changes" vuelve a éstos
    property var opening: null

    // perillas recién tocadas acá: hasta que la config las confirme, un
    // refresco que llegue en el medio no las pisa (si no, el slider salta para
    // atrás mientras se lo arrastra)
    property var held: ({})
    property var queue: []
    property real serial: Date.now()

    function keyLabel(k) {
        return (k || "").replace(/\s*,\s*/, "+");
    }

    function snap(v, step) {
        return parseFloat((Math.round(v / step) * step).toFixed(2));
    }

    function load(text) {
        let d;
        try {
            d = JSON.parse(text);
        } catch (e) {
            return;
        }
        // los grupos una sola vez: rearmar los Repeater cortaría un arrastre
        if (root.groups.length === 0) {
            root.tabs = d.tabs;
            root.quick = d.quick || [];
            root.groups = d.groups;
            root.details = d.details || {};
        }
        if (root.opening === null)
            root.opening = d.values;
        const now = Date.now();
        let v = {};
        for (const id in d.values)
            v[id] = (root.held[id] || 0) > now ? root.vals[id] : d.values[id];
        root.vals = v;
        root.keys = d.keys;
        if (JSON.stringify(d.monitors) !== JSON.stringify(root.monitors))
            root.monitors = d.monitors;
        if (JSON.stringify(d.players) !== JSON.stringify(root.players))
            root.players = d.players;
        root.daemonUp = d.daemon;
    }

    // una fila dependiente (`needs`) se atenúa mientras alguna de sus casillas
    // esté apagada: seguir tocándola no se nota
    function dimmed(row) {
        return (row.needs || []).some(id => root.vals[id] === false);
    }

    function commit(id, value, final) {
        let c = {};
        c[id] = value;
        root.commitMany(c, final);
        root.status = `${id} = ${JSON.stringify(value)}`;
    }

    // varias perillas de una: "Undo changes" las devuelve todas en una sola
    // escritura, no una por perilla
    function commitMany(changes, final) {
        let v = Object.assign({}, root.vals);
        let h = Object.assign({}, root.held);
        const ids = Object.keys(changes);
        for (const id of ids) {
            v[id] = changes[id];
            h[id] = Date.now() + 2000;
        }
        root.vals = v;
        root.held = h;
        if (!root.daemonUp) {
            // sin daemon nadie lee el archivo: se escribe el TOML directo, una
            // vez por gesto (al soltar el slider, no en cada pixel)
            if (final)
                Quickshell.execDetached(["python3", root.daemonPy, "--settings-set"]
                    .concat(ids.map(id => `${id}=${JSON.stringify(changes[id])}`)));
            return;
        }
        let q = root.queue.filter(e => !(e.id in changes));
        for (const id of ids) {
            root.serial = Math.max(root.serial + 1, Date.now());
            q.push({ s: root.serial, id: id, v: changes[id] });
        }
        root.queue = q.slice(-120);
        pipe.setText(root.queue.map(e => `${e.s.toFixed(0)} ${e.id}=${JSON.stringify(e.v)}`)
                     .join("\n") + "\n");
    }

    // lo tocado desde que se abrió la ventana, con el valor de entonces
    readonly property var undo: {
        let c = {};
        if (root.opening === null)
            return c;
        for (const id in root.opening)
            if (JSON.stringify(root.vals[id]) !== JSON.stringify(root.opening[id]))
                c[id] = root.opening[id];
        return c;
    }

    // el mismo control que hace settings.coerce, para avisar ANTES: el daemon
    // tira un valor inválido sin decir nada
    function textProblem(row, t) {
        if (t.length > 80)
            return "too long";
        if (/["\\\x00-\x1f]/.test(t))
            return "no quotes or backslashes";
        if (row.check === "name" && t.trim() === "")
            return "can't be empty";
        if (row.check === "key" && t.trim() !== "" && t.indexOf(",") < 0)
            return "a key needs its comma: MODS, KEY (e.g. SUPER SHIFT, Y)";
        return "";
    }

    // lo que está guardado en una fila de pantallas, como lista de nombres
    function screenList(row, v) {
        if (Array.isArray(v))
            return v.slice();
        return typeof v === "string" && !row.specials.some(o => o.value === v) ? [v] : [];
    }

    function run(args, what) {
        Quickshell.execDetached([root.fatalBin].concat(args));
        root.status = what;
    }

    // ------------------------------------------------------------ canales

    FileView {
        id: pipe
        path: `${root.runDir}/cartelitos-settings`
        printErrors: false
        atomicWrites: true
    }

    Process {
        id: snapshot
        command: ["python3", root.daemonPy, "--settings-json"]
        stdout: StdioCollector {
            onStreamFinished: root.load(text)
        }
        onExited: {
            if (root.again) {
                root.again = false;
                Qt.callLater(() => snapshot.running = true);
            }
        }
    }
    property bool again: false
    function refresh() {
        if (snapshot.running)
            again = true;
        else
            snapshot.running = true;
    }
    Component.onCompleted: refresh()

    // el TOML se relee cada segundo (es chico) y sólo si cambió se vuelve a
    // pedir el snapshot: así lo que se toque en la bandeja o a mano se ve acá
    property var lastCfg: null
    FileView {
        id: cfgFile
        path: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/cartelitos/config.toml`
        preload: true
        printErrors: false
        onLoaded: {
            const t = text();
            if (root.lastCfg !== null && t !== root.lastCfg)
                root.refresh();
            root.lastCfg = t;
        }
    }

    // el interruptor del tubo, el mismo archivo que lee el overlay
    FileView {
        id: crtSwitch
        path: `${root.runDir}/cartelitos-crt`
        preload: true
        printErrors: false
        onLoaded: root.crtOn = text().trim() === "1"
        onLoadFailed: root.crtOn = false
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            cfgFile.reload();
            crtSwitch.reload();
        }
    }

    // ¿hay daemon? Si se cae con la ventana abierta, los cambios pasan a ir
    // directo al TOML; si vuelve, de nuevo por el archivo
    Timer {
        interval: root.daemonUp ? 15000 : 3000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    // ------------------------------------------------------------ piezas Win95

    // bisel de dos líneas: levantado (botón, ventana) o hundido (campo, casilla)
    component Bevel: Item {
        property bool sunken: false
        anchors.fill: parent
        Rectangle { x: 0; y: 0; width: parent.width; height: 1; color: sunken ? "#808080" : "#ffffff" }
        Rectangle { x: 0; y: 0; width: 1; height: parent.height; color: sunken ? "#808080" : "#ffffff" }
        Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: sunken ? "#ffffff" : "#000000" }
        Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: sunken ? "#ffffff" : "#000000" }
        Rectangle { x: 1; y: 1; width: parent.width - 2; height: 1; color: sunken ? "#404040" : "#dfdfdf" }
        Rectangle { x: 1; y: 1; width: 1; height: parent.height - 2; color: sunken ? "#404040" : "#dfdfdf" }
        Rectangle { x: 1; y: parent.height - 2; width: parent.width - 2; height: 1; color: sunken ? "#dfdfdf" : "#808080" }
        Rectangle { x: parent.width - 2; y: 1; width: 1; height: parent.height - 2; color: sunken ? "#dfdfdf" : "#808080" }
    }

    component Button95: Rectangle {
        id: btn
        property string text
        signal clicked()
        implicitWidth: Math.max(75, label.implicitWidth + 20)
        implicitHeight: 23
        color: "#c0c0c0"
        Bevel { sunken: ma.pressed }
        Text {
            id: label
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: ma.pressed ? 1 : 0
            anchors.verticalCenterOffset: ma.pressed ? 1 : 0
            text: btn.text
            color: btn.enabled ? "#000000" : "#808080"
            font.pixelSize: 12
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            onClicked: btn.clicked()
        }
    }

    component Check95: Rectangle {
        property bool checked: false
        width: 13
        height: 13
        color: "#ffffff"
        Bevel { sunken: true }
        Text {
            anchors.centerIn: parent
            visible: parent.checked
            text: "✓"
            color: "#000000"
            font.pixelSize: 12
            font.bold: true
        }
    }

    component Radio95: Item {
        id: radio
        property string text
        property bool checked: false
        signal clicked()
        implicitWidth: 18 + lbl.implicitWidth + 8
        implicitHeight: 18
        Rectangle {
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            radius: 6
            color: "#ffffff"
            border.width: 1
            border.color: "#808080"
            Rectangle {
                anchors.centerIn: parent
                width: 4
                height: 4
                radius: 2
                color: "#000000"
                visible: radio.checked
            }
        }
        Text {
            id: lbl
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            text: radio.text
            color: "#000000"
            font.pixelSize: 12
        }
        MouseArea {
            anchors.fill: parent
            onClicked: radio.clicked()
        }
    }

    // interruptor grande de la franja "Quick": un botón Win95 que queda hundido
    // y con la luz verde mientras está prendido. El estado se lee de tres
    // maneras (bisel, luz y la palabra ON/OFF): no depende del color.
    component Tile95: Rectangle {
        id: tile
        property string text
        property string caption
        property bool on: false
        signal clicked()
        implicitHeight: 46
        color: on ? "#d8d8d8" : "#c0c0c0"
        Bevel { sunken: tile.on || tileMa.pressed }
        Rectangle {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            color: tile.on ? "#00c800" : "#808080"
            Bevel { sunken: true }
        }
        Item {
            x: 32
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: tileMa.pressed ? 1 : 0
            width: parent.width - 32 - 8
            height: tileTitle.implicitHeight + tileCaption.implicitHeight
            Text {
                id: tileTitle
                text: tile.text
                color: "#000000"
                font.pixelSize: 13
                font.bold: true
            }
            Text {
                anchors.right: parent.right
                anchors.baseline: tileTitle.baseline
                text: tile.on ? "ON" : "OFF"
                color: tile.on ? "#000000" : "#404040"
                font.pixelSize: 11
                font.bold: tile.on
                font.family: "monospace"
            }
            Text {
                id: tileCaption
                y: tileTitle.implicitHeight
                width: parent.width
                text: tile.caption
                color: "#404040"
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: tileMa
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }
    }

    // el recuadro grabado con el título encima del borde
    component Group95: Item {
        id: group
        property string title
        default property alias content: inner.data
        implicitHeight: inner.implicitHeight + 30
        Rectangle { x: 0; y: 7; width: group.width - 1; height: group.height - 8; color: "transparent"; border.color: "#808080" }
        Rectangle { x: 1; y: 8; width: group.width - 1; height: group.height - 8; color: "transparent"; border.color: "#ffffff" }
        Rectangle {
            x: 8
            y: 0
            width: heading.implicitWidth + 6
            height: 15
            color: "#c0c0c0"
            Text {
                id: heading
                x: 3
                text: group.title
                color: "#000000"
                font.pixelSize: 12
            }
        }
        Column {
            id: inner
            x: 11
            y: 22
            width: group.width - 22
            spacing: 11
        }
    }

    component Label95: Text {
        color: "#000000"
        font.pixelSize: 12
    }

    // #404040 sobre #c0c0c0 da ~5.7:1 (la #505050 de antes, ~4.4:1, no llegaba a 4.5)
    component Hint95: Text {
        color: "#404040"
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    // campo de texto hundido. Guarda con Enter o al salir del campo; Escape
    // deshace lo tipeado
    component Field95: Rectangle {
        id: field
        property alias text: input.text
        property alias input: input
        signal done()
        signal undone()
        implicitHeight: 21
        color: "#ffffff"
        Bevel { sunken: true }
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: "#000000"
            selectionColor: "#000080"
            selectedTextColor: "#ffffff"
            font.pixelSize: 12
            selectByMouse: true
            onEditingFinished: field.done()
            Keys.onEscapePressed: {
                field.undone();
                focus = false;
            }
        }
    }


    // ------------------------------------------------------------ la ventana

    PanelWindow {
        id: win
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "cartelitos-settings"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: frame.width
        implicitHeight: frame.height

        Item {
            id: keyItem
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Qt.quit()
        }

        Rectangle {
            id: frame
            readonly property int colW: 300
            width: 3 * colW + 2 * 10 + 2 * 12 + 2 * 10
            height: body.y + body.height + 12
            color: "#c0c0c0"
            Bevel {}

            // un click fuera de un campo de texto lo suelta (y el campo guarda)
            MouseArea {
                anchors.fill: parent
                onPressed: m => {
                    keyItem.forceActiveFocus();
                    m.accepted = false;
                }
            }

            // barra de título
            Rectangle {
                id: titlebar
                x: 3
                y: 3
                width: frame.width - 6
                height: 22
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#000080" }
                    GradientStop { position: 1.0; color: "#1084d0" }
                }
                Text {
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    text: "Fatal Lyrics — Settings"
                    color: "#ffffff"
                    font.pixelSize: 12
                    font.bold: true
                }
                Rectangle {
                    anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
                    width: 16
                    height: 14
                    color: "#c0c0c0"
                    Bevel { sunken: closeMa.pressed }
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: "#000000"
                        font.pixelSize: 10
                        font.bold: true
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        onClicked: Qt.quit()
                    }
                }
            }

            Column {
                id: body
                x: 12
                y: titlebar.y + titlebar.height + 12
                width: frame.width - 24
                spacing: 12

                // la franja "Quick": lo que más se prende y apaga, antes de las
                // pestañas. Las mismas perillas que las filas de abajo (mismo
                // id, mismo camino), sólo que a un click y sin buscarlas
                Group95 {
                    id: quickGroup
                    width: parent.width
                    title: "Quick"
                    visible: root.quick.length > 0

                    Row {
                        spacing: 8
                        Repeater {
                            model: root.quick

                            Tile95 {
                                id: tileItem
                                required property var modelData
                                readonly property bool isTube: modelData.id === "crt"
                                width: (quickGroup.width - 22 - 8 * (root.quick.length - 1)) / root.quick.length
                                text: modelData.label
                                caption: isTube && root.keys.crt_toggle
                                         ? root.keyLabel(root.keys.crt_toggle) : modelData.hint
                                on: isTube ? root.crtOn : root.vals[modelData.id] === true
                                // apuntarlo llena el panel de detalle, igual que las filas
                                HoverHandler {
                                    onHoveredChanged: if (hovered) root.sel = tileItem.modelData
                                }
                                onClicked: {
                                    if (isTube) {
                                        root.crtOn = !root.crtOn;
                                        root.run(["crt", root.crtOn ? "on" : "off"],
                                                 `CRT mode ${root.crtOn ? "on" : "off"}`);
                                    } else {
                                        root.commit(modelData.id, root.vals[modelData.id] !== true, true);
                                    }
                                }
                            }
                        }
                    }
                }

                // pestañas y su hoja: la elegida se pega a la hoja, como en
                // las Propiedades de pantalla de Win95
                Item {
                    width: parent.width
                    height: tabStrip.height + sheet.height - 2

                    Rectangle {
                        id: sheet
                        y: tabStrip.height - 2
                        width: parent.width
                        height: flick.height + 20
                        color: "#c0c0c0"
                        Bevel {}

                        // todas las páginas, una encima de otra: la hoja mide
                        // lo que la más alta, así cambiar de pestaña no cambia
                        // el tamaño de la ventana. Si no entra en la pantalla,
                        // se scrollea con la rueda
                        Flickable {
                            id: flick
                            x: 10
                            y: 10
                            width: parent.width - 20
                            height: Math.min(pages.tallest, (win.screen ? win.screen.height : 1080) - 360)
                            contentWidth: width
                            contentHeight: pages.tallest
                            clip: true
                            interactive: contentHeight > height
                            boundsBehavior: Flickable.StopAtBounds

                            Item {
                                id: pages
                                width: flick.width
                                property real tallest: 0
                                property var heights: []
                                function note(i, h) {
                                    let hs = heights.slice();
                                    hs[i] = h;
                                    heights = hs;
                                    tallest = Math.max(0, ...hs.filter(x => x !== undefined));
                                }

                                Repeater {
                                    model: root.tabs.length

                                    // opacity y no visible: una página invisible
                                    // deja de medirse (Column saltea los hijos que
                                    // no se ven) y la hoja cambiaría de alto
                                    Row {
                                        id: page
                                        required property int index
                                        spacing: 10
                                        opacity: page.index === root.tab ? 1 : 0
                                        enabled: page.index === root.tab
                                        onImplicitHeightChanged: pages.note(page.index, implicitHeight)
                                        Component.onCompleted: pages.note(page.index, implicitHeight)

                                        Repeater {
                                            model: 3

                                            Column {
                                                id: col
                                                required property int index
                                                width: frame.colW
                                                spacing: 12

                                                Repeater {
                                                    model: root.groups.filter(g => g.tab === page.index && g.column === col.index)

                                                    Group95 {
                                                        id: group
                                                        required property var modelData
                                                        width: col.width
                                                        title: modelData.title

                                                        Repeater {
                                                            model: group.modelData.rows

                                                            Item {
                                                                id: rowItem
                                                                required property var modelData
                                                                readonly property string rid: modelData.id
                                                                width: group.width - 22
                                                                height: loader.item ? loader.item.implicitHeight : 0
                                                                // la fila atenuada atenúa sólo su control: el nombre y
                                                                // la ayuda se leen igual (dicen por qué está apagada)
                                                                readonly property real ctlAlpha: root.dimmed(modelData) ? 0.45 : 1

                                                                // apuntar la fila llena el panel de detalle
                                                                HoverHandler {
                                                                    onHoveredChanged: if (hovered) root.sel = rowItem.modelData
                                                                }

                                                                Loader {
                                                                    id: loader
                                                                    width: parent.width
                                                                    sourceComponent: ({
                                                                        toggle: toggleRow, choice: choiceRow,
                                                                        slider: sliderRow, crt: crtRow, sync: syncRow,
                                                                        text: textRow, screens: screensRow, order: orderRow,
                                                                    })[rowItem.modelData.kind] || null
                                                                }

                                                                // casilla: la perilla on/off
                                                                Component {
                                                                    id: toggleRow
                                                                    Item {
                                                                        implicitHeight: toggleText.implicitHeight
                                                                        Check95 {
                                                                            opacity: rowItem.ctlAlpha
                                                                            y: 1
                                                                            checked: root.vals[rowItem.rid] === true
                                                                        }
                                                                        Column {
                                                                            id: toggleText
                                                                            x: 20
                                                                            width: parent.width - 20
                                                                            Label95 { text: rowItem.modelData.label }
                                                                            Hint95 { width: parent.width; text: rowItem.modelData.hint }
                                                                        }
                                                                        MouseArea {
                                                                            anchors.fill: parent
                                                                            onClicked: root.commit(rowItem.rid, root.vals[rowItem.rid] !== true, true)
                                                                        }
                                                                    }
                                                                }

                                                                // botones de opción: todas a la vista, una elegida
                                                                Component {
                                                                    id: choiceRow
                                                                    Column {
                                                                        spacing: 3
                                                                        Label95 { text: rowItem.modelData.label }
                                                                        Hint95 { width: parent.width; text: rowItem.modelData.hint }
                                                                        Flow {
                                                                            width: parent.width
                                                                            spacing: 2
                                                                            Repeater {
                                                                                model: rowItem.modelData.options
                                                                                Radio95 {
                                                                                    opacity: rowItem.ctlAlpha
                                                                                    required property var modelData
                                                                                    text: modelData.label
                                                                                    checked: root.vals[rowItem.rid] === modelData.value
                                                                                    onClicked: root.commit(rowItem.rid, modelData.value, true)
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }

                                                                // trackbar: click o arrastre en cualquier punto
                                                                Component {
                                                                    id: sliderRow
                                                                    Column {
                                                                        spacing: 2
                                                                        // nombre y número en una línea (la pista abajo de
                                                                        // cada uno estiraba la columna al doble que las otras);
                                                                        // la ayuda entera debajo, sin "…": se lee siempre
                                                                        Item {
                                                                            width: parent.width
                                                                            height: sliderName.implicitHeight
                                                                            Label95 { id: sliderName; text: rowItem.modelData.label }
                                                                            Label95 {
                                                                                id: sliderNum
                                                                                anchors.right: parent.right
                                                                                text: (root.vals[rowItem.rid] ?? 0).toFixed(rowItem.modelData.step >= 1 ? 0 : 2)
                                                                                font.family: "monospace"
                                                                            }
                                                                        }
                                                                        Hint95 { width: parent.width; text: rowItem.modelData.hint }
                                                                        Item {
                                                                            id: track
                                                                            opacity: rowItem.ctlAlpha
                                                                            readonly property var spec: rowItem.modelData
                                                                            readonly property real frac: Math.max(0, Math.min(1,
                                                                                ((root.vals[spec.id] ?? spec.min) - spec.min) / (spec.max - spec.min)))
                                                                            width: parent.width
                                                                            height: 22
                                                                            Rectangle {
                                                                                x: 5
                                                                                y: 9
                                                                                width: track.width - 10
                                                                                height: 4
                                                                                color: "#c0c0c0"
                                                                                Bevel { sunken: true }
                                                                            }
                                                                            Rectangle {
                                                                                x: 5 + track.frac * (track.width - 10) - width / 2
                                                                                y: 0
                                                                                width: 11
                                                                                height: 21
                                                                                color: "#c0c0c0"
                                                                                Bevel {}
                                                                            }
                                                                            MouseArea {
                                                                                anchors.fill: parent
                                                                                preventStealing: true
                                                                                function apply(mx, final) {
                                                                                    const s = track.spec;
                                                                                    const f = Math.max(0, Math.min((mx - 5) / (track.width - 10), 1));
                                                                                    root.commit(s.id, root.snap(s.min + f * (s.max - s.min), s.step), final);
                                                                                }
                                                                                onPressed: m => apply(m.x, false)
                                                                                onPositionChanged: m => {
                                                                                    if (pressed)
                                                                                        apply(m.x, false);
                                                                                }
                                                                                onReleased: m => apply(m.x, true)
                                                                            }
                                                                        }
                                                                    }
                                                                }

                                                                // texto: el player, un atajo, la fuente
                                                                Component {
                                                                    id: textRow
                                                                    Column {
                                                                        id: textCol
                                                                        spacing: 3
                                                                        readonly property string saved: root.vals[rowItem.rid] ?? ""
                                                                        onSavedChanged: if (!textField.input.activeFocus) textField.text = saved
                                                                        Component.onCompleted: textField.text = saved
                                                                        function save() {
                                                                            const t = textField.text;
                                                                            if (t === textCol.saved)
                                                                                return;
                                                                            const bad = root.textProblem(rowItem.modelData, t);
                                                                            if (bad) {
                                                                                root.status = `${rowItem.modelData.label}: ${bad} — not saved`;
                                                                                textField.text = textCol.saved;
                                                                                return;
                                                                            }
                                                                            root.commit(rowItem.rid, t.trim(), true);
                                                                        }
                                                                        Label95 { text: rowItem.modelData.label }
                                                                        Hint95 { width: parent.width; text: rowItem.modelData.hint + " · Enter saves" }
                                                                        Field95 {
                                                                            opacity: rowItem.ctlAlpha
                                                                            id: textField
                                                                            width: parent.width
                                                                            onDone: textCol.save()
                                                                            onUndone: {
                                                                                textField.text = textCol.saved;
                                                                                keyItem.forceActiveFocus();
                                                                            }
                                                                        }
                                                                        // lo que playerctl ve ahora, para no tipear
                                                                        Flow {
                                                                            width: parent.width
                                                                            spacing: 4
                                                                            visible: rowItem.modelData.suggest === "players" && root.players.length > 0
                                                                            Repeater {
                                                                                model: rowItem.modelData.suggest === "players" ? root.players : []
                                                                                Radio95 {
                                                                                    opacity: rowItem.ctlAlpha
                                                                                    required property var modelData
                                                                                    text: modelData
                                                                                    checked: textCol.saved === modelData
                                                                                    onClicked: root.commit(rowItem.rid, modelData, true)
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }

                                                                // qué pantallas: una opción especial o los
                                                                // monitores que se marquen
                                                                Component {
                                                                    id: screensRow
                                                                    Column {
                                                                        id: scrCol
                                                                        spacing: 3
                                                                        readonly property var row: rowItem.modelData
                                                                        readonly property var picked: root.screenList(row, root.vals[rowItem.rid])
                                                                        // los conectados, de izquierda a derecha, y los
                                                                        // que están guardados pero no aparecen
                                                                        readonly property var names: root.monitors.map(m => m.name)
                                                                            .concat(picked.filter(n => !root.monitors.some(m => m.name === n)))
                                                                        function toggle(name) {
                                                                            let on = scrCol.picked.indexOf(name) < 0
                                                                                ? scrCol.picked.concat([name])
                                                                                : scrCol.picked.filter(n => n !== name);
                                                                            on = scrCol.names.filter(n => on.indexOf(n) >= 0);
                                                                            root.commit(rowItem.rid, on.length ? on : scrCol.row.specials[0].value, true);
                                                                        }
                                                                        Label95 { text: scrCol.row.label }
                                                                        Hint95 { width: parent.width; text: scrCol.row.hint }
                                                                        Flow {
                                                                            width: parent.width
                                                                            spacing: 2
                                                                            Repeater {
                                                                                model: scrCol.row.specials
                                                                                Radio95 {
                                                                                    opacity: rowItem.ctlAlpha
                                                                                    required property var modelData
                                                                                    text: modelData.label
                                                                                    checked: root.vals[rowItem.rid] === modelData.value
                                                                                    onClicked: root.commit(rowItem.rid, modelData.value, true)
                                                                                }
                                                                            }
                                                                        }
                                                                        Repeater {
                                                                            model: scrCol.names
                                                                            Item {
                                                                                id: mon
                                                                                required property string modelData
                                                                                readonly property var info: root.monitors.find(m => m.name === modelData)
                                                                                width: scrCol.width
                                                                                height: 16
                                                                                Check95 { opacity: rowItem.ctlAlpha; y: 1; checked: scrCol.picked.indexOf(mon.modelData) >= 0 }
                                                                                Label95 { id: monName; x: 20; text: mon.modelData }
                                                                                Hint95 {
                                                                                    anchors { left: monName.right; leftMargin: 6; right: parent.right
                                                                                              baseline: monName.baseline }
                                                                                    text: mon.info ? mon.info.info : "not connected"
                                                                                    wrapMode: Text.NoWrap
                                                                                    elide: Text.ElideRight
                                                                                }
                                                                                MouseArea {
                                                                                    anchors.fill: parent
                                                                                    onClicked: scrCol.toggle(mon.modelData)
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }

                                                                // el orden de las pantallas del tubo: solo, o a mano
                                                                // con los números gigantes de `fatal crt setup`
                                                                Component {
                                                                    id: orderRow
                                                                    Column {
                                                                        id: ordCol
                                                                        spacing: 3
                                                                        readonly property var list: Array.isArray(root.vals[rowItem.rid])
                                                                            ? root.vals[rowItem.rid] : []
                                                                        function move(i, d) {
                                                                            let l = ordCol.list.slice();
                                                                            const t = l[i];
                                                                            l[i] = l[i + d];
                                                                            l[i + d] = t;
                                                                            root.commit(rowItem.rid, l, true);
                                                                        }
                                                                        Label95 { text: rowItem.modelData.label }
                                                                        Hint95 { width: parent.width; text: rowItem.modelData.hint }
                                                                        Flow {
                                                                            width: parent.width
                                                                            spacing: 2
                                                                            Radio95 {
                                                                                opacity: rowItem.ctlAlpha
                                                                                text: "Left to right"
                                                                                checked: root.vals[rowItem.rid] === "auto"
                                                                                onClicked: root.commit(rowItem.rid, "auto", true)
                                                                            }
                                                                            Radio95 {
                                                                                opacity: rowItem.ctlAlpha
                                                                                text: "By hand"
                                                                                checked: ordCol.list.length > 0
                                                                                onClicked: if (!checked && root.monitors.length)
                                                                                    root.commit(rowItem.rid, root.monitors.map(m => m.name), true)
                                                                            }
                                                                        }
                                                                        Repeater {
                                                                            model: ordCol.list
                                                                            Row {
                                                                                id: ordItem
                                                                                required property string modelData
                                                                                required property int index
                                                                                spacing: 4
                                                                                Label95 {
                                                                                    width: 120
                                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                                    text: `${ordItem.index + 1}. ${ordItem.modelData}`
                                                                                }
                                                                                Button95 {
                                                                                    opacity: rowItem.ctlAlpha
                                                                                    text: "▲"
                                                                                    implicitWidth: 23
                                                                                    enabled: ordItem.index > 0
                                                                                    onClicked: if (enabled) ordCol.move(ordItem.index, -1)
                                                                                }
                                                                                Button95 {
                                                                                    opacity: rowItem.ctlAlpha
                                                                                    text: "▼"
                                                                                    implicitWidth: 23
                                                                                    enabled: ordItem.index < ordCol.list.length - 1
                                                                                    onClicked: if (enabled) ordCol.move(ordItem.index, 1)
                                                                                }
                                                                            }
                                                                        }
                                                                        Row {
                                                                            spacing: 6
                                                                            Button95 {
                                                                                opacity: rowItem.ctlAlpha
                                                                                text: "Show numbers"
                                                                                onClicked: root.run(["crt", "setup"],
                                                                                    "a big number on each screen: read them left to right")
                                                                            }
                                                                            Button95 {
                                                                                opacity: rowItem.ctlAlpha
                                                                                text: "Hide them"
                                                                                onClicked: root.run(["crt", "setup", "off"], "screen numbers off")
                                                                            }
                                                                        }
                                                                    }
                                                                }

                                                                // el tubo: no es una perilla, es el interruptor en vivo
                                                                Component {
                                                                    id: crtRow
                                                                    Item {
                                                                        implicitHeight: crtText.implicitHeight
                                                                        Check95 { opacity: rowItem.ctlAlpha; y: 1; checked: root.crtOn }
                                                                        Column {
                                                                            id: crtText
                                                                            x: 20
                                                                            width: parent.width - 20
                                                                            Label95 { text: rowItem.modelData.label }
                                                                            Hint95 {
                                                                                width: parent.width
                                                                                text: rowItem.modelData.hint
                                                                                      + (root.keys.crt_toggle ? ` · ${root.keyLabel(root.keys.crt_toggle)}` : "")
                                                                            }
                                                                        }
                                                                        MouseArea {
                                                                            anchors.fill: parent
                                                                            onClicked: {
                                                                                root.crtOn = !root.crtOn;
                                                                                root.run(["crt", root.crtOn ? "on" : "off"],
                                                                                         `CRT mode ${root.crtOn ? "on" : "off"}`);
                                                                            }
                                                                        }
                                                                    }
                                                                }

                                                                // el sync: lo mismo que `fatal sync +|-|reset`
                                                                Component {
                                                                    id: syncRow
                                                                    Column {
                                                                        spacing: 5
                                                                        Label95 { text: rowItem.modelData.label }
                                                                        Hint95 {
                                                                            width: parent.width
                                                                            text: rowItem.modelData.hint
                                                                                  + (root.keys.sync_forward
                                                                                     ? ` · ${root.keyLabel(root.keys.sync_back)} / ${root.keyLabel(root.keys.sync_forward)}`
                                                                                     : "")
                                                                        }
                                                                        Row {
                                                                            spacing: 6
                                                                            Button95 {
                                                                                opacity: rowItem.ctlAlpha
                                                                                text: "Later  −0.1 s"
                                                                                onClicked: root.run(["sync", "-"], "lyric 0.1 s later")
                                                                            }
                                                                            Button95 {
                                                                                opacity: rowItem.ctlAlpha
                                                                                text: "Earlier  +0.1 s"
                                                                                onClicked: root.run(["sync", "+"], "lyric 0.1 s earlier")
                                                                            }
                                                                        }
                                                                        // `reset` sin nombre: el artista que suena. El
                                                                        // daemon se entera en el próximo tema
                                                                        Button95 {
                                                                            opacity: rowItem.ctlAlpha
                                                                            text: "Forget this artist"
                                                                            onClicked: root.run(["sync", "reset"],
                                                                                "learned sync for this artist forgotten (from the next track)")
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        id: tabStrip
                        x: 2
                        height: 24
                        Repeater {
                            model: root.tabs
                            Rectangle {
                                id: tabBtn
                                required property string modelData
                                required property int index
                                readonly property bool on: tabBtn.index === root.tab
                                y: on ? 0 : 2
                                width: tabLabel.implicitWidth + 20
                                height: on ? 24 : 22
                                color: "#c0c0c0"
                                Rectangle { x: 0; y: 2; width: 1; height: parent.height; color: "#ffffff" }
                                Rectangle { x: 2; y: 0; width: parent.width - 4; height: 1; color: "#ffffff" }
                                Rectangle { x: 1; y: 1; width: 1; height: 1; color: "#ffffff" }
                                Rectangle { x: parent.width - 1; y: 2; width: 1; height: parent.height - 2; color: "#000000" }
                                Rectangle { x: parent.width - 2; y: 1; width: 1; height: parent.height - 1; color: "#808080" }
                                Text {
                                    id: tabLabel
                                    anchors.centerIn: parent
                                    text: tabBtn.modelData
                                    color: "#000000"
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        keyItem.forceActiveFocus();
                                        root.tab = tabBtn.index;
                                        flick.contentY = 0;
                                    }
                                }
                            }
                        }
                    }
                }

                // qué hace la fila apuntada: el primer párrafo de su comentario
                // del TOML. Alto fijo (nombre + 4 renglones): un texto largo se
                // corta con "…" y la ventana no cambia de tamaño
                Rectangle {
                    width: parent.width
                    height: 74
                    color: "#c0c0c0"
                    Bevel { sunken: true }
                    Column {
                        x: 8
                        y: 6
                        width: parent.width - 16
                        spacing: 2
                        Label95 {
                            width: parent.width
                            elide: Text.ElideRight
                            font.bold: true
                            text: root.sel ? root.sel.label : "What does it do?"
                        }
                        Hint95 {
                            width: parent.width
                            height: 4 * 14
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            text: root.sel ? (root.details[root.sel.id] || root.sel.hint)
                                           : "Point at any setting to read what it does."
                        }
                    }
                }

                // botonera, a la derecha como en cualquier diálogo
                Item {
                    width: parent.width
                    height: 23
                    Row {
                        anchors.right: parent.right
                        spacing: 6
                        Button95 {
                            text: "Demo dialogs"
                            onClicked: root.run(["demo"], "demo dialogs sent")
                        }
                        Button95 {
                            readonly property int n: Object.keys(root.undo).length
                            text: "Undo changes"
                            enabled: n > 0
                            onClicked: {
                                if (n === 0)
                                    return;
                                root.commitMany(root.undo, true);
                                root.status = `${n} option${n === 1 ? "" : "s"} back to how they were`;
                            }
                        }
                        Button95 {
                            text: "Close"
                            onClicked: Qt.quit()
                        }
                    }
                }

                // barra de estado hundida
                Rectangle {
                    width: parent.width
                    height: 20
                    color: "#c0c0c0"
                    Bevel { sunken: true }
                    Text {
                        anchors { left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 6
                                  verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        text: !root.daemonUp
                              ? "fatal-lyrics isn't running: changes are saved and apply when it starts"
                              : (root.vals["effects.death_age_min"] ?? 0) > (root.vals["effects.death_age_max"] ?? 99)
                              ? "Heads up: in Lifetime, “Dies after” is above “…at most”"
                              : root.status || "Every change applies live and is saved to config.toml"
                        color: "#000000"
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
