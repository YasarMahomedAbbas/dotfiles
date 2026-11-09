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

    // ── Pipelines (docs/agent-board.md §2: `ticket.stages`, `stage_index`) ──
    // A pipeline is a session on a stage table: travel-smart's frontend pipeline
    // (Start …) or personal-assistant's (Refine …). Every view draws the same six
    // stages from the same fields, so the wall, the focus pane and the bar's pips
    // never disagree with the tmux strip.
    readonly property var defaultStages: ["Start", "Implement", "Review", "Docs", "Verify", "PR"]

    function isPipeline(s) { return !!(s && s.ticket && s.ticket.stage_index) }
    function stages(s) {
        var l = s && s.ticket && s.ticket.stages
        return l && l.length === 6 ? l : defaultStages
    }
    // elapsed, short: 12s · 5m · 2h04m (times are elapsed only)
    function el(ms) {
        var s = Math.max(0, Math.floor(ms / 1000))
        if (s < 60) return s + "s"
        if (s < 3600) return Math.floor(s / 60) + "m"
        var m = Math.floor(s % 3600 / 60)
        return Math.floor(s / 3600) + "h" + (m < 10 ? "0" : "") + m + "m"
    }
    // Implement's count: the checklist's tasks (travel-smart), else the issue's
    // checkpoints (personal-assistant); "" when neither is known.
    function implCount(t) {
        if (!t) return ""
        if (t.tasks_total) return (t.tasks_done || 0) + "/" + t.tasks_total
        if (t.checkpoints_total) return (t.checkpoints_done || 0) + "/" + t.checkpoints_total
        return ""
    }
    // One of: attn now bg done idle stale (slow working is "now", drawn yellow)
    function kind(s) {
        var st = status(s)
        return st === "needs_you" ? "attn" : (st === "working" || st === "slow") ? "now"
             : st === "background" ? "bg" : st === "done" ? "done" : st === "stale" ? "stale" : "idle"
    }
    function kindColor(s) { return statusColor(status(s)) }
    function stageLabel(s) {
        var i = s.ticket ? s.ticket.stage_index : 0
        return i >= 1 && i <= 6 ? stages(s)[i - 1] : (s.ticket && s.ticket.stage) || ""
    }
    // the short word under a strip: `verify`, `impl 3/5`, `needs you`
    function stageWord(s) {
        if (status(s) === "needs_you") return "needs you"
        var t = s.ticket || {}
        if (t.stage_index === 2) { var n = implCount(t); return "impl" + (n ? " " + n : "") }
        return stageLabel(s).toLowerCase()
    }
    // Six stage classes: done, then the current one by state (attn now bg, or
    // `todo` while idle on it), then todo.
    function stageClasses(s) {
        var idx = (s.ticket && s.ticket.stage_index) || 0, k = kind(s), out = []
        var cur = k === "attn" || k === "now" || k === "bg" ? k : "todo"
        for (var i = 1; i <= 6; i++) out.push(i < idx ? "done" : i === idx ? cur : "todo")
        return out
    }
    // The stepper's nodes: {label, cls, mark, sub}. `compact` puts Implement's
    // count in its label (Impl 3/5); otherwise it goes under it, and the current
    // stage carries its elapsed time.
    function steps(s, compact) {
        var cls = stageClasses(s), l = stages(s), t = s.ticket || {}, idx = t.stage_index || 0
        var n = implCount(t), out = []
        for (var i = 0; i < 6; i++) {
            var label = l[i], sub = ""
            if (i === 1 && n) { if (compact) label = "Impl " + n; else sub = n }
            if (!compact && i === idx - 1 && i !== 1) sub = el(now - (s.since || now))
            out.push({ label: label, cls: cls[i], mark: cls[i] === "done" ? "✓" : cls[i] === "attn" ? "!" : "", sub: sub })
        }
        return out
    }
    function title(s) {
        if (isPipeline(s) || (s.ticket && s.ticket.issue)) return (s.ticket.title || s.ticket.problem || sessionName(s))
        return sessionName(s) + (s.branch ? " · " + s.branch : "")
    }
    function issueText(s) { return s.ticket && s.ticket.issue ? "#" + s.ticket.issue : "" }
    function problem(s) {
        var t = s.ticket
        if (t && t.problem && t.problem !== t.title) return t.problem
        return ""
    }
    // time on the card's header: in this state for so long, or since it finished
    function timeText(s) {
        var k = kind(s)
        if (k === "attn") return el(now - ((s.attention && s.attention.since) || s.since || now))
        if (k === "done") return el(now - (s.finished_at || s.since || now)) + " ago"
        if (k === "idle" || k === "stale") return "idle " + el(now - (s.finished_at || s.since || now))
        return el(now - (s.since || now))
    }
    function runningList(s) {
        var out = []
        ;(s.agents || []).forEach(function (a) {
            if (a.status === "running" || a.status === "needs_you")
                out.push({ g: "◆", gc: a.status === "needs_you" ? Colors.attn : Colors.blue,
                           t: (a.type || "agent") + " · " + (a.description || ""), r: el(now - (a.started || now)) })
        })
        ;(s.shells || []).forEach(function (x) {
            if (x.status === "running")
                out.push({ g: "$", gc: Colors.blue, t: x.command || "", r: el(now - (x.started || now)) })
        })
        return out
    }
    function claudeTasks(s) {
        var ts = s.tasks || [], d = 0
        for (var i = 0; i < ts.length; i++) if (ts[i].status === "completed") d++
        return { done: d, total: ts.length, current: ts.filter(function (x) { return x.status === "in_progress" })[0] || null }
    }
    // The checkpoint being built: {k, n, name, tasks_done, tasks_total} or null
    function curCheckpoint(s) {
        var t = s.ticket || {}, cps = t.checkpoints || []
        for (var i = 0; i < cps.length; i++)
            if (!cps[i].done) return { k: i + 1, n: cps.length, name: cps[i].name, tasks_done: cps[i].tasks_done, tasks_total: cps[i].tasks_total }
        return null
    }
    function _cpName(n) { return String(n || "").replace(/^\S+\s+—\s+/, "") }
    // "Implement · checkpoint 3 of 5 · the bridge carries the link"
    function nowHead(s) {
        var k = kind(s), a = s.attention || {}
        var what = k === "attn" ? (a.kind === "plan" ? "a plan to approve"
                                 : a.kind === "permission" ? "permission · " + (a.title || "a tool")
                                 : "asking · " + (a.title || "a question"))
                 : ""
        if (isPipeline(s)) {
            var stage = stageLabel(s)
            if (!what && s.ticket.stage_index === 2) {
                var cp = curCheckpoint(s)
                if (cp) what = "checkpoint " + cp.k + " of " + cp.n + " · " + _cpName(cp.name)
                else if (s.ticket.checkpoints_total) what = "every checkpoint done · closing out"
            }
            if (!what && k === "now" && s.current) what = s.current.tool || "working"
            // the lines under it name what runs; the head only says how much
            if (!what && k === "bg") { var r = runningList(s); what = r.length ? r.length + " running in the background" : "in the background" }
            if (!what) what = k === "done" ? "finished · not looked at yet" : k === "idle" ? "idle" : ""
            return stage + (what ? " · " + what : "")
        }
        if (what) return "Needs you · " + what
        return k === "now" ? "Working" + (s.current ? " · " + (s.current.tool || "") : "")
             : k === "bg" ? "In the background" : k === "done" ? "Finished · not looked at yet"
             : k === "stale" ? "Gone quiet" : "Idle"
    }
    // The now band's lines: the question, what runs, or what finished
    function nowLines(s) {
        var k = kind(s), out = []
        if (k === "attn") {
            var a = s.attention || {}
            out.push({ g: "?", gc: Colors.attn, t: a.text || a.title || "", r: "" })
            return out
        }
        var c = s.current
        if (k === "now" && c)
            out.push({ g: "▶", gc: slow(s) ? Colors.yellow : Colors.fg0,
                       t: (c.tool || "") + (c.detail ? " " + c.detail : ""), r: el(now - (c.started || now)) })
        out = out.concat(runningList(s))
        var ct = claudeTasks(s)
        if (ct.total && out.length < 3)
            out.push({ g: "✓", gc: Colors.green, t: "tasks " + ct.done + " of " + ct.total + " ticked"
                       + (ct.current ? " · " + ct.current.subject : ""), r: "" })
        if (k === "done" && !out.length) out.push({ g: "✓", gc: Colors.green, t: "turn ended · ⏎ to read the reply", r: "" })
        return out.slice(0, 3)
    }
    // the task bar: travel-smart's tasks while implementing, else Claude's own
    function taskBar(s) {
        var t = s.ticket || {}
        if (isPipeline(s) && t.stage_index === 2 && t.tasks_total)
            return { f: (t.tasks_done || 0) / t.tasks_total, text: (t.tasks_done || 0) + "/" + t.tasks_total + " tasks" }
        var ct = claudeTasks(s)
        if (ct.total) return { f: ct.done / ct.total, text: ct.done + "/" + ct.total + " tasks" }
        return null
    }
    function chip(s) {
        var st = status(s)
        return st === "needs_you" ? "● NEEDS YOU" : st === "slow" ? "▶ SLOW" : st === "working" ? "▶ WORKING"
             : st === "background" ? "◐ BACKGROUND" : st === "done" ? "✓ DONE" : st === "stale" ? "○ STALE" : "○ IDLE"
    }
    // A plain session (no ticket) gets a card only while there is something to
    // act on: it needs you, or it finished and nobody looked. Otherwise it is a
    // one-liner under the cards.
    function wantsCard(s) {
        if (isPipeline(s)) return true
        var st = status(s)
        return st === "needs_you" || st === "done"
    }
    function glyph(s) {
        var st = status(s)
        return st === "needs_you" ? "●" : (st === "working" || st === "slow") ? "▶" : st === "background" ? "◐"
             : st === "done" ? "✓" : "○"
    }
    // what a one-liner says after its name: `Bash · 3s`, `idle 4m`
    function oneLiner(s) {
        var k = kind(s), c = s.current
        if (k === "now" && c) return (c.tool || "working") + " · " + el(now - (c.started || now))
        if (k === "bg") { var r = runningList(s); return (r.length ? r.length + " running · " : "") + el(now - (s.since || now)) }
        if (k === "attn") return "needs you · " + ((s.attention && s.attention.title) || "")
        return timeText(s)
    }
    function matches(s, f) {
        if (!f) return true
        var hay = [sessionName(s), s.branch || "", issueText(s), title(s), problem(s)].join(" ")
        return hay.toLowerCase().indexOf(f.toLowerCase()) !== -1
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
