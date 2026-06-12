import QtQuick
import QtQuick.Effects
import "Colors.js" as C

Item {
    id: root
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    signal closePopup()

    Rectangle {
        id: card
        anchors.fill: parent
        implicitWidth: actions.implicitWidth + 28
        implicitHeight: actions.implicitHeight + 28
        radius: 18
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0x3b/255, 0x42/255, 0x52/255, 0.96) }
            GradientStop { position: 1.0; color: Qt.rgba(0x2e/255, 0x34/255, 0x40/255, 0.97) }
        }
        border.width: 1
        border.color: Qt.rgba(0x4c/255, 0x56/255, 0x6a/255, 0.45)

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowVerticalOffset: 6
            shadowBlur: 1.0
            autoPaddingEnabled: true
        }

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 1; leftMargin: 18; rightMargin: 18 }
            height: 1
            color: Qt.rgba(0xec/255, 0xef/255, 0xf4/255, 0.08)
        }

        PowerActions {
            id: actions
            anchors.centerIn: parent
            onRequestClose: root.closePopup()
        }
    }
}
