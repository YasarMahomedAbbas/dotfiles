import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland

Item {
    implicitWidth: row.implicitWidth
    implicitHeight: 34

    function liveIds() {
        var ids = []
        for (var i = 0; i < Hyprland.workspaces.count; i++)
            ids.push(Hyprland.workspaces.get(i).id)
        return ids
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
            model: {
                var ids = liveIds()
                var max = 5
                for (var i = 0; i < ids.length; i++) max = Math.max(max, ids[i])
                var out = []
                for (var j = 1; j <= max; j++) out.push(j)
                return out
            }

            delegate: Item {
                required property int modelData
                readonly property bool isActive:
                    Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData
                readonly property bool isLive: liveIds().indexOf(modelData) !== -1
                readonly property bool isUrgent: {
                    for (var i = 0; i < Hyprland.workspaces.count; i++) {
                        var ws = Hyprland.workspaces.get(i)
                        if (ws.id === modelData) return ws.urgent
                    }
                    return false
                }

                implicitWidth: dot.width
                implicitHeight: 18

                // Glow halo behind the active indicator
                Rectangle {
                    anchors.centerIn: dot
                    width: dot.width; height: dot.height
                    radius: dot.radius
                    color: isUrgent ? Colors.red : Colors.accent
                    visible: isActive
                    opacity: 0.55
                    layer.enabled: isActive
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 28
                        autoPaddingEnabled: true
                    }
                }

                Rectangle {
                    id: dot
                    anchors.verticalCenter: parent.verticalCenter
                    width: isActive ? 22 : 9
                    height: 9
                    radius: 4.5
                    color: isUrgent ? Colors.red
                         : isActive ? Colors.accent
                         : isLive   ? Qt.rgba(0xd8/255, 0xde/255, 0xe9/255, 0.55)
                         :            Qt.rgba(0x4c/255, 0x56/255, 0x6a/255, 0.55)

                    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 160 } }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + modelData)
                }
            }
        }
    }
}
