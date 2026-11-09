import QtQuick
import QtQuick.Layouts
import Quickshell

// The agents island (docs/agent-board.md): a pip strip per pipeline, then the
// other sessions as counts, a fresh design, and which worktree's stack is live.
//   ● #2021 ▮▯▯▯▯▯   ▶ #246 ▮▮▯▯▯▯   ◐ #1964 ▮▮▮▮▮▯   ✓1   ts ● 1654
// Hovering a strip shows that session's card; clicking it jumps there. Clicking
// the rest opens the wall (SUPER+G). Glows rust while anything needs you.
Island {
    id: root

    property bool open: false
    signal toggleWall()

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int maxPipes: 6
    readonly property var live: Board.sessions.filter(function (s) { return !s.stale })
    readonly property var pipes: live.filter(function (s) { return Board.isPipeline(s) }).slice(0, maxPipes)
    // everything without a strip: plain sessions, and pipelines past maxPipes
    readonly property var rest: live.filter(function (s) { return pipes.indexOf(s) === -1 })
    function restCount(st) { return rest.filter(function (s) { return Board.status(s) === st || (st === "working" && Board.status(s) === "slow") }).length }

    property string hoverKey: ""
    property Item   hoverItem: null
    readonly property var hoverSession: {
        for (var i = 0; i < pipes.length; i++) if (pipes[i].key === hoverKey) return pipes[i]
        return null
    }

    hpad: 10
    glow: Board.needsYou > 0
    glowColor: Colors.attn

    // rust rim while something needs you, accent rim while the wall is open
    Rectangle {
        parent: root
        anchors.centerIn: parent
        width: row.width + root.hpad * 2
        height: root.height
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Board.needsYou > 0 ? Colors.alpha(Colors.attn, 0.85)
                    : root.open          ? Colors.alpha(Colors.accent, 0.5)
                    :                      "transparent"
        z: 2
    }

    // clicking anywhere but a strip opens the wall
    MouseArea {
        parent: root
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleWall()
        z: 1
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Repeater {
            model: root.pipes
            delegate: Rectangle {
                id: chipD
                required property var modelData
                readonly property bool hovered: root.hoverKey === modelData.key
                implicitWidth: pr.implicitWidth + 18
                implicitHeight: 24
                radius: 8
                color: hovered ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.3)
                border.width: 1
                border.color: hovered ? Colors.attn : Qt.rgba(1, 1, 1, 0.10)
                z: 3

                Row {
                    id: pr
                    anchors.centerIn: parent
                    spacing: 7
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Board.glyph(chipD.modelData) + " " + Board.issueText(chipD.modelData)
                        color: Board.status(chipD.modelData) === "idle" ? Colors.fg1 : Board.kindColor(chipD.modelData)
                        font.family: root.mono; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Pips {
                        anchors.verticalCenter: parent.verticalCenter
                        classes: Board.stageClasses(chipD.modelData)
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: { hideTimer.stop(); root.hoverItem = chipD; root.hoverKey = chipD.modelData.key }
                    onExited: hideTimer.restart()
                    onClicked: { root.hoverKey = ""; Board.run(["jump", chipD.modelData.key]) }
                }
            }
        }

        // the other sessions, as counts
        Text {
            visible: root.restCount("needs_you") > 0
            text: "●" + root.restCount("needs_you")
            color: Colors.attn
            font.family: root.mono; font.pixelSize: 12; font.weight: Font.Bold
        }
        Text {
            visible: root.restCount("working") > 0
            text: "▶" + root.restCount("working")
            color: Colors.fg0
            font.family: root.mono; font.pixelSize: 12; font.weight: Font.Bold
        }
        Text {
            visible: root.restCount("background") > 0
            text: "◐" + root.restCount("background")
            color: Colors.blue
            font.family: root.mono; font.pixelSize: 12; font.weight: Font.Bold
        }
        Text {
            visible: root.restCount("done") > 0
            text: "✓" + root.restCount("done")
            color: Colors.green
            font.family: root.mono; font.pixelSize: 12; font.weight: Font.Bold
        }
        // nothing at all running: still say so, so the island never collapses to a blob
        Text {
            visible: root.pipes.length === 0 && Board.needsYou + Board.working + Board.background + Board.unseen === 0
            text: "▶ 0"
            color: Colors.fg2
            font.family: root.mono; font.pixelSize: 12; font.weight: Font.Bold
        }
        Text {
            visible: Board.designRecent
            text: "◇ design"
            color: Colors.accent
            font.family: root.mono; font.pixelSize: 12
        }
        // live stack chip: "ts ● 1654" (◐ while starting)
        Row {
            visible: Board.liveStack !== null
            spacing: 5
            Text {
                text: Board.liveStack ? Board.liveStack.abbr : ""
                color: Colors.fg2
                font.family: root.mono; font.pixelSize: 11
            }
            Text {
                text: Board.liveStack && Board.liveStack.state === "starting" ? "◐" : "●"
                color: Board.liveStack && Board.liveStack.state === "starting" ? Colors.yellow : Colors.green
                font.family: root.mono; font.pixelSize: 11
            }
            Text {
                text: Board.liveStack ? Board.liveStack.label : ""
                color: Colors.fg1
                font.family: root.mono; font.pixelSize: 11
            }
        }
    }

    Timer { id: hideTimer; interval: 180; onTriggered: root.hoverKey = "" }

    // ── the hovered strip's card ────────────────────────────────────────
    PopupWindow {
        id: hover
        visible: root.hoverSession !== null && root.hoverItem !== null && root.visible
        anchor.item: root.hoverItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 10
        implicitWidth: 460
        implicitHeight: hoverCol.implicitHeight + 24
        color: "transparent"

        Glass { anchors.fill: parent; radius: 14 }
        ColumnLayout {
            id: hoverCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8
            WallCard {
                Layout.fillWidth: true
                session: root.hoverSession || ({})
                compact: true
                color: "transparent"
                border.width: 0
            }
            Text {
                Layout.leftMargin: 16
                text: "click jumps · SUPER+Shift+G for all"
                color: Colors.fg2
                font.family: root.mono; font.pixelSize: 11
            }
        }
    }
}
