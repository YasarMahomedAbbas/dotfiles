import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The keys cheatsheet (SUPER+/, or ? in the roster and the wall), built from the
// live config so it can't go stale:
//   Hyprland  `hyprctl binds -j` — only binds with a description, grouped by the
//             "Group: what it does" prefix (see hyprland.lua's KEYBINDINGS)
//   board     `board keys --json` — the roster's keys (built-in table as fallback)
//   tmux      `tmux list-keys -N` — keys that carry a note
// Type to filter · ↑/↓ (Tab) pick a Hyprland bind · ⏎ runs it · esc closes.
Item {
    id: root

    property bool active: false
    property int  maxHeight: 900

    signal requestClose()

    readonly property string mono: "JetBrainsMono Nerd Font"

    property var hyprItems:  []
    property var tmuxItems:  []
    property var boardItems: []
    property string filter: ""
    property int cursor: -1

    implicitHeight: Math.min(col.implicitHeight + 32, maxHeight)

    onActiveChanged: {
        if (!active) return
        filter = ""; input.text = ""; cursor = -1
        hyprProc.running = true
        tmuxProc.running = true
        boardProc.running = true
        Qt.callLater(function () { input.forceActiveFocus() })
    }

    // ── Sources ─────────────────────────────────────────────────────────
    readonly property var groupOrder: ["Agents", "In the roster", "tmux", "Windows", "Workspaces",
                                       "Apps", "Shell", "Notifications", "Capture", "Media", "Session"]

    function modKeys(mask) {
        var k = []
        if (mask & 64) k.push("⊞")
        if (mask & 4)  k.push("Ctrl")
        if (mask & 8)  k.push("Alt")
        if (mask & 1)  k.push("⇧")
        return k
    }
    function keyName(k) {
        var map = { "slash": "/", "space": "space", "Escape": "esc", "Return": "⏎", "down": "↓", "up": "↑",
                    "left": "←", "right": "→", "mouse:272": "LMB drag", "mouse:273": "RMB drag",
                    "mouse_down": "scroll ↓", "mouse_up": "scroll ↑" }
        if (map[k] !== undefined) return map[k]
        return k.replace(/^XF86Audio/, "").replace(/^XF86MonBrightness/, "Bright").replace(/^XF86/, "")
    }

    function parseHypr(text) {
        var binds = []
        try { binds = JSON.parse(text) } catch (e) { binds = [] }
        var out = []
        for (var i = 0; i < binds.length; i++) {
            var b = binds[i]
            if (!b.has_description || !b.description) continue
            var d = b.description, c = d.indexOf(": ")
            var g = c > 0 ? d.slice(0, c) : "Other", t = c > 0 ? d.slice(c + 2) : d
            var item = { src: "hypr", group: g, mask: b.modmask, key: b.key,
                         keys: modKeys(b.modmask).concat([keyName(b.key)]), desc: t,
                         run: b.key.indexOf("mouse:") === 0 ? null : d }
            // fold runs like "Go to workspace 1" … "Go to workspace 10" into one "1–0" line
            var prev = out[out.length - 1], m = t.match(/^(.*\D)\s(\d+)$/)
            if (m && prev && prev.group === g && prev.mask === b.modmask && prev.base === m[1]) {
                prev.last = keyName(b.key)
                prev.keys = modKeys(b.modmask).concat([prev.first + "–" + prev.last])
                prev.desc = m[1]; prev.run = null
                continue
            }
            if (m) { item.base = m[1]; item.first = keyName(b.key) }
            // two binds with the same description (SUPER+M / SUPER+Esc): one line, both keys
            if (prev && prev.group === g && prev.desc === t && !m) {
                prev.keys = prev.keys.concat(["·"]).concat(item.keys)
                continue
            }
            out.push(item)
        }
        hyprItems = out
    }

    function parseTmux(text) {
        var lines = text.split("\n").filter(function (l) { return l.trim().length })
        var count = {}
        lines.forEach(function (l) { var f = l.split(/\s+/)[0]; count[f] = (count[f] || 0) + 1 })
        var prefix = "", best = 0
        for (var k in count) if (count[k] > best) { best = count[k]; prefix = k }
        tmuxItems = lines.map(function (l) {
            var m = l.match(/^(\S+(?:\s\S+)?)\s{2,}(.*)$/) || l.match(/^(\S+)\s+(.*)$/)
            if (!m) return null
            var ks = m[1].split(/\s/)
            if (ks.length > 1 && ks[0] === prefix) ks[0] = "prefix"
            return { src: "tmux", group: "tmux", keys: ks, desc: m[2].trim(), run: null }
        }).filter(function (x) { return x })
    }

    readonly property var boardFallback: [
        [["j", "k"], "Move"], [["1–9"], "Answer the question"], [["⏎"], "Jump to pane"],
        [["s", "s"], "Start the stack"], [["v", "y"], "View / copy design"],
        [["o", "t", "c"], "localhost · ticket · checklist"], [["/"], "Filter"],
        [["?"], "All keys (here)"], [["esc"], "Close"]
    ]
    function parseBoard(text) {
        var data = null
        try { data = JSON.parse(text) } catch (e) { data = null }
        if (data && !Array.isArray(data)) data = data.keys || data.roster || null
        var out = []
        if (Array.isArray(data)) {
            for (var i = 0; i < data.length; i++) {
                var x = data[i]
                if (Array.isArray(x)) { out.push({ keys: [].concat(x[0]), desc: String(x[1] || "") }); continue }
                if (!x || typeof x !== "object") continue
                var ks = x.keys !== undefined ? x.keys : x.key
                if (typeof ks === "string") ks = ks.split(/\s+|(?!^)\+(?!$)/).filter(function (k) { return k.length })
                var d = x.desc || x.description || x.action || x.does || ""
                var g = x.group || "In the roster"
                // SUPER binds come live from hyprctl; the rest of "Agent board"
                // (prefix+i) joins the Agents column
                if (g !== "In the roster") {
                    if (ks && /^super$/i.test(ks[0])) continue
                    g = "Agents"
                }
                if (ks && ks.length) out.push({ keys: ks, desc: String(d), group: g })
            }
        }
        if (!out.length) out = boardFallback.map(function (f) { return { keys: f[0], desc: f[1] } })
        boardItems = out.map(function (o) {
            return { src: "board", group: o.group || "In the roster", keys: o.keys, desc: o.desc, run: null }
        })
    }

    Process {
        id: hyprProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { onStreamFinished: root.parseHypr(text) }
    }
    Process {
        id: tmuxProc
        command: ["sh", "-c", "tmux list-keys -N 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.parseTmux(text) }
    }
    Process {
        id: boardProc
        command: ["sh", "-c", 'command -v "$0" >/dev/null 2>&1 && "$0" keys --json 2>/dev/null', Board.boardCmd]
        stdout: StdioCollector { onStreamFinished: root.parseBoard(text) }
    }

    // ── Layout model ────────────────────────────────────────────────────
    function matches(it) {
        if (!filter) return true
        var f = filter.toLowerCase()
        return (it.group + " " + it.desc + " " + it.keys.join(" ")).toLowerCase().indexOf(f) !== -1
    }
    readonly property var groups: {
        var by = {}, all = hyprItems.concat(boardItems).concat(tmuxItems)
        all.forEach(function (it) { (by[it.group] = by[it.group] || []).push(it) })
        var names = Object.keys(by).sort(function (a, b) {
            var ia = groupOrder.indexOf(a), ib = groupOrder.indexOf(b)
            if (ia < 0) ia = 99; if (ib < 0) ib = 99
            return ia - ib || a.localeCompare(b)
        })
        return names.map(function (n) { return { name: n, items: by[n] } })
    }
    // three columns, each group dropped into the shortest one
    readonly property var columns: {
        var cols = [[], [], []], h = [0, 0, 0]
        groups.forEach(function (g) {
            var i = h.indexOf(Math.min.apply(null, h))
            cols[i].push(g); h[i] += g.items.length + 2
        })
        return cols
    }
    // Hyprland binds that match, in reading order (column by column): ↑/↓ walk these
    readonly property var runnable: {
        var r = []
        columns.forEach(function (c) { c.forEach(function (g) { g.items.forEach(function (it) {
            if (it.run && matches(it)) r.push(it) }) }) })
        return r
    }
    readonly property var picked: cursor >= 0 && cursor < runnable.length ? runnable[cursor] : null

    onFilterChanged: cursor = filter ? 0 : -1

    function runPicked() {
        var p = picked
        if (!p) return
        pending = p.run
        root.requestClose()
        runLater.restart()     // after the popup has let go of focus
    }
    property var pending: null
    Timer {
        id: runLater
        interval: 120
        onTriggered: {
            var r = root.pending; root.pending = null
            // Lua binds report only an opaque id, so run the dispatcher hyprland.lua
            // registered under the bind's description (its global BINDS table)
            if (r) Quickshell.execDetached(["hyprctl", "dispatch", "BINDS[" + JSON.stringify(r) + "]"])
        }
    }

    Glass { anchors.fill: parent }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 18; topMargin: 16; bottomMargin: 12 }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Text {
                text: "Keys"
                color: Colors.fg0
                font.family: root.mono; font.pixelSize: 18
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 10
                color: Qt.rgba(0, 0, 0, 0.3)
                border.width: 1
                border.color: Colors.alpha(Colors.accent, 0.5)
                Text {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "⌕"
                    color: Colors.fg2
                    font.family: root.mono; font.pixelSize: 13
                }
                TextInput {
                    id: input
                    anchors { left: parent.left; leftMargin: 30; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    color: Colors.accent
                    font.family: root.mono; font.pixelSize: 13
                    selectionColor: Colors.alpha(Colors.accent, 0.4)
                    onTextEdited: root.filter = text
                    Keys.onPressed: function (e) {
                        var n = root.runnable.length
                        if (e.key === Qt.Key_Escape) root.requestClose()
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.runPicked()
                        else if ((e.key === Qt.Key_Down || e.key === Qt.Key_Tab) && n) root.cursor = (root.cursor + 1) % n
                        else if ((e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) && n) root.cursor = (root.cursor - 1 + n) % n
                        else return
                        e.accepted = true
                    }
                }
            }
            Text {
                text: "SUPER+/ · ? in any panel"
                color: Colors.alpha(Colors.fg1, 0.7)
                font.family: root.mono; font.pixelSize: 11
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: cols.implicitHeight
            contentHeight: cols.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            RowLayout {
                id: cols
                width: flick.width
                spacing: 22

                Repeater {
                    model: root.columns
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: 14

                        Repeater {
                            model: modelData
                            delegate: ColumnLayout {
                                id: grp
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: grp.modelData.name.toUpperCase()
                                    color: Colors.accent
                                    font.family: root.mono; font.pixelSize: 11; font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                    Layout.bottomMargin: 2
                                }

                                Repeater {
                                    model: grp.modelData.items
                                    delegate: Rectangle {
                                        id: line
                                        required property var modelData
                                        readonly property bool hit: root.matches(modelData)
                                        readonly property bool isPicked: root.picked === modelData
                                        Layout.fillWidth: true
                                        implicitHeight: lr.implicitHeight + 4
                                        radius: 6
                                        opacity: hit ? 1 : 0.32
                                        color: isPicked ? Colors.alpha(Colors.accent, 0.28)
                                             : root.filter && hit ? Colors.alpha(Colors.accent, 0.12) : "transparent"
                                        border.width: isPicked ? 1 : 0
                                        border.color: Colors.accent
                                        onIsPickedChanged: if (isPicked) {
                                            var p = line.mapToItem(cols, 0, 0)
                                            if (p.y < flick.contentY) flick.contentY = p.y
                                            else if (p.y + height > flick.contentY + flick.height)
                                                flick.contentY = p.y + height - flick.height
                                        }

                                        RowLayout {
                                            id: lr
                                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                                      leftMargin: 6; rightMargin: 6 }
                                            spacing: 10
                                            Row {
                                                Layout.preferredWidth: 150
                                                Layout.minimumWidth: 150
                                                spacing: 3
                                                Repeater {
                                                    model: line.modelData.keys
                                                    delegate: Kbd {
                                                        required property var modelData
                                                        text: modelData
                                                    }
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: line.modelData.desc
                                                color: Colors.fg1
                                                elide: Text.ElideRight
                                                font.family: root.mono; font.pixelSize: 12
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: line.modelData.run !== null
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var i = root.runnable.indexOf(line.modelData)
                                                if (i >= 0) { root.cursor = i; root.runPicked() }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "type to filter · ↑/↓ pick a bind · ⏎ runs it · esc closes"
                color: Colors.fg2
                font.family: root.mono; font.pixelSize: 11
            }
            Text {
                text: "hyprctl binds · board keys · tmux list-keys -N"
                color: Colors.fg2
                font.family: root.mono; font.pixelSize: 11
            }
        }
    }
}
