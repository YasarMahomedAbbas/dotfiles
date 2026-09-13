# wt-dev — one live worktree per project

`wt-dev` decides which git worktree owns a project's dev stack, and makes that choice
visible. Source: `bin/.local/bin/wt-dev` (bash, stowed with the rest of `bin`).

---

## The problem

Every worktree of a repo wants the same host ports. Two dev stacks up at once is not
"parallel development" — it is one of these:

- the second stack fails to bind and you get a **half-started** stack, or
- both start, and whichever won the API port serves **every** frontend on the machine.

The second is the nasty one. A browser-facing URL like
`NEXT_PUBLIC_API_URL=http://localhost:5032/api` is a fact about the *host*, not about the
compose network, so a frontend built from `issue-510` will happily talk to a backend built
from `main` and nothing anywhere says so.

There is a quieter third case even with one stack: named volumes and `node_modules` outlive
a switch, so moving to a branch with a different lockfile silently runs the old dependency
tree.

## The answer

Exactly **one** worktree per project is live.

For **compose** projects the project name is pinned and `-f` / `--project-directory` move
instead, so switching trees recreates the one stack rather than starting a second. Relative
bind mounts resolve against the tree, so the source follows you with no changes to the
compose file at all. For **process** projects the dev command runs in its own session, so
the whole child tree dies with one signal — killing an `npm` shim otherwise leaves the real
port holder alive.

---

## Daily use

```
wt-dev use issue-510    # make that worktree live and start it
wt-dev up               # the current worktree            (= use .)
wt-dev status           # what is live, across every project
wt-dev down             # stop
wt-dev logs [svc]       # follow the live stack's output
wt-dev doctor           # who holds the declared ports right now
wt-dev compose -- ARGS  # docker compose against the live tree
```

**`use` returns immediately.** Everything that can fail fast runs synchronously — resolving
the worktree, the port preflight, the `require_files` check, the fingerprint decision — and
then the slow part detaches. This matters because `dotnet watch` recompiles from scratch on
every switch (the source tree under it changed) and compose's own `up -d` blocks until a
`depends_on: service_healthy` dependency reports healthy. Together that is minutes; holding
the terminal for it also freezes any tmux popup the switch was launched from.

Pass `--wait` to block instead. Other flags: `--build` forces a rebuild / setup re-run,
`--db NAME` or `--db auto` overrides the database on projects that declare `db_var`.

### Guardrails, all automatic

- **Port preflight.** Anything foreign holding a declared port aborts the start and is named.
- **Fingerprint check.** Lockfiles, Dockerfiles and project files are hashed. Compose shares
  one named volume across trees, so it compares against the *previously live* tree and drops
  `volatile_volumes` before rebuilding. A process runner builds into each tree, so it tracks
  per-tree state instead — a tree never prepared gets its `setup` run.
- **Adoption.** A stack started by plain `docker compose` is recognised from its own
  `com.docker.compose.project.config_files` label, so `status` reports what is actually
  running instead of "stopped".
- **Missing services.** A tree that declares a service which has not been created is called
  out, as is a port in `.wtdev.toml` that nothing in this tree publishes — branches differ in
  which services they define, so "live" does not imply every usual URL answers.

## Seeing what's live

- **tmux pill** — right of the status bar: `ts:issue-510 · ag:agents`. Green healthy, amber
  starting, red unhealthy or failed. Printed by `wt-dev tmux`.
- **`wt-dev status`** — live tree, branch, per-service health, URLs, dormant worktrees, port
  conflicts, and the log path while a stack is still starting.
- **`prefix + w`** — fzf switcher across every registered project. Enter makes a tree live,
  `ctrl-d` stops that project. `wt-dev pick --list` prints the rows without the UI.
- **Desktop notification** — because `use` detaches, the terminal that launched the switch has
  moved on by the time the stack lands, and the pill going green is easy to miss from another
  window. One notification when it is live (tree, branch, how long it took), one at critical
  urgency when it fails. Set `notify = false` in a project's `.wtdev.toml` to silence it; a
  machine with no notification daemon is not an error.

---

## Onboarding a project

1. Write a `.wtdev.toml` at the repo root. `wt-dev --help` documents every key; the two
   runners are `compose` and `process`.
2. Gitignore it. `wt-dev` reads it from the **main checkout**, and an untracked file survives
   checking that checkout out to a branch predating it — committed, it would disappear exactly
   when you switch branches.
3. Run `wt-dev use` once inside the repo. That registers it in `~/.config/wt-dev/projects`.
4. Optional: point the repo's own `make`/task runner at it, with a fallback for machines that
   do not have `wt-dev` (see travel-smart's `Makefile` for the `command -v` pattern).

## State

| Path | Holds |
| --- | --- |
| `~/.config/wt-dev/projects` | registered repo roots, one per line |
| `~/.local/state/wt-dev/<name>.state` | live tree, branch, db, pid, started-at, `phase` |
| `~/.local/state/wt-dev/<name>.trees` | per-tree preparation fingerprints (process runner) |
| `~/.local/state/wt-dev/<name>.log` | output of the detached start, and of process runners |
| `~/.local/state/wt-dev/pill` | tmux pill cache, 5s TTL |

Nothing lives inside the repos, so a worktree can be deleted without leaving state behind.

`phase` is `starting`, `ready` or `failed` — it is what lets `status` and the pill distinguish
"still compiling" from "up" and from "stopped", now that starts are detached.

---

## Extending it

The file reads top to bottom in layers: colours → config parser → git/project resolution →
state → fingerprint → port ownership → the two runners → rendering → commands → dispatch.

Things worth knowing before you change it:

- **`compose_cmd` acts on the globals `PROJ` and `MAIN`**, not on arguments. It asserts both
  with `:?` because an unset `PROJ` inside a command substitution just aborts that subshell
  under `set -u` — which once made every picker row render as dormant, silently.
- **The config parser never sources the file.** A repo config arrives from a branch, and
  `source`ing it would make checking out a branch enough to run code. It is a deliberately
  small `key = value` reader; arrays must be on one line.
- **`compose_ps` is pipe-separated, not TSV.** A service with no healthcheck reports an empty
  `Health`, and `read` collapses a run of TAB (an IFS whitespace character) into one delimiter,
  shifting every later field left.
- **Anything detached needs `< /dev/null`.** A background child that inherits the caller's
  stdin holds the pty open, and a tmux `display-popup -E` stays open as long as anything owns
  the pty — the popup then looks hung, waiting on a file descriptor rather than a keypress.
- **`wt-dev tmux` runs every status-interval tick.** It must never block: it serves a cached
  pill for 5s and time-boxes the `docker ps` beneath it.
- **The colours come from the theme.** `themes/templates/wt-dev-colors.sh.tmpl` renders to
  `~/.config/theme/wt-dev-colors.sh` via `theme-switch`; the pill's background is the same
  `bg2` role the other status-bar pills use. Add a role there, not a literal.
- **`--help` is the header comment** (`sed -n '2,51p'`). Extend the comment when you add a
  flag or config key, and check the line range still covers it.

### Known gaps

- **No tests.** The seams that would be worth covering: the config parser, `port_holder`,
  the state round-trip, and picker row-building via `pick --list`. Both bugs found on day one
  lived in the picker path, which needs a tty and a popup to exercise by hand.
- **`services` in `.wtdev.toml` is not read** — the service list comes from `docker compose
  config --services`.
- Lives in dotfiles rather than its own repo: three integration points (colour template, the
  pill in `themes/templates/tmux.conf.tmpl`, the keybinding in `tmux/.tmux.conf`) have to live
  here regardless, so a split would make most changes a two-repo edit. Worth revisiting if it
  gains a second user, needs CI, or gets rewritten for speed.
