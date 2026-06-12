import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "Colors.js" as C

Item {
    implicitWidth: row.implicitWidth
    implicitHeight: 34

    property int volumePct: 0
    property bool muted: false

    function refresh() { volReadProc.running = true }

    Process {
        id: volReadProc
        command: ["bash", "-c",
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = text.trim().match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
                if (m) {
                    volumePct = Math.round(parseFloat(m[1]) * 100)
                    muted     = m[2] !== undefined
                }
            }
        }
    }

    Process {
        id: muteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        onRunningChanged: if (!running) Qt.callLater(refresh)
    }

    Process {
        id: volUpProc
        command: ["wpctl", "set-volume", "-l", "1", "@DEFAULT_AUDIO_SINK@", "5%+"]
        onRunningChanged: if (!running) Qt.callLater(refresh)
    }

    Process {
        id: volDownProc
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]
        onRunningChanged: if (!running) Qt.callLater(refresh)
    }

    Timer {
        interval: 2000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: refresh()
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Text {
            text: muted ? "󰝟"
                        : volumePct >= 70 ? "󰕾" : volumePct >= 30 ? "󰖀" : "󰕿"
            font.pixelSize: 15
            font.family: "JetBrainsMono Nerd Font"
            color: muted ? C.muted : C.yellow
        }
        Text {
            text: muted ? "muted" : volumePct + "%"
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Medium
            color: muted ? C.muted : C.fg1
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: muteProc.running = true
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0) volUpProc.running   = true
            else                        volDownProc.running = true
        }
    }
}
