import QtQuick
import "Colors.js" as C

Item {
    implicitWidth: lbl.implicitWidth
    implicitHeight: 34

    signal togglePower()

    Text {
        id: lbl
        anchors.centerIn: parent
        text: "󰐥"
        font.pixelSize: 15
        font.family: "JetBrainsMono Nerd Font"
        color: hover.containsMouse ? C.red : C.fg2
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: hover.containsMouse ? 1.15 : 1.0
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: togglePower()
    }
}
