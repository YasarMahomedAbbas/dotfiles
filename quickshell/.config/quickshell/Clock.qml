import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    implicitWidth: row.implicitWidth
    implicitHeight: 34

    signal toggleCalendar()

    SystemClock {
        id: clock
        precision: SystemClock.Precision.Minutes
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 9

        Text {
            text: "󰥔"
            font.pixelSize: 14
            font.family: "JetBrainsMono Nerd Font"
            color: Colors.teal
        }
        Text {
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.pixelSize: 13
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.DemiBold
            color: Colors.fg0
        }
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width: 3; height: 3; radius: 1.5
            color: Colors.muted
        }
        Text {
            text: Qt.formatDateTime(clock.date, "ddd dd MMM")
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font"
            font.weight: Font.Medium
            color: Colors.fg1
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: toggleCalendar()
    }
}
