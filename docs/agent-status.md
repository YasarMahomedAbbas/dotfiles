# agent-status — knowing which Claude session wants you

Several Claude Code sessions run at once, mostly **detached**, each driving a ticket through
the `frontend-pipeline` skill. This is the machinery that answers, at a glance, *which one has
stopped and is waiting for a human* — and, once you know that, *what it is waiting about*.

Sources: `bin/.local/bin/claude-hook-state`, `pipeline-status`, `ticket-context`,
`sesh-list-bells`, `sesh-preview`, `sesh-clean-name`, `ticket-pill`, `agent-sidebar`,
`ticket-window` (bash,
stowed with the rest of `bin`); consumed by the sesh picker (`<prefix>+s`), the tmux status
bar, the [sidebar](agent-sidebar.md) (`<prefix>+a`) and the [Stream Deck](streamdeck.md).

---

## The problem

The obvious signal is wrong, and wrong in the direction that destroys the whole thing.

Claude Code's **`Stop` hook fires at the end of every assistant turn**. Not when a session goes
idle — every turn. The pipeline orchestrator runs each stage as a subagent, reports, and
immediately starts the next one, so a single unattended ticket crosses `Stop` a dozen times
while needing nothing from you. It also rings the terminal bell each time.

The previous setup treated `Stop` as "needs attention" whenever the session was detached, and
`monitor-bell` popped a desktop notification on the bell. So a long autonomous run produced two
notifications per turn boundary, none of which meant anything. The bell appeared to fire at
random. The cost is not the noise — it is that **a signal which fires when nothing is wrong
stops being read at all**, and then the one time a session really is parked on a question, it
sits there for an hour.

There is a second, subtler problem. A pipeline stage that stops to ask you something ends its
turn *exactly* like a stage that finished successfully. Nothing Claude's own hooks can observe
distinguishes them. So the pipeline has to say so itself.

---

## The answer

Four states, of which **only two are alerts**:

| State | Means | Set by | Alert? |
|---|---|---|---|
| `working` | Claude is running | `UserPromptSubmit`, `PostToolUse` | no |
| `blocked` | A permission prompt is up | `PermissionRequest`, `Notification[permission_prompt]` | **yes** |
| `waiting` | Finished, and you never came back | `Notification[idle_prompt]` | **yes** |
| `done` | A turn ended | `Stop` | **no** |

`waiting` is Claude Code's `idle_prompt` notification, which fires ~60s after a turn ends with
no input from you — that genuinely means the session has stopped and is yours. `blocked` fires
immediately. `done` is silent, and that split is the entire point of this subsystem.

Two independent writers, and **the pipeline wins**:

```
pipeline-status  ──> @pipeline_state / @pipeline_label   (running | blocked | done)
claude-hook-state ─> @claude_state / @claude_detail / @claude_pane / @claude_ts
```

`pipeline-status` is called by the `frontend-pipeline` orchestrator at every stage boundary and
every escalation. It is the **only** source that can report a parked human decision, for the
reason above. `claude-hook-state` covers every other session.

Consumers read them in this order:

1. `@pipeline_state` — richest, and the only one that knows about a parked decision.
2. The window name (`issue-830 ⏸ plan-brief`) — a fallback for a run started before
   `pipeline-status` existed, or a window renamed by hand.
3. `@claude_state` — with two guards: the pane it names must still live in that session (a
   stale id means the flag outlived the Claude that set it), and **a session you are attached
   to shows no Claude alert at all**, because you can already see it. Pipeline states are
   exempt from that last rule — they describe the ticket, not your attention.

---

## Where it shows

### The sesh picker (`<prefix>+s`)

Sessions that want you sort to the top:

```
 issue-559    feat/frontend/quotation-room-description   ⏸ plan-brief · doc-drift
 issue-612    fix/frontend/wallet-statement-booked-by    ▶ implement-plan
 travelsmart  develop                                    ▶ working
 issue-705    main                                       ✓ PR
 dotfiles
```

Three columns: name, branch, status. The **branch** is what tells two worktrees of the same
project apart when the session name doesn't — `issue-559` says which ticket but not what it
became. A detached worktree (what a pipeline sits on until `start-ticket` creates the branch)
shows `@<short-sha>`, so "hasn't branched yet" is visible rather than blank.

### The preview pane — a ticket card

```
  issue-559   needs you · plan-brief · doc-drift

  #559  Quotations: editable agent copy on a hotel item
  feat/frontend/quotation-room-description
  3 commit(s) ahead of develop · 3 file(s) uncommitted

  pipeline  ✓ plan  ✓ build  ▶ review  · docs  · verify  · PR
  Checkpoint 4 — Field, accessor and derived original
  tasks     ████████████████░░░░░░░░ 16/24

  1: claude *  1p    2: git  1p
  ─────────────────────────────────
  <last 14 lines of Claude's pane>
```

It used to be a raw dump of Claude's last output. That answers "what did Claude just print",
which is the wrong question when you are scanning six sessions for the one that needs you —
you want the ticket, the stage, and whether it is stuck. The pane tail is kept, last and
short, because when a session *is* parked on a question, that question is in it.

Everything above the rule comes from `ticket-context`, which reads the branch, the ticket
folder and the pipeline's own stage log in `NOTES_<slug>.md` — **the same evidence the
orchestrator uses to decide what to run next**, so the card cannot disagree with it.

The card's headline is the `problem` key, not `title` — see [`problem`](#problem--the-one-line-that-says-what-the-ticket-is-for) below.

### The tmux status bar — a ticket pill

Everything above answers "which session wants me". This answers the other half: **you are
already in a session and cannot remember what it is about.** The bar carries a pill naming
the problem, next to the session pill:

```
  issue-849    #849 Rate calculator — save an agency's rate for a ho…    1 issue-849 ▶ build    ts:issue-849    host    22:47
  └ session       └ ticket-pill                                          └ window list          └ wt-dev pill
```

`ticket-pill` is a `#()` in `status-left` (`themes/templates/tmux.conf.tmpl`) and follows the
same two rules as the `wt-dev tmux` pill: it prints **itself or nothing** — caps, colours and
all, because tmux cannot branch a `#{?...}` on the output of a `#()` and an empty pill still
renders as a blob — and it serves a **cached** answer (10s, under `~/.cache/ticket-pill/`)
with the resolver behind a `timeout`, so a slow git can never stall the bar.

Two things about it are less obvious:

- **The session name is passed in** (`#(ticket-pill #{session_name})`). tmux caches a `#()`
  job by its *expanded command string*, so a bare `#(ticket-pill)` would run once and paint
  one session's ticket onto every attached session. Interpolating the session name gives each
  session its own job.
- **Every `#` in the text is doubled** before printing. tmux re-reads `#[...]` in a `#()`'s
  output, so a literal `#` would be parsed as the start of a style. `##849` is what comes back
  out as `#849`.

It sizes itself from `#{client_width}`, capping at 62 characters and dropping out entirely
below the point where it would crowd the centred window list — on a narrow client the window
list is the thing you cannot afford to lose.

### The sidebar (`<prefix>+a`)

A read-only pane down the left of the window, carrying one card per agent — state,
stage, the `problem` line, the pipeline rail and the checklist bar — so the picker's
question is answered without opening the picker:

```
 AGENTS                   22:47
 ⏸ issue-915  merge develop? …
   agents must decide where a
   price item comes from bef…
   ✓✓✓✓▶·  ██████████████ 8/8
▎▶ travelsmart        working
```

It reads the options below exactly as the picker does, with **one deliberate
divergence**: the picker drops a Claude alert on an attached session, because a session
you are attached to is one you can already see. The sidebar tests that claim properly —
attached *and* the `@claude_pane` window is the session's **active** window — because a
session is often attached on its `git` or `dev` window while Claude is blocked two
windows over. Full reference: [agent-sidebar.md](agent-sidebar.md).

### The ticket window

The other surfaces say *which* session wants you; this one is for once you are in it. Every
`issue-<n>` session gets a detached window named `ticket` running `nvim -R` on a rendered
`ticket.md`: the problem line, then **the plan's summary** — NOTES' `## Planning` section
(approach, what was decided with you, open risks) and one `✓ / ▶ / ·` line per checkpoint —
then the GitHub issue and its comments.

- **It exists from the first second.** lazytickets' worktree `setup` runs `ticket-window`
  before `npm ci`, so the window lands while the install is still going — before planning
  has run, which is exactly when the other surfaces used to have nothing to say.
- **Any Claude started in an issue worktree opens it too.** A `SessionStart` hook runs
  `ticket-window` in the background, so a session bootstrapped by `/frontend-pipeline` (or
  started by hand) gets the window without lazytickets, and a resumed one refetches the issue.
  Outside an `issue-<n>` worktree it is a silent no-op.
- **It follows the ticket folder.** A Claude `PostToolUse(Write|Edit)` hook
  (`ticket-window --hook`) re-renders on every `TASK_CHECKLIST_` / `NOTES_` write, and nvim
  re-checks the file every 2 s, so the summary moves as stages write. The hook replaced
  `open-plan-in-nvim` (since deleted), which split the *full* checklist in beside Claude — a document for the
  implement stage, not for a human coming back to a session.
- **Its files live in the worktree's private git dir** (`.git/worktrees/issue-<n>/ticket.{json,md,meta}`):
  never committed, gone with `git worktree remove`. `ticket.meta` is also where
  `ticket-context` gets a `title` before a checklist exists.
- The window is tagged `@ticket_window`, not found by name; close it and a re-render will not
  reopen it — only a plain `ticket-window` (which also refetches the issue) does.

### The Stream Deck

One key per session, colour for the state and a band naming the stage. Full detail in
[streamdeck.md](streamdeck.md).

---

## The commands

```bash
# Where is this working tree in the pipeline? (key=value lines; missing keys are omitted)
ticket-context ~/projects/org/whitewolfstudios/worktrees/issue-559
ticket-context issue-559          # or by tmux session name

# The status-bar pill for a session (tmux calls this; you would only run it to debug)
ticket-pill issue-559             # prints a tmux format string, or nothing
rm -rf ~/.cache/ticket-pill       # force it to re-resolve on the next redraw

# The ticket window (lazytickets setup and the Claude hook call these)
ticket-window                     # in a worktree: refetch the issue, re-render, open the window if missing
ticket-window --render            # re-render from the cached issue — no network
ticket-window --hook              # PostToolUse(Write|Edit) entry point; JSON on stdin

# Announce a pipeline transition (the orchestrator calls these; you rarely will)
pipeline-status running implement-plan
pipeline-status blocked "plan-brief · doc-drift"
pipeline-status done    PR
pipeline-status                   # clear

# Record Claude's own state (called only from ~/.claude/settings.json hooks)
claude-hook-state working|blocked|waiting|done
claude-hook-state working --if-blocked    # only writes if currently blocked
claude-hook-state                         # clear (SessionEnd)
```

`ticket-context` emits: `dir root branch slug issue title problem folder stage stage_index
stage_total tasks_done tasks_total checkpoint dirty commits`. Its stage table is a
transcription of the one in `frontend-pipeline/SKILL.md` — if that table changes, this must
follow. Before a checklist exists, `title` comes from the `ticket.meta` snapshot
`ticket-window` took (the GitHub issue title), so `problem` — which falls back to `title` — is
never blank on a ticket that is still in planning.

### `problem` — the one line that says what the ticket is for

`title` is the checklist's H1 and names the *feature* ("South African money formatting"). That
only reminds you of a ticket you already remember. `problem` is the sentence saying what is
actually **wrong**, and it is what both the status bar and the picker card lead with. Three
sources, tried in order:

| Source | Written by | Shape |
|---|---|---|
| `Problem:` line in the checklist | `frontend-start-ticket` | a problem statement by construction |
| the `Issue:` line's title | whoever filed the GitHub issue | usually names the symptom |
| `title` | the checklist H1 | names the feature — last resort |

The `Issue:` fallback is why nothing needed backfilling when `Problem:` was introduced: ~80% of
the checklists already in the tree resolve through it, in either of the two shapes the tree
uses (`Issue: #844 — <title> (<url>)` and the older `Issue(s): #252 <title>`). It requires the
`#<n>` to be present — a ticket with no GitHub issue writes `Issue: none — handed over in
session`, whose tail is provenance, not problem.

---

## State

Everything lives as tmux **session options**, so it dies with the session and there is no file
to go stale:

| Option | Written by | Meaning |
|---|---|---|
| `@pipeline_state` | `pipeline-status` | `running` / `blocked` / `done` |
| `@pipeline_label` | `pipeline-status` | the stage, or the escalation kind |
| `@claude_state` | `claude-hook-state` | `working` / `blocked` / `waiting` / `done` |
| `@claude_detail` | `claude-hook-state` | short reason, e.g. `allow Bash?` |
| `@claude_pane` | `claude-hook-state` | the pane Claude runs in — the ownership guard |
| `@claude_ts` | `claude-hook-state` | epoch seconds of the last write |

`@claude_state` and `@claude_detail` are cleared by tmux's `client-session-changed` and
`client-attached` hooks (`tmux/.tmux.conf`), so looking at a session dismisses its alert —
and `sesh connect` fires `switch-client`, so picking it in the picker clears it too. Pipeline
options are **not** cleared that way: a parked decision stays parked until the orchestrator
answers it.

---

## Extending it

**Adding a consumer.** Read `@pipeline_state` first, then `@claude_state` with the pane check.
Batch the reads — `tmux list-sessions -F '#{session_name}|#{@claude_state}|…'` returns user
options in a format string, so a whole dashboard costs one call, not one per session. The
Stream Deck polls ~1×/s; a per-session `show-options` there was ~20 subprocess spawns a second.

**Adding a state.** Update `claude-hook-state`'s case list, then every consumer:
`sesh-list-bells`, `sesh-preview`, `streamdeck-dashboard`, `agent-sidebar`. Nothing enforces
this — a consumer that doesn't know a state silently renders it as idle.

**Adding a picker column.** `sesh-list-bells` builds the row; `sesh-clean-name` must be able to
recover the bare session name from it, because that string is handed to `sesh connect`. It
strips from the first run of **2+ spaces**, which is the column gutter — `sesh list` never
emits a double space of its own. Do not anchor a stripper on the status glyph: the branch
column sits between the name and the glyph, and a glyph-anchored strip leaves it behind and
hands `sesh connect` a name that does not exist.

### Known gaps

- **Nothing enforces the vocabulary across repos.** `pipeline-status` is called from
  `frontend-pipeline/SKILL.md` in the travel-smart repo; the readers live here. Renaming a
  state breaks them silently, in the direction of "no status shown".
- **The picker's list has no stage for an idle pipeline session.** Between runs a worktree
  shows only branch and no status, even though `ticket-context` could derive the stage. The
  list deliberately does no git-per-row beyond the branch; the card has the full picture.
- **`@claude_ts` is written but nothing reads it.** It is there so a consumer can age out a
  stale state; none does yet.
