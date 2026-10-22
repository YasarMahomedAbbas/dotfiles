# Agent board

What every Claude session is doing, who needs you, and where each ticket stands, from
one source of truth. Replaces `claude-hook-state`, the `@claude_*` tmux options and the
agent sidebar.

```
claude session ──(agent-board mod)──▶ ~/.cache/claude-board/<pane>.json
                                              │
                         `board` CLI (reads, enriches, acts)
          ┌──────────────┬──────────────┬─────┴────────┬───────────────┐
   quickshell island  roster popup   sesh picker   tmux pill    streamdeck
   + roster + wall    (prefix+i)     + preview     (#(board pill))
```

## 1. State file (written by the mod)

One file per Claude process, `~/.cache/claude-board/<key>.json`, where `<key>` is the
tmux pane id without the `%` (`%42` → `42`) or `nopane-<session_id>` outside tmux.
Written atomically (write `.tmp`, rename) on every change, plus a heartbeat every 10 s.
Removed on `session.end`; one Claude process can run several sessions (`/clear`,
`/resume`), and the file comes back with the next session under its new `session_id`.
A process with no file is invisible to every display. Readers treat a file whose `heartbeat` is older than 30 s
**and** whose `pid` is gone as stale: shown grey, deleted after 10 min.

```jsonc
{
  "v": 1,
  "session_id": "…",               // Claude session id
  "pid": 12345,                     // Claude process pid
  "heartbeat": 1791456780123,       // epoch ms
  "tmux": { "session": "issue-1654", "pane": "%42", "window": "1" },   // null outside tmux
  "cwd": "/home/…/worktrees/issue-1654/Frontend",
  "branch": "fix/frontend/sign-in-autofill-submit",
  "model": "Opus 5.5 (1M context)",
  "remote": "session_01AbC…",       // Remote Control id while connected (^session_[A-Za-z0-9]{1,64}$), else null

  // top-level state, exactly one of:
  //   needs_you   main loop blocked on the person (permission, question, plan approval)
  //   working     main loop turn in progress
  //   background  main turn ended, but agents or background shells still run
  //   idle        nothing running anywhere in this session
  "state": "needs_you",
  "since": 1791456700000,           // when `state` last changed
  "finished_at": 1791456000000,     // last time the session went idle (for "unseen")

  // present only while state == needs_you
  "attention": {
    "kind": "question",             // permission | question | plan
    "title": "Results",             // AskUserQuestion header / tool name / "Plan"
    "text": "The stack is live on issue-1654. Run the 8-step Edge guide…",
    "options": [                    // what pressing 1..9 in the pane selects, in order
      { "key": "1", "label": "All 8 passed" },
      { "key": "2", "label": "Defer to QA" }
    ],
    "since": 1791456700000
  },

  // the main loop's tool in flight, null between tools
  "current": {
    "tool": "Bash",
    "detail": "pnpm test",          // Bash: command (first line, ≤120 chars); Agent: description; Skill: name; else tool's short subject
    "started": 1791456650000,
    "typical_ms": 220000,           // median of past runs of the same normalised command in this project, null if < 3 runs
    "runs": 12
  },

  // subagents and background work started by this session (last 20, newest first)
  "agents": [
    { "id": "a587…", "type": "Explore", "description": "map booking flow",
      "status": "running", "started": 1791456500000, "ended": null, "parent": null }
  ],
  "shells": [
    { "id": "b12", "command": "pnpm dev", "status": "running", "started": 1791456000000 }
  ],

  // Claude's own task list (TaskCreate/TaskUpdate/TodoWrite), in order
  "tasks": [ { "subject": "State model", "status": "completed" } ],

  // design canvases published from this session (Artifact publish with the Design type,
  // or a `DESIGN_CANVAS issue=<n> url=<url>` line in the transcript)
  "designs": [ { "url": "https://claude.ai/artifact/…", "title": "…", "issue": 1430, "boards": 11, "at": 1791456780000 } ]
}
```

State rules (each state names the event that ends it, so none can stick):

| state | enters on | leaves on |
|---|---|---|
| needs_you | main-loop permission prompt, AskUserQuestion, ExitPlanMode | the next main-loop tool call starts, a model step streams, a prompt is submitted, or the turn ends |
| working | main-loop turn starts (typed prompt or a background task waking it) | turn ends → background or idle |
| background | turn ended while `agents`/`shells` have a running entry | last running entry ends → idle; a new turn → working |
| idle | nothing running | a turn starts |

A subagent's permission prompt does **not** make the session `needs_you`; it is shown on
that agent (`status: "needs_you"`). The mod never sends desktop notifications itself, and
Claude Code's own (`agentPushNotifEnabled`, terminal OSC) are switched off.

## 2. `board` CLI (bin/.local/bin/board)

The only reader the displays use. Aggregates state files, drops stale ones, enriches each
with `ticket-context` (cached 30 s per worktree) and `wt-dev status --short` (cached 5 s).

| command | does |
|---|---|
| `board list [--json]` | sessions sorted needs_you › working › background › unseen › idle. JSON: array of state files plus `ticket` {issue,title,problem,stage,stage_index,stage_total,tasks_done,tasks_total,checkpoint,slug}, `stack` (`live`/`starting`/`off`/null), `unseen` (bool), `stale` (bool), `key` |
| `board summary [--json]` | counts `{needs_you, working, background, unseen, designs}` and the live stack per project |
| `board pill` | tmux status-right pill (prints nothing when all quiet) |
| `board roster` | fzf roster popup (tmux `prefix+i`); same keys as the quickshell roster |
| `board jump <key>` | focus Ghostty (`hyprctl dispatch 'hl.dsp.focus({ window = "class:com.mitchellh.ghostty" })'`), `tmux switch-client` + select window/pane, mark seen |
| `board next` | jump to the oldest `needs_you` session (SUPER+N) |
| `board answer <key> <n>` | `tmux send-keys` option `n` to that pane (only while that session is needs_you) |
| `board stack <key> [--yes]` | `wt-dev use <worktree> --db auto`; without `--yes` prints what it would stop |
| `board design <key> [--copy]` | `xdg-open` the newest design url (or `wl-copy` it) |
| `board seen <key>` | marks finished work as seen (tmux `pane-focus-in` hook calls this) |
| `board keys [--json]` | the board's own key table (roster keys) for the cheatsheet |

Unseen: `finished_at` newer than `~/.cache/claude-board/seen/<key>` (touched by `board seen`).

## 3. Keys

| keys | does |
|---|---|
| SUPER+G | roster (quickshell) |
| SUPER+N | `board next` |
| SUPER+Shift+G | checklist wall (quickshell) |
| SUPER+/ | keys cheatsheet (quickshell; Hyprland binds via `hyprctl binds -j` descriptions from `bindd`, tmux via `tmux list-keys -N`, board via `board keys --json`) |
| prefix+i | `board roster` in a tmux popup |
| in roster | j/k move · ⏎ jump · 1-9 answer · s s stack · v design · y copy link · o localhost · t ticket · c checklist · / filter · ? keys · esc |

## 4. Colours (status semantics, all themes)

Read from `~/.config/theme/quickshell-colors.json` / `sesh-colors.sh`: needs_you = `red`,
working = `fg0` (frost), background = `blue` (steel `#8fa8c8` in ember), done/idle
finished = `green`, slow (past typical) = `yellow`, design = `accent`.

## 5. Terminal side

Everything in the terminal reads `board`; nothing reads tmux options for Claude state any
more (`claude-hook-state`, `@claude_state/_pane/_detail/_ts`, the window-name marks and
the agent sidebar are gone).

| surface | source | shows |
|---|---|---|
| tmux status-right | `#(board pill)` in `themes/templates/tmux.conf.tmpl` | `● 2 needs you` (red pill), `▶ 1 ◐ 3` (fg0 / blue; ▶ yellow when a turn runs past typical). Prints itself, caps included, or nothing. Under Hyprland the host and clock pills are dropped (quickshell shows them) |
| `prefix+i` | `board roster` in a `display-popup -E -w 90% -h 80%` | fzf roster: glyph, ticket, problem, what it is doing, stack chip; preview = question + options, stage strip, checklist summary, agents with elapsed, design link. Opens with input hidden so letters are keys; `/` shows the filter, `esc` leaves it (or closes). Reloads every 3 s |
| `pane-focus-in` hook | `board seen #{pane_id}` | focusing a pane clears its `✓ unseen`; `board list` also treats a pane some client is looking at as seen |
| sesh picker (`prefix+s`) | `sesh-list-bells` (one `board list --json` per render) | status column `● needs you · <title>` / `▶ <detail> <elapsed>[ slow]` / `◐ background · N agents` / `✓ unseen` / nothing when idle |
| picker preview | `sesh-preview` | banner from the board, the question and its options, then the ticket card from `ticket-context` and the pane tail of the board's pane |
| Stream Deck | `streamdeck-dashboard` (one `board list --json` per poll) | session keys coloured per §4, press → `board jump <key>`; key 9 DESIGN in accent when a design exists, press → `board design <key>` |

Colours come from `~/.config/theme/sesh-colors.sh`, which gained `SESH_FG0_COLOR`,
`SESH_BLUE_COLOR`, `SESH_BG_COLOR` and `SESH_PILL_BG` for the board; until the next
`theme-switch` the readers derive fg0/blue from `SESH_FZF_COLORS` (`fg+`, `prompt`).

**Still from the old status machinery, unchanged:**

- `ticket-context <dir|session>` resolves where a frontend-pipeline worktree stands (branch,
  slug, issue, title, `problem`, stage from the NOTES stage log, checklist progress). It
  is what `board` enriches `ticket` from. `problem` is the one line saying what is wrong:
  the checklist's `Problem:` line, else the `Issue:` line's title, else `title`.
- `pipeline-status <running|blocked|done> <label>` stamps `@pipeline_state` /
  `@pipeline_label`. It no longer renames windows; `board` uses the label as the stage
  when `ticket-context` has none.
- `ticket-pill` (status-left) and `ticket-window` (the `ticket` window per `issue-<n>`
  session) are untouched.
- `sesh-clean-name` strips a picker row from its first run of 2+ spaces (the column
  gutter), so any column `sesh-list-bells` adds after the name is safe; never anchor a
  strip on a status glyph.
