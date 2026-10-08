import QtQuick

// A segmented progress strip. Each cell is a code:
//   "d" done (green) · "r" running (frost; the last running cell pulses)
//   "b" background work (blue; pulses like running)
//   "a" needs you (red outline, pulsing) · "s" slow (yellow) · "" not started
Item {
    id: root

    property var cells: []
    property real gap: 2
    property bool animate: true

    implicitWidth: 150
    implicitHeight: 10

    Row {
        anchors.fill: parent
        spacing: root.gap

        Repeater {
            model: root.cells.length

            delegate: Rectangle {
                id: cell
                required property int index
                readonly property string code: root.cells[index] || ""
                readonly property bool now: (code === "r" || code === "b") && root.cells[index + 1] !== code

                width: root.cells.length ? (root.width - root.gap * (root.cells.length - 1)) / root.cells.length : 0
                height: root.height
                radius: 1.5
                color: code === "d" ? Colors.green
                     : code === "r" ? Colors.fg0
                     : code === "s" ? Colors.yellow
                     : code === "b" ? Colors.blue
                     : code === "a" ? "transparent"
                     :                Colors.bg3
                border.width: code === "a" ? 1.5 : 0
                border.color: Colors.red

                // needs-you cells breathe a red fill
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    visible: cell.code === "a"
                    color: Colors.red
                    opacity: 0
                    SequentialAnimation on opacity {
                        running: cell.code === "a" && root.animate && root.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0;    duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                // the running cell pulses
                SequentialAnimation on opacity {
                    running: cell.now && root.animate && root.visible
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) cell.opacity = 1
                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1;   duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
