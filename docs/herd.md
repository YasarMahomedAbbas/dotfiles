# herd — start an agent somewhere and give it a job

Status: **built** (2026-11-07): script, `ticket` recipe, pinned bar, skill. Source: the `herd`
stow package. Install: `stow herd`, then per machine copy `~/.config/herd/config.example.json`
→ `config.json` and `projects.example.json` → `projects.json` (both gitignored), and on a
herdr machine use the `herd` layout (below).

"Do X in a herd" starts a coding agent (Claude, Codex, pi, …) in its own terminal — a tab, a
pane, a space, or out of sight — and hands it the job. Tickets are one kind of job, not the
only one: "in a herd, figure out why my PC is slow" is just as valid as "do #2021 in a herd".

---

## Why

Every project's pipeline skill writes its own tmux launch line
(`tmux new-session -d -s issue-<n> … "claude '/pipeline #<n>'"`), with its own session
prefix and its own cleanup. Seven slightly different copies across four repos, all of them
tied to tmux. Moving to herdr means touching every one — and the next change would too.

herd is the one place that knows how to start, find and close an agent session. Skills say
what they want; herd decides how the current machine does it.

## Pieces

| Piece | Where (stowed) | What |
|---|---|---|
| `herd` | `herd/.local/bin/herd` | bash script: the mechanics, no judgement |
| config | `herd/.config/herd/` | `config`, `runners`, `projects`, `recipes/` |
| skill | `herd/.claude/skills/herd/SKILL.md`, `herd/.codex/skills/herd` (a link to it) | turns "in a herd …" into a `herd` call |
| pinned bar | `herd/.config/herdr-app/mods/herd-pane/` | herdr pane-header mod (see Pinned description bar) |

`herd` is a **universal** package (Hyprland and Ubuntu machines): add it to the universal
`stow` line in the README and both install guides, and `jq` to their package lists (`git` and
`gh` are already there). New recipe files need `stow --restow herd` on the other machines.

Portability rules: plain bash, standard tools only (`git`, `jq`; `gh` for the ticket recipe
only). No `rg`/`fd` (Ubuntu's fd is `fdfind`), no fish, nothing Hyprland/quickshell/Wayland.
Paths come from XDG and the config, never from `$HOME/projects` assumptions.

## The settings

Every herd is the same handful of settings, each with a default:

| Setting | Flag | Values | Default |
|---|---|---|---|
| task | `-- "…"` | anything | required (a recipe may supply it) |
| where it runs | `--at` | a folder, a project name from `projects`, `~` | the caller's folder |
| placement | `--place` | `tab`, `right`, `down`, `space`, `bg` | `tab` in the current space |
| target | `--tab <id>`, `--pane <id>` | an existing tab or pane | current one |
| runner | `--runner` | a name from `runners` | `claude` |
| name | `--name` | tab title | made from the task |
| description | `--desc` | one line for the pinned bar | made from the task |
| reports back | `--report` / `--no-report` | | report when started from another agent, else not |
| recipe | `--recipe` | a file in `recipes/` | none: the task goes to the agent verbatim |
| backend | `--backend` | `herdr`, `hc`, `tmux`, `here` | detected, see below |
| group | `--group <id>` | label shared by related herds | none (swarm uses it) |

```
herd [--place tab|right|down|space|bg] [--at <folder|project>] [--runner claude|codex|pi]
     [--name "…"] [--desc "…"] [--report] [--recipe <name>] [--backend …] -- "the task"
herd ls [--group <id>] [--recipe ticket]     # live herds, JSON with --json
herd stage <stage> [running|blocked|done]    # from inside a herd: update its labels
herd close <name|id>                         # end it and close its tab/pane
herd go <name|id>                            # bring it on screen
```

Re-running `herd` for something already live (same recipe key, e.g. ticket `#2021`) goes to
the existing herd instead of opening a second one.

## Backend: decided per call, not per machine

First rule that answers wins:

1. `--backend` on the call, or `HERD_BACKEND` in the environment.
2. Where it was called from: `TMUX` set → **tmux**; `HC_TERMINAL_ID` set → **herdr**. Both
   set (tmux inside herdr) → tmux, the innermost.
3. The machine default, `backend=` in `~/.config/herd/config`. Covers calls from no terminal:
   autopilot timers, cron, a Stream Deck key.
4. What's installed: herdr window running → hc → tmux → run here in the foreground.

Children inherit the environment, so a herd started from a herd lands in the same backend.

| Placement | herdr | hc only | tmux | here |
|---|---|---|---|---|
| `tab` | tab in the space | background | window | foreground |
| `right` / `down` | split in the tab | background | split-window | foreground |
| `space` | new space | background | new session | foreground |
| `bg` | hc terminal, no pane | hc terminal | detached session | refused |

A placement the backend can't do falls back down its column and says so on stderr.

**herdr mechanics**: see "Settled in the build" at the end. If the window isn't open, herd
starts an hc terminal labelled for the project's space; its tab appears when herdr opens.

## Runners: agent-agnostic

`~/.config/herd/runners` — one entry per agent: how to start it with a first message, and its
permission mode. Adding an agent is adding an entry.

```
claude  argv=["claude","--permission-mode","auto"]   task=arg
codex   argv=["codex"]                               task=arg
pi      argv=["pi"]                                  task=send   # start, wait ready, hc send
```

The pinned bar and tab names come from labels, which don't care which agent runs. The
working/needs-you dot comes from each agent's own status report to herdr (Claude Code does
this; check Codex's before relying on it).

## Recipes: how herd grows

A recipe is a small file in `~/.config/herd/recipes/<name>` that fills in settings and may run
steps before launch. No recipe = the task goes to the agent unchanged.

**`ticket`** — the one the pipelines use:

- input: a ticket ref (`#2021`, `M0-22`, `pa#352`) and optionally the project
- resolves the project (from the ref or the caller's repo) and its ticket source via an
  adapter: GitHub issues, GitHub project board; a work tracker is one more adapter
- makes the worktree and branch with that repo's convention (`wt-dev` paths stay valid)
- first message: that repo's pipeline for the chosen runner (`/frontend-pipeline #2021`;
  travel-smart's Codex copy for a Codex herd)
- name `#2021 sign-in autofill` (ref + 2–3 words of the slug), description = the ticket's
  problem line, labels `herd.recipe=ticket herd.key=<ref> ticket.stage=…`
- writes `ticket.md` into the worktree's private git dir, as `ticket-window` does today
- keeps the machine awake: it returns `inhibit`, so herd runs the agent under
  `systemd-inhibit --what=idle:sleep` until it exits (hypridle's 30-min suspend froze an
  unattended run for 4 h on 2026-11-08). Any recipe can return `inhibit: "<why>"`.

Later recipes, as needed: `review` (an hc template as a role), `swarm` (below).

## Pinned description bar

Every herd's pane shows a bar above the terminal: name (a ticket's ref) and title, the
one-line description under it, and the stage/status on the right. It is herdr's pane header,
swapped for the `herd-pane` mod, which reads the terminal's `herd.*` labels from
`terminals()` — live, no polling. Panes that aren't herds keep the usual one-line header.

The header is set in the layout, and herdr's shipped `main` layout is rewritten on update, so
it lives in a personal clone: `herdr-app do layout.clone '{"name":"main","as":"herd"}'`, then
in `~/.config/herdr-app/layouts/herd.json` set the pane header to
`{"content": {"mod": "herd-pane"}, "height": 44}`. (The layout file is herdr's own, not stowed.)

On tmux, `herd` sets the pane title to `name — desc` and stores the labels as `@herd_*` pane
options; show it with `pane-border-status top`.

## Room for swarm (not built)

A swarm = one orchestrator herd that starts N worker herds as panes in its own tab, workers
reporting to it. The design already allows it:

- `--tab` / `--pane` targets let the orchestrator place workers beside itself
- `--report` sends to the parent; `hc wait --children any` waits without polling
- `--group` labels let it list, message and close its workers; the bar can say "worker 2/4"

So swarm is a recipe, not a rewrite.

## The skill

"In a herd …" from Claude or Codex. It decides the settings from the sentence and calls
`herd`; it never launches anything itself.

| You say | Call |
|---|---|
| in a herd, figure out why my PC is slow | `herd --at ~ --name "slow pc" -- "…"` |
| open a pane herd in this tab and check the failing test | `herd --place right -- "…"` |
| in a background herd, summarise yesterday's logs | `herd --place bg --report -- "…"` |
| do #2021 in a herd | `herd --recipe ticket -- "#2021"` |
| do M0-22 in a codex herd | `herd --recipe ticket --runner codex -- "M0-22"` |
| herd the top 3 Todo tickets | three `herd --recipe ticket` calls |

## Order of work

1. **`herd` script** — settings, backend detection, herdr + tmux + here backends, runners,
   labels, `ls`/`stage`/`close`/`go`, reporting to the parent.
2. **`ticket` recipe + pinned bar mod.**
3. **Skill** for Claude and Codex; stow + install-guide updates.
4. **Port the pipelines** onto `herd --recipe ticket`, removing every tmux call:
   - travel-smart Frontend: `frontend-pipeline` (Claude and Codex copies), `frontend-autopilot`,
     `resume-work`, `frontend-raise-pr`, `frontend-start-ticket` (comment only)
   - personal-assistant: `pipeline` (drop its `unset TMUX`), `autopilot` (`@autopilot` →
     label), `resume-work` (`@pipeline_state`/`@builder_job` → labels)
   - immich-tv, paperless-companion: `pipeline`, `autopilot`
   - skills template (`~/projects/personal/skills`): add `herd stage` at stage boundaries,
     re-copy into agents, prepahead, EquipX
5. **Retire** the `ticket-window` hooks in `~/.claude/settings.json` (done 2026-11-07; they
   were no-ops outside tmux). `ticket-window` itself stays while lazyissues still calls it.
   `pipeline-status` forwards to `herd stage` and keeps its tmux options for the board.
6. **Later:** swarm recipe.

Out of scope here: the ticket board (being rebuilt separately), personal-assistant's builder
(issue #352), lazyissues/lazycontracts, the sesh family and other personal tmux tools.

## Settled in the build

- herdr placement: `tab` → `herdr-app do tab.new`, `space` → `space.new`, `right`/`down` →
  `pane.split` beside the caller's pane (or `--pane`), `bg` → `hc run --bg`. `--tab <id>` uses
  hc adoption (`herdr.space` + `herdr.tab` labels), which adds the terminal to that tab as a
  split. Labels go on afterwards with `hc label`.
- Herds started visibly have no hc parent (`--no-parent`), so they don't show as this
  session's sub-agents and outlive it. Reporting goes through `HERD_PARENT` in the child's
  environment and `herd report`, which works on herdr and tmux alike.
- `hc ls` leaves labels out; `herd ls` reads each live terminal with `hc get`.
- Extra labels: `--label k=v` (repeatable), visible in `herd ls --json` as `.labels`.

## Still open

- Codex's status reporting to herdr (the working/needs-you dot) — check on the first Codex herd.
- The herdr sessions mod has its own `projects.json`; it could read herd's instead.
