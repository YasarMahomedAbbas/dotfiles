import QtQuick
import QtQuick.Layouts
import Quickshell

// The one notification the board makes: a session just started needing you.
// A glass card dropped under the agents island for 8 s; nothing else toasts.
//   ● claude board · issue-1654
//   #1654 needs you
//   Results: The stack is live on issue-1654. Run the 8-step Edge guide…
// Click opens the roster. SUPER+space dismisses it (quickshell:dismisstoast).
PanelWindow {
    id: root

    property real rightOffset: 10        // right edge, aligned with the agents island
    property var  session: null
    property bool shown: false

    signal openRoster()

    readonly property string mono: "JetBrainsMono Nerd Font"

    function show(s) {
        session = s
        shown = true
        hideTimer.restart()
    }
    function dismiss() { shown = false }

    Connections {
        target: Board
        function onNeedsYouEntered(s) { root.show(s) }
        // gone the moment it's answered, or the session leaves needs_you
        function onSessionsChanged() {
            if (!root.shown || !root.session) return
            var k = root.session.key, still = Board.sessions.some(function (x) { return x.key === k && x.state === "needs_you" })
            if (!still) root.dismiss()
        }
    }

    Timer { id: hideTimer; interval: 8000; onTriggered: root.dismiss() }

    visible: shown || card.opacity > 0
    anchors { top: true; right: true }
    margins { top: 4; right: rightOffset }
    exclusiveZone: 0
    implicitWidth: 400
    implicitHeight: col.implicitHeight + 24 + 24      // + room for the shadow
    color: "transparent"

    Item {
        id: card
        x: 10
        width: parent.width - 20
        height: col.implicitHeight + 24
        opacity: root.shown ? 1 : 0
        y: root.shown ? 0 : -14
        Behavior on opacity { NumberAnimation { duration: 260 } }
        Behavior on y { NumberAnimation { duration: 450; easing.type: Easing.OutQuint } }

        Glass {
            anchors.fill: parent
            edge: Colors.alpha(Colors.attn, 0.6)
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; topMargin: 12 }
            spacing: 3

            Text {
                text: "<font color='" + Colors.attn + "'>●</font>  claude board · "
                      + (root.session ? Board.sessionName(root.session) : "")
                textFormat: Text.StyledText
                color: Colors.alpha(Colors.fg1, 0.7)
                font.family: root.mono; font.pixelSize: 11
            }
            Text {
                Layout.fillWidth: true
                text: !root.session ? ""
                    : Board.isPipeline(root.session) ? "#" + root.session.ticket.issue + " needs you"
                    : Board.sessionName(root.session) + " needs you"
                color: Colors.fg0
                elide: Text.ElideRight
                font.family: root.mono; font.pixelSize: 14; font.weight: Font.Bold
            }
            Text {
                Layout.fillWidth: true
                readonly property var a: root.session ? root.session.attention : null
                text: !a ? "" : (a.title && a.text ? a.title + ": " + a.text : (a.text || a.title || ""))
                visible: text !== ""
                color: Colors.fg1
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: root.mono; font.pixelSize: 12
            }
            Text {
                Layout.topMargin: 4
                text: "SUPER+G to answer · SUPER+N to jump there"
                color: Colors.fg2
                font.family: root.mono; font.pixelSize: 11
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.dismiss(); root.openRoster() }
        }
    }
}
