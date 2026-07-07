// cartelitos — cada línea de letra aparece como diálogo de error Win95
// en posición random de la pantalla derecha (DP-6).
// - El cartel de la línea que suena AHORA es 1.3x más grande y sin efectos.
// - Los viejos vibran como holograma cyberpunk y mueren glitcheando (CRT).
// - Íconos estilo Windows random: error / advertencia / pregunta / info.
// - Al cambiar de canción aparece un cartel "Now Playing" con la portada.
// - Arrastrables desde la barra de título. Yes/Cancel/✕ cierran; "No" duplica.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    property int maxDialogs: 12
    property string targetScreen: "DP-6"
    property int serial: 0
    property int currentLyricSerial: -1
    property var dialogList: []

    function screenByName(name) {
        const ss = Quickshell.screens;
        for (let i = 0; i < ss.length; i++)
            if (ss[i].name === name)
                return ss[i];
        return ss[0];
    }

    function randomIcon() {
        const r = Math.random();
        if (r < 0.40) return "warning";
        if (r < 0.65) return "error";
        if (r < 0.85) return "question";
        return "info";
    }

    function pushDialog(entry, markCurrent) {
        entry.serial = root.serial++;
        entry.screenName = root.targetScreen;
        entry.rx = 0.02 + Math.random() * 0.90;
        entry.ry = 0.02 + Math.random() * 0.84;
        entry.deathAge = 3 + Math.floor(Math.random() * 5); // muere entre 3 y 7 carteles después
        if (markCurrent)
            root.currentLyricSerial = entry.serial;
        let arr = root.dialogList.slice();
        arr.push(entry);
        while (arr.length > root.maxDialogs)
            arr.shift();
        root.dialogList = arr;
    }

    function show(text, title, icon) {
        pushDialog({ kind: "lyric", text: text, title: title || "Spotify", icon: icon || randomIcon(), art: "" }, true);
    }

    function nowPlaying(title, artist, album, art) {
        pushDialog({ kind: "np", text: artist + (album ? " — " + album : ""), title: title || "Now Playing", icon: "info", art: art || "" }, true);
    }

    // "No" duplica el cartel (el original queda)
    function duplicate(d) {
        pushDialog({ kind: d.kind, text: d.text, title: d.title, icon: d.icon, art: d.art }, false);
    }

    function dismiss(serial) {
        root.dialogList = root.dialogList.filter(d => d.serial !== serial);
    }

    // El daemon manda eventos JSON por línea:
    // {"cmd":"show","text","title"} / {"cmd":"np","title","artist","album","art"} / {"cmd":"clear"}
    SocketServer {
        active: true
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/cartelitos.sock`
        handler: Socket {
            parser: SplitParser {
                onRead: message => {
                    try {
                        const ev = JSON.parse(message);
                        if (ev.cmd === "show")
                            root.show(ev.text, ev.title, ev.icon);
                        else if (ev.cmd === "np")
                            root.nowPlaying(ev.title, ev.artist, ev.album, ev.art);
                        else if (ev.cmd === "clear")
                            root.dialogList = [];
                    } catch (e) {
                        console.log("cartelitos: evento inválido:", message);
                    }
                }
            }
        }
    }

    Variants {
        model: root.dialogList

        PanelWindow {
            id: win
            required property var modelData

            // edad = cuántos carteles aparecieron después de éste
            readonly property int age: root.serial - modelData.serial - 1
            readonly property bool current: modelData.serial === root.currentLyricSerial
            readonly property real glitchiness: Math.min(age / 5, 1)
            readonly property bool isNp: modelData.kind === "np"
            property bool dying: false

            // factor de tamaño: el cartel actual es más grande
            readonly property real k: current ? 1.3 : 1.0
            readonly property real iconW: isNp ? 72 : 32

            // offset de arrastre manual
            property real dx: 0
            property real dy: 0

            // estado del glitch
            property bool burst: false
            property real jx: 0
            property real jy: 0
            property real burstOpacity: 1
            property real holoOpacity: 1
            property color burstTint: "#ff00ff"
            property var burstSeed: []

            screen: root.screenByName(modelData.screenName)
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "cartelitos"
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            TextMetrics {
                id: tm
                text: win.modelData.text
                font.pixelSize: Math.round(13 * win.k)
            }

            readonly property int dlgW: Math.max(300 * k, Math.min(tm.width, 360 * k) + (iconW + 78) * k)

            implicitWidth: dlgW
            implicitHeight: frame.implicitHeight

            anchors { left: true; top: true }
            margins {
                left: Math.min(Math.max(0, Math.round(modelData.rx * (win.screen.width - dlgW) + win.dx + win.jx)), win.screen.width - 80)
                top: Math.min(Math.max(0, Math.round(modelData.ry * (win.screen.height - 200) + win.dy + win.jy)), win.screen.height - 60)
            }

            // paleta tipo GPU muriéndose: magenta, verde, morado, cyan, rosa
            readonly property var gpuPalette: ["#ff00ff", "#00ff00", "#7b2bff", "#00ffff", "#ff0080", "#39ff14", "#000000", "#ffffff"]

            function scramble(strength) {
                jx = (Math.random() - 0.5) * 26 * strength;
                jy = (Math.random() - 0.5) * 16 * strength;
                burstOpacity = 1 - Math.random() * 0.5 * strength;
                burstTint = gpuPalette[Math.floor(Math.random() * 5)];
                let seed = [];
                const n = 3 + Math.floor(Math.random() * (4 + 6 * strength));
                for (let i = 0; i < n; i++) {
                    const block = Math.random() < 0.5; // bloque de corrupción vs scanline
                    seed.push({
                        x: block ? Math.random() * 0.75 : -0.1,
                        y: Math.random() * 0.92,
                        w: block ? 0.12 + Math.random() * 0.45 : 1.2,
                        h: block ? 8 + Math.random() * 34 * strength : 2 + Math.random() * 5,
                        c: gpuPalette[Math.floor(Math.random() * gpuPalette.length)],
                        o: 0.5 + Math.random() * 0.45,
                    });
                }
                burstSeed = seed;
            }

            function doBurst(strength) {
                scramble(strength);
                burst = true;
                burstEnd.interval = 60 + Math.random() * 90;
                burstEnd.restart();
            }

            Timer {
                id: burstEnd
                onTriggered: {
                    if (win.dying)
                        return;
                    win.burst = false;
                    win.jx = 0;
                    win.jy = 0;
                    win.burstOpacity = 1;
                }
            }

            // vibración de holograma: micro-jitter permanente (solo carteles viejos)
            Timer {
                interval: 90
                repeat: true
                running: !win.dying && !win.current
                onTriggered: {
                    if (win.burst)
                        return;
                    const amp = 1.8 + 1.4 * win.glitchiness;
                    win.jx = (Math.random() - 0.5) * 2 * amp;
                    win.jy = (Math.random() - 0.5) * 2 * amp;
                }
            }

            // flicker de holograma en la opacidad (solo carteles viejos)
            Timer {
                interval: 140
                repeat: true
                running: !win.dying && !win.current
                onTriggered: win.holoOpacity = 1 - Math.random() * (0.16 + 0.1 * win.glitchiness)
            }

            // bursts de glitch espontáneos y frecuentes (solo carteles viejos)
            Timer {
                running: !win.dying && !win.current
                repeat: true
                interval: 400
                onTriggered: {
                    interval = 160 + Math.random() * (550 - 380 * win.glitchiness);
                    if (Math.random() < 0.55 + 0.4 * win.glitchiness)
                        win.doBurst(0.6 + win.glitchiness);
                }
            }

            // al dejar de ser el actual, el achique queda tapado por un burst
            onCurrentChanged: {
                if (!current && !dying)
                    doBurst(1.2);
            }

            onAgeChanged: {
                if (age >= modelData.deathAge && !dying)
                    die();
            }

            function die() {
                dying = true;
                burst = true;
                deathAnim.start();
                deathEnd.start();
            }

            // muerte: jitter violento continuo + colapso vertical CRT
            Timer {
                interval: 45
                repeat: true
                running: win.dying
                onTriggered: win.scramble(1.6)
            }
            Timer {
                id: deathEnd
                interval: 380
                onTriggered: root.dismiss(win.modelData.serial)
            }

            property real deathScale: 1
            property real deathOpacity: 1
            SequentialAnimation {
                id: deathAnim
                PauseAnimation { duration: 140 }
                ParallelAnimation {
                    NumberAnimation { target: win; property: "deathScale"; to: 0.04; duration: 200; easing.type: Easing.InQuad }
                    NumberAnimation { target: win; property: "deathOpacity"; to: 0; duration: 230 }
                }
            }

            // marco con bevel clásico
            Rectangle {
                id: frame
                anchors.fill: parent
                implicitHeight: column.implicitHeight + 4
                color: "#c0c0c0"
                clip: true
                opacity: win.burstOpacity * win.deathOpacity * win.holoOpacity
                transform: Scale {
                    origin.y: frame.height / 2
                    yScale: win.deathScale
                }

                Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 2; color: "#ffffff" }
                Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 2; color: "#ffffff" }
                Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 2; color: "#404040" }
                Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 2; color: "#404040" }

                Column {
                    id: column
                    anchors { fill: parent; margins: 2 }

                    // barra de título (arrastrable)
                    Rectangle {
                        width: parent.width
                        height: Math.round(26 * win.k)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#000080" }
                            GradientStop { position: 1.0; color: "#1084d0" }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property real px: 0
                            property real py: 0
                            onPressed: m => { px = m.x; py = m.y; }
                            onPositionChanged: m => {
                                if (!pressed)
                                    return;
                                win.dx += m.x - px;
                                win.dy += m.y - py;
                            }
                        }

                        Text {
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter; right: closeBtn.left; rightMargin: 6 }
                            text: win.modelData.title
                            color: "#ffffff"
                            font.pixelSize: Math.round(12 * win.k)
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: closeBtn
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            width: Math.round(18 * win.k)
                            height: Math.round(16 * win.k)
                            color: closeMa.pressed ? "#a8a8a8" : "#c0c0c0"

                            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 1; color: "#ffffff" }
                            Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 1; color: "#ffffff" }
                            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 1; color: "#404040" }
                            Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 1; color: "#404040" }

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: "#000000"
                                font.pixelSize: Math.round(10 * win.k)
                                font.bold: true
                            }
                            MouseArea {
                                id: closeMa
                                anchors.fill: parent
                                onClicked: root.dismiss(win.modelData.serial)
                            }
                        }
                    }

                    // cuerpo: ícono (o portada) + texto
                    Row {
                        width: parent.width
                        padding: Math.round(14 * win.k)
                        spacing: Math.round(14 * win.k)

                        // portada de álbum (solo Now Playing)
                        Image {
                            visible: win.isNp && win.modelData.art !== ""
                            width: Math.round(72 * win.k)
                            height: Math.round(72 * win.k)
                            source: win.isNp ? win.modelData.art : ""
                            fillMode: Image.PreserveAspectCrop
                        }

                        // ícono estilo Windows (error/advertencia/pregunta/info)
                        Canvas {
                            visible: !win.isNp || win.modelData.art === ""
                            width: Math.round(32 * win.k)
                            height: Math.round(32 * win.k)
                            onWidthChanged: requestPaint()
                            onPaint: {
                                const c = getContext("2d");
                                c.reset();
                                c.scale(width / 32, height / 32);
                                const icon = win.modelData.icon;
                                if (icon === "warning") {
                                    c.beginPath();
                                    c.moveTo(16, 2);
                                    c.lineTo(30, 29);
                                    c.lineTo(2, 29);
                                    c.closePath();
                                    c.fillStyle = "#ffd800";
                                    c.fill();
                                    c.lineWidth = 1.5;
                                    c.strokeStyle = "#000000";
                                    c.stroke();
                                    c.fillStyle = "#000000";
                                    c.fillRect(14.6, 11, 2.8, 10);
                                    c.fillRect(14.6, 23.5, 2.8, 2.8);
                                } else if (icon === "error") {
                                    c.beginPath();
                                    c.arc(16, 16, 14, 0, Math.PI * 2);
                                    c.fillStyle = "#d32f2f";
                                    c.fill();
                                    c.strokeStyle = "#7a0000";
                                    c.lineWidth = 1;
                                    c.stroke();
                                    c.strokeStyle = "#ffffff";
                                    c.lineWidth = 3.2;
                                    c.lineCap = "round";
                                    c.beginPath();
                                    c.moveTo(10.5, 10.5); c.lineTo(21.5, 21.5);
                                    c.moveTo(21.5, 10.5); c.lineTo(10.5, 21.5);
                                    c.stroke();
                                } else {
                                    // question / info: círculo azul con símbolo blanco
                                    c.beginPath();
                                    c.arc(16, 16, 14, 0, Math.PI * 2);
                                    c.fillStyle = "#2458c8";
                                    c.fill();
                                    c.strokeStyle = "#0a1f66";
                                    c.lineWidth = 1;
                                    c.stroke();
                                    c.fillStyle = "#ffffff";
                                    c.textAlign = "center";
                                    c.textBaseline = "middle";
                                    c.font = "bold 20px sans-serif";
                                    c.fillText(icon === "question" ? "?" : "i", 16, 17);
                                }
                            }
                        }

                        Text {
                            width: parent.width - (win.iconW + 14 + 28) * win.k
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.modelData.text
                            color: "#000000"
                            font.pixelSize: Math.round(13 * win.k)
                            font.bold: win.isNp
                            wrapMode: Text.Wrap
                        }
                    }

                    // botones: Yes/Cancel cierran, "No" duplica el cartel; Now Playing solo OK
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Math.round(8 * win.k)
                        bottomPadding: Math.round(12 * win.k)

                        Repeater {
                            model: win.isNp ? ["OK"] : ["Yes", "No", "Cancel"]

                            Rectangle {
                                required property string modelData
                                required property int index
                                width: Math.round(76 * win.k)
                                height: Math.round(24 * win.k)
                                color: btnMa.pressed ? "#a8a8a8" : "#c0c0c0"
                                border.width: index === 0 ? 1 : 0
                                border.color: "#000000"

                                Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right; margins: index === 0 ? 1 : 0 } height: 1; color: "#ffffff" }
                                Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom; margins: index === 0 ? 1 : 0 } width: 1; color: "#ffffff" }
                                Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: index === 0 ? 1 : 0 } height: 1; color: "#404040" }
                                Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom; margins: index === 0 ? 1 : 0 } width: 1; color: "#404040" }

                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    color: "#000000"
                                    font.pixelSize: Math.round(12 * win.k)
                                }

                                // rectángulo punteado de foco en el botón default
                                Rectangle {
                                    visible: parent.index === 0
                                    anchors { fill: parent; margins: 4 }
                                    color: "transparent"
                                    border.width: 1
                                    border.color: "#000000"
                                    opacity: 0.55
                                }

                                MouseArea {
                                    id: btnMa
                                    anchors.fill: parent
                                    onClicked: {
                                        if (parent.modelData === "No")
                                            root.duplicate(win.modelData);
                                        else
                                            root.dismiss(win.modelData.serial);
                                    }
                                }
                            }
                        }
                    }
                }

                // fringe cromático (aberración RGB de holograma), solo viejos
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 2
                    color: "#ff00ff"
                    opacity: win.current ? 0 : 0.40
                }
                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 2
                    color: "#00ffff"
                    opacity: win.current ? 0 : 0.40
                }

                // banda de escaneo que recorre el cartel (holograma), solo viejos
                Rectangle {
                    id: sweep
                    x: 0
                    visible: !win.current
                    width: frame.width
                    height: Math.round(10 * win.k)
                    color: "#ffffff"
                    opacity: 0.11
                    NumberAnimation on y {
                        from: -12
                        to: 400
                        duration: 1800 + (win.modelData.serial % 5) * 300
                        loops: Animation.Infinite
                    }
                }

                // tinte de corrupción durante el burst
                Rectangle {
                    anchors.fill: parent
                    visible: win.burst
                    color: win.burstTint
                    opacity: win.dying ? 0.35 : 0.18
                }

                // bloques y scanlines de corrupción tipo artefactos de GPU
                Repeater {
                    model: win.burst ? win.burstSeed : []
                    Rectangle {
                        required property var modelData
                        x: modelData.x * frame.width
                        y: modelData.y * frame.height
                        width: modelData.w * frame.width
                        height: modelData.h
                        color: modelData.c
                        opacity: modelData.o
                    }
                }
            }
        }
    }
}
