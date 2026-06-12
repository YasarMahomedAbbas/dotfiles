import QtQuick
import QtQuick.Effects
import "Colors.js" as C

// A frosted-glass "island": a translucent rounded container that groups
// several bare modules. The wallpaper bleeds through slightly, a soft drop
// shadow lifts it off the desktop, and a faint top highlight gives a glass
// edge. Place a single laid-out child (usually a RowLayout) inside — the
// island hugs it with `hpad` of breathing room on each side.
Item {
    id: root

    property real hpad: 12
    property real radius: 15
    property bool glow: false              // optional accent rim glow
    property color glowColor: C.accent

    default property alias content: holder.data

    implicitWidth: card.implicitWidth
    implicitHeight: 34

    // Accent rim glow (drawn behind the card)
    Rectangle {
        anchors.fill: card
        radius: card.radius
        visible: root.glow
        color: "transparent"
        border.width: 1
        border.color: root.glowColor
        opacity: 0.5
        layer.enabled: root.glow
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 24
            autoPaddingEnabled: true
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        implicitWidth: holder.width + root.hpad * 2
        implicitHeight: parent.height
        radius: root.radius

        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0x43/255, 0x4c/255, 0x5e/255, 0.62) }
            GradientStop { position: 1.0; color: Qt.rgba(0x2e/255, 0x34/255, 0x40/255, 0.72) }
        }
        border.width: 1
        border.color: Qt.rgba(0x4c/255, 0x56/255, 0x6a/255, 0.40)

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.40)
            shadowVerticalOffset: 3
            shadowBlur: 0.8
            autoPaddingEnabled: true
        }

        // Glass top-edge highlight
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 1; leftMargin: root.radius; rightMargin: root.radius }
            height: 1
            color: Qt.rgba(0xec/255, 0xef/255, 0xf4/255, 0.07)
        }

        // Content slot — hugs its child so the island width never feeds back
        // through centered children (no binding loops). Children only need a
        // vertical anchor.
        Item {
            id: holder
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            width: childrenRect.width
        }
    }
}
