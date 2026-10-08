import QtQuick
import QtQuick.Layouts

// The checklist wall (SUPER+Shift+G, or c in the roster): one card per session,
// two columns. A pipeline card lists the six stages (Implement split into its
// tasks); any other session shows Claude's own task list.
//   h/j/k/l ←↓↑→ move · ⏎ jump · ? keys · esc close
Item {
    id: root

    property bool   active: false
    property string focusKey: ""         // session to select on open
    property int    maxHeight: 900

    signal requestClose()
    signal openKeys()

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property var sessions: Board.sessions.filter(function (s) { return !s.stale })

    property int sel: 0
    readonly property var cur: sessions.length ? sessions[Math.max(0, Math.min(sel, sessions.length - 1))] : null

    implicitHeight: Math.min(col.implicitHeight + 28, maxHeight)

    onActiveChanged: {
        if (!active) return
        sel = 0
        for (var i = 0; i < sessions.length; i++) if (sessions[i].key === focusKey) sel = i
        Board.refresh()
        Qt.callLater(function () { keys.forceActiveFocus() })
        Qt.callLater(ensureVisible)
    }
    onSelChanged: Qt.callLater(ensureVisible)

    function move(d) {
        if (!sessions.length) return
        var n = sel + d
        if (n >= 0 && n < sessions.length) sel = n
    }
    function ensureVisible() {
        var it = cards.itemAt(sel)
        if (!it) return
        if (it.y < flick.contentY) flick.contentY = it.y
        else if (it.y + it.height > flick.contentY + flick.height)
            flick.contentY = it.y + it.height - flick.height
    }

    // Key handler. Not `focus: true` up front: it takes focus when the popup
    // opens, so it never holds the bar's focus while hidden.
    Item {
        id: keys
        Keys.onPressed: function (e) {
            var t = e.text
            if (e.key === Qt.Key_Escape) root.requestClose()
            else if (t === "l" || e.key === Qt.Key_Right || e.key === Qt.Key_Tab) root.move(1)
            else if (t === "h" || e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) root.move(-1)
            else if (t === "j" || e.key === Qt.Key_Down) root.move(2)
            else if (t === "k" || e.key === Qt.Key_Up) root.move(-2)
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (root.cur) { Board.run(["jump", root.cur.key]); root.requestClose() }
            }
            else if (t === "?") root.openKeys()
            else return
            e.accepted = true
        }
    }

    Glass { anchors.fill: parent }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 16; bottomMargin: 10 }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6; Layout.rightMargin: 6
            Text {
                text: "Where we're at"
                color: Colors.fg0
                font.family: root.mono; font.pixelSize: 17
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "SUPER+Shift+G · or c in the roster · h/j/k/l · ⏎ jump · esc"
                color: Colors.alpha(Colors.fg1, 0.7)
                font.family: root.mono; font.pixelSize: 11
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: grid.implicitHeight
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            GridLayout {
                id: grid
                width: flick.width
                columns: 2
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    id: cards
                    model: root.sessions
                    delegate: WallCard {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        session: modelData
                        selected: index === root.sel
                        onClicked: root.sel = index
                        onActivated: { Board.run(["jump", modelData.key]); root.requestClose() }
                    }
                }
            }
        }

        Text {
            visible: root.sessions.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Board.available ? "no Claude sessions" : "`" + Board.boardCmd + "` isn't available yet"
            color: Colors.fg2
            font.family: root.mono; font.pixelSize: 12
        }
    }
}
