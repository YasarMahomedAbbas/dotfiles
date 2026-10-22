# agent-board

A Claude Code mod (function hooks, no command hooks) that writes this session's status
for the agent board. The contract is section 1 of [`docs/agent-board.md`](../../docs/agent-board.md).

## What it writes

- `~/.cache/claude-board/<key>.json`, where `<key>` is the tmux pane id without `%`
  (`%42` → `42`), or `nopane-<session_id>` outside tmux. It is written atomically
  (`<key>.json.tmp`, then `mv`) on every change and every 10 s (heartbeat), and removed
  on `session.end`. A `/clear` empties it and carries on under the new session id. Any
  other `session.end` that keeps the process alive (`/resume` into another session) stops
  the heartbeat; the following `session.start` starts it again from a clean state.
- The tmux session option `@board_state` (`needs_you` / `working` / `background` / `idle`),
  set on each change through the session id (`$N`), unset when the session ends and set
  again when a new one starts in the same process.
- `$.store` key `durations`: the last 20 run times of each normalised Bash command per
  project (main repo root, shared across worktrees, plus the subdirectory). This is where
  `current.typical_ms` comes from (the median, once there are 3 runs).

How each state is detected:

| state | set by | cleared by |
|---|---|---|
| working | `turn.start` (a typed prompt, or a background task waking the session with empty text); also any main-loop `tool.call` / `turn.step` | main-loop `turn.complete` |
| needs_you | main-loop `tool.call` of AskUserQuestion / ExitPlanMode (before `next`), `classic.PermissionRequest` without `agent_id` that no settings hook decided | the next main-loop `tool.call` starts, main-loop `turn.step`, `prompt.submit`, `turn.complete`, the asking call resolving, or (permission) the `ToolProgress` pill of the in-flight call rendering |
| background | main-loop `turn.complete` while an agent or a background shell runs | the last one ends (subagent `turn.complete`, `$.agent.list()` poll, a `<task-notification>` row, TaskStop) |
| idle | none of the above | `turn.start` |

A subagent's permission prompt (`classic.PermissionRequest` with `agent_id`) only marks that
agent `needs_you`. `classic.Notification` is not hooked, so `idle_prompt` changes nothing.

## Install

```sh
claude plugin marketplace add ~/projects/personal/dotfiles/claude-mods
claude plugin install agent-board@dotfiles-mods
```

The marketplace is a folder and the entry a relative path, so sessions read the mod from
this folder: after editing it, run `/reload-plugins` in a running session. To try it on
one session without installing: `claude --plugin-dir ~/projects/personal/dotfiles/claude-mods/agent-board`.

## Test

```sh
claude plugin validate ~/projects/personal/dotfiles/claude-mods/agent-board
claude plugin test ~/projects/personal/dotfiles/claude-mods/agent-board
```

The tests (`tests/agent-board.test.ts`) mock the clock, store, env, file system and host
commands, and drive the mod through the engine's own events.

## Limits

- The plugin API exposes no process id. The mod runs `sh -c 'echo $PPID'` and walks up
  `/proc` to the `claude` process (verified live: it is the CLI's own pid). If that fails,
  `pid` is `null` and readers fall back to the heartbeat.
- `$.fs` has no rename or delete, so the rename and the removal go through `mv` / `rm`.
- After a permission prompt is approved, nothing in the API says so directly. `needs_you`
  clears when the call resolves, when the next tool call or model step starts, or when the
  foreground call's "run in background" pill renders. A long approved non-Bash tool can
  show `needs_you` until it returns.
- The ExitPlanMode attention options are Claude Code's usual plan dialog choices,
  hard-coded. The plan text is not in the tool's input, so `attention.text` is a fixed line.
