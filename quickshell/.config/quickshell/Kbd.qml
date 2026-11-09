import QtQuick

// A keycap: ⊞ G, 1–9, ⏎.
Rectangle {
    id: root

    property string text: ""
    property color fg: Colors.fg0
    property int size: 10

    implicitWidth: Math.max(label.implicitWidth + 10, implicitHeight)
    implicitHeight: label.implicitHeight + 3
    radius: 5
    color: Qt.rgba(1, 1, 1, 0.07)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.14)

    // heavier bottom edge, like a physical key
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 2; rightMargin: 2 }
        height: 1
        color: Qt.rgba(1, 1, 1, 0.14)
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.fg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: root.size
    }
}
