import QtQuick

// A rounded status pill: "● Verify in Edge · 0:42", "◇ design · 11 boards".
Rectangle {
    id: root

    property string text: ""
    property color fg: Colors.fg1
    property color fill: "transparent"
    property color edge: "transparent"
    property int size: 11
    property bool bold: true
    property bool mono: true

    implicitWidth: label.implicitWidth + 18
    implicitHeight: label.implicitHeight + 4
    radius: height / 2
    color: fill
    border.width: 1
    border.color: edge

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.fg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: root.size
        font.weight: root.bold ? Font.DemiBold : Font.Medium
    }
}
