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
  bin/        → ~/.local/bin/          (work, tmux-dev-layout, tmux-cycle-layout, sesh-picker, sesh-list-bells, sesh-preview, theme-switch, powermenu, gnome-powermenu)
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
background-coloured by Claude status — red = needs you (`@claude_alert`), amber = working
(`@claude_busy`), dim = idle — reusing the exact pane-ownership logic from `sesh-list-bells`
so a misattributed option never lights a key. The attached session gets a cyan border. Press
a session key to switch your terminal to it. The bottom row is actions: **PICK** (sesh popup),
**THEME** (cycle `theme-switch`), **REC** (`screen-record` toggle), **MIC** / **MUTE**
(`wpctl`). A **MEDIA** key opens a second page of music controls (`playerctl` transport +
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
