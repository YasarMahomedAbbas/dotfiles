# agent-sidebar — every agent, at a glance, without opening anything

```
 ┌────────────────────────────────────────────┬───────────────────────────────┐
 │ ▄▀█ █▀▀ █▀▀ █▄░█ ▀█▀ █▀                    │ ~/…/worktrees/issue-915 (main)│
 │ █▀█ █▄█ ██▄ █░▀█ ░█░ ▄█                    │                               │
 │ ─────────────────────────────────── 22:47  │ ⏺ I've rebased onto develop,  │
 │                                            │   but the quotation reducer   │
 │ ⏸ issue-915       merge develop? · raise-pr│   conflicts. Do you want me   │
 │   agents must decide where a price item    │   to take develop's version?  │
 │   comes from before deciding they want     │                               │
 │   one — blank and saved are two entries    │ > │                           │
 │   ✓✓✓✓▶·  ████████████████████████████ 8/8 │                               │
 │                                            │                               │
 │▎▶ travelsmart                      working │                               │
 │                                            │                               │
 │ idle                                       │                               │
 │ dotfiles · vault                           │                               │
 └────────────────────────────────────────────┴───────────────────────────────┘
   prefix+a toggles it here · prefix+A everywhere in this session
```

Source: `bin/.local/bin/agent-sidebar`, bound in `tmux/.tmux.conf`. It is the fourth
consumer of the state described in [agent-status.md](agent-status.md), after the sesh
picker, the status-bar ticket pill and the [Stream Deck](streamdeck.md) — read that
first; this document only covers what is specific to the sidebar.

---

## Why, given the picker already answers this

The picker (`prefix+s`) answers *which session wants me* better than this does: it has
more room, it sorts, it previews, and it can take you there. But it is **a place you
go**. You have to decide to look before it can tell you anything, which means the
question "is anything waiting on me?" is only asked when you already suspect the
answer is yes. That is precisely backwards for a set of agents whose whole point is
that they run unattended.

The sidebar's only claim over the picker is that **you did not have to ask**. So the
design follows from that one property:

- **It is read-only, and spawned with `split-window -d`.** It never takes focus, never
  reads a key, and hides its cursor. This is load-bearing, not a simplification to be
  undone later: a surface that is permanently on screen next to the pane you type into
  must not be able to swallow a keystroke meant for the agent. Jumping between sessions
  stays the picker's job — the thing you *did* choose to open.
- **It is collapsible, and off by default.** `prefix+a` here, `prefix+A` for the whole
  session. The two keys are the same decision at two scopes, so whatever `prefix+a`
  would do in this window, `prefix+A` does to all of them.
- **It costs two tmux calls a tick**, whatever the number of sessions (below).

## What a card says

Three lines and a rail, in the order you actually read them:

| | |
|---|---|
| `⏸ issue-915   merge develop? · raise-pr` | state, session, and what it is doing — the label is the pipeline stage, or Claude's own detail |
| `agents must decide where a price…` | **`problem`**, not `title` — see [agent-status.md](agent-status.md#problem--the-one-line-that-says-what-the-ticket-is-for). Three lines, hard, with an ellipsis when it overflows |
| `✓✓✓✓▶·  ██████████████████ 8/8` | the six pipeline stages, one cell each, and the checklist bar |

The picker's card spells the stages out (`✓ plan ✓ build ▶ review · docs`). In a sidebar
the *shape* is the information — how much is green and where the `▶` sits — so the rail
is compressed to one cell per stage and put on the same line as the bar.

**The default width is 44 columns** (`AGENT_SIDEBAR_WIDTH`), and three problem lines at
that width is ~120 characters — enough for most of what `frontend-start-ticket` writes.
The first draft was 34 and capped the problem at two lines, which truncated nearly every
one of them; a card whose description always ends in `…` is a card you stop reading.
Every line is measured against the live `#{pane_width}`, not the default, so resizing the
pane re-lays-out on the next tick rather than clipping.

### The header is three lines on purpose

A single line of text at the very top of a full-height pane sits level with both the tmux
status bar and the first card, and reads as neither. The block wordmark gives the eye
something to land on, and the rule puts air between the chrome and the first agent. The
wordmark is 23 columns; below 26 there is no room for it and the header falls back to the
plain word.

`▎` in the left gutter is the session you are attached to, including when it is down in
the `idle` line. Sessions with no agent state at all get one dim comma-joined line
rather than a card each; a sidebar full of `dotfiles` and `vault` is a sidebar you stop
reading.

## The one deliberate divergence from the picker

`sesh-list-bells` **drops a Claude alert on an attached session**, on the reasoning that
a session you are attached to is one you can already see. For a picker you opened on
purpose that is right, and it stops `idle_prompt` painting a red bell on the very
session you are sitting in.

For a sidebar that is always up it is **wrong**, because *attached* does not mean *on
screen*. Sessions here have several windows — `claude`, `git`, `dev` — and you are as
likely to be watching `dev` scroll while Claude, two windows over, has been parked on a
permission prompt for ten minutes. The picker's rule would hide exactly that.

So the sidebar suppresses a Claude alert only when the pane is **genuinely visible**:
the session is attached *and* the pane named by `@claude_pane` is in that session's
**active window**. Pipeline states stay exempt from the test in both consumers — they
describe the ticket, not your attention.

This is [Herdr](https://herdr.dev/)'s state roll-up arrived at from the other end.
Herdr rolls a pane's state *up* into its tab and workspace; here the visibility test is
pushed *down* from the session to the window. Same observation: the interesting unit is
the pane, and anything that reasons at session granularity will eventually lie to you.

## What it costs

Two tmux calls per tick regardless of session count — `list-sessions -F` and
`list-panes -a -F` return user options inside a format string, so the whole frame is two
subprocesses. A per-session `show-options` would be ~20 spawns a tick, which is the
mistake `streamdeck-dashboard` already documents learning not to make.

`ticket-context` is the expensive one — three `git` calls — so it is deliberately **not**
on the tick. It is memoised per session for `TICKET_TTL` (10 s) under
`~/.cache/agent-sidebar/`, behind a `timeout`, on exactly the reasoning `ticket-pill`
caches its answer: a slow git must never stall the repaint. The consequence is a
two-speed sidebar, and that is the intended behaviour — **the glyph and stage label move
within `TICK` (2 s), the ticket card behind them settles within 10 s.**

The frame is diffed against the last one and redrawn only when it differs, so an idle
sidebar is a string comparison and a `sleep`, and the pane never flickers. Lines are
cleared as they are written (`\033[K`) with a final `\033[J`, rather than clearing the
screen first, which flashes.

## The commands

```bash
agent-sidebar toggle     [window]    # what prefix+a runs
agent-sidebar toggle-all [session]   # what prefix+A runs
agent-sidebar open|close [window]
agent-sidebar once [width]           # print ONE frame and exit — how to debug it
rm -rf ~/.cache/agent-sidebar        # force the ticket cards to re-resolve
```

`once` is the whole renderer minus the loop, so a layout bug is one command away from a
diff:

```bash
for w in 28 34 44; do agent-sidebar once $w; done
```

Two things about the plumbing:

- **The bindings interpolate `#{window_id}` / `#{session_id}` in.** With two clients
  attached, tmux's idea of the "current" window is per-client, so the untargeted form
  would toggle a sidebar into whichever session tmux considers current — which is the
  same trap `pipeline-status` carries a note about, and it is worth not falling into it
  twice.
- **The pane is found again by a pane option**, `@agent_sidebar`, not by index or
  position, so splitting, swapping or resizing the window around it cannot lose it.

## State

| Option | Scope | Meaning |
|---|---|---|
| `@agent_sidebar` | pane | this pane *is* a sidebar — how `toggle` finds it again |
| `@agent_sidebar_on` | session | `prefix+A` was used here, so new windows inherit one |

`@agent_sidebar_on` is read by the `after-new-window` hook in `tmux/.tmux.conf`. A
session that never opted in is unaffected, which is why the hook does not fire sidebars
into the `git` and `dev` windows `tmux-dev-layout` builds at session creation.

Note the usual tmux trap: deleting the `set-hook` line does **not** remove it from a
running server, and `prefix + r` only re-sources the file. Restart the server, or
`set-hook -gu after-new-window`, if you ever take it out.

## Known gaps

- **The state precedence is now written out four times** — here, `sesh-list-bells`,
  `sesh-preview` and `streamdeck-dashboard` — because each consumer needs a different
  shape and cost profile. It is the drift risk `agent-status.md` flags under *Adding a
  state*, now one copy worse. Lifting it into a shared `agent-state` resolver is the
  obvious next move and was deliberately not bundled into building the sidebar.
- **An alert in a non-active window is shown but not named.** You are told `issue-915`
  is blocked; you are not told it is the `claude` window rather than the one you are
  looking at. The window name is right there in `panes_raw` if it turns out to matter.
- **No scrolling.** Past roughly eight agent cards the tail is simply cut off by the
  pane. The sort order means what falls off the bottom is what is finished, which is
  the right thing to lose, but it is a cut-off rather than a decision.
