import QtQuick
import QtQuick.Layouts

// One checklist card on the wall: status chip · title · time, the overall
// segmented bar, then one row per stage (or task) with its own cells.
Rectangle {
    id: root

    property var  session: ({})
    property bool selected: false

    signal clicked()
    signal activated()

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property var m: Board.card(session)
    readonly property color kc: m.kind === "attn" ? Colors.red
                              : m.kind === "run"  ? Colors.fg0
                              : m.kind === "bg"   ? Colors.blue
                              : m.kind === "done" ? Colors.green
                              :                     Colors.fg2

    implicitHeight: body.implicitHeight + 20
    radius: 12
    color: selected ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.28)
    border.width: selected ? 2 : 1
    border.color: selected ? Colors.accent
                : m.kind === "attn" ? Colors.alpha(Colors.red, 0.6)
                : m.kind === "run"  ? Colors.alpha(Colors.fg0, 0.25)
                : m.kind === "done" ? Colors.alpha(Colors.green, 0.45)
                : m.kind === "bg"   ? Colors.alpha(Colors.blue, 0.4)
                :                     Qt.rgba(1, 1, 1, 0.10)

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
        onDoubleClicked: root.activated()
    }

    function glyph(g) {
        return g === "d" ? "✓" : g === "a" ? "●" : g === "b" ? "◐" : (g === "r" || g === "s") ? "▶" : "○"
    }
    function glyphColor(g) {
        return g === "d" ? Colors.green : g === "a" ? Colors.red : g === "s" ? Colors.yellow : g === "b" ? Colors.blue
             : g === "r" ? Colors.fg0 : Colors.fg2
    }

    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; topMargin: 10 }
        spacing: 4

        // header: chip · title · time
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: chipT.implicitWidth + 16
                implicitHeight: chipT.implicitHeight + 2
                radius: 4
                color: root.m.kind === "idle" ? "transparent" : Colors.alpha(root.kc, root.m.kind === "run" ? 0.08 : 0.18)
                border.width: 1.5
                border.color: root.kc
                Text {
                    id: chipT
                    anchors.centerIn: parent
                    text: root.m.chip
                    color: root.kc
                    font.family: root.mono; font.pixelSize: 11; font.weight: Font.Bold
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.m.title
                color: Colors.fg0
                elide: Text.ElideRight
                font.family: root.mono; font.pixelSize: 12; font.weight: Font.Bold
            }
            Text {
                text: root.m.time
                color: Colors.alpha(Colors.fg1, 0.7)
                font.family: root.mono; font.pixelSize: 11
            }
        }

        // overall bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.preferredWidth: 110
                text: root.m.total
                color: Colors.fg1
                font.family: root.mono; font.pixelSize: 11
            }
            Segs {
                Layout.fillWidth: true
                implicitHeight: 12
                cells: root.m.all
                animate: false
            }
        }

        // one row per stage / task
        // model is a count, not the rows array: the card model is rebuilt every
        // second (timers), and an int model keeps the delegates (and their
        // pulse animations) alive across those rebuilds.
        Repeater {
            model: root.m.rows.length
            delegate: RowLayout {
                required property int index
                readonly property var modelData: root.m.rows[index] || ({ g: "", label: "", cells: [], st: "", stColor: Colors.fg2 })
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.preferredWidth: 14
                    text: root.glyph(modelData.g)
                    color: root.glyphColor(modelData.g)
                    font.family: root.mono; font.pixelSize: 11
                }
                Text {
                    Layout.preferredWidth: 120
                    Layout.maximumWidth: 120
                    text: modelData.label
                    elide: Text.ElideRight
                    color: modelData.g === "" ? Colors.fg2 : modelData.g === "d" ? Colors.fg1 : Colors.fg0
                    font.family: root.mono; font.pixelSize: 11
                }
                Segs {
                    Layout.fillWidth: true
                    implicitHeight: 10
                    cells: modelData.cells
                }
                Text {
                    Layout.preferredWidth: 150
                    Layout.maximumWidth: 150
                    text: modelData.st
                    elide: Text.ElideRight
                    color: modelData.g === "d" ? Colors.alpha(Colors.fg1, 0.6) : modelData.stColor
                    font.family: root.mono; font.pixelSize: 11
                }
            }
        }
    }
}
