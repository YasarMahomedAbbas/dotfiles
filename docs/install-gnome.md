# Install guide — GNOME (Ubuntu)

The **universal** CLI/editor stack only. GNOME provides the desktop (notifications, lock
screen, launcher, clipboard), so the Hyprland packages are **not** installed here.

## 1. Clone + stow

```bash
sudo apt update && sudo apt install -y stow git
git clone <repo-url> ~/projects/personal/dotfiles
cd ~/projects/personal/dotfiles
```

Stow the universal packages **only** — do **not** stow `hypr waybar mako wofi`:

```bash
stow bin gh-dash ghostty git fish lazygit nvim sesh starship tmux
```

> On a fresh Ubuntu box `~/.config/fish` may already exist as a real dir — back it up and
> remove it first, or stow will refuse.

## 2. Universal apps

**From apt:**

```bash
sudo apt install -y \
  git tmux fish ripgrep fd-find fzf wl-clipboard xclip \
  build-essential curl unzip
```

(`fd-find`'s binary is `fdfind`; optionally `ln -s $(which fdfind) ~/.local/bin/fd`.)
(`zoxide` is in apt on Ubuntu 22.10+ — `sudo apt install zoxide`; on older releases see the table below.)

**Not in apt (or too old) — install manually:**

| Tool | How |
|---|---|
| **neovim** (latest) | apt's is too old for LazyVim → `sudo add-apt-repository ppa:neovim-ppa/unstable && sudo apt install neovim`, or a GitHub release |
| **starship** | `curl -sS https://starship.rs/install/install.sh \| sh` |
| **lazygit** | GitHub release (`jesseduffield/lazygit`) |
| **delta** (git-delta) | GitHub release `.deb` (`dandavison/delta`) — binary is `delta` |
| **diffnav** | GitHub release (`dlvhdr/diffnav`) — `git`'s core pager |
| **gh** | GitHub CLI apt repo (cli.github.com), then `sudo apt install gh` |
| **gh-dash** | `gh extension install dlvhdr/gh-dash` |
| **ghostty** | not in apt → see ghostty.org/docs/install (snap / community `.deb` / build) |
| **JetBrainsMono Nerd Font** | download from `ryanoasis/nerd-fonts` releases → unzip into `~/.local/share/fonts/` → `fc-cache -f` ⚠️ apt's `fonts-jetbrains-mono` is the **non-Nerd** build (no icons) |
| **sesh** | tmux session manager (picker on `<prefix>+s`) → GitHub release (`joshmedeski/sesh`) or `go install github.com/joshmedeski/sesh/v2@latest` |
| **zoxide** | smarter `cd` + sesh's recent-dir source → apt on 22.10+, else `curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \| sh` |
| **eza** | file/tree previews in the sesh picker → `cargo install eza` or GitHub release (`eza-community/eza`) |
| **yazi** | file-manager window in `tmux-dev-layout` → `cargo install --locked yazi-fm` or GitHub release (`sxyazi/yazi`) |
| **claude** | claude.com/code — required by the `work` script |

## 3. Post-install

```bash
nvim "+Lazy! sync" +qa
chsh -s $(which fish)
```

> **Fish note:** `config.fish` sources the CachyOS default config only when it exists, so on
> Ubuntu fish starts clean (just starship + your functions). Any CachyOS-provided aliases/
> theme won't be present — add Ubuntu equivalents to `config.fish` if you want them.

## 4. GNOME desktop — Nord theming (optional, not managed by stow)

This is the GNOME equivalent of the Hyprland eye-candy. None of it is a stow package.

```bash
sudo apt install -y gnome-tweaks gnome-shell-extension-manager
```

- **GTK + shell theme:** `Nordic` (EliverLara) — clone to `~/.themes`, then set the GTK theme
  in Tweaks and the Shell theme via the **User Themes** extension.
- **Cursor:** Nordic-cursors → `~/.icons`, set in Tweaks.
- **Icons:** `Zafiro-Nord`, or Papirus with a Nord folder color.
- **Font:** set JetBrainsMono Nerd Font as the monospace/interface font in Tweaks.
- **Extensions** (via Extension Manager): Blur my Shell, Just Perfection, Vitals, Dash to
  Dock, Caffeine, AppIndicator.
- **Wallpaper:** reuse `hypr/.config/hypr/wallpapers/darksouls.png` from the repo.

### Make GNOME settings reproducible

GNOME config lives in dconf (a binary store — not stow-symlinkable). Snapshot / restore it:

```bash
# capture on a configured machine
dconf dump /org/gnome/ > ~/projects/personal/dotfiles/gnome/dconf-gnome.ini
# restore on a fresh machine
dconf load /org/gnome/ < ~/projects/personal/dotfiles/gnome/dconf-gnome.ini
```

See [install-hyprland.md](install-hyprland.md) for the full Hyprland desktop setup.
