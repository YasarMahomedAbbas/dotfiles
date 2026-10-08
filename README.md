# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

Unified on the **Nord** color palette across every tool.

## Structure

Each directory is a stow package mirroring the home directory structure. `.stowrc`
pins the stow target to `$HOME`, so plain `stow <pkg>` works regardless of where the
repo is cloned.

**Universal** (both the Hyprland and the GNOME/Ubuntu machine):

```
dotfiles/
  bin/        → ~/.local/bin/          (work, tmux-dev-layout, tmux-cycle-layout, sesh-picker, sesh-list-bells, sesh-preview, sesh-clean-name,
                                        ticket-context, ticket-pill, board, pipeline-status, theme-switch, powermenu, gnome-powermenu)
  gh-dash/    → ~/.config/gh-dash/
  ghostty/    → ~/.config/ghostty/     (colors theme-driven; see Theming)
  git/        → ~/.gitconfig
  fish/       → ~/.config/fish/
  lazygit/    → ~/.config/lazygit/
  nvim/       → ~/.config/nvim/        (gbprod/nord.nvim)
  sesh/       → ~/.config/sesh/        (tmux session manager; Nord picker on <prefix>+s)
  starship/   → ~/.config/starship.toml
  tmux/       → ~/.tmux.conf, ~/.tmux/
  themes/     → (not stowed) color palettes + templates for `theme-switch`; see Theming
```

**Hyprland-only** (the Wayland desktop; GNOME does not use these):

```
  hypr/       → ~/.config/hypr/        (hyprland, hyprlock, hypridle, hyprpaper, colors.conf, wallpapers/)
  waybar/     → ~/.config/waybar/
  mako/       → ~/.config/mako/
  wofi/       → ~/.config/wofi/      (launcher + powermenu styles)
  streamdeck/ → ~/.local/bin/ + ~/.config/systemd/user/  (Stream Deck session dashboard; see Stream Deck)
```

**GNOME-only** (not a stow package — scripts/config applied directly):

```
  gnome/      → apply-keybinds.sh     (Tiling Shell + Hyprland-like binds; see docs/install-gnome.md)
```

## Install

Full per-machine guides (clone, stow, every dependency):

- **[Hyprland (Arch / CachyOS)](docs/install-hyprland.md)** — universal stack + Nord Wayland desktop.
- **[GNOME (Ubuntu)](docs/install-gnome.md)** — universal stack + Hyprland-like tiling (Tiling Shell) & Nord theming.

Quick reference — `.stowrc` pins the target to `$HOME`, so `stow <pkg>` works from anywhere:

```bash
# universal (both machines)
stow bin gh-dash ghostty git fish lazygit nvim sesh starship tmux
# Hyprland desktop only
stow hypr waybar mako wofi streamdeck   # streamdeck also needs a one-time setup (see Stream Deck)
```

> **Updating later:** after a `git pull` pulls in commits that add *new* files (e.g. from another
> machine), re-link them with `stow --restow <pkg>` — stow doesn't link files that didn't exist
> when you last stowed, so new scripts/configs stay missing from `~` until you restow.

## Usage

### theme-switch — color presets

One palette drives every app. Switch the whole desktop at once:

```bash
theme-switch              # list themes (active marked)
theme-switch dark-nord    # nord · dark-nord · vscode-dark
```

Full details in **[docs/theming.md](docs/theming.md)**.

### work

Open an editor+claude pane for a directory:

```bash
work              # uses current directory
work ~/some/path  # uses specified directory
```

Works both inside and outside an existing tmux session.

### sesh — session picker (`<prefix>+s`)

Inside tmux, `<prefix>+s` opens a Nord-themed [sesh](https://github.com/joshmedeski/sesh)
picker in a popup (fuzzy-jump to any running session, configured project, or
[zoxide](https://github.com/ajeetdsouza/zoxide) directory). Configured projects live in
`sesh/.config/sesh/sesh.toml`.

Sessions get their windows from **`tmux-dev-layout`** (claude · git · any extra dev windows
you specify), so there are no per-project layout files to maintain:

```bash
# run as a session's first-window command; each 'name|dir|command' adds a window
tmux-dev-layout <project-path> [--claude-dir DIR] ['dev||npm run dev'] ...
```

#### Status column and the ticket card

Running sessions carry a **branch** and a **status** column, and the ones that want you sort
to the top:

```
 issue-559    feat/frontend/quotation-room-description   ● needs you · Results
 issue-612    fix/frontend/wallet-statement-booked-by    ▶ pnpm test 3m
 travelsmart  develop                                    ◐ background · 2 agents
 issue-705    main                                       ✓ unseen
 dotfiles
```

The status comes from the agent board (`board list --json`): `●` red = Claude is blocked on
you (permission, question, plan approval), `▶` = a turn is running (yellow + `slow` once it
runs past its typical time), `◐` blue = agents or shells still run after the turn, `✓` green
= finished since you last looked. Idle shows nothing.

The preview pane is a **ticket card** — issue, one-line description, branch, position in the
pipeline, checklist progress — rather than a dump of Claude's last output, because when you
are scanning six sessions the question is which ticket this is and where it got to.

Full reference — the state files, the `board` CLI and every surface that reads it:
**[docs/agent-board.md](docs/agent-board.md)**.

### board — the agent board (`<prefix>+i`)

Every Claude session, who needs you, what each is doing, its ticket and its dev stack, from
one source of truth (state files written by a Claude mod). `<prefix>+i` opens the roster
popup (⏎ jump, 1-9 answer, `s s` switch the dev stack, `v`/`y` design, `?` keys); the tmux
status bar carries `● N needs you  ▶ N ◐ N`.

```bash
board list            # sessions, most urgent first (--json for scripts)
board next            # jump to the oldest session that needs you
board stack <key>     # what switching the dev stack here would do (--yes to do it)
```

Full reference: **[docs/agent-board.md](docs/agent-board.md)**.

### wt-dev — one live worktree per project (`<prefix>+w`)

Decides which git worktree owns a project's dev stack, and makes that choice visible. Every
worktree wants the same host ports, so two stacks up means a half-started stack — or, worse,
one branch's frontend silently talking to another branch's backend, because a browser-facing
`http://localhost:5032` names the *host*, not the compose network.

```bash
wt-dev use issue-510    # make that worktree live and start it (returns immediately)
wt-dev status           # what is live, across every project
wt-dev doctor           # who holds the declared ports right now
```

`<prefix>+w` opens an fzf switcher across every registered project, and the pill on the right
of the tmux status bar names whatever is currently live. A project opts in with a `.wtdev.toml`
at its repo root — `compose` and `process` runners are both supported.

Full reference — the guardrails, onboarding a project, state layout, and notes for extending
it: **[docs/wt-dev.md](docs/wt-dev.md)**.

### wt-session

Open or create a tmux dev session for a worktree/directory. Builds the same
`tmux-dev-layout` windows; works inside or outside tmux:

```bash
wt-session <path>
```

### tmux-cycle-layout

Cycle through tmux pane layouts. Bind it in `.tmux.conf`:

```
bind <key> run-shell "tmux-cycle-layout"
```

### Stream Deck — physical session dashboard

`streamdeck/` drives a 15-key Elgato Stream Deck (MK.2) as a live dashboard for the
tmux + Claude workflow. The top row shows one key per tmux session (up to five),
background-coloured by its most urgent Claude from `board list --json` — red = needs you,
frost = working, yellow = slow, blue = background agents, green = finished and unseen, dim =
idle. The attached session gets a cyan border. Press a session key to `board jump` to that
Claude; a **DESIGN** key lights in the accent colour when a design canvas exists and opens it. The bottom row is actions: **PICK** (sesh popup),
**THEME** (cycle `theme-switch`), **MIC** / **MUTE** (`wpctl`). A **MEDIA** key opens a second page of music controls (`playerctl` transport +
`wpctl` volume), a **WORK** key opens a project launcher — one key per configured project
(logo + name, bordered by its live session state) that create-or-switches via `sesh connect`,
spawning a ghostty on workspace 1 if no terminal is open — and a **VPS** key opens an SSH
launcher, one key per `~/.ssh/config` host, each opening a fresh ghostty running `ssh <host>`.
Colours follow the active theme via `~/.config/theme/sesh-colors.sh`.

A small Python daemon (`streamdeck-dashboard`, using `python-elgato-streamdeck`) polls tmux
~1×/s and runs as a systemd user service. One-time setup after `stow streamdeck`:

```bash
streamdeck-dashboard-setup                                   # creates the venv (see docs/install-hyprland.md for deps)
systemctl --user enable --now streamdeck-dashboard.service
```

Layout and action bindings live in the config block at the top of `streamdeck-dashboard`.
Full reference — setup, configuration, service management, troubleshooting: **[docs/streamdeck.md](docs/streamdeck.md)**.
