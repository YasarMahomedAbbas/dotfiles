import QtQuick

// The bar's pip strip: six small squares, one per stage (Board.stageClasses):
// done green, the current one frost / steel (breathing) or rust, the rest dim.
Row {
    id: root

    property var classes: []
    property int pip: 7

    spacing: 2

    Repeater {
        model: root.classes.length
        delegate: Rectangle {
            id: p
            required property int index
            readonly property string c: root.classes[index] || "todo"
            width: root.pip; height: root.pip; radius: 2
            color: c === "done" ? Colors.green : c === "now" ? Colors.fg0 : c === "bg" ? Colors.blue
                 : c === "attn" ? Colors.attn : Qt.rgba(1, 1, 1, 0.18)
            SequentialAnimation on opacity {
                running: (p.c === "now" || p.c === "bg") && root.visible
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.35; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.35; to: 1; duration: 800; easing.type: Easing.InOutSine }
            }
        }
    }
}
