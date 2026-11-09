import QtQuick
import QtQuick.Layouts

// The six-stage stepper (design: "Where"): a dot per stage on one line, done
// ones green with a ✓, the current one live (frost ring while working, steel
// while background, rust ! while it needs you), the rest an empty ring. The
// line into a stage turns green once it is reached. `steps` is Board.steps(s).
Item {
    id: root

    property var  steps: []
    property int  dot: 18                  // dot diameter: 18 on a card, 26 in focus
    property int  labelSize: 11
    property bool showSub: false           // a third line: Implement's count, the current stage's time

    readonly property string mono: "JetBrainsMono Nerd Font"

    implicitHeight: dot + 6 + labelSize + 2 + (showSub ? labelSize + 4 : 0)

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: root.steps.length
            delegate: Item {
                id: st
                required property int index
                readonly property var m: root.steps[index] || ({ label: "", cls: "todo", mark: "", sub: "" })
                readonly property bool live: m.cls === "now" || m.cls === "bg"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true

                // the line from the previous stage's dot to this one
                Rectangle {
                    visible: st.index > 0
                    x: -width / 2
                    y: root.dot / 2 - height / 2
                    width: st.width
                    height: root.dot > 20 ? 3 : 2
                    color: st.m.cls === "todo" ? Qt.rgba(1, 1, 1, 0.14) : Colors.green
                }

                Rectangle {
                    id: d
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.dot; height: root.dot; radius: root.dot / 2
                    color: st.m.cls === "done" ? Colors.green : st.m.cls === "attn" ? Colors.attn : Colors.bg1
                    border.width: st.m.cls === "done" || st.m.cls === "attn" ? 0 : 2
                    border.color: st.m.cls === "now" ? Colors.fg0 : st.m.cls === "bg" ? Colors.blue : Qt.rgba(1, 1, 1, 0.22)

                    Text {
                        anchors.centerIn: parent
                        visible: st.m.mark !== ""
                        text: st.m.mark
                        color: Colors.bg0
                        font.family: root.mono; font.pixelSize: Math.round(root.dot * 0.55); font.weight: Font.Bold
                    }
                    // the live dot breathes
                    Rectangle {
                        anchors.centerIn: parent
                        visible: st.live
                        width: Math.round(root.dot * 0.36); height: width; radius: width / 2
                        color: st.m.cls === "bg" ? Colors.blue : Colors.fg0
                        SequentialAnimation on opacity {
                            running: st.live && root.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.35; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.35; to: 1; duration: 800; easing.type: Easing.InOutSine }
                        }
                    }
                }

                Text {
                    id: lbl
                    anchors { top: d.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: st.m.label
                    color: st.m.cls === "todo" ? Colors.fg2 : st.m.cls === "done" ? Colors.alpha(Colors.fg1, 0.8) : Colors.fg0
                    font.family: root.mono; font.pixelSize: root.labelSize
                    font.weight: st.m.cls === "todo" || st.m.cls === "done" ? Font.Normal : Font.Bold
                }
                Text {
                    visible: root.showSub
                    anchors { top: lbl.bottom; topMargin: 3; horizontalCenter: parent.horizontalCenter }
                    text: st.m.sub || ""
                    color: Colors.fg2
                    font.family: root.mono; font.pixelSize: root.labelSize - 1
                }
            }
        }
    }
}
