import QtQuick
import QtQuick.Layouts

// The agents island (docs/agent-board.md): what needs you, what's running,
// what's in the background, a fresh design, and which worktree's stack is live.
//   ● 1 needs you   ▶ 3   ◐ 1   ◇ design   ts ● 1654
// Glows rust while anything needs you. Click opens the roster (SUPER+G).
Island {
    id: root

    property bool open: false
    signal toggleRoster()

    hpad: 13
    glow: Board.needsYou > 0
    glowColor: Colors.attn

    // rust rim while something needs you, accent rim while the roster is open
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

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Text {
            visible: Board.needsYou > 0
            text: "● " + Board.needsYou + " needs you"
            color: Colors.attn
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.Bold
        }
        Text {
            text: "▶ " + Board.working
            color: Board.working > 0 ? Colors.fg0 : Colors.fg2
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.Bold
        }
        Text {
            visible: Board.background > 0
            text: "◐ " + Board.background
            color: Colors.blue
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.Bold
        }
        Text {
            visible: Board.designRecent
            text: "◇ design"
            color: Colors.accent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
        }
        // live stack chip: "ts ● 1654" (◐ while starting)
        Row {
            visible: Board.liveStack !== null
            spacing: 5
            Text {
                text: Board.liveStack ? Board.liveStack.abbr : ""
                color: Colors.fg2
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
            }
            Text {
                text: Board.liveStack && Board.liveStack.state === "starting" ? "◐" : "●"
                color: Board.liveStack && Board.liveStack.state === "starting" ? Colors.yellow : Colors.green
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
            }
            Text {
                text: Board.liveStack ? Board.liveStack.label : ""
                color: Colors.fg1
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
            }
        }
    }

    MouseArea {
        parent: root
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleRoster()
    }
}
