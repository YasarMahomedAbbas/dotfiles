import QtQuick
import Quickshell.Hyprland

Item {
    implicitWidth: titleText.implicitWidth
    implicitHeight: 34
    visible: titleText.text.length > 0

    Text {
        id: titleText
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        width: Math.min(implicitWidth, 360)
        text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
        elide: Text.ElideRight
        font.pixelSize: 12
        font.family: "JetBrainsMono Nerd Font"
        font.italic: true
        font.weight: Font.Medium
        color: Colors.fg2
    }
}
