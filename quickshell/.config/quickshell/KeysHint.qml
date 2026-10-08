import QtQuick
import QtQuick.Layouts

// The tiny "⊞ /" island: the way into the keys cheatsheet, always visible.
Island {
    id: root

    signal toggleKeys()

    hpad: 9

    RowLayout {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Kbd { text: "⊞" }
        Kbd { text: "/" }
    }

    MouseArea {
        parent: root
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleKeys()
    }
}
