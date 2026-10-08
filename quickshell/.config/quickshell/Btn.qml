import QtQuick
import QtQuick.Layouts

// An action button with its key: [1] All 8 passed, [⏎] Jump to pane.
Rectangle {
    id: root

    property string key: ""
    property string text: ""
    property bool primary: false

    signal clicked()

    implicitWidth: row.implicitWidth + 22
    implicitHeight: row.implicitHeight + 10
    radius: 10
    color: primary ? Colors.accent : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06))
    border.width: 1
    border.color: primary ? Colors.accent : Qt.rgba(1, 1, 1, 0.14)

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Rectangle {
            visible: root.key !== ""
            implicitWidth: kl.implicitWidth + 8
            implicitHeight: kl.implicitHeight + 1
            radius: 4
            color: root.primary ? Qt.rgba(0, 0, 0, 0.15) : Qt.rgba(0, 0, 0, 0.3)
            Text {
                id: kl
                anchors.centerIn: parent
                text: root.key
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                color: root.primary ? Colors.bg0 : Colors.fg1
            }
        }
        Text {
            text: root.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: root.primary ? Colors.bg0 : Colors.fg0
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
