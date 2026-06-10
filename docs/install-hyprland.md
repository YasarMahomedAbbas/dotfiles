# Install guide — Hyprland (Arch / CachyOS)

Full setup: the universal CLI/editor stack **plus** the Nord-themed Wayland desktop.
Package names below are for `pacman`; `sesh` is the only AUR package (use `paru`/`yay`).

## 1. Clone + stow

```bash
sudo pacman -S --needed stow git
git clone <repo-url> ~/projects/personal/dotfiles
cd ~/projects/personal/dotfiles
```

`.stowrc` pins the target to `$HOME`, so `stow <pkg>` links into `~` regardless of clone location.

Stow **everything** on this machine (universal + Hyprland-only):

```bash
stow bin gh-dash ghostty git fish lazygit nvim sesh starship tmux   # universal
stow hypr waybar mako wofi                                          # Hyprland desktop
```

> If a target already exists as a real file/dir (e.g. a default `~/.config/fish`), remove or
> back it up first — stow won't overwrite real files.

## 2. Universal apps (used on both machines)

```bash
sudo pacman -S --needed \
  ghostty neovim starship lazygit git-delta diffnav \
  fish tmux ripgrep fd fzf zoxide eza yazi github-cli ttf-jetbrains-mono-nerd
paru -S --needed sesh             # AUR (tmux session manager; picker on <prefix>+s)
```

| Tool | Role in this config |
|---|---|
| ghostty | terminal (`theme = Nord`, JetBrainsMono Nerd Font) |
| neovim | editor (LazyVim + `gbprod/nord.nvim`) |
| starship | prompt (Nord palette) |
| lazygit | git TUI (uses `delta` as pager) |
| git-delta + diffnav | `git`'s pager/diff stack (see `~/.gitconfig`) |
| sesh | tmux session manager — Nord picker on `<prefix>+s`, config in `sesh/.config/sesh/sesh.toml` |
| fzf | fuzzy finder — backs the sesh picker (`sesh-picker`) |
| zoxide | smarter `cd` + recent-dir source for the sesh picker (`zoxide init fish` in `config.fish`) |
| eza | tree/file previews in the sesh picker |
| yazi | file-manager window in `tmux-dev-layout` |
| github-cli (`gh`) | required by gh-dash |
| ttf-jetbrains-mono-nerd | glyphs for ghostty/tmux/starship/nvim |

## 3. Hyprland desktop stack

```bash
sudo pacman -S --needed \
  hyprland hyprpaper hyprlock hypridle \
  waybar mako wofi \
  cliphist wl-clipboard flameshot polkit-kde-agent \
  brightnessctl playerctl wireplumber dolphin grim slurp
```

| Package | Wired up in |
|---|---|
| hyprland | compositor (`hypr/.config/hypr/hyprland.conf`) |
| hyprpaper | wallpaper — set from `exec-once`, image in `hypr/.config/hypr/wallpapers/` |
| hyprlock / hypridle | Nord lock screen + idle (5m lock → 10m DPMS → 30m suspend) |
| waybar | Nord status bar |
| mako | Nord notifications (`SUPER+Space` dismiss) |
| wofi | app launcher (`SUPER+R`), clipboard picker (`SUPER+Shift+V`), and the `powermenu` script (`SUPER+M` / `SUPER+Escape`) |
| cliphist + wl-clipboard | clipboard history |
| flameshot | screenshots (`SUPER+P`) |
| polkit-kde-agent | privilege-escalation prompts |
| brightnessctl / playerctl / wireplumber | media & brightness keys |
| dolphin | file manager (`SUPER+E`) |

> Edit `monitor=HDMI-A-1,...` in `hyprland.conf` to match your display (current setup is a
> 3440×1440 ultrawide).

## 4. Post-install

```bash
gh extension install dlvhdr/gh-dash                          # the gh-dash TUI
nvim "+Lazy! sync" +qa                                       # install nvim plugins
```

- Set fish as your shell: `chsh -s $(which fish)`
- tmux uses inline styling — no plugin manager to install.
- Re-theme everything later by editing `hypr/.config/hypr/colors.conf` + the per-tool palettes.

See [install-gnome.md](install-gnome.md) for the Ubuntu/GNOME machine (universal stack only).
