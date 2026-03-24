# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Structure

Each directory is a stow package mirroring the home directory structure:

```
dotfiles/
  bin/        → ~/.local/bin/          (shell scripts: work, tmux-cycle-layout)
  gh-dash/    → ~/.config/gh-dash/
  ghostty/    → ~/.config/ghostty/
  git/        → ~/.gitconfig
  lazygit/    → ~/.config/lazygit/
  nvim/       → ~/.config/nvim/
  starship/   → ~/.config/starship.toml
  tmux/       → ~/.tmux.conf, ~/.tmux/
```

## Install
Clone the repo, 

```bash
stow bin
stow gh-dash
stow ghostty
stow git
stow lazygit
stow nvim
stow starship
stow tmux
```

Or all at once:

```bash
stow */
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
