import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    implicitWidth: row.implicitWidth
    implicitHeight: 34

    signal toggleWeather()

    property string tempC: "--"
    property string desc:  "…"
    property string icon:  "󰔏"

    // Map WWO weather codes to Nerd Font (Material Design) glyphs
    function weatherIcon(code) {
        var c = parseInt(code)
        if (c === 113) return "󰖙"                       // sunny
        if (c === 116) return "󰖕"                       // partly cloudy
        if (c === 119 || c === 122) return "󰖐"          // cloudy / overcast
        if (c === 143 || c === 248 || c === 260) return "󰖑" // fog/mist
        if (c === 200 || c >= 386) return "󰖓"           // thunder
        if (c === 176 || c === 293 || c === 263) return "󰼵" // light showers
        if (c >= 179 && c <= 230) return "󰖘"            // snow
        if (c >= 281 && c <= 377) {                     // rain family
            if (c >= 323 && c <= 377) return "󰖘"        // sleet/snow
            return "󰖗"
        }
        return "󰖐"
    }

    Process {
        id: weatherProc
        command: ["bash", "-c",
            "curl -sf --max-time 8 'https://wttr.in/?format=j1' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    var cur  = data.current_condition[0]
                    tempC = cur.temp_C
                    desc  = cur.weatherDesc[0].value
                    icon  = weatherIcon(cur.weatherCode)
                } catch (e) {
                    desc = "N/A"
                }
            }
        }
    }

    Timer {
        interval: 600000  // refresh every 10 min
        running: true; repeat: true
        triggeredOnStart: true
        onTriggered: weatherProc.running = true
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Text {
            text: icon
            font.pixelSize: 15
            font.family: "JetBrainsMono Nerd Font"
            color: Colors.teal
        }
        Text {
            text: tempC + "°"
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Medium
            color: Colors.fg1
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: toggleWeather()
    }
}
