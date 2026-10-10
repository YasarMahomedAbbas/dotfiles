# Agent board: the Hyprland / quickshell side

The desktop half of [agent-board.md](agent-board.md). Everything here reads the board
through the `board` CLI (§2); nothing reads `~/.cache/claude-board` directly.

| file (`quickshell/.config/quickshell/`) | what it is |
|---|---|
| `Board.qml` | singleton: polls the CLI, exposes sessions + counts, helpers, the Ghostty border |
| `AgentsIsland.qml` | bar island: `● N needs you  ▶ N  ◐ N  ◇ design  ts ● 1654` |
| `KeysHint.qml` | the small `⊞ /` island (opens the cheatsheet) |
| `Roster.qml`, `RosterRow.qml` | SUPER+G popup |
| `ChecklistWall.qml`, `WallCard.qml` | SUPER+Shift+G popup |
| `KeysCheatsheet.qml` | SUPER+/ popup (not `Keys.qml`: that name collides with QtQuick's attached `Keys`) |
| `Toast.qml` | the one toast (its own layer-shell window, under the agents island) |
| `Glass.qml`, `Chip.qml`, `Segs.qml`, `Kbd.qml`, `Btn.qml` | shared pieces |

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

Status colours (§4) are `Board.statusColor()`: needs_you red, working fg0, slow yellow
(`current.started` older than `current.typical_ms`), background blue, unseen-done green,
idle/stale fg2. Stage strips use `ticket.stage_index` as the stage running now (1-based,
earlier stages done).

## What each key runs

| where | key | runs |
|---|---|---|
| roster | ⏎ | `board jump <key>`, then closes |
| roster | 1-9 | `board answer <key> <n>` (only offered while that session is needs_you) |
| roster | s | `board stack <key>` (dry run; its output is the confirmation line) |
| roster | s again | `board stack <key> --yes` |
| roster | v / y | `board design <key>` / `board design <key> --copy` |
| roster | o / t | `board __open-url <key>` / `board __ticket <key>` (the CLI's roster internals, the same ones `board roster`'s fzf binds use; not in the §2 table) |
| roster | c | opens the wall on that session |
| roster | / ? esc | filter · cheatsheet · close (esc first cancels a pending `s`, then clears the filter) |
| wall | h/j/k/l ⏎ ? esc | move · `board jump <key>` · cheatsheet · close |
| cheatsheet | type, ↑/↓, ⏎ | filter, pick a Hyprland bind, `hyprctl dispatch 'BINDS["<description>"]'` |

The cheatsheet reads `hyprctl binds -j` (binds with a description only), `board keys
--json` (its "In the roster" group; the "Agent board" SUPER entries are dropped because
the live Hyprland binds cover them, `prefix+i` joins the Agents column; a built-in
table stands in when the CLI is missing) and `tmux list-keys -N`.

## Bind descriptions (hyprland.lua)

Every bind goes through the config's `bind(keys, "Group: what it does", dispatcher, opts)`
helper, which sets the bind's `description` and also stores the dispatcher in the global
`BINDS` table under that description. Lua binds show up in `hyprctl binds -j` as
`__lua <id>`, so the cheatsheet runs a bind with `hyprctl dispatch 'BINDS["<description>"]'`.
The cheatsheet makes one column group per `Group`, in this order:
Agents, In the roster, tmux, Windows, Workspaces, Apps, Shell, Notifications, Capture,
Media, Session (anything else after, alphabetically). Runs like `Go to workspace 1` …
`10` fold into one `1–0` line.

New binds: `SUPER+G` → `hl.dsp.global("quickshell:roster")`, `SUPER+SHIFT+G` →
`hl.dsp.global("quickshell:wall")`, `SUPER+slash` → `hl.dsp.global("quickshell:keys")`,
`SUPER+N` → `exec board next`, and a second `SUPER+space` bind →
`hl.dsp.global("quickshell:dismisstoast")`
next to mako's (Hyprland runs every bind on the same combo, so both fire).

## Toast

`Board.needsYouEntered` fires when a session enters needs_you with a new
`key + attention.since` (sessions already waiting when the shell starts don't toast).
The toast shows 8 s, hides early once that session leaves needs_you, opens the roster on
click, and SUPER+space dismisses it. Nothing else toasts.

## Ghostty border (Hyprland 0.56)

While `needs_you > 0`, every `com.mitchellh.ghostty` window gets
`active_border_color` and `inactive_border_color` = red → accent at 45deg (re-applied
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

On its first poll the shell restores once, in case an earlier instance left the border red.

## Developing against a fixture

`QS_BOARD_CMD=/path/to/fake-board` points `Board.qml` at any script that prints the
§2 JSON; `QS_BOARD_NO_BORDER=1` keeps it from touching real Ghostty windows. The
popups can be rendered without disturbing the running bar: a test `shell.qml` that puts
them in a `FloatingWindow` under `QT_QPA_PLATFORM=offscreen` (layer effects don't render
there), or the real `shell.qml` inside a headless KWin
(`kwin_wayland --virtual --socket qsdev-test`, then
`WAYLAND_DISPLAY=qsdev-test qs -p <copy>` with `HYPRLAND_INSTANCE_SIGNATURE` unset),
grabbing items with `grabToImage`. QtTest's `TestCase.keyClick` drives the keys.
