#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# GNOME → Hyprland-like keybinds + Tiling Shell config.
#
# Idempotent. Re-run any time. Mirrors the binds in hypr/.config/hypr/hyprland.conf
# onto GNOME (mutter/shell dconf) + the Tiling Shell extension.
#
# Reversible: `dconf load /org/gnome/ < ~/gnome-backup-pre-tiling.ini` (full restore),
# or `gnome-extensions disable tilingshell@ferrarodomenico.com` (just stop tiling).
# ---------------------------------------------------------------------------
set -euo pipefail

TS_UUID="tilingshell@ferrarodomenico.com"
TS_SCHEMADIR="$HOME/.local/share/gnome-shell/extensions/$TS_UUID/schemas"
TS="org.gnome.shell.extensions.tilingshell"

gset()  { gsettings set "$@"; }
tset()  { gsettings --schemadir "$TS_SCHEMADIR" set "$TS" "$@"; }

# Nord palette
NORD8="#88C0D0"   # frost cyan — Hyprland active border

echo "==> Free Super+1..9 (GNOME binds these to 'switch to app N' in the dash)"
for i in $(seq 1 9); do
  gset org.gnome.shell.keybindings "switch-to-application-$i" "[]"
done

echo "==> Stop the Ubuntu dock from stealing Super+1..9 to launch dock apps"
gset org.gnome.shell.extensions.dash-to-dock hot-keys false
gset org.gnome.shell.extensions.dash-to-dock hotkeys-overlay false
gset org.gnome.shell.extensions.dash-to-dock hotkeys-show-dock false

echo "==> Disable Ubuntu's tiling-assistant (would fight Tiling Shell over every window)"
# Ubuntu enables its defaults outside enabled-extensions, so disable explicitly.
gnome-extensions disable tiling-assistant@ubuntu.com 2>/dev/null || true

echo "==> Static workspaces (Hyprland-style fixed 1..10)"
gset org.gnome.mutter dynamic-workspaces false
gset org.gnome.desktop.wm.preferences num-workspaces 10

echo "==> Workspace switch  Super+1..0   /   move-to-workspace  Super+Shift+1..0"
keys=(1 2 3 4 5 6 7 8 9 0)
for idx in "${!keys[@]}"; do
  n=$(( idx + 1 ))            # workspace number 1..10
  k="${keys[$idx]}"          # key 1..9,0
  gset org.gnome.desktop.wm.keybindings "switch-to-workspace-$n" "['<Super>$k']"
  gset org.gnome.desktop.wm.keybindings "move-to-workspace-$n"   "['<Super><Shift>$k']"
done

echo "==> Window management  (close / maximize / fullscreen)"
gset org.gnome.desktop.wm.keybindings close            "['<Super>c']"            # Hypr: Super+C killactive
gset org.gnome.desktop.wm.keybindings toggle-maximized "['<Super>f']"            # Hypr: Super+F fullscreen 1
gset org.gnome.desktop.wm.keybindings toggle-fullscreen "['<Super><Shift>f']"    # Hypr: Super+Shift+F fullscreen 0

echo "==> Move screen lock off Super+L (frees it for Tiling Shell focus-right)"
gset org.gnome.settings-daemon.plugins.media-keys screensaver "['<Super><Control>l']"  # lock = Super+Ctrl+L

echo "==> Launcher + screenshot (shell)"
gset org.gnome.shell.keybindings toggle-application-view "['<Super>r']"          # Hypr: Super+R wofi drun
gset org.gnome.shell.keybindings show-screenshot-ui      "['<Super>p', 'Print']" # Hypr: Super+P flameshot

echo "==> Custom launch keybinds  (terminal / files / powermenu)"
MK="org.gnome.settings-daemon.plugins.media-keys"
CKB="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
gset "$MK" custom-keybindings "['$CKB/ghostty/', '$CKB/files/', '$CKB/powermenu/']"

ck() { # path name command binding
  local p="$MK.custom-keybinding:$CKB/$1/"
  gset "$p" name "$2"; gset "$p" command "$3"; gset "$p" binding "$4"
}
ck ghostty   "Terminal"   "ghostty"                               "<Super>q"   # Hypr: Super+Q terminal
ck files     "Files"      "nautilus"                              "<Super>e"   # Hypr: Super+E file manager
ck powermenu "Power Menu" "$HOME/.local/bin/gnome-powermenu"      "<Super>m"   # Hypr: Super+M powermenu

# ---------------------------------------------------------------------------
#  Tiling Shell — the dwindle/auto-tile + Nord look + vim focus/move
# ---------------------------------------------------------------------------
echo "==> Tiling Shell: auto-tile, gaps, Nord border, blur"
tset enable-autotiling true
tset inner-gaps 4                       # Hypr: gaps_in = 4
tset outer-gaps 8                       # Hypr: gaps_out = 8
tset enable-window-border true
tset window-use-custom-border-color true
tset window-border-color "$NORD8"       # Hypr: col.active_border nord8
tset window-border-width 2              # Hypr: border_size = 2
tset enable-blur-selected-tilepreview true
tset enable-blur-snap-assistant true
tset enable-wraparound-focus true

echo "==> Tiling Shell: simple layouts (Layout 1 = clean 50/50 halves, selected by default)"
# Tiling Shell is zone-based: a new window drops into the most-central empty zone of the
# active layout. The shipped default is a fancy 22/56/22 layout (a lone window lands in the
# 56% centre, not full-width). These plain layouts give clean side-by-side instead.
# A SINGLE window still sits in one zone (a half) — use Super+F to fill the screen.
gsettings --schemadir "$TS_SCHEMADIR" set "$TS" layouts-json \
'[{"id":"Layout 1","tiles":[{"x":0,"y":0,"width":0.5,"height":1,"groups":[1]},{"x":0.5,"y":0,"width":0.5,"height":1,"groups":[1]}]},{"id":"Layout 2","tiles":[{"x":0,"y":0,"width":0.3333,"height":1,"groups":[1]},{"x":0.3333,"y":0,"width":0.3334,"height":1,"groups":[1]},{"x":0.6667,"y":0,"width":0.3333,"height":1,"groups":[1]}]},{"id":"Layout 3","tiles":[{"x":0,"y":0,"width":0.6,"height":1,"groups":[1]},{"x":0.6,"y":0,"width":0.4,"height":1,"groups":[1]}]},{"id":"Layout 4","tiles":[{"x":0,"y":0,"width":0.5,"height":0.5,"groups":[1]},{"x":0.5,"y":0,"width":0.5,"height":0.5,"groups":[1]},{"x":0,"y":0.5,"width":0.5,"height":0.5,"groups":[1]},{"x":0.5,"y":0.5,"width":0.5,"height":0.5,"groups":[1]}]}]'

echo "==> Tiling Shell: vim focus (Super+hjkl) and move (Super+Shift+hjkl)"
tset focus-window-left  "['<Super>h']"
tset focus-window-right "['<Super>l']"
tset focus-window-up    "['<Super>k']"
tset focus-window-down  "['<Super>j']"
tset move-window-left   "['<Super><Shift>h']"
tset move-window-right  "['<Super><Shift>l']"
tset move-window-up     "['<Super><Shift>k']"
tset move-window-down   "['<Super><Shift>j']"
tset untile-window      "['<Super>v']"   # Hypr: Super+V togglefloating (pop out of tiling)

# ---------------------------------------------------------------------------
#  Extensions: enable Tiling Shell on next login, drop Ubuntu's tiling-assistant
#  (which would fight Tiling Shell over Super+arrow tiling).
# ---------------------------------------------------------------------------
echo "==> Queue Tiling Shell on, tiling-assistant off"
python3 - "$TS_UUID" <<'PY'
import subprocess, sys, ast
uuid = sys.argv[1]
cur = subprocess.check_output(
    ["gsettings","get","org.gnome.shell","enabled-extensions"]).decode()
lst = ast.literal_eval(cur)
lst = [e for e in lst if e != "tiling-assistant@ubuntu.com"]
if uuid not in lst:
    lst.append(uuid)
subprocess.run(["gsettings","set","org.gnome.shell","enabled-extensions", str(lst)])
print("enabled-extensions =", lst)
PY

echo ""
echo "Done. Keybinds & workspaces apply live now."
echo "Tiling Shell (auto-tile, borders, hjkl focus) activates after you LOG OUT and back in."
