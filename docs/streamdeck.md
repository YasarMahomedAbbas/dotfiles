# Stream Deck — physical tmux/Claude session dashboard

Turns a 15-key Elgato Stream Deck (MK.2 / Original, 3×5, 72×72px keys) into a live
dashboard for the tmux + Claude Code workflow: a glance at your desk tells you which
agent needs you, and one press jumps your terminal there.

Package: `streamdeck/` → `~/.local/bin/` (daemon + setup script) and
`~/.config/systemd/user/` (service unit).

---

## What it shows

```
┌──────┬──────┬──────┬──────┬──────┐
│ sess │ sess │ sess │ sess │ sess │  keys 0–4  — sessions, alphabetical (up to 5)
├──────┼──────┼──────┼──────┼──────┤
│MEDIA │ WORK │      │ VPS  │      │  key 5 opens media, 6 opens work, 8 opens VPS; 7 & 9 blank
├──────┼──────┼──────┼──────┼──────┤
│ PICK │THEME │      │ MIC  │ MUTE │  keys 10–14 — actions (12 blank)
└──────┴──────┴──────┴──────┴──────┘
```

**Sessions (keys 0–4)** — one key per running tmux session, sorted alphabetically so
positions stay stable (muscle memory), up to five (extra sessions aren't shown). The key
shows the session name — or, if the session is a configured work project with a logo, that
logo instead (keyed by session name, so e.g. a running `travelsmart` or `vault` shows its
mark). Its background color is the Claude status:

| Color | Meaning | Driven by |
|---|---|---|
| 🔴 red | Needs you — Claude finished or is waiting | `@claude_alert` |
| 🟡 amber | Working | `@claude_busy` |
| ⚫ dim slate | Idle session | — |
| cyan border | The session your terminal is currently attached to | most-recent tmux client |

Colors follow the active theme (`~/.config/theme/sesh-colors.sh` — the same
`SESH_BELL_COLOR` / `SESH_BUSY_COLOR` the sesh picker uses), and update live when you
run `theme-switch`.

**Press a session key** → switches your most-recently-active tmux client to that session
and focuses the terminal window (same as pressing a project on the work page). If no tmux
client is attached anywhere, it jumps to workspace 1 and launches ghostty attached to the
session.

**MEDIA (key 5)** — opens the media page (below). **WORK (key 6)** — opens the work
(project launcher) page (below). **VPS (key 8)** — opens the VPS page (below). The rest
of the middle row (keys 7 & 9) is blank.

**Actions (keys 10–14):**

| Key | Label | Does | Live state |
|---|---|---|---|
| 10 | PICK | Opens the sesh picker popup (`display-popup … sesh-picker`) on the attached client | — |
| 11 | THEME | Opens the theme picker page (below) | — |
| 13 | MIC | Toggles mic mute (`wpctl … @DEFAULT_AUDIO_SOURCE@`) | icon turns red when muted |
| 14 | MUTE | Toggles output mute (`wpctl … @DEFAULT_AUDIO_SINK@`) | icon turns red when muted |

---

## Media page

Press **MEDIA** (key 5) to switch the deck to a music-control page. It drives whatever
MPRIS player is active via `playerctl`, and output volume via `wpctl` — so it works with
Spotify, browsers, `mpv`, etc. without any per-app config.

A centred 3×2 cluster of controls, outer columns left blank:

```
┌──────┬──────┬──────┬──────┬──────┐
│      │ PREV │ PLAY │ NEXT │      │  keys 1–3 — transport
├──────┼──────┼──────┼──────┼──────┤
│      │ MUTE │ VOL- │ VOL+ │      │  keys 6–8 — volume
├──────┼──────┼──────┼──────┼──────┤
│ BACK │      │      │      │      │  key 10 — return to the main page
└──────┴──────┴──────┴──────┴──────┘
```

| Key | Label | Does | Live state |
|---|---|---|---|
| 1 | PREV | `playerctl previous` | — |
| 2 | PLAY | `playerctl play-pause` | glyph/label become ⏸ PAUSE while playing |
| 3 | NEXT | `playerctl next` | — |
| 6 | MUTE | Toggles output mute (`wpctl … @DEFAULT_AUDIO_SINK@`) | icon turns red when muted |
| 7 | VOL- | output volume −5% | — |
| 8 | VOL+ | output volume +5% (capped at 150%) | — |
| 10 | BACK | Returns to the main session page | — |

The page polls `playerctl status` on the same ~1s cadence, so the play/pause glyph tracks
the player even when you pause from elsewhere. Presses on the blank keys are ignored.

---

## Work page

Press **WORK (key 6)** to switch the deck to a project launcher — one key per configured
project (keys 0–9), **BACK** on key 10. Each key shows the project's logo (or a nerd-font
glyph in the theme accent for projects without one) above its name.

```
┌──────┬──────┬──────┬──────┬──────┐
│ proj │ proj │ proj │ proj │ proj │  keys 0–4 — projects (logo/glyph + name)
├──────┼──────┼──────┼──────┼──────┤
│ proj │      │      │      │      │  keys 5–9 — more projects (up to 10 total)
├──────┼──────┼──────┼──────┼──────┤
│ BACK │      │      │      │      │  key 10 — return to the main page
└──────┴──────┴──────┴──────┴──────┘
```

Each key's **border** reflects that project's tmux session state, so you can see at a glance
what's already running:

| Border | Meaning |
|---|---|
| cyan | The session your terminal is currently attached to |
| 🔴 red | Live — Claude needs you (`@claude_alert`) |
| 🟡 amber | Live — Claude working (`@claude_busy`) |
| 🟢 green | Live — running but idle |
| none | Not running |

**Press a project key** and the deck drops back to the main page after:

- **If the session is already live** — `sesh connect -s` switches your most-recently-active
  tmux client to it (works even though the daemon runs outside tmux), and Hyprland focuses a
  ghostty window. Same behaviour as pressing its session key on the main page, but reachable
  by project rather than by whatever's currently running.
- **If it isn't** — the same `sesh connect -s` creates it first, honouring the project's
  `startup_command` in `sesh.toml` (the standard `tmux-dev-layout`), then switches + focuses.
- **If no terminal is open at all** (no tmux client anywhere) — Hyprland jumps to workspace 1
  and launches `ghostty -e sesh connect <name>`, which attaches to the session (creating it
  first if needed) in a fresh window.

The projects and their order are the `WORK_PROJECTS` list in the daemon; each entry pairs a
`sesh.toml` session **name** (so the layout and live-state detection line up) with a label, an
optional logo file, and a fallback glyph. Logos are small PNGs committed under
`streamdeck/.local/share/streamdeck-dashboard/logos/` — pre-rasterized from each project's own
logo (SVGs via `rsvg-convert`, and a warm rounded card baked behind dark marks so they read on
a dark key). To add a project: add its `[[session]]` to `sesh.toml`, drop a `<name>.png` in the
logos dir (or rely on the glyph), add a `WORK_PROJECTS` row, then `stow --restow streamdeck`
and restart the service.

---

## VPS page

Press **VPS (key 8)** to switch the deck to an SSH launcher — one key per configured host,
centred in the middle row (keys 6 & 8), **BACK** on key 10. Each key shows the host's logo
(or a server glyph in the theme accent for hosts without one) above its label.

```
┌──────┬──────┬──────┬──────┬──────┐
│      │      │      │      │      │
├──────┼──────┼──────┼──────┼──────┤
│      │ host │      │ host │      │  keys 6 & 8 — one per SSH host (server glyph + label)
├──────┼──────┼──────┼──────┼──────┤
│ BACK │      │      │      │      │  key 10 — return to the main page
└──────┴──────┴──────┴──────┴──────┘
```

**Press a host key** and the deck drops back to the main page after launching a **fresh
ghostty** running `ssh <alias>`. Unlike the work page, a VPS press *always* opens a new
terminal window (one per press) — it never reuses or switches an existing client, so each
SSH session gets its own window. The alias is resolved from `~/.ssh/config`, so all the
connection details (HostName, User, Port, IdentityFile) live there rather than in the daemon.

The hosts and their order are the `VPS_HOSTS` list in the daemon — each entry is
`(ssh_alias, label, logo_file, glyph)`, where `ssh_alias` must be a `Host` entry in
`~/.ssh/config` and `logo_file` is a PNG in `LOGO_DIR` (or `None` to fall back to the glyph).
To add a VPS: add its `Host` block to `~/.ssh/config`, drop a `<name>.png` in the logos dir
(or rely on the glyph), add a `VPS_HOSTS` row, then `stow --restow streamdeck` (only if you
added a logo) and restart the service.

The ghostty windows are launched in their own transient systemd scope (via
`systemd-run --user --scope`, see [How it works](#how-it-works)), so they survive a restart
of the dashboard service.

---

## Theme picker page

Press **THEME** (key 11) to switch the deck to a picker of every `theme-switch` palette —
one key per theme (keys 0–9), **BACK** on key 10. Each key previews the theme with its own
`bg0` as the background and a colour-picker (eyedropper) icon plus the theme name drawn in the
theme's own `accent` colour. The **active** theme gets a border in that accent colour.

```
┌──────┬──────┬──────┬──────┬──────┐
│ 🎨   │ 🎨   │ 🎨   │ …    │ …    │  keys 0–9 — one per palette (icon + name in its accent)
├──────┼──────┼──────┼──────┼──────┤
│ …    │      │      │      │      │
├──────┼──────┼──────┼──────┼──────┤
│ BACK │      │      │      │      │  key 10 — return to the main page
└──────┴──────┴──────┴──────┴──────┘
```

Press a theme key to apply it (`theme-switch <name>`) — it takes effect live across the
desktop, and the deck stays on the picker with the active border moving to your choice, so
you can audition several before pressing **BACK**. The palettes are read from
`<repo>/themes/palettes/*.env`, resolved from the `theme-switch` symlink (or `$DOTFILES`).

---

## How it works

A small Python daemon, `streamdeck-dashboard`, using the
[`python-elgato-streamdeck`](https://github.com/abcminiuser/python-elgato-streamdeck)
library and Pillow for key images. It:

- polls tmux roughly once a second (`POLL = 1.0`) and re-renders **only** the keys whose
  appearance changed, keeping USB traffic minimal;
- reads status with the same guard as `sesh-list-bells`: `@claude_alert` / `@claude_busy`
  hold a pane id, and the status only counts if that pane still exists **and** belongs to
  the session — so a hook that mis-stamps the option onto the wrong session never lights a
  wrong key. The options themselves are set by Claude Code hooks in `~/.claude/settings.json`;
- handles key presses on a background thread, then refreshes immediately so toggles feel
  instant;
- launches every GUI child (ghostty terminals for session/work/VPS) in its **own transient
  systemd scope** via `systemd-run --user --scope`, so those windows live outside the
  service's cgroup and are **not** killed when the service restarts. The unit also sets
  `KillMode=process` (only the daemon is signalled on stop), so any terminal — and the tmux
  server/client inside it — that predates the scope change survives a restart too;
- resets the deck (blanks all keys) on shutdown, so stopping the service clears it.

It runs as a **systemd user service** (`streamdeck-dashboard.service`) ordered after
`graphical-session.target`. The service's `PATH` includes `~/.local/bin` so it can reach
`sesh-picker` and `theme-switch`.

### Why a venv

The daemon runs from a machine-local virtualenv at
`~/.local/share/streamdeck-dashboard/venv` (not committed). It's created with
`--system-site-packages` so it reuses the system `python-pillow` (no Pillow build) and
only pip-installs the small, pure-Python `streamdeck` library, which talks to the system
`hidapi`. The systemd unit's `ExecStart` points at this venv's Python.

---

## Setup

Prerequisites and one-time steps (also summarized in
[install-hyprland.md](install-hyprland.md) §4):

```bash
# 1. System dependencies
sudo pacman -S --needed hidapi python-pillow

# 2. udev rule — lets your user talk to the deck without root (vendor-wide match)
sudo tee /etc/udev/rules.d/40-streamdeck.rules >/dev/null <<'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0fd9", MODE="0660", TAG+="uaccess"
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0fd9", MODE="0660", TAG+="uaccess"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger      # then replug the deck

# 3. Link the package (from the repo root)
stow streamdeck

# 4. Create the venv and start the service
streamdeck-dashboard-setup
systemctl --user enable --now streamdeck-dashboard.service
```

> The udev rule lives in `/etc` (root-owned) so it can't be stowed — recreate it per
> machine with the snippet above. Verify the deck is accessible: `ls -l /dev/hidraw*` for
> the Elgato device should show a trailing `+` (an ACL is applied) after replugging.

---

## Configuration

Everything tunable is a config block at the top of
`streamdeck/.local/bin/streamdeck-dashboard`; edit and restart the service.

| What | Where | Notes |
|---|---|---|
| Poll interval | `POLL` | seconds between tmux polls |
| Session key range | `SESSION_SLOTS` | defaults to keys 0–4 (5 slots, top row) |
| Media button | `MEDIA_KEY` | main-page key that opens the media page (default 5) |
| Work button | `WORK_KEY` | main-page key that opens the work page (default 6) |
| VPS button | `VPS_KEY` | main-page key that opens the VPS page (default 8) |
| Theme button | `THEME_KEY` | main-page action key that opens the theme picker (default 11) |
| Theme key range | `THEME_SLOTS` / `THEME_BACK_KEY` | picker-page slots (0–9) and BACK (10) |
| Work key range | `WORK_SLOTS` / `WORK_BACK_KEY` | work-page slots (0–9) and BACK (10) |
| VPS key range | `VPS_SLOTS` / `VPS_BACK_KEY` | VPS-page host slots (centred: keys 6 & 8) and BACK (10) |
| Projects | `WORK_PROJECTS` | ordered `(session_name, label, logo_file, glyph)` rows for the work page |
| VPS hosts | `VPS_HOSTS` | ordered `(ssh_alias, label, logo_file, glyph)` rows for the VPS page; alias must be a `~/.ssh/config` Host |
| Logos | `LOGO_DIR` | where work-page logo PNGs live (`~/.local/share/streamdeck-dashboard/logos`) |
| Picker command | `PICKER_POPUP` | the `display-popup` args for the PICK key |
| Colors | `COLORS` | fallback palette; `alert`/`busy` are overridden live from the theme |
| Action keys | `ACTIONS` dict | main-page actions — `{key: (glyph, label, is_active_fn, handler_fn)}` |
| Media keys | `MEDIA_ACTIONS` dict | media-page keys, same tuple shape; key 10 (`None` handler) is BACK |
| Active-state glyphs | `ACTIVE_GLYPH` | glyph swap when a toggle is active (e.g. mic-muted) |
| Brightness | `deck.set_brightness(70)` in `main()` | 0–100 |

To **add or re-map an action key**, edit the `ACTIONS` dict. For example, key 12 is free —
add a tuple to make it run a script:

```python
12: ("", "TERM", None, lambda: sh("my-script")),
```

The `is_active_fn` (3rd item) returns a bool to tint the key's icon with the accent color
(used by MIC/MUTE); pass `None` for a plain action. Note that `MEDIA_KEY`, `WORK_KEY` and
`THEME_KEY` are page-openers intercepted in `_press_main` (their glyph entry only controls how
the key looks), so re-mapping those means changing the intercept, not just the tuple.

After any edit:

```bash
systemctl --user restart streamdeck-dashboard.service
```

---

## Managing the service

```bash
systemctl --user status streamdeck-dashboard.service      # is it running?
systemctl --user restart streamdeck-dashboard.service     # after editing the daemon
systemctl --user stop streamdeck-dashboard.service        # blanks the deck
systemctl --user disable --now streamdeck-dashboard.service
journalctl --user -u streamdeck-dashboard -f              # live logs
```

The daemon logs a line on connect (`connected: Stream Deck … (15 keys)`) and on clean
shutdown, and logs a traceback (without dying) if a poll cycle errors.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Keys stay blank, service keeps restarting | Deck not accessible — check the udev rule and **replug**; `journalctl --user -u streamdeck-dashboard` will show the error. |
| `No module named 'StreamDeck'` | venv missing or stale — re-run `streamdeck-dashboard-setup`. |
| Names/positions mirrored | Key indexing assumes top-left origin; if a future deck differs, remap `SESSION_SLOTS`. |
| PICK / MIC do nothing | The service needs the graphical env; it inherits `WAYLAND_DISPLAY` from the user session. Check `systemctl --user show-environment | grep WAYLAND`. |
| Wrong session lit | Status uses pane-ownership; if it persists, check the `@claude_*` hooks in `~/.claude/settings.json` (they must resolve the session via `-t "$TMUX_PANE"`). |
| Work page shows glyphs, no logos | Logos not stowed — `stow --restow streamdeck` so `~/.local/share/streamdeck-dashboard/logos/` is populated (new files aren't linked by a plain `stow`). A missing logo silently falls back to the glyph. |
| WORK key does nothing / opens wrong dir | The project's `name` in `WORK_PROJECTS` must match its `sesh.toml` session name; `sesh connect` resolves the path/layout from there. Focus needs `hyprctl` + `ghostty` on the service PATH (both in `/usr/bin`). |
| Colors don't match theme | `theme-switch` writes `~/.config/theme/sesh-colors.sh`; the daemon re-reads it each poll. |

---

See the **Stream Deck** section of the [README](../README.md) for the short version.
