// fatal-lyrics — the sliders.
//
// `fatal tune` opens this: a small panel with the handful of settings you want to
// move while the music is playing, because a number typed into a menu tells you
// nothing about how hard a tube should beat.
//
// It writes one `key=value` line into $XDG_RUNTIME_DIR/cartelitos-tune; the
// daemon watches that file and puts the value in the config, so the change lands
// on the tube about a second later and is still there next time.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    // valores de arranque; los pisa la config real al leerla
    property var vals: ({
        word_flash: 0.3, flicker: 0.25, intensity: 0.45, camera: 1.0,
        bloom: 1.0, scanlines: 0.5, noise: 0.22, water_amp: 0.55,
        infect_lead: 0.35, alarm_threshold: 0.87,
    })

    readonly property var rows: [
        { key: "word_flash", label: "Word flash",    max: 1.0,
          hint: "how much each word flashes as it lands" },
        { key: "flicker",   label: "Beat / flicker", max: 1.0,
          hint: "how hard and how often it beats" },
        { key: "intensity", label: "Restlessness",   max: 1.5,
          hint: "signal breaks, static" },
        { key: "camera",    label: "Framing",        max: 2.0,
          hint: "how much the shot moves" },
        { key: "bloom",     label: "Phosphor glow",  max: 2.0,
          hint: "light around the letters" },
        { key: "scanlines", label: "Scanlines",      max: 1.0,
          hint: "depth of the comb" },
        { key: "noise",     label: "Static",         max: 1.0,
          hint: "grain on the tube" },
        { key: "water_amp", label: "Water",          max: 1.0,
          hint: "sea swell and pond shiver" },
        { key: "infect_lead", label: "Infect lead",  max: 0.5,
          hint: "how far ahead the colour jumps to the next screen" },
        { key: "alarm_threshold", label: "Alarm rarity", max: 1.0,
          hint: "how rare the red \"critical\" screen is" },
    ]

    // el canal hacia el daemon: una línea por cambio
    FileView {
        id: pipe
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/cartelitos-tune`
        printErrors: false
        atomicWrites: true
    }

    // la config, para arrancar con los valores de verdad
    FileView {
        id: cfg
        path: `${Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"}/cartelitos/config.toml`
        preload: true
        printErrors: false
        onLoaded: {
            const body = text();
            let out = {};
            for (const key in root.vals) {
                const re = new RegExp("\\[crt\\][\\s\\S]*?\\n\\s*" + key + "\\s*=\\s*([0-9.]+)");
                const m = re.exec(body);
                out[key] = m ? parseFloat(m[1]) : root.vals[key];
            }
            root.vals = out;
        }
    }

    function commit(key, value) {
        let next = root.vals;
        next[key] = value;
        root.vals = next;
        pipe.setText(key + "=" + value.toFixed(3) + "\n");
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens[0]
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "cartelitos-tune"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        anchors { right: true; bottom: true }
        margins { right: 28; bottom: 28 }
        implicitWidth: 440
        implicitHeight: card.height

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Qt.quit()
        }

        Rectangle {
            id: card
            width: parent.width
            height: column.implicitHeight + 28
            radius: 6
            color: "#0d0b12"
            border.width: 1
            border.color: "#2b2438"

            Column {
                id: column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "FATAL LYRICS — CRT"
                        color: "#b46bff"
                        font.pixelSize: 12
                        font.bold: true
                        font.letterSpacing: 2
                    }
                    Text {
                        text: "esc to close"
                        color: "#55496b"
                        font.pixelSize: 11
                    }
                }

                Repeater {
                    model: root.rows

                    Item {
                        id: row
                        required property var modelData
                        width: column.width
                        height: 44

                        readonly property real value: root.vals[modelData.key]

                        Text {
                            id: name
                            text: row.modelData.label
                            color: "#cfc4e0"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            id: num
                            anchors.right: parent.right
                            text: row.value.toFixed(2)
                            color: "#b46bff"
                            font.pixelSize: 12
                            font.family: "monospace"
                        }
                        Text {
                            anchors { left: name.right; leftMargin: 8; baseline: name.baseline
                                      right: num.left; rightMargin: 8 }
                            text: row.modelData.hint
                            color: "#5d5273"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        // la barra: click o arrastre en cualquier punto
                        Rectangle {
                            id: track
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 6 }
                            height: 8
                            radius: 4
                            color: "#1c1726"

                            Rectangle {
                                width: Math.max(track.height, track.width * row.value / row.modelData.max)
                                height: track.height
                                radius: track.radius
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#6b3bb0" }
                                    GradientStop { position: 1.0; color: "#c98bff" }
                                }
                            }

                            Rectangle {
                                x: Math.min(track.width - width,
                                            Math.max(0, track.width * row.value / row.modelData.max - width / 2))
                                y: -3
                                width: 14
                                height: 14
                                radius: 7
                                color: "#eadcff"
                            }

                            MouseArea {
                                anchors { fill: parent; margins: -10 }
                                preventStealing: true
                                function apply(mx) {
                                    const f = Math.max(0, Math.min(mx / track.width, 1));
                                    root.commit(row.modelData.key,
                                                Math.round(f * row.modelData.max * 100) / 100);
                                }
                                onPressed: mouse => apply(mouse.x)
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        apply(mouse.x);
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "se guarda en la config y se aplica en el tubo al toque"
                    color: "#4b4160"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
