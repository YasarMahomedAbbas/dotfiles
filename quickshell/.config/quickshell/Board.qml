pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The agent board (docs/agent-board.md): every Claude session, read through the
// `board` CLI — the only reader the displays use. Polled once a second (one
// process per tick runs `board list --json` and `board summary --json`).
// ~/.cache/claude-board is not watched: FileView watches files, not directories,
// and inotifywait isn't installed, so the 1 s poll is the refresh path.
//
// Never throws: a missing CLI, empty output or malformed JSON leaves the last
// good data in place (or nothing, with `available` false).
//
// Also owns the Hyprland side effect of "something needs you": while any
// session is needs_you, every Ghostty window's border is set to attn (rust) → accent.
Singleton {
    id: root

    // `QS_BOARD_CMD=/path/to/fake-board qs -p …` points the shell at a fixture.
    property string boardCmd: Quickshell.env("QS_BOARD_CMD") || "board"

    property var  sessions: []          // `board list --json`, CLI order
    property var  summary:  ({})        // `board summary --json`
    property bool available: false      // the CLI ran and printed JSON
    property real now: Date.now()       // ticks every second, for elapsed timers

    readonly property int needsYou:   _count("needs_you")
    readonly property int working:    _count("working")
    readonly property int background: _count("background")
    readonly property int unseen:     typeof summary.unseen === "number" ? summary.unseen
                                      : sessions.filter(function (s) { return s.unseen }).length
    // Any design canvas published in the last hour
    readonly property bool designRecent: {
        var cut = now - 3600000
        for (var i = 0; i < sessions.length; i++) {
            var d = sessions[i].designs || []
            for (var j = 0; j < d.length; j++) if ((d[j].at || 0) > cut) return true
        }
        return false
    }
    // The live (or starting) stack: {abbr, state, label}, or null
    readonly property var liveStack: {
        var st = summary.stacks || summary.stack || null
        if (!st) return null
        if (!Array.isArray(st)) {
            // tolerate a {project: {...}} map or a single object
            if (st.state !== undefined) st = [st]
            else st = Object.keys(st).map(function (k) {
                var v = st[k]; if (typeof v !== "object" || v === null) v = { state: v }
                if (!v.project) v.project = k; return v })
        }
        var pick = null
        for (var i = 0; i < st.length; i++) {
            var x = st[i]; if (!x) continue
            if (x.state === "live") { pick = x; break }
            if (x.state === "starting" && !pick) pick = x
        }
        if (!pick) return null
        // `board summary --json` gives {"<project>": {state, tree, branch}}:
        // "travel-smart" + tree "issue-1654" → "ts ● 1654"; the main checkout → its branch
        var tree = String(pick.tree || "")
        var num = tree.match(/^issue-(\d+)$/)
        var label = pick.issue ? String(pick.issue)
                  : num ? num[1]
                  : (tree === pick.project && pick.branch) ? pick.branch : tree
        var proj = String(pick.project || "")
        var words = proj.split(/[-_ .]+/).filter(function (w) { return w.length })
        var abbr = pick.short || (words.length > 1 ? words.map(function (w) { return w[0] }).join("") : proj.slice(0, 3))
        return { abbr: abbr, state: pick.state, label: label }
    }

    // A session newly entered needs_you (deduped by key + attention.since).
    // Not emitted for sessions already waiting when the shell starts.
    signal needsYouEntered(var session)

    function _count(st) {
        if (typeof summary[st] === "number") return summary[st]
        return sessions.filter(function (s) { return s.state === st && !s.stale }).length
    }

    // ── Helpers shared by the island, roster, wall and toast ────────────
    function fmt(ms) {
        var s = Math.max(0, Math.floor(ms / 1000))
        var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60
        function p(n) { return n < 10 ? "0" + n : "" + n }
        return h ? h + ":" + p(m) + ":" + p(x) : m + ":" + p(x)
    }
    function ago(ms) {   // coarse: 4m, 2h, 3d
        var m = Math.max(0, Math.floor(ms / 60000))
        if (m < 60) return m + "m"
        if (m < 1440) return Math.floor(m / 60) + "h"
        return Math.floor(m / 1440) + "d"
    }
    function isPipeline(s) { return !!(s && s.ticket && (s.ticket.issue || s.ticket.slug)) }
    function sessionName(s) {
        if (s.tmux && s.tmux.session) return s.tmux.session
        var c = (s.cwd || "").split("/").filter(function (p) { return p.length })
        return c.length ? c[c.length - 1] : s.key
    }
    function shortName(s) {
        var n = sessionName(s)
        var parts = n.split(/[-_ .]+/).filter(function (p) { return p.length })
        if (parts.length > 1) return parts.map(function (p) { return p[0] }).join("").slice(0, 4)
        return n.slice(0, 3)
    }
    function slow(s) {
        var c = s.current
        return !!(s.state === "working" && c && c.typical_ms && c.started && now - c.started > c.typical_ms)
    }
    // One of: needs_you working slow background done idle stale
    function status(s) {
        if (s.stale) return "stale"
        if (s.state === "needs_you") return "needs_you"
        if (s.state === "working") return slow(s) ? "slow" : "working"
        if (s.state === "background") return "background"
        if (s.unseen) return "done"
        return "idle"
    }
    function statusColor(st) {
        switch (st) {
        case "needs_you":  return Colors.attn
        case "working":    return Colors.fg0
        case "slow":       return Colors.yellow
        case "background": return Colors.blue
        case "done":       return Colors.green
        default:           return Colors.fg2
        }
    }
    function runningAgents(s) {
        return (s.agents || []).filter(function (a) { return a.status === "running" || a.status === "needs_you" }).length
             + (s.shells || []).filter(function (a) { return a.status === "running" }).length
    }
    function newestDesign(s) {
        var d = s.designs || [], best = null
        for (var i = 0; i < d.length; i++) if (!best || (d[i].at || 0) > (best.at || 0)) best = d[i]
        return best
    }

    // ── Pipeline stages (ticket-context's stage_index is 1-based, the stage now
    //    running; earlier stages are done) ────────────────────────────────
    readonly property var stageLabels: ["Start ticket", "Implement plan", "Review", "Doc drift", "Verify", "Raise PR"]
    readonly property var stageVerbs:  ["Starting", "Implementing", "Reviewing", "Doc drift", "Verifying", "Raising PR"]
    readonly property var stageCellCount: [3, 0, 2, 1, 3, 2]   // 0 = tasks_total

    function stageLabel(s) {
        var i = s.ticket ? s.ticket.stage_index : 0
        return i >= 1 && i <= stageLabels.length ? stageLabels[i - 1] : (s.ticket && s.ticket.stage) || ""
    }
    function stateCode(s) {
        var st = status(s)
        return st === "needs_you" ? "a" : st === "slow" ? "s"
             : st === "working" ? "r" : st === "background" ? "b" : ""
    }
    // One cell per stage, for the roster's stage strip
    function stageCells(s) {
        var t = s.ticket; if (!t) return []
        var n = t.stage_total || 6, idx = t.stage_index || 0, out = []
        for (var i = 1; i <= n; i++) out.push(i < idx ? "d" : i === idx ? stateCode(s) : "")
        return out
    }
    function _rep(c, n) { var a = []; for (var i = 0; i < n; i++) a.push(c); return a }
    function _activity(s) {
        var c = s.current
        if (c && c.started) {
            var t = (c.detail || c.tool || "") + " " + fmt(now - c.started)
            return slow(s) ? t + " slow" : t
        }
        var n = runningAgents(s)
        if (n) return n + (n === 1 ? " agent" : " agents")
        return ""
    }

    // The checklist card for one session:
    //   { kind, chip, title, time, total, rows: [{ g, label, cells, st, stColor }] }
    // A pipeline session gets its six stages (Implement split into its tasks);
    // anything else gets Claude's own task list.
    function card(s) {
        var st = status(s), code = stateCode(s)
        var kind = st === "needs_you" ? "attn" : (st === "working" || st === "slow") ? "run"
                 : st === "background" ? "bg" : st === "done" ? "done" : "idle"
        var rows = [], total = "", chip = ""
        var stColor = st === "needs_you" ? Colors.attn : st === "slow" ? Colors.yellow
                    : st === "background" ? Colors.blue : Colors.fg0
        var waiting = st === "needs_you" ? "Waiting on you" : _activity(s)

        if (isPipeline(s)) {
            var t = s.ticket, idx = t.stage_index || 0
            var td = t.tasks_done || 0, tt = t.tasks_total || 0
            for (var i = 1; i <= stageLabels.length; i++) {
                var n = stageCellCount[i - 1] || Math.max(tt, 3)
                var r = { g: "", label: stageLabels[i - 1], cells: _rep("", n), st: "", stColor: Colors.fg2 }
                if (i < idx) {
                    r.g = "d"; r.cells = _rep("d", n)
                    r.st = (i === 2 && tt) ? tt + " of " + tt : "Done"
                } else if (i === idx) {
                    r.g = code; r.st = waiting; r.stColor = stColor
                    if (i === 2 && tt) {
                        r.cells = _rep("d", Math.min(td, n)).concat(td < n ? [code] : [])
                        r.cells = r.cells.concat(_rep("", n - r.cells.length))
                        if (!waiting) r.st = td + " of " + tt
                    } else if (code === "a") {
                        r.cells = _rep("a", n)
                    } else if (code && s.current && s.current.typical_ms) {
                        var k = Math.max(1, Math.round(Math.min(1, (now - s.current.started) / s.current.typical_ms) * n))
                        r.cells = _rep(code, k).concat(_rep("", n - k))
                    } else if (code) {
                        r.cells = [code].concat(_rep("", n - 1))
                    }
                }
                rows.push(r)
            }
            total = (idx === 2 && tt) ? td + " of " + tt + " tasks" : "stage " + idx + " of " + (t.stage_total || 6)
            chip = st === "needs_you" ? "● Needs you" : st === "slow" ? "▶ Slow"
                 : st === "working" ? "▶ " + (stageVerbs[idx - 1] || "Working")
                 : st === "background" ? "◐ Background" : st === "done" ? "✓ Done" : st === "stale" ? "stale" : "· Idle"
        } else {
            var tasks = s.tasks || [], done = 0
            for (var j = 0; j < tasks.length && j < 10; j++) {
                var ts = tasks[j].status
                if (ts === "completed") done++
                var c = ts === "completed" ? "d" : ts === "in_progress" ? (code || "r") : ""
                rows.push({ g: c, label: tasks[j].subject || "", stColor: c === "d" ? Colors.fg2 : stColor,
                            cells: c === "d" ? _rep("d", 4) : c ? [c, "", "", ""] : _rep("", 4),
                            st: c === "d" ? "Done" : c ? (waiting || "Running") : "" })
            }
            if (!tasks.length) {
                var ag = (s.agents || []).filter(function (a) { return a.status === "running" })
                for (var q = 0; q < ag.length && q < 4; q++)
                    rows.push({ g: "b", label: ag[q].type || "Agent", cells: ["b", "", "", ""], stColor: Colors.blue,
                                st: (ag[q].description || "") + " " + fmt(now - (ag[q].started || now)) })
                if (!rows.length)
                    rows.push({ g: code, label: s.current ? s.current.tool : (st === "needs_you" ? "Question" : "Nothing running"),
                                cells: code ? [code, "", "", ""] : _rep("", 4), st: waiting, stColor: stColor })
            }
            total = tasks.length ? done + " of " + tasks.length + " steps" : (st === "idle" || st === "done" ? "idle" : "")
            chip = st === "needs_you" ? "● Needs you" : st === "slow" ? "▶ Slow" : st === "working" ? "▶ Working"
                 : st === "background" ? "◐ Background" : st === "done" ? (tasks.length && done === tasks.length ? "✓ All done" : "✓ Done")
                 : st === "stale" ? "stale" : "· Idle"
        }

        var time = ""
        if (st === "needs_you") time = fmt(now - ((s.attention && s.attention.since) || s.since))
        else if (st === "working" || st === "slow" || st === "background") time = fmt(now - s.since)
        else if (s.finished_at) time = "done " + Qt.formatTime(new Date(s.finished_at), "HH:mm")

        var title = isPipeline(s) ? "#" + s.ticket.issue + " " + (s.ticket.title || "") : sessionName(s)
        return { kind: kind, chip: chip, title: title, time: time, total: total, rows: rows,
                 all: rows.reduce(function (a, r) { return a.concat(r.cells) }, []) }
    }

    // ── Actions ─────────────────────────────────────────────────────────
    function run(args) {
        Quickshell.execDetached([root.boardCmd].concat(args))
        refreshSoon.restart()
    }
    function refresh() { if (!poll.running) poll.running = true }

    Timer { id: refreshSoon; interval: 250; onTriggered: root.refresh() }

    // ── Polling ─────────────────────────────────────────────────────────
    property string _lastList: ""
    property bool   _seeded: false
    property var    _toasted: ({})

    function _strip(k, v) { return k === "heartbeat" ? undefined : v }

    function ingest(text) {
        var t = (text || "").trim()
        if (!t.length) { available = false; if (sessions.length) sessions = []; return }
        var parts = t.split("\x1e")
        var list = null, sum = null
        try { list = JSON.parse(parts[0]) } catch (e) { list = null }
        try { if (parts.length > 1 && parts[1].trim().length) sum = JSON.parse(parts[1]) } catch (e) { sum = null }
        if (!Array.isArray(list)) return
        available = true
        if (sum && typeof sum === "object") summary = sum
        // Only republish when something but the heartbeat changed, so delegates
        // (and their pulse animations) aren't rebuilt every second.
        var sig = JSON.stringify(list, _strip)
        if (sig !== _lastList) { _lastList = sig; sessions = list }

        var seen = {}
        for (var i = 0; i < list.length; i++) {
            var s = list[i]
            if (s.state !== "needs_you" || s.stale) continue
            var id = s.key + "|" + ((s.attention && s.attention.since) || s.since)
            seen[id] = true
            if (_seeded && !_toasted[id]) needsYouEntered(s)
        }
        _toasted = seen
        if (!_seeded) { _seeded = true; _applyBorder() }
    }

    Process {
        id: poll
        command: ["sh", "-c",
            'command -v "$0" >/dev/null 2>&1 || exit 0; "$0" list --json; printf "\\n\\036\\n"; "$0" summary --json',
            root.boardCmd]
        stdout: StdioCollector { onStreamFinished: root.ingest(text) }
    }

    Timer {
        interval: 1000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: { root.now = Date.now(); root.refresh() }
    }

    // ── Ghostty border while something needs you ───────────────────────
    // Hyprland 0.56 (Lua config): `hl.dsp.window.set_prop`'s gradient parser drops the
    // first colour token, so the first colour is passed twice. There is no working
    // unset (`unset`/`-1` leave an empty gradient), so "restore" writes the current
    // general:col.{active,inactive}_border values back.
    // Starts "on" so the first poll restores borders a previous instance (before
    // a reload or restart) may have left rust. QS_BOARD_NO_BORDER=1 turns it off
    // (fixture testing).
    property bool _borderOn: true
    readonly property bool _borderEnabled: !Quickshell.env("QS_BOARD_NO_BORDER")
    readonly property bool _wantBorder: needsYou > 0

    function _hex(c) { return "0xff" + c.toString().slice(1, 7) }
    function _applyBorder() {
        if (!_borderEnabled || !_seeded) return
        if (!_wantBorder && !_borderOn) return
        borderProc.command = ["bash", "-c", root._borderScript, "border",
            _wantBorder ? "1" : "0", _hex(Colors.attn), _hex(Colors.accent)]
        borderProc.running = true
        _borderOn = _wantBorder
    }
    on_WantBorderChanged: _applyBorder()

    // New Ghostty windows opened while something waits get the border too.
    Timer { interval: 5000; repeat: true; running: root._wantBorder; onTriggered: root._applyBorder() }

    readonly property string _borderScript: '
        addrs=$(hyprctl clients -j | jq -r \'.[] | select(.class == "com.mitchellh.ghostty") | .address\')
        [ -n "$addrs" ] || exit 0
        conv() { hyprctl getoption "$1" -j | jq -r \'.gradient // .custom\' |
            awk \'{ o = ""; for (i = 1; i <= NF; i++) o = o " " ($i ~ /deg$/ ? $i : "0x" $i); split(o, f, " "); print f[1] o }\'; }
        if [ "$1" = 1 ]; then a="$2 $2 $3 45deg"; i="$a"
        else a=$(conv general:col.active_border); i=$(conv general:col.inactive_border); fi
        cmds=""
        for ad in $addrs; do
            for p in active inactive; do
                [ $p = active ] && v="$a" || v="$i"
                cmds="$cmds dispatch hl.dsp.window.set_prop({ prop = \'${p}_border_color\', value = \'$v\', window = \'address:$ad\' });"
            done
        done
        hyprctl --batch "$cmds" >/dev/null'

    Process { id: borderProc }
}
