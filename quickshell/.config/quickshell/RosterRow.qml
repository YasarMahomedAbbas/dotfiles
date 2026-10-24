import QtQuick
import QtQuick.Layouts

// One roster row: ticket number · title + brief · status / stack / design chips
// over the stage strip. The selected row opens to the question (numbered
// options) and the action list; `confirming` shows the stack-switch line.
Rectangle {
    id: root

    property var  session: ({})
    property bool selected: false
    property bool confirming: false
    property string confirmText: ""

    signal clicked()
    signal activated()
    signal answer(int n)
    signal action(string k)      // an action button: o s t c v y

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property var s: session
    readonly property string st: Board.status(s)
    readonly property bool pipeline: Board.isPipeline(s)
    readonly property bool quiet: !pipeline && (st === "idle" || st === "stale")
    readonly property var dsg: Board.newestDesign(s)
    readonly property var att: s.attention || null

    implicitHeight: body.implicitHeight + 18
    radius: 12
    color: selected ? Qt.rgba(1, 1, 1, 0.06) : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
    border.width: selected ? 1 : 0
    border.color: Qt.rgba(1, 1, 1, 0.10)

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
        onDoubleClicked: root.activated()
    }

    // ── Chip texts ─────────────────────────────────────────────────────
    function statusChip() {
        var now = Board.now, c = s.current
        switch (st) {
        case "needs_you":
            return "● " + (pipeline ? Board.stageLabel(s) : (att && att.title) || "needs you")
                 + " · " + Board.fmt(now - ((att && att.since) || s.since))
        case "working":
        case "slow":
            if (c && c.started) {
                var d = (c.detail || c.tool || "")
                if (d.length > 26) d = d.slice(0, 25) + "…"
                return "▶ " + d + " " + Board.fmt(now - c.started)
                     + (st === "slow" ? " slow" : c.typical_ms ? " / ~" + Board.fmt(c.typical_ms) : "")
            }
            if (pipeline && s.ticket.stage_index === 2 && s.ticket.tasks_total)
                return "▶ implement · " + s.ticket.tasks_done + " of " + s.ticket.tasks_total
            return "▶ " + (pipeline ? Board.stageLabel(s).toLowerCase() : "working") + " · " + Board.fmt(now - s.since)
        case "background":
            var n = Board.runningAgents(s)
            return "◐ " + n + (n === 1 ? " agent" : " agents") + " · " + Board.fmt(now - s.since)
        case "done":
            return "✓ done " + Board.ago(now - (s.finished_at || s.since)) + " ago"
        case "stale":
            return "stale"
        default:
            return "idle " + Board.ago(now - (s.finished_at || s.since))
        }
    }
    function brief() {
        if (pipeline && s.ticket.problem && s.ticket.problem !== s.ticket.title) return s.ticket.problem
        var ag = (s.agents || []).filter(function (a) { return a.status === "running" })
        if (ag.length) return ag.map(function (a) { return a.description }).join(" · ")
        if (s.current && s.current.detail && st !== "idle") return s.current.tool + ": " + s.current.detail
        if (att && att.text) return att.text
        return ""
    }

    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; topMargin: 9 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // ticket number (or the session's short name)
            Text {
                Layout.preferredWidth: 64
                Layout.alignment: Qt.AlignVCenter
                text: root.pipeline ? "#" + root.s.ticket.issue : Board.shortName(root.s)
                color: root.quiet ? Colors.fg2 : Colors.fg0
                font.family: root.mono
                font.pixelSize: root.quiet ? 14 : 19
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: root.pipeline && root.s.ticket.title ? root.s.ticket.title : Board.sessionName(root.s)
                    color: root.quiet ? Colors.alpha(Colors.fg1, 0.7) : Colors.fg0
                    font.family: root.mono; font.pixelSize: 13; font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.brief()
                    color: Colors.alpha(Colors.fg1, 0.62)
                    font.family: root.mono; font.pixelSize: 11
                    wrapMode: Text.Wrap
                    maximumLineCount: root.selected ? 2 : 1
                    elide: Text.ElideRight
                    lineHeight: 1.1
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 300
                Layout.maximumWidth: 300
                spacing: 5

                Flow {
                    Layout.fillWidth: true
                    layoutDirection: Qt.RightToLeft
                    spacing: 5

                    // RightToLeft: the first chip sits rightmost
                    Chip {
                        visible: root.s.stack !== null && root.s.stack !== undefined
                        text: root.s.stack === "live" ? "● stack live"
                            : root.s.stack === "starting" ? "◐ starting…" : "○ stack · s"
                        fg: root.s.stack === "live" ? Colors.green : root.s.stack === "starting" ? Colors.yellow : Colors.fg1
                        edge: Colors.bg3
                        bold: false
                    }
                    Chip {
                        visible: root.dsg !== null
                        text: "◇ design" + (root.dsg && root.dsg.boards ? " · " + root.dsg.boards + " boards" : "")
                        fg: Colors.accent
                        fill: Colors.alpha(Colors.accent, 0.16)
                        edge: Colors.alpha(Colors.accent, 0.5)
                    }
                    Chip {
                        readonly property color c: Board.statusColor(root.st)
                        text: root.statusChip()
                        fg: c
                        fill: root.st === "idle" || root.st === "stale" ? "transparent"
                            : Colors.alpha(c, root.st === "working" ? 0.08 : 0.15)
                        edge: root.st === "needs_you" ? Colors.alpha(c, 0.45)
                            : root.st === "idle" || root.st === "stale" ? Colors.bg3 : "transparent"
                    }
                }

                Segs {
                    visible: root.pipeline
                    Layout.alignment: Qt.AlignRight
                    implicitWidth: 150
                    implicitHeight: 7
                    cells: Board.stageCells(root.s)
                }
            }
        }

        // ── Stack switch confirmation (first `s`) ──────────────────────
        Rectangle {
            visible: root.selected && root.confirming
            Layout.fillWidth: true
            implicitHeight: conf.implicitHeight + 20
            radius: 12
            color: Colors.alpha(Colors.yellow, 0.10)
            border.width: 1
            border.color: Colors.alpha(Colors.yellow, 0.35)
            ColumnLayout {
                id: conf
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: root.confirmText
                    color: Colors.fg0
                    wrapMode: Text.Wrap
                    font.family: root.mono; font.pixelSize: 12
                }
                Text {
                    text: "s again to switch the stack · esc cancels"
                    color: Colors.yellow
                    font.family: root.mono; font.pixelSize: 11
                }
            }
        }

        // ── Expanded: the question (or what it's doing) + actions ───────
        RowLayout {
            visible: root.selected
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                implicitHeight: ask.implicitHeight + 20
                radius: 12
                color: Qt.rgba(0, 0, 0, 0.28)
                ColumnLayout {
                    id: ask
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; topMargin: 10 }
                    spacing: 6
                    Text {
                        text: root.att ? ("CLAUDE ASKED · " + Board.fmt(Board.now - (root.att.since || root.s.since)) + " AGO")
                            : root.dsg && !root.s.current ? "DESIGN CANVAS"
                            : "NOW"
                        color: Colors.alpha(Colors.fg1, 0.6)
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 0.8
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.att ? (root.att.text || root.att.title || "")
                            : root.s.current ? root.s.current.tool + " · " + (root.s.current.detail || "")
                              + " · " + Board.fmt(Board.now - root.s.current.started)
                            : root.dsg ? (root.dsg.title || root.dsg.url)
                            : root.st === "background" ? Board.runningAgents(root.s) + " running in the background"
                            : "nothing running"
                        color: Colors.fg0
                        wrapMode: Text.Wrap
                        font.family: root.mono; font.pixelSize: 12
                    }
                    // running agents, for a session that isn't asking
                    Repeater {
                        model: root.att ? [] : (root.s.agents || []).filter(function (a) { return a.status !== "done" && !a.ended }).slice(0, 4)
                        delegate: Text {
                            required property var modelData
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "▶ " + (modelData.type || "Agent") + "  " + (modelData.description || "")
                                  + "  " + Board.fmt(Board.now - (modelData.started || Board.now))
                            color: modelData.status === "needs_you" ? Colors.attn : Colors.blue
                            font.family: root.mono; font.pixelSize: 11
                        }
                    }
                    Flow {
                        visible: root.att !== null && (root.att.options || []).length > 0
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: root.att ? (root.att.options || []).slice(0, 9) : []
                            delegate: Btn {
                                required property var modelData
                                required property int index
                                key: modelData.key || String(index + 1)
                                text: modelData.label || ""
                                primary: index === 0
                                onClicked: root.answer(index + 1)
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                implicitHeight: acts.implicitHeight + 20
                radius: 12
                color: Qt.rgba(0, 0, 0, 0.28)
                ColumnLayout {
                    id: acts
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; topMargin: 10 }
                    spacing: 6
                    Text {
                        text: "ACTIONS"
                        color: Colors.alpha(Colors.fg1, 0.6)
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 0.8
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Btn { key: "⏎"; text: "Jump to pane"; primary: root.att === null; onClicked: root.activated() }
                        Btn { visible: root.s.stack === "live"; key: "o"; text: "Open stack"; onClicked: root.action("o") }
                        Btn { visible: root.s.stack !== null && root.s.stack !== undefined && root.s.stack !== "live"; key: "s s"; text: "Start stack"; onClicked: root.action("s") }
                        Btn { visible: root.pipeline; key: "t"; text: "Ticket on GitHub"; onClicked: root.action("t") }
                        Btn { key: "c"; text: "Checklist"; onClicked: root.action("c") }
                        Btn { visible: root.dsg !== null; key: "v"; text: "View design"; onClicked: root.action("v") }
                        Btn { visible: root.dsg !== null; key: "y"; text: "Copy link"; onClicked: root.action("y") }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.s.stack === "live" ? "Stack is live here"
                            : root.s.stack === "starting" ? "Stack is starting"
                            : root.s.branch ? root.s.branch : ""
                        color: Colors.alpha(Colors.fg1, 0.6)
                        elide: Text.ElideRight
                        font.family: root.mono; font.pixelSize: 11
                    }
                }
            }
        }
    }
}
