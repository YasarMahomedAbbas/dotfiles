# Agent board: the Hyprland / quickshell side

The desktop half of [agent-board.md](agent-board.md). Everything here reads the board
through the `board` CLI (§2); nothing reads `~/.cache/claude-board` directly.

| file (`quickshell/.config/quickshell/`) | what it is |
|---|---|
| `Board.qml` | singleton: polls the CLI, exposes sessions + counts, helpers, the Ghostty border |
| `AgentsIsland.qml` | bar island: a pip strip per pipeline (`▶ #246 ▮▮▯▯▯▯`), the other sessions as counts (`✓1`), `◇ design`, `ts ● 1654`; hovering a strip shows its card (a `PopupWindow`), clicking it jumps |
| `KeysHint.qml` | the small `⊞ /` island (opens the cheatsheet) |
| `Wall.qml`, `WallCard.qml` | SUPER+G popup: the wall |
| `Focus.qml` | SUPER+Shift+G popup: list + focus |
| `BoardActions.qml` | what a key does to the selection (jump, answer, stack, design, open, ticket), shared by the wall and the focus view |
| `Stepper.qml`, `Pips.qml` | the six-stage stepper (cards, focus) and the bar's pip strip |
| `KeysCheatsheet.qml` | SUPER+/ popup (not `Keys.qml`: that name collides with QtQuick's attached `Keys`) |
| `Toast.qml` | the one toast (its own layer-shell window, under the agents island) |
| `Glass.qml`, `Chip.qml`, `CountChip.qml`, `Kbd.qml`, `Btn.qml` | shared pieces |

`Bar.qml` hosts the island, the keys hint and the three popups (same pattern as the
dashboard: one popup at a time, the bar takes keyboard focus while one is open,
`HyprlandFocusGrab` closes it on an outside click). `shell.qml` holds the toast and the
`GlobalShortcut`s.

## Data

`Board.qml` runs one process a second:
`board list --json; printf '\n\x1e\n'; board summary --json` (skipped silently when the
CLI is not on `PATH`). The list is republished only when something other than
`heartbeat` changed, so delegates and their pulse animations are not rebuilt every
second; elapsed timers tick from `Board.now` (a 1 s clock) against the epoch-ms fields.
There is no directory watch: FileView watches files, not directories, and `inotifywait`
is not installed, so the poll is the refresh path. Bad or empty output keeps the last
good data; with no CLI the agents island stays hidden.

Counts come from `summary` (falling back to counting the list). `◇ design` shows when
any session has a design whose `at` is under an hour old. The stack chip takes the first
`live` (else `starting`) project from `summary.stacks` (`{"<project>": {state, tree,
branch}}`): the project's initials (`travel-smart` → `ts`), then the issue number from
an `issue-<n>` tree, or the branch for the main checkout.

Status colours (§4) are `Board.statusColor()`: needs_you attn (rust), working fg0, slow
yellow (`current.started` older than `current.typical_ms`), background blue, unseen-done
green, idle/stale fg2.

A **pipeline** is a session whose `ticket.stage_index` is set (travel-smart or
personal-assistant, §5's stage tables). Its six stages are `ticket.stages` (the labels),
`stage_index` the one running now (1-based, earlier ones done), and the current one takes
the session's state: `Board.stageClasses()` gives `done`, then `attn` / `now` / `bg` (or
`todo` while idle on it), then `todo`, and the stepper, the focus list's segments and the
bar's pips all draw from it. Implement's count is the checklist's tasks on travel-smart,
the issue's checkpoints on personal-assistant (`Board.implCount()`).

## The wall (SUPER+G)

A card per pipeline in two columns, read top to bottom: the status chip, issue, title and
time in its state; the problem; the stepper (Implement labelled `Impl 3/5`); then *now*:
the stage in words (`Implement · checkpoint 3 of 5 · <name>`, `Start · asking · <title>`),
the tool / agents / shells running, a task bar, or the question with its numbered options
(click or 1-9). A plain session (no ticket) gets a card only while it needs you or
finished unseen; every other one is a line under the cards (`▶ personal-assistant · main
Bash · 3s`, `○ vault · main idle 4m`). The header counts each state. The selection is
outlined in rust.

## List + focus (SUPER+Shift+G, or f on a wall card)

Left, every session: glyph, issue, title, time, then the six segments and the stage word
(`impl 2/4`), or for a plain session what it is doing. Right, the selected one in full:
title, problem, branch · tmux session · model; the large stepper (Implement's count and the
current stage's time under their labels); Implement's checkpoints from `ticket.checkpoints`
(✓ done, ▶ the one being built with its task bar: its own tasks on travel-smart, Claude's
task list on personal-assistant, ○ ahead); running now (the tool against its typical time,
agents and shells, the last 15 minutes' finished ones dimmed), or the question and its
options while it asks; Claude's own task list.

## What each key runs

| where | key | runs |
|---|---|---|
| wall, focus | ⏎ | `board jump <key>`, then closes |
| wall, focus | 1-9 | `board answer <key> <n>` (only while that session is needs_you) |
| wall, focus | s | `board stack <key>` (dry run; its output is the confirmation line) |
| wall, focus | s again | `board stack <key> --yes` |
| wall, focus | v / y | `board design <key>` / `board design <key> --copy` |
| wall, focus | o / t | `board __open-url <key>` / `board __ticket <key>` (the CLI's roster internals, the same ones `board roster`'s fzf binds use; not in the §2 table) |
| wall | h/l, j/k | move one card / one row of cards (one line among the plain sessions) |
| wall | f | the focus view on that session |
| focus | j/k | next / previous session |
| focus | f | back to the wall on that session |
| wall, focus | / ? esc | filter · cheatsheet · close (esc first cancels a pending `s`, then clears the filter) |
| island | hover · click | that pipeline's card · `board jump <key>`; clicking the rest of the island opens the wall |
| cheatsheet | type, ↑/↓, ⏎ | filter, pick a Hyprland bind, `hyprctl dispatch 'BINDS["<description>"]'` |

The cheatsheet reads `hyprctl binds -j` (binds with a description only), `board keys
--json` (its "On the wall" group; the "Agent board" SUPER entries are dropped because
the live Hyprland binds cover them, `prefix+i` joins the Agents column; a built-in
table stands in when the CLI is missing) and `tmux list-keys -N`.

## Bind descriptions (hyprland.lua)

Every bind goes through the config's `bind(keys, "Group: what it does", dispatcher, opts)`
helper, which sets the bind's `description` and also stores the dispatcher in the global
`BINDS` table under that description. Lua binds show up in `hyprctl binds -j` as
`__lua <id>`, so the cheatsheet runs a bind with `hyprctl dispatch 'BINDS["<description>"]'`.
The cheatsheet makes one column group per `Group`, in this order:
Agents, On the wall, tmux, Windows, Workspaces, Apps, Shell, Notifications, Capture,
Media, Session (anything else after, alphabetically). Runs like `Go to workspace 1` …
`10` fold into one `1–0` line.

New binds: `SUPER+G` → `hl.dsp.global("quickshell:roster")` (the wall; the shortcut kept
the roster's name so a running Hyprland's bind still reaches it), `SUPER+SHIFT+G` →
`hl.dsp.global("quickshell:wall")` (list + focus), `SUPER+slash` → `hl.dsp.global("quickshell:keys")`,
`SUPER+N` → `exec board next`, and a second `SUPER+space` bind →
`hl.dsp.global("quickshell:dismisstoast")`
next to mako's (Hyprland runs every bind on the same combo, so both fire).

## Toast

`Board.needsYouEntered` fires when a session enters needs_you with a new
`key + attention.since` (sessions already waiting when the shell starts don't toast).
The toast shows 8 s, hides early once that session leaves needs_you, opens the wall on that
session on click, and SUPER+space dismisses it. Nothing else toasts.

## Ghostty border (Hyprland 0.56)

While `needs_you > 0`, every `com.mitchellh.ghostty` window gets
`active_border_color` and `inactive_border_color` = attn (rust) → accent at 45deg (re-applied
every 5 s, so new windows get it too). Two quirks of the installed Hyprland:

- `setprop` is a dispatcher now. With the Lua config it is
  `hyprctl dispatch "hl.dsp.window.set_prop({ prop = 'active_border_color', value = '…', window = 'address:0x…' })"`;
  `hyprctl setprop` answers "unknown request". `hyprctl getoption -j` reports the
  gradient as `.gradient` (the legacy config used `.custom`).
- Its gradient parser drops the first colour token, so the first colour is passed twice.
- There is no working unset (`unset`, `-1`, `default` all leave an empty gradient, a
  dark border), so "restore" writes the current `general:col.active_border` /
  `col.inactive_border` values back. A theme switch while no one needs you therefore
  doesn't recolour Ghostty until the next needs-you cycle (or a Ghostty restart).

On its first poll the shell restores once, in case an earlier instance left the border rust.

## Developing against a fixture

`QS_BOARD_CMD=/path/to/fake-board` points `Board.qml` at any script that prints the
§2 JSON; `QS_BOARD_NO_BORDER=1` keeps it from touching real Ghostty windows. The
popups can be rendered without disturbing the running bar: a test `shell.qml` that puts
them in a `FloatingWindow` under `QT_QPA_PLATFORM=offscreen` (layer effects don't render
there), or the real `shell.qml` inside a headless KWin
(`kwin_wayland --virtual --socket qsdev-test`, then
`WAYLAND_DISPLAY=qsdev-test qs -p <copy>` with `HYPRLAND_INSTANCE_SIGNATURE` unset),
grabbing items with `grabToImage`. QtTest's `TestCase.keyClick` drives the keys.
