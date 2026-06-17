import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// The five power actions as circular accent buttons. Lays out horizontally
// (icon over label) by default, or vertically (icon beside label) when
// `vertical` is set. Emits `requestClose()` after dispatching an action.
Item {
    id: root

    property bool vertical: false
    signal requestClose()

    readonly property var actions: [
        { icon: "󰌾", label: "Lock",     accent: Colors.blue,   cmd: ["loginctl", "lock-session"] },
        { icon: "󰤄", label: "Suspend",  accent: Colors.teal,   cmd: ["systemctl", "suspend"] },
        { icon: "󰍃", label: "Logout",   accent: Colors.yellow, cmd: ["hyprctl", "dispatch", "exit"] },
        { icon: "󰜉", label: "Reboot",   accent: Colors.orange, cmd: ["systemctl", "reboot"] },
        { icon: "󰐥", label: "Shutdown", accent: Colors.red,    cmd: ["systemctl", "poweroff"] },
    ]

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight

    Grid {
        id: grid
        anchors.centerIn: parent
        columns: root.vertical ? 1 : root.actions.length
        rowSpacing: root.vertical ? 8 : 0
        columnSpacing: root.vertical ? 0 : 8

        Repeater {
            model: root.actions
            delegate: GridLayout {
                required property var modelData
                flow: root.vertical ? GridLayout.LeftToRight : GridLayout.TopToBottom
                columns: root.vertical ? 2 : 1
                rowSpacing: 6
                columnSpacing: 11

                Rectangle {
                    id: btn
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    width: 42; height: 42; radius: 21
                    color: btnHover.containsMouse
                        ? Qt.rgba(modelData.accent.r, modelData.accent.g, modelData.accent.b, 0.18)
                        : Qt.rgba(0x43/255, 0x4c/255, 0x5e/255, 0.50)
                    border.width: 1
                    border.color: btnHover.containsMouse
                        ? modelData.accent
                        : Qt.rgba(0x4c/255, 0x56/255, 0x6a/255, 0.45)
                    scale: btnHover.containsMouse ? 1.08 : 1.0
                    Behavior on color { ColorAnimation { duration: 130 } }
                    Behavior on border.color { ColorAnimation { duration: 130 } }
                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.icon
                        font.pixelSize: 18
                        font.family: "JetBrainsMono Nerd Font"
                        color: btnHover.containsMouse ? modelData.accent : Colors.fg1
                        Behavior on color { ColorAnimation { duration: 130 } }
                    }

                    MouseArea {
                        id: btnHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Qt.createQmlObject(
                                'import Quickshell.Io; Process { command: ' +
                                JSON.stringify(modelData.cmd) + '; running: true }', root)
                            root.requestClose()
                        }
                    }
                }

                Text {
                    text: modelData.label
                    Layout.alignment: root.vertical ? (Qt.AlignLeft | Qt.AlignVCenter)
                                                    : Qt.AlignHCenter
                    font.pixelSize: root.vertical ? 11 : 9
                    font.weight: Font.Medium
                    font.family: "JetBrainsMono Nerd Font"
                    color: btnHover.containsMouse ? Colors.fg0 : Colors.muted
                    Behavior on color { ColorAnimation { duration: 130 } }
                }
            }
        }
    }
}
