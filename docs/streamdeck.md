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
│MEDIA │      │      │      │      │  key 5 opens the media page; 6–9 blank
├──────┼──────┼──────┼──────┼──────┤
│ PICK │THEME │ REC  │ MIC  │ MUTE │  keys 10–14 — actions
└──────┴──────┴──────┴──────┴──────┘
```

**Sessions (keys 0–4)** — one key per running tmux session, sorted alphabetically so
positions stay stable (muscle memory), up to five (extra sessions aren't shown). The key
shows the session name; its background color is the Claude status:

| Color | Meaning | Driven by |
|---|---|---|
| 🔴 red | Needs you — Claude finished or is waiting | `@claude_alert` |
| 🟡 amber | Working | `@claude_busy` |
| ⚫ dim slate | Idle session | — |
| cyan border | The session your terminal is currently attached to | most-recent tmux client |

Colors follow the active theme (`~/.config/theme/sesh-colors.sh` — the same
`SESH_BELL_COLOR` / `SESH_BUSY_COLOR` the sesh picker uses), and update live when you
run `theme-switch`.

**Press a session key** → switches your most-recently-active tmux client to that session.

**MEDIA (key 5)** — opens the media page (below). The rest of the middle row (keys 6–9)
is blank.

**Actions (keys 10–14):**

| Key | Label | Does | Live state |
|---|---|---|---|
| 10 | PICK | Opens the sesh picker popup (`display-popup … sesh-picker`) on the attached client | — |
| 11 | THEME | Opens the theme picker page (below) | — |
| 12 | REC | Toggles `screen-record` (wf-recorder) | icon turns red while recording |
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
- resets the deck (blanks all keys) on shutdown, so stopping the service clears it.

It runs as a **systemd user service** (`streamdeck-dashboard.service`) ordered after
`graphical-session.target`. The service's `PATH` includes `~/.local/bin` so it can reach
`sesh-picker`, `theme-switch`, and `screen-record`.

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
| Theme button | `THEME_KEY` | main-page action key that opens the theme picker (default 11) |
| Theme key range | `THEME_SLOTS` / `THEME_BACK_KEY` | picker-page slots (0–9) and BACK (10) |
| Picker command | `PICKER_POPUP` | the `display-popup` args for the PICK key |
| Colors | `COLORS` | fallback palette; `alert`/`busy` are overridden live from the theme |
| Action keys | `ACTIONS` dict | main-page actions — `{key: (glyph, label, is_active_fn, handler_fn)}` |
| Media keys | `MEDIA_ACTIONS` dict | media-page keys, same tuple shape; key 10 (`None` handler) is BACK |
| Active-state glyphs | `ACTIVE_GLYPH` | glyph swap when a toggle is active (e.g. mic-muted) |
| Brightness | `deck.set_brightness(70)` in `main()` | 0–100 |

To **re-map an action key**, edit its tuple in `ACTIONS`. For example, to make key 12 run
a script instead of toggling `screen-record`:

```python
12: ("", "TERM", None, lambda: sh("my-script")),
```

The `is_active_fn` (3rd item) returns a bool to tint the key's icon with the accent color
(used by REC/MIC/MUTE); pass `None` for a plain action. Note that `MEDIA_KEY` and `THEME_KEY`
are page-openers intercepted in `_press_main` (their `ACTIONS`/glyph entry only controls how
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
| PICK / REC do nothing | The service needs the graphical env; it inherits `WAYLAND_DISPLAY` from the user session. Check `systemctl --user show-environment | grep WAYLAND`. |
| Wrong session lit | Status uses pane-ownership; if it persists, check the `@claude_*` hooks in `~/.claude/settings.json` (they must resolve the session via `-t "$TMUX_PANE"`). |
| Colors don't match theme | `theme-switch` writes `~/.config/theme/sesh-colors.sh`; the daemon re-reads it each poll. |

---

See the **Stream Deck** section of the [README](../README.md) for the short version.
