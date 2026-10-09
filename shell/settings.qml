// fatal-lyrics — la ventana de Ajustes.
//
// `fatal ajustes` (o "Settings…" en la bandeja) abre esto: todas las opciones
// que antes colgaban del menú de la bandeja, más los sliders del tubo, en UNA
// ventana con la misma pinta que los carteles — un diálogo de Win95.
//
// Qué se dibuja no vive acá: lo dice cartelitos/settings.py (GROUPS), que esta
// ventana pide con `cartelitos.py --settings-json` al abrir y cada vez que el
// TOML cambia (la bandeja o un editor también lo tocan). Acá hay un widget por
// tipo de fila y nada más, así que una opción nueva no se agrega en este archivo.
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

    property var groups: []
    property var vals: ({})
    property bool crtOn: false
    property var keys: ({})
    property string terminal: ""
    property bool daemonUp: true
    property string status: ""

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
        if (root.groups.length === 0)
            root.groups = d.groups;
        const now = Date.now();
        let v = {};
        for (const id in d.values)
            v[id] = (root.held[id] || 0) > now ? root.vals[id] : d.values[id];
        root.vals = v;
        root.keys = d.keys;
        root.terminal = d.terminal;
        root.daemonUp = d.daemon;
    }

    function commit(id, value, final) {
        let v = Object.assign({}, root.vals);
        v[id] = value;
        root.vals = v;
        let h = Object.assign({}, root.held);
        h[id] = Date.now() + 2000;
        root.held = h;
        root.status = `${id} = ${JSON.stringify(value)}`;
        if (!root.daemonUp) {
            // sin daemon nadie lee el archivo: se escribe el TOML directo, una
            // vez por gesto (al soltar el slider, no en cada pixel)
            if (final)
                Quickshell.execDetached(["python3", root.daemonPy, "--settings-set",
                                         `${id}=${JSON.stringify(value)}`]);
            return;
        }
        root.serial = Math.max(root.serial + 1, Date.now());
        let q = root.queue.filter(e => e.id !== id);
        q.push({ s: root.serial, id: id, v: value });
        root.queue = q.slice(-40);
        pipe.setText(root.queue.map(e => `${e.s.toFixed(0)} ${e.id}=${JSON.stringify(e.v)}`)
                     .join("\n") + "\n");
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

    component Hint95: Text {
        color: "#505050"
        font.pixelSize: 11
        wrapMode: Text.WordWrap
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
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Qt.quit()
        }

        Rectangle {
            id: frame
            readonly property int colW: 300
            width: 3 * colW + 2 * 10 + 2 * 12
            height: body.y + body.height + 12
            color: "#c0c0c0"
            Bevel {}

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

                Row {
                    spacing: 10

                    Repeater {
                        model: 3

                        Column {
                            id: col
                            required property int index
                            width: frame.colW
                            spacing: 12

                            Repeater {
                                model: root.groups.filter(g => g.column === col.index)

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

                                            Loader {
                                                id: loader
                                                width: parent.width
                                                sourceComponent: ({
                                                    toggle: toggleRow, choice: choiceRow,
                                                    slider: sliderRow, crt: crtRow, sync: syncRow,
                                                })[rowItem.modelData.kind] || null
                                            }

                                            // casilla: la perilla on/off
                                            Component {
                                                id: toggleRow
                                                Item {
                                                    implicitHeight: toggleText.implicitHeight
                                                    Check95 {
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
                                                    Item {
                                                        width: parent.width
                                                        height: sliderName.implicitHeight
                                                        Label95 { id: sliderName; text: rowItem.modelData.label }
                                                        Label95 {
                                                            anchors.right: parent.right
                                                            text: (root.vals[rowItem.rid] ?? 0).toFixed(2)
                                                            font.family: "monospace"
                                                        }
                                                    }
                                                    Hint95 { width: parent.width; text: rowItem.modelData.hint }
                                                    Item {
                                                        id: track
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

                                            // el tubo: no es una perilla, es el interruptor en vivo
                                            Component {
                                                id: crtRow
                                                Item {
                                                    implicitHeight: crtText.implicitHeight
                                                    Check95 { y: 1; checked: root.crtOn }
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

                                            // el sync: lo mismo que `fatal sync +|-`
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
                                                            text: "Later  −0.1 s"
                                                            onClicked: root.run(["sync", "-"], "lyric 0.1 s later")
                                                        }
                                                        Button95 {
                                                            text: "Earlier  +0.1 s"
                                                            onClicked: root.run(["sync", "+"], "lyric 0.1 s earlier")
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
                            text: "All options…"
                            enabled: root.terminal !== ""
                            onClicked: Quickshell.execDetached([root.terminal, "-e", root.fatalBin, "config"])
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
                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        text: !root.daemonUp
                              ? "fatal-lyrics isn't running: changes are saved and apply when it starts"
                              : root.status || "Every change applies live and is saved to config.toml"
                        color: "#000000"
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
