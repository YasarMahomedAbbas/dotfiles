import QtQuick
import Quickshell.Io

// What a key does to the selected session, shared by the wall (SUPER+G) and the
// focus view (SUPER+Shift+G), so both honour the old roster's keys the same way:
//   ⏎ jump · 1-9 answer · s s stack · v design · y copy link · o open stack · t ticket
// `flash` is the last thing said; `confirmKey` is the session a first `s` armed.
Item {
    id: root

    property string flash: ""
    property string confirmKey: ""
    property string confirmText: ""

    signal requestClose()

    function say(msg) { flash = msg; flashTimer.restart() }
    Timer { id: flashTimer; interval: 4000; onTriggered: root.flash = "" }

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
    // o / t use the CLI's roster internals (the ones `board roster`'s fzf binds
    // call): `__open-url` opens the live stack's first url, `__ticket` runs
    // `gh issue view <n> --web` against the right repo.
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
    // A key for the selection: true when it was one of ours.
    function key(t, s) {
        if (t >= "1" && t <= "9" && t.length === 1) answer(s, parseInt(t))
        else if (t === "s") stack(s)
        else if (t === "v") design(s, false)
        else if (t === "y") design(s, true)
        else if (t === "o") openStack(s)
        else if (t === "t") openTicket(s)
        else return false
        return true
    }
    // moving off a session drops a pending `s`
    function moved(s) { if (!s || s.key !== confirmKey) confirmKey = "" }

    Process {
        id: preview
        stdout: StdioCollector {
            onStreamFinished: root.confirmText = text.trim() || "wt-dev use on this worktree"
        }
    }
}
