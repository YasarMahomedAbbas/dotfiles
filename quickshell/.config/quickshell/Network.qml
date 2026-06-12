import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "Colors.js" as C

Item {
    implicitWidth: row.implicitWidth
    implicitHeight: 34

    // state: "wifi|<ssid>", "wired", "offline"
    property string state: "offline"

    readonly property string netIcon: {
        if (state.indexOf("wifi|") === 0) return "󰖩"
        if (state === "wired")            return "󰈀"
        return "󰤭"
    }
    readonly property string netText: {
        if (state.indexOf("wifi|") === 0) return state.substring(5)
        if (state === "wired")            return "wired"
        return "offline"
    }

    Process {
        id: netProc
        command: ["bash", "-c",
            "ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2); " +
            "if [ -n \"$ssid\" ]; then echo \"wifi|$ssid\"; " +
            "elif ip route get 1.1.1.1 2>/dev/null | grep -qv 'wifi\\|wlan'; then echo wired; " +
            "else echo offline; fi"]
        stdout: StdioCollector {
            onStreamFinished: state = text.trim()
        }
    }

    Timer {
        interval: 10000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: netProc.running = true
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Text {
            text: netIcon
            font.pixelSize: 14
            font.family: "JetBrainsMono Nerd Font"
            color: state === "offline" ? C.muted : C.accent
        }
        Text {
            text: netText
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Medium
            color: C.fg1
        }
    }
}
