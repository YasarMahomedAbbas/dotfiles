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
  bin/        → ~/.local/bin/          (work, tmux-dev-layout, tmux-cycle-layout, sesh-picker, sesh-preview, powermenu)
  gh-dash/    → ~/.config/gh-dash/
  ghostty/    → ~/.config/ghostty/     (theme = Nord)
  git/        → ~/.gitconfig
  fish/       → ~/.config/fish/
  lazygit/    → ~/.config/lazygit/
  nvim/       → ~/.config/nvim/        (gbprod/nord.nvim)
  sesh/       → ~/.config/sesh/        (tmux session manager; Nord picker on <prefix>+s)
  starship/   → ~/.config/starship.toml
  tmux/       → ~/.tmux.conf, ~/.tmux/
```

**Hyprland-only** (the Wayland desktop; GNOME does not use these):

```
  hypr/       → ~/.config/hypr/        (hyprland, hyprlock, hypridle, hyprpaper, colors.conf, wallpapers/)
  waybar/     → ~/.config/waybar/
  mako/       → ~/.config/mako/
  wofi/       → ~/.config/wofi/      (launcher + powermenu styles)
```

## Install

Full per-machine guides (clone, stow, every dependency):

- **[Hyprland (Arch / CachyOS)](docs/install-hyprland.md)** — universal stack + Nord Wayland desktop.
- **[GNOME (Ubuntu)](docs/install-gnome.md)** — universal stack only + GNOME Nord theming.

Quick reference — `.stowrc` pins the target to `$HOME`, so `stow <pkg>` works from anywhere:

```bash
# universal (both machines)
stow bin gh-dash ghostty git fish lazygit nvim sesh starship tmux
# Hyprland desktop only
stow hypr waybar mako wofi
```

## Usage

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

Sessions get their windows from **`tmux-dev-layout`** (editor + claude split · git · optional
dev · files), so there are no per-project layout files to maintain:

```bash
tmux-dev-layout <project-path> [dev-command]   # run as a session's first-window command
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
