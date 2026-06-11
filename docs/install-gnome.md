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

## 4. Hyprland-like tiling + keybinds (Tiling Shell)

GNOME floats windows by default. [**Tiling Shell**](https://github.com/domferr/tilingshell)
is the GNOME extension that gets you the Hyprland feel — auto-tiling, gaps, Nord window
borders, and vim `hjkl` focus/move. The keybinds are mapped 1:1 from
`hypr/.config/hypr/hyprland.conf` onto GNOME's dconf + the extension's own settings.

**Install the extension** (CLI; no browser needed):

```bash
ver=$(curl -s "https://extensions.gnome.org/extension-info/?uuid=tilingshell@ferrarodomenico.com&shell_version=$(gnome-shell --version | grep -oP '\d+' | head -1)" | python3 -c 'import sys,json;print(json.load(sys.stdin)["version_tag"])')
curl -sL "https://extensions.gnome.org/download-extension/tilingshell@ferrarodomenico.com.shell-extension.zip?version_tag=$ver" -o /tmp/tilingshell.zip
gnome-extensions install --force /tmp/tilingshell.zip
```

> On **Wayland** a freshly installed extension isn't visible to the running shell until you
> **log out and back in** — there's no live shell restart like X11's `Alt+F2 r`. The apply
> script below queues it into `enabled-extensions`, so it auto-enables on next login.

**Back up dconf first** (so the whole thing is one-command reversible):

```bash
dconf dump /org/gnome/ > ~/gnome-backup-pre-tiling.ini
```

**Apply the keybinds + tiling config** (idempotent; safe to re-run):

```bash
./gnome/apply-keybinds.sh      # from the repo root
```

Then **log out and back in**. Keybinds/workspaces work immediately; the tiling, borders,
gaps and `hjkl` focus activate once the extension loads on login.

### What you get — Hyprland → GNOME bind map

| Hyprland | GNOME equivalent | Key |
|---|---|---|
| `Super+Q` terminal | ghostty (custom keybind) | `Super+Q` |
| `Super+C` killactive | close window | `Super+C` |
| `Super+R` wofi drun | Show Apps / launcher | `Super+R` |
| `Super+E` file manager | nautilus (custom keybind) | `Super+E` |
| `Super+F` fullscreen 1 | toggle-maximized | `Super+F` |
| `Super+Shift+F` fullscreen 0 | toggle-fullscreen | `Super+Shift+F` |
| `Super+V` togglefloating | Tiling Shell untile (pop out) | `Super+V` |
| `Super+P` flameshot | GNOME screenshot UI | `Super+P` |
| `Super+M` powermenu | `gnome-powermenu` (zenity) | `Super+M` |
| lock screen (moved off `Super+L`) | screensaver | `Super+Ctrl+L` |
| `Super+hjkl` movefocus | Tiling Shell focus | `Super+hjkl` |
| (mouse) movewindow | Tiling Shell move/swap | `Super+Shift+hjkl` |
| `Super+1..0` workspace | switch-to-workspace 1..10 | `Super+1..0` |
| `Super+Shift+1..0` move-to-ws | move-to-workspace 1..10 | `Super+Shift+1..0` |

**Tuned to match `hyprland.conf`:** auto-tiling on, `inner-gaps=4` / `outer-gaps=8`
(= `gaps_in`/`gaps_out`), `2px` Nord-cyan border `#88C0D0` (= `col.active_border` nord8),
blur on tile previews. Tweak any of it in **Tiling Shell → Settings** or by editing
`gnome/apply-keybinds.sh`.

> **Not auto-mapped** (no clean GNOME native): `Super+S` scratchpad, `Super+Space`
> notification-dismiss, `Super+Shift+V` clipboard history. For clipboard history install the
> **Clipboard Indicator** extension; the GNOME notification list (top bar clock) covers the rest.
> Ubuntu's `tiling-assistant` is disabled by the apply script so it doesn't fight Tiling Shell.

### Troubleshooting — a Super+key does nothing

Tiling Shell registers its keybinds **once, at load**. If another binding owns that key
combo at that moment, mutter silently rejects the duplicate and Tiling Shell never gets it
(e.g. GNOME's default lock on `Super+L` blocks `focus-window-right` until lock is moved off
it — which `apply-keybinds.sh` does). Running the script *before* first login avoids this.
If you hit it after a live change, free the key, then re-register by reloading the extension:

```bash
gnome-extensions disable tilingshell@ferrarodomenico.com
gnome-extensions enable  tilingshell@ferrarodomenico.com
```

### Reverting

```bash
gnome-extensions disable tilingshell@ferrarodomenico.com   # stop tiling, keep binds
dconf load /org/gnome/ < ~/gnome-backup-pre-tiling.ini     # full restore to pre-setup state
```

## 5. GNOME desktop — Nord theming (optional, not managed by stow)

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
