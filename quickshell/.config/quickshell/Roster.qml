import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The roster (SUPER+G): every Claude session, its ticket and status, dropped
// under the agents island. Takes the keyboard the moment it opens.
//
//   j/k ↑/↓ move · ⏎ jump (`board jump`) · 1-9 answer (`board answer`)
//   s s stack (`board stack`, then `--yes`) · v design · y copy design link
//   o open the live stack's url · t ticket on GitHub · c checklist wall
//   / filter · ? keys · esc close
Item {
    id: root

    property bool active: false          // set by the bar while open
    property int  maxHeight: 700

    signal requestClose()
    signal openWall(string key)
    signal openKeys()

    implicitWidth: 820
    implicitHeight: col.implicitHeight + 24

    readonly property string mono: "JetBrainsMono Nerd Font"

    property int    sel: 0
    property string filter: ""
    property bool   filtering: false
    property string confirmKey: ""       // first `s` pressed on this session
    property string confirmText: ""
    property string flash: ""

    readonly property var rows: {
        var f = filter.toLowerCase()
        return Board.sessions.filter(function (s) {
            if (!f) return true
            var hay = [Board.sessionName(s), s.branch || "", s.ticket ? "#" + s.ticket.issue : "",
                       s.ticket ? s.ticket.title || "" : "", s.ticket ? s.ticket.problem || "" : ""].join(" ")
            return hay.toLowerCase().indexOf(f) !== -1
        })
    }
    readonly property var cur: rows.length ? rows[Math.max(0, Math.min(sel, rows.length - 1))] : null

    onActiveChanged: {
        if (!active) return
        sel = 0; filter = ""; filtering = false
        confirmKey = ""; flash = ""
        Board.refresh()
        Qt.callLater(function () { keys.forceActiveFocus() })
    }
    onSelChanged: { if (cur && cur.key !== confirmKey) confirmKey = ""; list.positionViewAtIndex(sel, ListView.Contain) }

    function say(msg) { flash = msg; flashTimer.restart() }
    Timer { id: flashTimer; interval: 4000; onTriggered: root.flash = "" }

    function move(d) { if (rows.length) sel = Math.max(0, Math.min(rows.length - 1, sel + d)) }

    function jump(s) {
        if (!s) return
        Board.run(["jump", s.key])
        root.requestClose()
    }
    function answer(s, n) {
        if (!s || s.state !== "needs_you") { say("nothing to answer there"); return }
        var opts = (s.attention && s.attention.options) || []
        if (opts.length && n > opts.length) { say("only " + opts.length + " options"); return }
        Board.run(["answer", s.key, String(n)])
        say("sent " + n + " → " + Board.sessionName(s))
    }
    function stack(s) {
        if (!s) return
        if (confirmKey === s.key) {
            Board.run(["stack", s.key, "--yes"])
            confirmKey = ""
            say("starting the stack for " + Board.sessionName(s))
            return
        }
        confirmKey = s.key
        confirmText = "checking what this would stop…"
        preview.command = ["sh", "-c", '"$0" stack "$1" 2>&1', Board.boardCmd, s.key]
        preview.running = true
    }
    function design(s, copy) {
        if (!s || !Board.newestDesign(s)) { say("no design for this session"); return }
        Board.run(copy ? ["design", s.key, "--copy"] : ["design", s.key])
        say(copy ? "design link copied" : "opening the design")
    }
    // o / t use the CLI's roster internals (the same ones `board roster`'s fzf
    // binds call): `__open-url` opens the live stack's first url, `__ticket`
    // runs `gh issue view <n> --web` against the right repo.
    function openStack(s) {
        if (!s) return
        if (s.stack !== "live" && s.stack !== "starting") { say("this worktree's stack isn't live"); return }
        Board.run(["__open-url", s.key])
        say("opening the stack")
    }
    function openTicket(s) {
        if (!s || !s.ticket || !s.ticket.issue) { say("no ticket for this session"); return }
        Board.run(["__ticket", s.key])
        say("opening #" + s.ticket.issue)
    }

    function act(k, s) {
        if (k === "s") stack(s)
        else if (k === "v") design(s, false)
        else if (k === "y") design(s, true)
        else if (k === "o") openStack(s)
        else if (k === "t") openTicket(s)
        else if (k === "c") openWall(s ? s.key : "")
    }

    Process {
        id: preview
        stdout: StdioCollector {
            onStreamFinished: root.confirmText = text.trim() || "wt-dev use on this worktree"
        }
    }

    // ── Keyboard ────────────────────────────────────────────────────────
    // Key handler. Not `focus: true` up front: it takes focus when the popup
    // opens, so it never holds the bar's focus while hidden.
    Item {
        id: keys
        Keys.onPressed: function (e) {
            var t = e.text, s = root.cur
            if (e.key === Qt.Key_Escape) {
                if (root.confirmKey) root.confirmKey = ""
                else if (root.filter) root.filter = ""
                else root.requestClose()
            } else if (t === "j" || e.key === Qt.Key_Down || e.key === Qt.Key_Tab) root.move(1)
            else if (t === "k" || e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) root.move(-1)
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.jump(s)
            else if (t >= "1" && t <= "9" && t.length === 1) root.answer(s, parseInt(t))
            else if ("svyotc".indexOf(t) !== -1 && t.length === 1) root.act(t, s)
            else if (t === "/") { root.filtering = true; filterInput.forceActiveFocus() }
            else if (t === "?") root.openKeys()
            else return
            e.accepted = true
        }
    }

    Glass { anchors.fill: parent }

    ColumnLayout {
        id: col
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14; topMargin: 12 }
        spacing: 6

        // ── Header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6; Layout.rightMargin: 6
            spacing: 12

            Text {
                text: "Agents"
                color: Colors.fg0
                font.family: root.mono
                font.pixelSize: 17
            }

            // filter field: `/` focuses it, ⏎/↓ returns to the list, esc clears
            Rectangle {
                visible: root.filtering || root.filter !== ""
                Layout.fillWidth: true
                implicitHeight: 24
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.3)
                border.width: 1
                border.color: root.filtering ? Colors.alpha(Colors.accent, 0.5) : Qt.rgba(1, 1, 1, 0.12)
                Text {
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    text: "⌕"
                    color: Colors.accent
                    font.family: root.mono; font.pixelSize: 12
                }
                TextInput {
                    id: filterInput
                    anchors { left: parent.left; leftMargin: 24; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: root.filter
                    onTextEdited: { root.filter = text; root.sel = 0 }
                    color: Colors.fg0
                    font.family: root.mono; font.pixelSize: 12
                    selectionColor: Colors.alpha(Colors.accent, 0.4)
                    Keys.onPressed: function (e) {
                        if (e.key === Qt.Key_Escape) { root.filter = ""; root.filtering = false; keys.forceActiveFocus(); e.accepted = true }
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Down) {
                            root.filtering = false; keys.forceActiveFocus(); e.accepted = true
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true; visible: !(root.filtering || root.filter !== "") }

            Text {
                text: "SUPER+G · " + Board.sessions.length + " sessions"
                      + (Board.needsYou ? " · " + Board.needsYou + " needs you" : "")
                      + (Board.working ? " · " + Board.working + " running" : "")
                color: Colors.alpha(Colors.fg1, 0.7)
                font.family: root.mono; font.pixelSize: 11
            }
        }

        // ── Rows ────────────────────────────────────────────────────────
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.maxHeight - 90)
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.rows
            currentIndex: root.sel

            delegate: RosterRow {
                required property var modelData
                required property int index
                width: list.width
                session: modelData
                selected: index === root.sel
                confirming: root.confirmKey !== "" && root.confirmKey === modelData.key
                confirmText: root.confirmText
                onClicked: root.sel = index
                onActivated: root.jump(modelData)
                onAnswer: function (n) { root.answer(modelData, n) }
                onAction: function (k) { root.sel = index; root.act(k, modelData) }
            }
        }

        // empty states
        Text {
            visible: root.rows.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 10; Layout.bottomMargin: 10
            horizontalAlignment: Text.AlignHCenter
            text: !Board.available ? "`" + Board.boardCmd + "` isn't available yet"
                : root.filter ? "nothing matches “" + root.filter + "”"
                : "no Claude sessions"
            color: Colors.fg2
            font.family: root.mono; font.pixelSize: 12
        }

        // ── Footer ──────────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6; Layout.rightMargin: 6
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.filtering ? "type to filter · ⏎ back to the list · esc clears"
                    : root.confirmKey ? "s again to confirm · esc cancels"
                    : "j/k move · ⏎ jump · 1-9 answer · s stack · v design · c checklist · / filter · ? keys · esc"
                color: Colors.fg2
                font.family: root.mono; font.pixelSize: 11
            }
            Text {
                text: root.flash || "~/.cache/claude-board"
                color: root.flash ? Colors.accent : Colors.fg2
                font.family: root.mono; font.pixelSize: 11
            }
        }
    }
}
