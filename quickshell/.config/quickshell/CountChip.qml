import QtQuick

// A square-cornered count chip in the wall's header: `● 1 needs you`, `▶ 2`.
Rectangle {
    id: root

    property string text: ""
    property color c: Colors.fg1
    property bool tint: false

    implicitWidth: t.implicitWidth + 16
    implicitHeight: t.implicitHeight + 8
    radius: 4
    color: tint ? Colors.alpha(c, 0.16) : "transparent"
    border.width: 1.5
    border.color: Colors.alpha(c, 0.75)

    Text {
        id: t
        anchors.centerIn: parent
        text: root.text
        color: root.c
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
        font.weight: Font.Bold
    }
}
