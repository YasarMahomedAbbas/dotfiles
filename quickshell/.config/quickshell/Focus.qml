import QtQuick
import QtQuick.Layouts

// The focus view (SUPER+Shift+G, or f on a wall card): a compact list of every
// session on the left (glyph, issue, title, a six-segment strip, the stage word)
// and the selected one in full on the right: problem and branch, the large
// stepper, Implement's checkpoints with the current one's task bar, what runs
// now (the tool against its typical time, agents, shells), Claude's own tasks.
//   j/k ↓/↑ next session · ⏎ jump · 1-9 answer · s s v y o t · f wall · / filter · ? keys · esc
Item {
    id: root

    property bool   active: false
    property string focusKey: ""
    property int    maxHeight: 900

    signal requestClose()
    signal openWall(string key)
    signal openKeys()

    readonly property string mono: "JetBrainsMono Nerd Font"

    property int    sel: 0
    property string filter: ""
    property bool   filtering: false

    readonly property var rows: Board.sessions.filter(function (s) { return !s.stale && Board.matches(s, root.filter) })
    readonly property var cur: rows.length ? rows[Math.max(0, Math.min(sel, rows.length - 1))] : null
    readonly property var s: cur || ({})
    readonly property string k: cur ? Board.kind(cur) : "idle"
    readonly property color kc: cur ? Board.kindColor(cur) : Colors.fg2
    readonly property var tool: cur && cur.current ? cur.current : null
    readonly property var cps: (cur && cur.ticket && cur.ticket.checkpoints) || []
    readonly property var curCp: cur ? Board.curCheckpoint(cur) : null

    implicitHeight: Math.min(740, maxHeight)

    onActiveChanged: {
        if (!active) return
        sel = 0; filter = ""; filtering = false
        acts.confirmKey = ""; acts.flash = ""
        for (var i = 0; i < rows.length; i++) if (rows[i].key === focusKey) sel = i
        Board.refresh()
        Qt.callLater(function () { keys.forceActiveFocus() })
    }
    onSelChanged: { acts.moved(cur); list.positionViewAtIndex(sel, ListView.Contain) }

    function move(d) { if (rows.length) sel = Math.max(0, Math.min(rows.length - 1, sel + d)) }

    BoardActions {
        id: acts
        onRequestClose: root.requestClose()
    }

    Item {
        id: keys
        Keys.onPressed: function (e) {
            var t = e.text
            if (e.key === Qt.Key_Escape) {
                if (acts.confirmKey) acts.confirmKey = ""
                else if (root.filter) root.filter = ""
                else root.requestClose()
            }
            else if (t === "j" || e.key === Qt.Key_Down || e.key === Qt.Key_Tab) root.move(1)
            else if (t === "k" || e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) root.move(-1)
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) acts.jump(root.cur)
            else if (t === "f") root.openWall(root.cur ? root.cur.key : "")
            else if (t === "/") { root.filtering = true; filterInput.forceActiveFocus() }
            else if (t === "?") root.openKeys()
            else if (!acts.key(t, root.cur)) return
            e.accepted = true
        }
    }

    Glass { anchors.fill: parent; radius: 18 }

    RowLayout {
        anchors { fill: parent; margins: 1 }
        spacing: 0

        // ── the list ────────────────────────────────────────────────────
        ColumnLayout {
            Layout.preferredWidth: 340
            Layout.fillHeight: true
            Layout.margins: 12
            Layout.topMargin: 18
            spacing: 4

            RowLayout {
                Layout.leftMargin: 12; Layout.bottomMargin: 8
                spacing: 10
                Text { text: "Agents"; color: Colors.fg0; font.family: root.mono; font.pixelSize: 15 }
                Text { text: root.rows.length + " open"; color: Colors.fg2; font.family: root.mono; font.pixelSize: 11 }
            }
            Rectangle {
                visible: root.filtering || root.filter !== ""
                Layout.fillWidth: true
                implicitHeight: 24
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.3)
                border.width: 1
                border.color: root.filtering ? Colors.alpha(Colors.attn, 0.5) : Qt.rgba(1, 1, 1, 0.12)
                TextInput {
                    id: filterInput
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: root.filter
                    onTextEdited: { root.filter = text; root.sel = 0 }
                    color: Colors.fg0
                    font.family: root.mono; font.pixelSize: 12
                    Keys.onPressed: function (e) {
                        if (e.key === Qt.Key_Escape) { root.filter = ""; root.filtering = false; keys.forceActiveFocus(); e.accepted = true }
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Down) {
                            root.filtering = false; keys.forceActiveFocus(); e.accepted = true
                        }
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: root.rows
                delegate: Rectangle {
                    id: rowD
                    required property var modelData
                    required property int index
                    readonly property bool isSel: index === root.sel
                    readonly property bool pipe: Board.isPipeline(modelData)
                    readonly property color c: Board.kindColor(modelData)
                    width: list.width
                    implicitHeight: rc.implicitHeight + 20
                    radius: 10
                    color: isSel ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                    border.width: 1
                    border.color: isSel ? Colors.attn : "transparent"
                    ColumnLayout {
                        id: rc
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text { text: Board.glyph(rowD.modelData); color: rowD.c; font.family: root.mono; font.pixelSize: 12 }
                            Text {
                                visible: text !== ""
                                text: Board.issueText(rowD.modelData)
                                color: Colors.alpha(Colors.fg1, 0.75)
                                font.family: root.mono; font.pixelSize: 12
                            }
                            Text {
                                Layout.fillWidth: true
                                text: Board.title(rowD.modelData)
                                elide: Text.ElideRight
                                color: Colors.fg0
                                font.family: root.mono; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            Text { text: Board.el(Board.now - (rowD.modelData.since || Board.now)); color: Colors.fg2; font.family: root.mono; font.pixelSize: 11 }
                        }
                        RowLayout {
                            visible: rowD.pipe
                            Layout.fillWidth: true
                            spacing: 3
                            Repeater {
                                model: rowD.pipe ? Board.stageClasses(rowD.modelData) : []
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    height: 6; radius: 2
                                    color: modelData === "done" ? Colors.green : modelData === "now" ? Colors.fg0
                                         : modelData === "bg" ? Colors.blue : modelData === "attn" ? Colors.attn
                                         : Qt.rgba(1, 1, 1, 0.14)
                                }
                            }
                            Text {
                                Layout.preferredWidth: 74
                                horizontalAlignment: Text.AlignRight
                                text: Board.stageWord(rowD.modelData)
                                color: rowD.c
                                elide: Text.ElideRight
                                font.family: root.mono; font.pixelSize: 11
                            }
                        }
                        Text {
                            visible: !rowD.pipe
                            text: Board.oneLiner(rowD.modelData)
                            color: Colors.fg2
                            font.family: root.mono; font.pixelSize: 11
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.sel = rowD.index
                        onDoubleClicked: acts.jump(rowD.modelData)
                    }
                }
            }
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: Qt.rgba(1, 1, 1, 0.10) }

        // ── the focus pane ──────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 30
            Layout.topMargin: 26
            spacing: 22
            visible: root.cur !== null

            // what
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        visible: text !== ""
                        text: Board.issueText(root.s)
                        color: Colors.alpha(Colors.fg1, 0.75)
                        font.family: root.mono; font.pixelSize: 14
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.cur ? Board.title(root.s) : ""
                        elide: Text.ElideRight
                        color: Colors.fg0
                        font.family: root.mono; font.pixelSize: 20; font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.cur ? Board.chip(root.s).toLowerCase() + " · " + Board.timeText(root.s) : ""
                        color: root.kc
                        font.family: root.mono; font.pixelSize: 12
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.cur ? Board.problem(root.s) : ""
                    wrapMode: Text.Wrap
                    color: Colors.alpha(Colors.fg1, 0.8)
                    font.family: root.mono; font.pixelSize: 14
                    lineHeight: 1.2
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: [root.s.branch || "", (root.s.tmux && root.s.tmux.session) || "", root.s.model || ""]
                          .filter(function (x) { return x }).join(" · ")
                    color: Colors.fg2
                    font.family: root.mono; font.pixelSize: 11
                }
            }

            // where
            Rectangle {
                visible: root.cur !== null && Board.isPipeline(root.s)
                Layout.fillWidth: true
                implicitHeight: big.implicitHeight + 34
                radius: 14
                color: Qt.rgba(0, 0, 0, 0.25)
                Stepper {
                    id: big
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8; topMargin: 20 }
                    dot: 26; labelSize: 12; showSub: true
                    steps: root.cur ? Board.steps(root.s, false) : []
                }
            }

            // checkpoints | running now
            RowLayout {
                Layout.fillWidth: true
                spacing: 26

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 10
                    visible: root.cps.length > 0
                    Text { text: "IMPLEMENT · CHECKPOINTS"; color: Colors.fg2; font.family: root.mono; font.pixelSize: 11; font.letterSpacing: 1 }
                    Repeater {
                        model: root.cps.slice(0, 12)
                        delegate: ColumnLayout {
                            id: cpD
                            required property var modelData
                            required property int index
                            readonly property bool isCur: root.curCp !== null && root.curCp.k === index + 1
                            // its own tasks (travel-smart), else Claude's task list
                            readonly property var ct: Board.claudeTasks(root.s)
                            readonly property var bar: !isCur ? null
                                : modelData.tasks_total ? { d: modelData.tasks_done || 0, t: modelData.tasks_total }
                                : ct.total ? { d: ct.done, t: ct.total } : null
                            Layout.fillWidth: true
                            spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Text {
                                    Layout.preferredWidth: 14
                                    text: cpD.modelData.done ? "✓" : cpD.isCur ? (root.k === "attn" ? "!" : "▶") : "○"
                                    color: cpD.modelData.done ? Colors.green : cpD.isCur ? root.kc : Colors.fg2
                                    font.family: root.mono; font.pixelSize: 13
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: cpD.modelData.name
                                    elide: Text.ElideRight
                                    color: cpD.isCur ? Colors.fg0 : Colors.alpha(Colors.fg1, 0.75)
                                    font.family: root.mono; font.pixelSize: 13
                                }
                                Text {
                                    visible: cpD.modelData.tasks_total > 0 && !cpD.isCur
                                    text: (cpD.modelData.tasks_done || 0) + "/" + (cpD.modelData.tasks_total || 0)
                                    color: Colors.fg2
                                    font.family: root.mono; font.pixelSize: 11
                                }
                            }
                            RowLayout {
                                visible: cpD.bar !== null
                                Layout.fillWidth: true
                                Layout.leftMargin: 24
                                spacing: 10
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 5; radius: 3
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    Rectangle {
                                        width: cpD.bar ? parent.width * cpD.bar.d / Math.max(1, cpD.bar.t) : 0
                                        height: parent.height; radius: 3
                                        color: root.kc
                                    }
                                }
                                Text {
                                    text: cpD.bar ? cpD.bar.d + " of " + cpD.bar.t + " tasks" : ""
                                    color: Colors.alpha(Colors.fg1, 0.75)
                                    font.family: root.mono; font.pixelSize: 11
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 10

                    Text { text: root.k === "attn" ? "ASKING YOU" : "RUNNING NOW"; color: root.k === "attn" ? Colors.attn : Colors.fg2; font.family: root.mono; font.pixelSize: 11; font.letterSpacing: 1 }

                    // the question and its options
                    WallCard {
                        visible: root.k === "attn"
                        Layout.fillWidth: true
                        session: root.s
                        compact: false
                        onAnswer: function (n) { acts.answer(root.cur, n) }
                    }

                    // the tool in flight against its typical time
                    Rectangle {
                        visible: root.k === "now" && root.tool !== null
                        Layout.fillWidth: true
                        implicitHeight: curCol.implicitHeight + 24
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: Colors.alpha(root.kc, 0.25)
                        ColumnLayout {
                            id: curCol
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Text { text: "▶"; color: root.kc; font.family: root.mono; font.pixelSize: 13 }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.tool ? (root.tool.tool || "") + (root.tool.detail ? " · " + root.tool.detail : "") : ""
                                    elide: Text.ElideRight
                                    color: Colors.fg0
                                    font.family: root.mono; font.pixelSize: 13
                                }
                                Text {
                                    text: root.tool ? Board.el(Board.now - (root.tool.started || Board.now)) : ""
                                    color: Colors.alpha(Colors.fg1, 0.75)
                                    font.family: root.mono; font.pixelSize: 13
                                }
                            }
                            RowLayout {
                                visible: root.tool !== null && !!root.tool.typical_ms
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 4; radius: 2
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    Rectangle {
                                        width: root.tool && root.tool.typical_ms
                                               ? parent.width * Math.min(1, (Board.now - (root.tool.started || Board.now)) / root.tool.typical_ms) : 0
                                        height: parent.height; radius: 2
                                        color: root.kc
                                    }
                                }
                                Text {
                                    text: root.tool && root.tool.typical_ms ? "typical " + Board.el(root.tool.typical_ms) : ""
                                    color: Colors.fg2
                                    font.family: root.mono; font.pixelSize: 11
                                }
                            }
                        }
                    }

                    // agents and shells: running, and what finished in the last quarter hour
                    Repeater {
                        model: {
                            if (!root.cur) return []
                            var cut = Board.now - 15 * 60000, out = []
                            ;(root.s.agents || []).forEach(function (a) {
                                var live = a.status === "running" || a.status === "needs_you"
                                if (live || (a.ended || 0) > cut)
                                    out.push({ g: live ? "◆" : "✓", gc: a.status === "needs_you" ? Colors.attn : live ? Colors.blue : Colors.green,
                                               t: "agent · " + (a.description || a.type || ""), live: live,
                                               r: Board.el((a.ended || Board.now) - (a.started || Board.now)) })
                            })
                            ;(root.s.shells || []).forEach(function (x) {
                                var live = x.status === "running"
                                if (live || (x.started || 0) > cut)
                                    out.push({ g: live ? "$" : "✓", gc: live ? Colors.blue : Colors.green, t: x.command || "", live: live,
                                               r: Board.el(Board.now - (x.started || Board.now)) })
                            })
                            return out.slice(0, 8)
                        }
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10
                            Text { text: modelData.g; color: modelData.gc; font.family: root.mono; font.pixelSize: 12 }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.t
                                elide: Text.ElideRight
                                color: modelData.live ? Colors.fg1 : Colors.fg2
                                font.family: root.mono; font.pixelSize: 12
                            }
                            Text { text: modelData.r; color: Colors.fg2; font.family: root.mono; font.pixelSize: 12 }
                        }
                    }
                    Text {
                        visible: root.cur !== null && root.k !== "attn" && !(root.k === "now" && root.s.current)
                                 && Board.runningList(root.s).length === 0
                        text: root.k === "done" ? "turn ended · ⏎ to read the reply" : "nothing running"
                        color: Colors.fg2
                        font.family: root.mono; font.pixelSize: 12
                    }

                    // Claude's own task list
                    Text {
                        visible: (root.s.tasks || []).length > 0
                        Layout.topMargin: 8
                        text: "ITS OWN TASKS"
                        color: Colors.fg2
                        font.family: root.mono; font.pixelSize: 11; font.letterSpacing: 1
                    }
                    Repeater {
                        model: (root.s.tasks || []).slice(0, 10)
                        delegate: Text {
                            required property var modelData
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: (modelData.status === "completed" ? "✓ " : modelData.status === "in_progress" ? "▶ " : "○ ") + (modelData.subject || "")
                            color: modelData.status === "completed" ? Colors.fg2 : modelData.status === "in_progress" ? Colors.fg0 : Colors.alpha(Colors.fg1, 0.75)
                            font.family: root.mono; font.pixelSize: 12
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // keys
            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: acts.confirmKey ? acts.confirmText + " · s again to switch · esc cancels"
                        : "⏎ jump · 1-9 answer · t ticket · s s stack · v y design · o open · j/k next session · f wall · / filter · ? keys"
                    color: acts.confirmKey ? Colors.yellow : Colors.fg2
                    font.family: root.mono; font.pixelSize: 11
                }
                Text {
                    text: acts.flash || "esc"
                    color: acts.flash ? Colors.attn : Colors.fg2
                    font.family: root.mono; font.pixelSize: 11
                }
            }
        }

        Text {
            visible: root.cur === null
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: !Board.available ? "`" + Board.boardCmd + "` isn't available yet" : "no Claude sessions"
            color: Colors.fg2
            font.family: root.mono; font.pixelSize: 12
        }
    }
}
