// fatal-lyrics — letras de Spotify como diálogos de error Win95 glitcheados.
// - El cartel de la línea que suena AHORA es más grande y (por default) sin efectos.
// - Los viejos vibran como holograma, quedan con la ventana PARTIDA (tearing) y
//   mueren glitcheando con colapso CRT.
// - Config: ~/.config/cartelitos/config.toml (el daemon la manda por el socket).
// - Viejos: click = cerrar, barra de título = arrastrar. Actual: botones completos.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

ShellRoot {
    id: root

    // config (defaults; el daemon los pisa con el evento "config")
    // screen: "auto" | "all" | nombre | lista de nombres
    property var targetScreen: "auto"
    property int maxDialogs: 12
    property real cfgScale: 1.0
    property real cfgCurrentScale: 1.3
    property string spawnArea: "full"
    property string glitchLevel: "normal"
    property bool effectsOnCurrent: false
    property bool tearingOn: true
    property int deathAgeMin: 3
    property int deathAgeMax: 7
    property int maxLifetime: 60
    property bool clickThrough: false
    property bool trollNo: true
    property bool burnIn: true
    property bool cascadeDeath: true
    property bool karaokeOn: false
    property string npCorner: "top-right"
    property int npMargin: 14
    property bool npVinyl: true

    // estado del Now Playing (ventana propia, no es un diálogo);
    // compartido entre pantallas para que la animación vaya sincronizada
    property bool npShown: false
    property string npTitle: ""
    property string npInfo: ""
    property string npArt: ""
    property real npProgress: 0
    property bool npDocked: false
    property int npSerial: 0

    Timer {
        id: npDockTimer
        interval: 4000
        onTriggered: root.npDocked = true
    }

    // multiplicadores según nivel de glitch
    readonly property real gProb: glitchLevel === "off" ? 0 : glitchLevel === "soft" ? 0.5 : glitchLevel === "aggressive" ? 1.6 : 1
    readonly property real gStr: glitchLevel === "off" ? 0 : glitchLevel === "soft" ? 0.6 : glitchLevel === "aggressive" ? 1.5 : 1

    property int serial: 0
    property int currentLyricSerial: -1
    property var dialogList: []

    // cascada: cada incremento dispara la muerte en cadena de los carteles vivos
    property int clearGen: 0

    // posición de la canción (eventos "pos" a 1 Hz) para el karaoke;
    // se extrapola con el reloj local, con tope por si el player se pausó
    property real posAbs: 0
    property double posAt: 0
    function songPos() {
        return posAbs + Math.min((Date.now() - posAt) / 1000, 1.5);
    }

    // pantallas donde corre el overlay según la config
    function matchScreens(v) {
        const ss = Quickshell.screens;
        if (v === "all")
            return [...ss];
        if (Array.isArray(v)) {
            const r = ss.filter(s => v.indexOf(s.name) >= 0);
            return r.length > 0 ? r : [ss[0]];
        }
        for (let i = 0; i < ss.length; i++)
            if (ss[i].name === v)
                return [ss[i]];
        return [ss[0]];
    }
    readonly property var activeScreens: matchScreens(targetScreen)

    function randomIcon() {
        const r = Math.random();
        if (r < 0.40) return "warning";
        if (r < 0.65) return "error";
        if (r < 0.85) return "question";
        return "info";
    }

    function spawnPos() {
        let rx = 0.02 + Math.random() * 0.90;
        let ry = 0.02 + Math.random() * 0.84;
        const a = root.spawnArea;
        if (a === "top")
            ry = 0.02 + Math.random() * 0.23;
        else if (a === "bottom")
            ry = 0.60 + Math.random() * 0.26;
        else if (a === "left")
            rx = 0.02 + Math.random() * 0.28;
        else if (a === "right")
            rx = 0.64 + Math.random() * 0.28;
        else if (a === "edges") {
            if (Math.random() < 0.5)
                rx = Math.random() < 0.5 ? 0.02 + Math.random() * 0.12 : 0.78 + Math.random() * 0.14;
            else
                ry = Math.random() < 0.5 ? 0.02 + Math.random() * 0.12 : 0.72 + Math.random() * 0.14;
        }
        return { rx: rx, ry: ry };
    }

    function pushDialog(entry, markCurrent) {
        const pos = spawnPos();
        entry.serial = root.serial++;
        entry.rx = pos.rx;
        entry.ry = pos.ry;
        entry.deathAge = root.deathAgeMin + Math.floor(Math.random() * (root.deathAgeMax - root.deathAgeMin + 1));
        if (markCurrent)
            root.currentLyricSerial = entry.serial;
        let arr = root.dialogList.slice();
        arr.push(entry);
        while (arr.length > root.maxDialogs)
            arr.shift();
        root.dialogList = arr;
    }

    function show(text, title, icon, t0, t1) {
        pushDialog({
            text: text, title: title || "Spotify", icon: icon || randomIcon(),
            t0: t0 ?? 0, t1: t1 ?? 0,
        }, true);
    }

    function nowPlaying(title, artist, album, art) {
        npTitle = title || "Now Playing";
        npInfo = artist + (album ? " — " + album : "");
        npArt = art || "";
        npProgress = 0;
        npShown = true;
        npDocked = false;
        npSerial++;
        npDockTimer.restart();
    }

    // botón "No" (si troll_no): duplica el cartel, el original queda
    function duplicate(d) {
        pushDialog({ text: d.text, title: d.title, icon: d.icon }, false);
    }

    function dismiss(serial) {
        root.dialogList = root.dialogList.filter(d => d.serial !== serial);
    }

    function applyConfig(ev) {
        targetScreen = ev.screen ?? targetScreen;
        maxDialogs = ev.max_dialogs ?? maxDialogs;
        cfgScale = ev.scale ?? cfgScale;
        cfgCurrentScale = ev.current_scale ?? cfgCurrentScale;
        spawnArea = ev.spawn_area ?? spawnArea;
        glitchLevel = ev.glitch ?? glitchLevel;
        effectsOnCurrent = ev.effects_on_current ?? effectsOnCurrent;
        tearingOn = ev.tearing ?? tearingOn;
        deathAgeMin = ev.death_age_min ?? deathAgeMin;
        deathAgeMax = ev.death_age_max ?? deathAgeMax;
        maxLifetime = ev.max_lifetime ?? maxLifetime;
        clickThrough = ev.click_through ?? clickThrough;
        trollNo = ev.troll_no ?? trollNo;
        burnIn = ev.burn_in ?? burnIn;
        cascadeDeath = ev.cascade ?? cascadeDeath;
        karaokeOn = ev.karaoke ?? karaokeOn;
        npCorner = ev.np_corner ?? npCorner;
        npMargin = ev.np_margin ?? npMargin;
        npVinyl = ev.np_vinyl ?? npVinyl;
    }

    // El daemon manda eventos JSON por línea: config / show / np / clear
    SocketServer {
        active: true
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/cartelitos.sock`
        handler: Socket {
            parser: SplitParser {
                onRead: message => {
                    try {
                        const ev = JSON.parse(message);
                        if (ev.cmd === "show")
                            root.show(ev.text, ev.title, ev.icon, ev.t0, ev.t1);
                        else if (ev.cmd === "np")
                            root.nowPlaying(ev.title, ev.artist, ev.album, ev.art);
                        else if (ev.cmd === "pos") {
                            root.npProgress = ev.l > 0 ? Math.min(ev.p / ev.l, 1) : 0;
                            root.posAbs = ev.p;
                            root.posAt = Date.now();
                        } else if (ev.cmd === "clear") {
                            root.npShown = false;
                            // cascada: en vez de esfumarse, mueren en cadena (dominó CRT)
                            if (root.cascadeDeath && root.dialogList.length > 0)
                                root.clearGen++;
                            else
                                root.dialogList = [];
                        } else if (ev.cmd === "config")
                            root.applyConfig(ev);
                    } catch (e) {
                        console.log("cartelitos: evento inválido:", message);
                    }
                }
            }
        }
    }

    // una instancia del overlay por pantalla activa ("all"/lista = varias);
    // cada monitor spawnea los carteles en posiciones propias
    Variants {
        model: root.activeScreens

        Scope {
            id: perScreen
            required property var modelData
            readonly property var scr: modelData

            Variants {
                model: root.dialogList

                PanelWindow {
                    id: win
                    required property var modelData

                    // edad = cuántos carteles aparecieron después de éste
                    readonly property int age: root.serial - modelData.serial - 1
                    readonly property bool current: modelData.serial === root.currentLyricSerial
                    readonly property real glitchiness: Math.min(age / 5, 1)
                    property bool dying: false
                    property bool ghosting: false

                    // factor de tamaño: config global + extra del cartel actual
                    readonly property real k: root.cfgScale * (current ? root.cfgCurrentScale : 1.0)
                    readonly property real iconW: 32
                    readonly property bool fx: !current || root.effectsOnCurrent

                    // karaoke: la línea actual se pinta palabra por palabra; el timing
                    // por palabra se estima proporcional al largo (lrclib solo da líneas)
                    readonly property bool karaokeActive: root.karaokeOn && current
                        && (modelData.t1 || 0) > (modelData.t0 || 0)
                    property string karaokeText: ""
                    function htmlEsc(s) {
                        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                    }
                    function updateKaraoke() {
                        const words = modelData.text.split(" ").filter(w => w.length > 0);
                        if (words.length === 0)
                            return;
                        // termina de pintar ~1 s antes del próximo cartel: si no, la
                        // última palabra nunca llega a verse pintada (t1 = ya la reemplazó)
                        const dur = modelData.t1 - modelData.t0;
                        const lead = Math.min(1.0, dur * 0.35);
                        const f = Math.max(0, Math.min(
                            (root.songPos() - modelData.t0) / Math.max(dur - lead, 0.5), 1));
                        let total = 0;
                        const weights = words.map(w => { const n = w.length + 1; total += n; return n; });
                        let acc = 0, cut = 0;
                        for (let i = 0; i < words.length; i++) {
                            acc += weights[i];
                            if (acc <= f * total + 0.001)
                                cut = i + 1;
                        }
                        let out = "";
                        if (cut > 0)
                            out = '<font color="#000080">' + htmlEsc(words.slice(0, cut).join(" ")) + "</font>";
                        if (cut > 0 && cut < words.length)
                            out += " ";
                        if (cut < words.length)
                            out += htmlEsc(words.slice(cut).join(" "));
                        karaokeText = out;
                    }
                    Timer {
                        interval: 120
                        repeat: true
                        running: win.karaokeActive
                        triggeredOnStart: true
                        onTriggered: win.updateKaraoke()
                    }

                    // tearing: la ventana partida en franjas desplazadas (solo viejos)
                    readonly property int tearPad: 22
                    property var tearSeed: []
                    readonly property bool torn: root.tearingOn && !current && tearSeed.length > 0

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

                    screen: perScreen.scr
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "cartelitos"
                    exclusionMode: ExclusionMode.Ignore
                    color: "transparent"

                    // click_through: región de input vacía, el mouse pasa de largo
                    Region { id: emptyMask }
                    mask: root.clickThrough ? emptyMask : null

                    TextMetrics {
                        id: tm
                        text: win.modelData.text
                        font.pixelSize: Math.round(13 * win.k)
                    }

                    readonly property int dlgW: Math.max(300 * k, Math.min(tm.width, 360 * k) + (iconW + 78) * k)

                    implicitWidth: dlgW + tearPad * 2
                    implicitHeight: content.height

                    // en multi-pantalla cada monitor randomiza su propia posición
                    // (mismo cartel, lugar distinto en cada una)
                    property real prx: modelData.rx
                    property real pry: modelData.ry
                    Component.onCompleted: {
                        if (root.activeScreens.length > 1) {
                            const p = root.spawnPos();
                            prx = p.rx;
                            pry = p.ry;
                        }
                    }

                    readonly property real baseX: prx * (screen.width - implicitWidth)
                    readonly property real baseY: pry * (screen.height - 200)

                    // arrastre: delta clampeado contra la base (si no, en los bordes el acumulado
                    // se dispara) y jitter fuera de los márgenes mientras se arrastra — el jitter
                    // metido en la posición realimentaba el delta y la ventana "salía volando"
                    property bool dragHeld: false
                    function dragBy(ddx, ddy) {
                        dx = Math.max(-baseX, Math.min(dx + ddx, screen.width - 80 - baseX));
                        dy = Math.max(-baseY, Math.min(dy + ddy, screen.height - 60 - baseY));
                    }

                    anchors { left: true; top: true }
                    margins {
                        left: Math.round(Math.min(Math.max(0, win.baseX + win.dx + (win.dragHeld ? 0 : win.jx)), win.screen.width - 80))
                        top: Math.round(Math.min(Math.max(0, win.baseY + win.dy + (win.dragHeld ? 0 : win.jy)), win.screen.height - 60))
                    }

                    // paleta tipo GPU muriéndose: magenta, verde, morado, cyan, rosa
                    readonly property var gpuPalette: ["#ff00ff", "#00ff00", "#7b2bff", "#00ffff", "#ff0080", "#39ff14", "#000000", "#ffffff"]

                    function scramble(strength) {
                        jx = (Math.random() - 0.5) * 26 * strength;
                        jy = (Math.random() - 0.5) * 16 * strength;
                        burstOpacity = 1 - Math.random() * 0.5 * Math.min(strength, 1.2);
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

                    // genera los cortes de tearing; dxAmp = desplazamiento máximo de cada franja
                    function genTear(dxAmp) {
                        if (!root.tearingOn || current)
                            return;
                        const H = content.height;
                        if (H <= 4)
                            return;
                        const cuts = 2 + Math.floor(Math.random() * (2 + 3 * glitchiness));
                        let ys = [0, H];
                        for (let i = 0; i < cuts; i++)
                            ys.push(Math.random() * H);
                        ys.sort((a, b) => a - b);
                        let seed = [];
                        for (let i = 0; i < ys.length - 1; i++) {
                            const h = ys[i + 1] - ys[i];
                            if (h < 2)
                                continue;
                            seed.push({ y0: ys[i], h: h, dx: (Math.random() - 0.5) * 2 * dxAmp });
                        }
                        tearSeed = seed;
                    }

                    readonly property real tearBase: 3 + 6 * glitchiness

                    function doBurst(strength) {
                        scramble(strength);
                        genTear(10 + 16 * strength);
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
                            win.genTear(win.tearBase);
                        }
                    }

                    // vibración de holograma: micro-jitter permanente
                    Timer {
                        interval: 90
                        repeat: true
                        running: !win.dying && win.fx && root.gStr > 0
                        onTriggered: {
                            if (win.burst)
                                return;
                            const amp = (1.8 + 1.4 * win.glitchiness) * root.gStr;
                            win.jx = (Math.random() - 0.5) * 2 * amp;
                            win.jy = (Math.random() - 0.5) * 2 * amp;
                        }
                    }

                    // flicker de holograma en la opacidad
                    Timer {
                        interval: 140
                        repeat: true
                        running: !win.dying && win.fx && root.gStr > 0
                        onTriggered: win.holoOpacity = 1 - Math.random() * (0.16 + 0.1 * win.glitchiness) * root.gStr
                    }

                    // bursts de glitch espontáneos y frecuentes
                    Timer {
                        running: !win.dying && win.fx && root.gProb > 0
                        repeat: true
                        interval: 400
                        onTriggered: {
                            interval = 160 + Math.random() * (550 - 380 * win.glitchiness);
                            if (Math.random() < (0.55 + 0.4 * win.glitchiness) * root.gProb)
                                win.doBurst((0.6 + win.glitchiness) * root.gStr);
                        }
                    }

                    // vida máxima: que no queden flotando infinito si la música se paró
                    Timer {
                        interval: Math.max(1000, root.maxLifetime * 1000)
                        running: root.maxLifetime > 0 && !win.dying
                        onTriggered: win.die()
                    }

                    // cascada: al limpiar mueren en cadena, del más viejo al más nuevo
                    Connections {
                        target: root
                        enabled: !win.dying
                        function onClearGenChanged() {
                            const rank = root.dialogList.findIndex(d => d.serial === win.modelData.serial);
                            cascadeTimer.interval = 60 + Math.max(0, rank) * 110;
                            cascadeTimer.restart();
                        }
                    }
                    Timer {
                        id: cascadeTimer
                        onTriggered: {
                            if (!win.dying)
                                win.die();
                        }
                    }

                    // al dejar de ser el actual: burst que tapa el achique + tearing permanente
                    onCurrentChanged: {
                        if (!current && !dying) {
                            if (root.gStr > 0)
                                doBurst(1.2);
                            else
                                genTear(tearBase);
                        }
                    }

                    onAgeChanged: {
                        if (age >= modelData.deathAge && !dying)
                            die();
                        else if (age > 0 && !dying)
                            genTear(tearBase); // más viejo → cortes nuevos, nunca queda sana
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
                        running: win.dying && !win.ghosting
                        onTriggered: win.scramble(1.6)
                    }
                    Timer {
                        id: deathEnd
                        interval: root.burnIn ? 2900 : 380
                        onTriggered: root.dismiss(win.modelData.serial)
                    }

                    // burn-in: tras el colapso queda una sombra quemada estática que se apaga
                    Timer {
                        interval: 370
                        running: win.dying && root.burnIn
                        onTriggered: {
                            win.ghosting = true;
                            win.burst = false;
                            win.jx = 0;
                            win.jy = 0;
                            ghostFade.start();
                        }
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

                    // contenido real del cartel; cuando está "torn" se oculta y se
                    // renderiza vía franjas ShaderEffectSource desplazadas
                    Item {
                        id: content
                        x: win.tearPad
                        y: 0
                        width: win.dlgW
                        height: frame.implicitHeight
                        visible: !win.ghosting

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
                                        onPressed: m => { px = m.x; py = m.y; win.dragHeld = true; }
                                        onReleased: win.dragHeld = false
                                        onCanceled: win.dragHeld = false
                                        onPositionChanged: m => {
                                            if (pressed)
                                                win.dragBy(m.x - px, m.y - py);
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

                                // cuerpo: ícono + texto
                                Row {
                                    width: parent.width
                                    padding: Math.round(14 * win.k)
                                    spacing: Math.round(14 * win.k)

                                    // ícono estilo Windows (error/advertencia/pregunta/info)
                                    Canvas {
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
                                            } else if (icon === "question") {
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
                                                c.fillText("?", 16, 17);
                                            } else {
                                                // info: círculo azul, "i" dibujada (punto + palo, bien centrada)
                                                c.beginPath();
                                                c.arc(16, 16, 14, 0, Math.PI * 2);
                                                c.fillStyle = "#2458c8";
                                                c.fill();
                                                c.strokeStyle = "#0a1f66";
                                                c.lineWidth = 1;
                                                c.stroke();
                                                c.fillStyle = "#ffffff";
                                                c.beginPath();
                                                c.arc(16, 10.2, 2.3, 0, Math.PI * 2);
                                                c.fill();
                                                c.fillRect(14.6, 14.2, 2.8, 9.4);
                                            }
                                        }
                                    }

                                    Text {
                                        width: parent.width - (win.iconW + 14 + 28) * win.k
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: win.karaokeActive ? win.karaokeText : win.modelData.text
                                        textFormat: win.karaokeActive ? Text.StyledText : Text.PlainText
                                        color: "#000000"
                                        font.pixelSize: Math.round(13 * win.k)
                                        wrapMode: Text.Wrap
                                    }
                                }

                                // botones: Yes/Cancel cierran, "No" duplica (si troll_no)
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: Math.round(8 * win.k)
                                    bottomPadding: Math.round(12 * win.k)

                                    Repeater {
                                        model: ["Yes", "No", "Cancel"]

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
                                                    if (parent.modelData === "No" && root.trollNo)
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
                                x: 0
                                visible: !win.current && root.gStr > 0
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

                    // franjas de tearing: la ventana partida de verdad
                    Repeater {
                        model: win.torn ? win.tearSeed : []
                        ShaderEffectSource {
                            required property var modelData
                            sourceItem: content
                            hideSource: true
                            live: true
                            sourceRect: Qt.rect(0, modelData.y0, content.width, modelData.h)
                            x: win.tearPad + modelData.dx
                            y: modelData.y0
                            width: content.width
                            height: modelData.h
                        }
                    }

                    // burn-in: silueta quemada del cartel, estática, que se desvanece
                    Item {
                        id: ghost
                        x: win.tearPad
                        width: win.dlgW
                        height: content.height
                        visible: win.ghosting
                        opacity: 0

                        Rectangle { anchors.fill: parent; color: "#e8d5ff"; opacity: 0.10 }
                        Rectangle { width: parent.width; height: Math.round(26 * win.k) + 2; color: "#b9a4ff"; opacity: 0.16 }
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: 1
                            border.color: "#d9c9ff"
                            opacity: 0.35
                        }
                        // resto de la línea del colapso CRT
                        Rectangle {
                            y: parent.height / 2 - 1
                            width: parent.width
                            height: 2
                            color: "#ffffff"
                            opacity: 0.5
                        }
                    }
                    NumberAnimation {
                        id: ghostFade
                        target: ghost
                        property: "opacity"
                        from: 1
                        to: 0
                        duration: 2400
                        easing.type: Easing.OutQuad
                    }

                    // input de carteles viejos (torn): click = cerrar, título = arrastrar
                    MouseArea {
                        anchors.fill: parent
                        enabled: win.torn && !win.ghosting
                        property real px: 0
                        property real py: 0
                        property bool dragging: false
                        onPressed: m => {
                            dragging = m.y < Math.round(26 * win.k) + 6;
                            px = m.x;
                            py = m.y;
                            if (dragging)
                                win.dragHeld = true;
                        }
                        onReleased: win.dragHeld = false
                        onCanceled: win.dragHeld = false
                        onPositionChanged: m => {
                            if (dragging && pressed)
                                win.dragBy(m.x - px, m.y - py);
                        }
                        onClicked: {
                            if (!dragging)
                                root.dismiss(win.modelData.serial);
                        }
                    }
                }
            }

            // Now Playing: funda de vinilo — aparece grande en el centro al cambiar de
            // canción y a los segundos se estaciona chiquita en una esquina, con barra
            // de progreso Win95. Ventana propia full-screen con máscara solo en la funda.
            PanelWindow {
                id: npWin
                visible: root.npShown
                screen: perScreen.scr
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "cartelitos-np"
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                anchors { left: true; right: true; top: true; bottom: true }

                Region { id: npCardMask; item: npCard }
                Region { id: npEmptyMask }
                mask: root.clickThrough ? npEmptyMask : npCardMask

                readonly property real bigW: Math.round(300 * root.cfgScale * root.cfgCurrentScale)
                readonly property real smallW: Math.round(170 * root.cfgScale)

                // un solo parámetro anima posición y tamaño juntos → trayectoria recta
                property real dockT: root.npDocked ? 1 : 0
                Behavior on dockT { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }

                // disco de vinilo que asoma girando por el costado de la funda
                // (np_vinyl); declarado antes de npCard para quedar DETRÁS
                Item {
                    id: npDisc
                    // asoma hacia el centro de la pantalla: esquinas derechas → izquierda
                    readonly property real dir: root.npCorner.indexOf("right") >= 0 ? -1 : 1
                    property real out: 0
                    Behavior on out { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

                    visible: root.npVinyl && out > 0.01
                    width: (npCard.width - npCard.pad * 2) * 0.96
                    height: width
                    x: npCard.x + (npCard.width - width) / 2 + dir * out * width * 0.42
                    y: npCard.y + npCard.pad + (npCard.width - npCard.pad * 2 - height) / 2

                    // al cambiar de tema el disco arranca guardado y sale a los ~900 ms
                    Connections {
                        target: root
                        function onNpSerialChanged() {
                            npDisc.out = 0;
                            discDelay.restart();
                        }
                    }
                    Timer {
                        id: discDelay
                        interval: 900
                        onTriggered: npDisc.out = 1
                    }

                    Item {
                        anchors.fill: parent
                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1800 // ~33 rpm
                            loops: Animation.Infinite
                            running: npDisc.visible && root.npShown
                        }

                        // vinilo: disco negro con surcos y un brillo que gira con él
                        Canvas {
                            anchors.fill: parent
                            onWidthChanged: requestPaint()
                            onPaint: {
                                const c = getContext("2d");
                                c.reset();
                                c.scale(width / 200, height / 200);
                                c.beginPath();
                                c.arc(100, 100, 99, 0, Math.PI * 2);
                                c.fillStyle = "#101010";
                                c.fill();
                                c.strokeStyle = "rgba(255,255,255,0.05)";
                                c.lineWidth = 1;
                                for (let r = 44; r < 96; r += 4.5) {
                                    c.beginPath();
                                    c.arc(100, 100, r, 0, Math.PI * 2);
                                    c.stroke();
                                }
                                // brillo asimétrico: hace visible la rotación
                                c.strokeStyle = "rgba(255,255,255,0.09)";
                                c.lineWidth = 26;
                                c.beginPath();
                                c.arc(100, 100, 68, -0.5, 0.55);
                                c.stroke();
                                c.beginPath();
                                c.arc(100, 100, 68, Math.PI - 0.5, Math.PI + 0.55);
                                c.stroke();
                                c.strokeStyle = "rgba(255,255,255,0.14)";
                                c.lineWidth = 1.5;
                                c.beginPath();
                                c.arc(100, 100, 98, 0, Math.PI * 2);
                                c.stroke();
                            }
                        }

                        // etiqueta central con la portada, recortada en círculo
                        ClippingRectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.37
                            height: width
                            radius: width / 2
                            color: "#2a2a2a"

                            Image {
                                anchors.fill: parent
                                visible: root.npArt !== ""
                                source: root.npArt
                                fillMode: Image.PreserveAspectCrop
                            }
                        }

                        // agujero del eje
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.045
                            height: width
                            radius: width / 2
                            color: "#000000"
                        }
                    }
                }

                Rectangle {
                    id: npCard
                    readonly property real f: width / 300
                    readonly property int pad: Math.round(8 * f)
                    readonly property int barH: Math.round(16 * f)

                    // extremos del recorrido calculados con el tamaño de cada punta;
                    // x/y/width interpolan con el mismo t → va directo, sin curva
                    function hFor(w) {
                        const g = w / 300;
                        return w + Math.round(4 * g) + Math.round(16 * g) + Math.round(8 * g);
                    }
                    readonly property real cx0: (npWin.width - npWin.bigW) / 2
                    readonly property real cy0: (npWin.height - hFor(npWin.bigW)) / 2
                    // "center": se achica en el lugar, sin viajar a ninguna esquina
                    readonly property real cx1: root.npCorner === "center" ? (npWin.width - npWin.smallW) / 2
                        : root.npCorner.indexOf("left") >= 0 ? root.npMargin
                        : npWin.width - npWin.smallW - root.npMargin
                    readonly property real cy1: root.npCorner === "center" ? (npWin.height - hFor(npWin.smallW)) / 2
                        : root.npCorner.indexOf("top") === 0 ? root.npMargin
                        : npWin.height - hFor(npWin.smallW) - root.npMargin

                    // offset de arrastre manual; se resetea al cambiar de tema
                    property real ox: 0
                    property real oy: 0

                    width: npWin.bigW + (npWin.smallW - npWin.bigW) * npWin.dockT
                    height: width + Math.round(4 * f) + barH + pad
                    x: cx0 + (cx1 - cx0) * npWin.dockT + ox
                    y: cy0 + (cy1 - cy0) * npWin.dockT + oy
                    color: "#c0c0c0"

                    Connections {
                        target: root
                        function onNpSerialChanged() {
                            npCard.ox = 0;
                            npCard.oy = 0;
                        }
                    }

                    // bevel exterior clásico
                    Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 2; color: "#ffffff" }
                    Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 2; color: "#ffffff" }
                    Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 2; color: "#404040" }
                    Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 2; color: "#404040" }

                    // portada con bevel hundido
                    Item {
                        id: npArtBox
                        x: npCard.pad
                        y: npCard.pad
                        width: npCard.width - npCard.pad * 2
                        height: width

                        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 2; color: "#404040" }
                        Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 2; color: "#404040" }
                        Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 2; color: "#ffffff" }
                        Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 2; color: "#ffffff" }

                        Rectangle {
                            anchors { fill: parent; margins: 2 }
                            color: "#3a3a3a"
                            clip: true

                            Image {
                                anchors.fill: parent
                                visible: root.npArt !== ""
                                source: root.npArt
                                fillMode: Image.PreserveAspectCrop
                            }

                            // sin portada: nota sobre gris oscuro
                            Text {
                                visible: root.npArt === ""
                                anchors.centerIn: parent
                                text: "♪"
                                color: "#c0c0c0"
                                font.pixelSize: Math.round(96 * npCard.f)
                            }

                            // banda inferior: tema — artista
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: npText.implicitHeight + Math.round(14 * npCard.f)
                                color: "#000000"
                                opacity: 0.62
                            }
                            Column {
                                id: npText
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                    leftMargin: Math.round(10 * npCard.f)
                                    rightMargin: Math.round(10 * npCard.f)
                                    bottomMargin: Math.round(8 * npCard.f)
                                }
                                spacing: Math.round(2 * npCard.f)

                                Text {
                                    width: parent.width
                                    text: root.npTitle
                                    color: "#ffffff"
                                    font.pixelSize: Math.max(9, Math.round(15 * npCard.f))
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: root.npInfo
                                    color: "#d8d8d8"
                                    font.pixelSize: Math.max(8, Math.round(12 * npCard.f))
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // barra de progreso Win95: bloques azules en canaleta hundida
                    Rectangle {
                        id: npBar
                        x: npCard.pad
                        y: npArtBox.y + npArtBox.height + Math.round(4 * npCard.f)
                        width: npArtBox.width
                        height: npCard.barH
                        color: "#c0c0c0"

                        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 1; color: "#404040" }
                        Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 1; color: "#404040" }
                        Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 1; color: "#ffffff" }
                        Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 1; color: "#ffffff" }

                        Row {
                            id: npBlocks
                            x: 3
                            y: 3
                            spacing: 2
                            readonly property int blockW: Math.max(4, Math.round(9 * npCard.f))
                            readonly property int total: Math.max(1, Math.floor((npBar.width - 4) / (blockW + 2)))

                            Repeater {
                                model: Math.round(root.npProgress * npBlocks.total)
                                Rectangle {
                                    width: npBlocks.blockW
                                    height: npBar.height - 6
                                    color: "#000080"
                                }
                            }
                        }
                    }

                    // arrastrar = moverla donde quieras; click seco = esconder hasta
                    // la próxima canción (umbral de 5 px para distinguirlos)
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: pressed && moved ? Qt.ClosedHandCursor : Qt.ArrowCursor
                        property real px: 0
                        property real py: 0
                        property bool moved: false
                        onPressed: m => {
                            px = m.x;
                            py = m.y;
                            moved = false;
                        }
                        onPositionChanged: m => {
                            if (!pressed)
                                return;
                            const ddx = m.x - px;
                            const ddy = m.y - py;
                            if (!moved && Math.abs(ddx) + Math.abs(ddy) < 5)
                                return;
                            moved = true;
                            const bx = npCard.cx0 + (npCard.cx1 - npCard.cx0) * npWin.dockT;
                            const by = npCard.cy0 + (npCard.cy1 - npCard.cy0) * npWin.dockT;
                            npCard.ox = Math.max(-bx, Math.min(npCard.ox + ddx, npWin.width - npCard.width - bx));
                            npCard.oy = Math.max(-by, Math.min(npCard.oy + ddy, npWin.height - npCard.height - by));
                        }
                        onClicked: {
                            if (!moved)
                                root.npShown = false;
                        }
                    }
                }
            }
        }
    }
}
