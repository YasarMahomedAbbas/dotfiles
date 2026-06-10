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
  bin/        → ~/.local/bin/          (shell scripts: work, tmux-cycle-layout, powermenu)
  gh-dash/    → ~/.config/gh-dash/
  ghostty/    → ~/.config/ghostty/     (theme = Nord)
  git/        → ~/.gitconfig
  fish/       → ~/.config/fish/
  lazygit/    → ~/.config/lazygit/
  nvim/       → ~/.config/nvim/        (gbprod/nord.nvim)
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
stow bin gh-dash ghostty git fish lazygit nvim starship tmux
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

### tmux-cycle-layout

Cycle through tmux pane layouts. Bind it in `.tmux.conf`:

```
bind <key> run-shell "tmux-cycle-layout"
```
