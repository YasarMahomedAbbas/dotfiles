import QtQuick
import QtQuick.Layouts

// One card on the wall (SUPER+G), read top to bottom as on the design:
//   what   status chip · issue · title · elapsed, then the problem
//   where  the six-stage stepper (pipelines only)
//   now    the stage in words, then the tool / agents / shells, a task bar,
//          or the question with its numbered options (1-9 answers)
Rectangle {
    id: root

    property var  session: ({})
    property bool selected: false
    property bool compact: false           // the bar's hover card: no options, no bar

    signal clicked()
    signal activated()
    signal answer(int n)

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property var s: session
    readonly property string k: Board.kind(s)
    readonly property color kc: Board.kindColor(s)
    readonly property bool pipe: Board.isPipeline(s)
    readonly property var lines: Board.nowLines(s)
    readonly property var opts: k === "attn" && s.attention ? (s.attention.options || []).slice(0, 9) : []
    readonly property var bar: k === "attn" || compact ? null : Board.taskBar(s)

    implicitHeight: body.implicitHeight + 28
    radius: 12
    color: selected ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.28)
    border.width: selected ? 2 : 1
    border.color: selected ? Colors.attn
                : k === "attn" ? Colors.alpha(Colors.attn, 0.65)
                : k === "bg"   ? Colors.alpha(Colors.blue, 0.4)
                : k === "now"  ? Colors.alpha(Colors.fg0, 0.25)
                :                Qt.rgba(1, 1, 1, 0.10)

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
        onDoubleClicked: root.activated()
    }

    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; topMargin: 14 }
        spacing: 12

        // ── what ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: chipT.implicitWidth + 16
                implicitHeight: chipT.implicitHeight + 8
                radius: 4
                color: root.k === "attn" ? Colors.alpha(root.kc, 0.16) : "transparent"
                border.width: 1.5
                border.color: root.k === "now" ? Colors.alpha(root.kc, 0.5) : root.kc
                Text {
                    id: chipT
                    anchors.centerIn: parent
                    text: Board.chip(root.s)
                    color: root.kc
                    font.family: root.mono; font.pixelSize: 11; font.weight: Font.Bold
                }
            }
            Text {
                visible: text !== ""
                text: Board.issueText(root.s)
                color: Colors.alpha(Colors.fg1, 0.75)
                font.family: root.mono; font.pixelSize: 12
            }
            Text {
                Layout.fillWidth: true
                text: Board.title(root.s)
                color: Colors.fg0
                elide: Text.ElideRight
                font.family: root.mono; font.pixelSize: 13; font.weight: Font.Bold
            }
            Text {
                text: Board.timeText(root.s)
                color: Colors.alpha(Colors.fg1, 0.75)
                font.family: root.mono; font.pixelSize: 11
            }
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: Board.problem(root.s)
            color: Colors.alpha(Colors.fg1, 0.75)
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 1.15
            font.family: root.mono; font.pixelSize: 12
        }

        // ── where ───────────────────────────────────────────────────────
        Stepper {
            visible: root.pipe
            Layout.fillWidth: true
            steps: Board.steps(root.s, true)
        }

        // ── now ─────────────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
        Text {
            Layout.fillWidth: true
            text: Board.nowHead(root.s)
            color: root.kc
            elide: Text.ElideRight
            font.family: root.mono; font.pixelSize: 12; font.weight: Font.Bold
        }
        Repeater {
            model: root.lines.length
            delegate: RowLayout {
                required property int index
                readonly property var l: root.lines[index] || ({ g: "", gc: Colors.fg2, t: "", r: "" })
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.preferredWidth: 12
                    text: l.g
                    color: l.gc
                    font.family: root.mono; font.pixelSize: 12
                }
                Text {
                    Layout.fillWidth: true
                    text: l.t
                    color: Colors.fg1
                    elide: Text.ElideRight
                    wrapMode: l.g === "?" ? Text.Wrap : Text.NoWrap
                    maximumLineCount: l.g === "?" ? 3 : 1
                    font.family: root.mono; font.pixelSize: 12
                }
                Text {
                    text: l.r
                    color: Colors.fg2
                    font.family: root.mono; font.pixelSize: 12
                }
            }
        }
        Flow {
            visible: root.opts.length > 0 && !root.compact
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: root.compact ? [] : root.opts
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    implicitWidth: optRow.implicitWidth + 16
                    implicitHeight: optRow.implicitHeight + 10
                    radius: 6
                    color: optMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    Row {
                        id: optRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            width: kT.implicitWidth + 12; height: kT.implicitHeight + 6; radius: 4
                            color: Colors.attn
                            Text {
                                id: kT
                                anchors.centerIn: parent
                                text: modelData.key || String(index + 1)
                                color: Colors.bg0
                                font.family: root.mono; font.pixelSize: 11; font.weight: Font.Bold
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label || ""
                            color: Colors.fg0
                            font.family: root.mono; font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        id: optMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.answer(index + 1)
                    }
                }
            }
        }
        RowLayout {
            visible: root.bar !== null
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                Layout.fillWidth: true
                height: 5; radius: 3
                color: Qt.rgba(1, 1, 1, 0.10)
                Rectangle {
                    width: parent.width * (root.bar ? Math.max(0, Math.min(1, root.bar.f)) : 0)
                    height: parent.height; radius: 3
                    color: root.kc
                }
            }
            Text {
                text: root.bar ? root.bar.text : ""
                color: Colors.alpha(Colors.fg1, 0.75)
                font.family: root.mono; font.pixelSize: 11
            }
        }
    }
}
