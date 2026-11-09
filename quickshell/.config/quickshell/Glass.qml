import QtQuick
import QtQuick.Effects

// The board's glass panel chrome (roster, wall, keys, toast): a dark translucent
// sheet with a faint white wash, a light rim and a deep shadow. Fill a popup
// with it and lay the content on top.
Rectangle {
    id: root

    property color edge: Qt.rgba(1, 1, 1, 0.16)

    radius: 16
    gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(Colors.bg2.r, Colors.bg2.g, Colors.bg2.b, 0.94) }
        GradientStop { position: 1.0; color: Qt.rgba(Colors.bg0.r, Colors.bg0.g, Colors.bg0.b, 0.95) }
    }
    border.width: 1
    border.color: edge

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.55)
        shadowVerticalOffset: 10
        shadowBlur: 1.0
        autoPaddingEnabled: true
    }

    // glass top-edge highlight
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: 1; leftMargin: root.radius; rightMargin: root.radius }
        height: 1
        color: Qt.rgba(1, 1, 1, 0.22)
    }
}
