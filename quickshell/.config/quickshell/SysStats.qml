import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    implicitWidth: row.implicitWidth
    implicitHeight: 32

    property int cpuPct: 0
    property int memPct: 0

    // CPU delta tracking
    property var _cpuPrev: ({idle: 0, total: 0})

    Process {
        id: cpuProc
        command: ["bash", "-c",
            "awk '/^cpu /{idle=$5; total=0; for(i=2;i<=NF;i++) total+=$i; print idle\" \"total; exit}' /proc/stat"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split(" ").map(Number)
                var idle = parts[0], total = parts[1]
                if (_cpuPrev.total > 0 && (total - _cpuPrev.total) > 0) {
                    var dIdle  = idle  - _cpuPrev.idle
                    var dTotal = total - _cpuPrev.total
                    cpuPct = Math.max(0, Math.min(100, Math.round(100 * (1 - dIdle / dTotal))))
                }
                _cpuPrev = { idle: idle, total: total }
            }
        }
    }

    Process {
        id: memProc
        command: ["bash", "-c",
            "awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%d\", int((t-a)/t*100)}' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: memPct = parseInt(text.trim()) || 0
        }
    }

    Timer {
        interval: 2000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: { cpuProc.running = true; memProc.running = true }
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        // CPU
        RowLayout {
            spacing: 7
            Text {
                text: "󰻠"
                font.pixelSize: 14
                font.family: "JetBrainsMono Nerd Font"
                color: cpuPct >= 85 ? Colors.red : Colors.purple
            }
            Text {
                text: cpuPct + "%"
                font.pixelSize: 12
                font.family: "JetBrainsMono Nerd Font"
                font.weight: Font.Medium
                color: Colors.fg1
            }
        }

        // RAM
        RowLayout {
            spacing: 7
            Text {
                text: "󰍛"
                font.pixelSize: 14
                font.family: "JetBrainsMono Nerd Font"
                color: memPct >= 85 ? Colors.red : Colors.accent2
            }
            Text {
                text: memPct + "%"
                font.pixelSize: 12
                font.family: "JetBrainsMono Nerd Font"
                font.weight: Font.Medium
                color: Colors.fg1
            }
        }
    }
}
