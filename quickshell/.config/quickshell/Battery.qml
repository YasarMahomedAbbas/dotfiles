import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    implicitWidth: visible ? row.implicitWidth : 0
    implicitHeight: 34
    visible: capacity > -1

    property int capacity: -1
    property string status: "Unknown"

    Process {
        id: batProc
        command: ["bash", "-c",
            "cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo '-1'); " +
            "stat=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo 'Unknown'); " +
            "echo \"$cap $stat\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split(" ")
                capacity = parseInt(parts[0])
                status   = parts[1] || "Unknown"
            }
        }
    }

    Timer {
        interval: 30000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: batProc.running = true
    }

    readonly property color batColor: {
        if (status === "Charging")          return Colors.green
        if (capacity <= 15)                 return Colors.red
        if (capacity <= 30)                 return Colors.orange
        return Colors.green
    }

    readonly property string batIcon: {
        if (status === "Charging")          return "󰂄"
        if (status === "Full")              return "󰁹"
        if (capacity >= 90)                 return "󰂂"
        if (capacity >= 70)                 return "󰂀"
        if (capacity >= 50)                 return "󰁾"
        if (capacity >= 30)                 return "󰁼"
        if (capacity >= 15)                 return "󰁺"
        return "󰂃"
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Text {
            text: batIcon
            font.pixelSize: 15
            font.family: "JetBrainsMono Nerd Font"
            color: batColor
        }
        Text {
            text: capacity + "%"
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Medium
            color: Colors.fg1
        }
    }
}
