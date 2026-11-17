# Stream Deck — physical herdr / agent dashboard

Turns a 15-key Elgato Stream Deck (MK.2 / Original, 3×5, 72×72px keys) into a live
dashboard for herdr and its coding agents: a glance at your desk tells you which project
needs you, and one press puts herdr on it.

Package: `streamdeck/` → `~/.local/bin/` (daemon + setup script),
`~/.config/systemd/user/` (service unit) and `~/.local/share/streamdeck-dashboard/logos/`.

---

## Main page

```
┌──────┬──────┬──────┬──────┬──────┐
│space │space │space │space │space │  keys 0–4  herdr spaces, in herdr's order
├──────┼──────┼──────┼──────┼──────┤
│MEDIA │ WORK │AGENTS│ VPS  │DESIGN│  5 media · 6 work · 7 agents · 8 VPS · 9 newest design
├──────┼──────┼──────┼──────┼──────┤
│ PICK │THEME │      │ MIC  │ MUTE │  10 sessions picker · 11 theme page · 13/14 mute toggles
└──────┴──────┴──────┴──────┴──────┘
```

Key 12 is free.

### Space keys (0–4)

One key per herdr space, in the order herdr lists them, so positions follow your space
order (alt-1…9). With more than five spaces, the ones that want you are guaranteed a key —
needs-you first, then finished-unseen, then busy, then idle — and the five shown keep
herdr's order.

The colour is the space's **most urgent agent** (an agent is any terminal herdr knows runs
Claude, Codex, pi, …):

| Colour | Meaning | Source |
|---|---|---|
| 🔴 red, pulsing rim | Needs you — permission, question, plan | herdr `blocked` (or `error`) |
| 🟢 green | Finished since you last looked | herdr `done` |
| 🟡 yellow | Working past the command's typical time | herdr `working` + board `current.typical_ms` |
| ⚪ frost | Working | herdr `working` |
| 🔵 steel blue | Turn ended, sub-agents / shells still running | board `state: background` |
| ⚫ dim | Idle, or no agents | — |
| cyan border | The space herdr is showing | `herdr-app ls` `active` |

An **active** space (red/yellow/frost/blue) is a card: the space name (`×2` when several
of its agents are busy), what the urgent agent wants or is doing (the question's title,
the command, `2 agents`), a ticking timer with the ticket number, then the six-stage
pipeline strip and, while implementing, the task strip. A **quiet** space (green/dim)
shows the project's logo — or its name — over a band (`✓ 5m ago`, `✓ 2 done`, or the
ticket's stage).

**Press** a space key: herdr shows that space's most urgent non-idle agent
(`agent.focus`), or just the space (`space.select`, keeping its tab) when everything in it
is idle, and the herdr window comes to the front. If the window is closed, the press opens
it first — hc kept the terminals running — then does the same.

### Other main-page keys

| Key | Does |
|---|---|
| 5 MEDIA | media page |
| 6 WORK | work page |
| 7 AGENTS | agents page |
| 8 VPS | VPS page |
| 9 DESIGN | brush in the theme accent, with an accent border, when any Claude session published a design canvas; press opens the newest (`board design <key>`). Dim otherwise |
| 10 PICK | herdr's sessions picker (`mod.open sessions`, the same as C-f s): open spaces, projects, recent folders |
| 11 THEME | theme page |
| 13 MIC | toggles mic mute (`wpctl … @DEFAULT_AUDIO_SOURCE@`); red slashed icon when muted |
| 14 MUTE | toggles output mute (`wpctl … @DEFAULT_AUDIO_SINK@`); red icon when muted |

---

## Where the state comes from

One poll a second reads:

- **`herdr-app ls`** — spaces, their tabs and terminals, each terminal's agent `status`
  (`working` / `blocked` / `done` / `idle`) and which space is shown. Instant (it asks the
  running window over its socket).
- **`hc ls --json`** instead, **while the herdr window is closed**: each live terminal's
  status and `where` (`space / tab`), so the deck keeps working headless. Spaces then come
  in hc's order, nothing gets the cyan border, and "done" can't tell seen from unseen.
- **`board list --json`** (the agent board, [agent-board.md](agent-board.md)) — the
  detail herdr doesn't have: the question's title, the command in flight and its typical
  duration, background agents, the ticket and its stage/task progress, design canvases.
  A board entry is matched to its herdr terminal through the Claude process's
  `HC_TERMINAL_ID` (`/proc/<pid>/environ`), so the agent-board mod needs no herdr support.
  Agents the board doesn't know (Codex, pi) still colour their space from herdr alone.

Colours follow the active theme (`~/.config/theme/sesh-colors.sh`, re-read every poll), so
`theme-switch` shows on the deck at once.

---

## Agents page

Press **AGENTS** (key 7, the centre) for a card per running agent — every key but BACK
(10), so up to 14 — meant to stay open while you work. Cards keep herdr's order (space,
then tab), so an agent keeps its key; with more than 14, the ones that need you or have
finished are guaranteed a key.

Each card is the same as an active space key, for one agent: the title is the ticket
(`#2219`), else the tab's name (`hub retro fixes`), else the space's name, in the
project's colour; then what it wants or is doing, the timer, and the stage and task
strips. Quiet agents show a band on top, over their title: `idle 14m` (how long since it last did anything) or `✓ 5m ago` on green when it finished and you haven't looked. No logos on this page, so every key says what it is. The agent herdr is
showing has the cyan border.

**Press** a card: herdr shows that agent and comes to the front; the deck stays on this
page. BACK returns to the main page.

---

## Media page

```
┌──────┬──────┬──────┬──────┬──────┐
│      │ PREV │ PLAY │ NEXT │      │  keys 1–3  playerctl previous / play-pause / next
├──────┼──────┼──────┼──────┼──────┤
│      │ MUTE │ VOL- │ VOL+ │      │  keys 6–8  output mute, volume −5% / +5% (cap 150%)
├──────┼──────┼──────┼──────┼──────┤
│ BACK │      │      │      │      │
└──────┴──────┴──────┴──────┴──────┘
```

Drives whatever MPRIS player is active (Spotify, browsers, mpv). PLAY turns into PAUSE
while something plays, polled each second.

---

## Work page

One key per project in `WORK_PROJECTS` (keys 0–9), BACK on 10. Each shows the project's
logo, or a glyph in the theme accent, over its label; the border is its space's state:

| Border | Meaning |
|---|---|
| cyan | herdr is showing this space |
| red / yellow / frost / blue | open, and an agent in it needs you / is slow / working / in the background |
| green | open and quiet |
| none | no space for it |

**Press** a project: if a space with that name is open, herdr shows it; otherwise herdr
opens a space named after the project, in its folder, with `claude` running — exactly what
picking a project in herdr's sessions picker does. The deck then returns to the main page.

The folder comes from the same files the sessions picker reads: herd's
`~/.config/herd/projects.json` (`root` + `workdir`), then the sessions mod's
`projects.json` (`dotfiles`, `gegrond`, `vault`, …); a name in both uses the latter.

To add a project: make sure it's in one of those files, drop a `<name>.png` in
`streamdeck/.local/share/streamdeck-dashboard/logos/` (or give it a glyph), add a
`WORK_PROJECTS` row, then `stow --restow streamdeck` and restart the service. A space whose
name matches a `WORK_PROJECTS` logo shows that logo on the main page too. Logos are small
PNGs pre-rasterised from each project's own logo (SVGs via `rsvg-convert`, with a warm
rounded card behind dark marks so they read on a dark key).

---

## VPS page

One key per machine in `VPS_HOSTS` (keys 6 and 8), BACK on 10; bordered like the work
page by the state of a space on that machine.

**Press** a machine: herdr shows the first open space on it, or opens a new space there
(`space.new --machine <name>`). The names are hc's (`hc machine ls`), which holds the ssh
details; add a machine with `hc machine add`, then a `VPS_HOSTS` row.

---

## Theme page

One key per `theme-switch` palette (keys 0–9), BACK on 10, each drawn in its own colours
(its `bg0`, an eyedropper and the name in its `accent`); the active one has an accent
border. A press applies it live and stays on the page, so you can audition several. The
palettes are `<repo>/themes/palettes/*.env`, found through the `theme-switch` symlink (or
`$DOTFILES`).

---

## How it works

A small Python daemon using
[`python-elgato-streamdeck`](https://github.com/abcminiuser/python-elgato-streamdeck) and
Pillow:

- each poll, the page on screen returns its keys as `{key: (signature, render)}` and its
  presses as `{key: action}`; a key is only redrawn when its signature changed (a ticking
  timer redraws once a second, everything else almost never), and keys a page leaves out
  are blanked, so switching pages leaves nothing stale;
- presses run on the library's callback thread and refresh immediately; anything that
  waits on herdr (opening the window) runs on its own thread so the deck never freezes;
- the herdr window, when the deck opens it, starts in its **own transient systemd scope**
  (`systemd-run --user --scope`), and the unit has `KillMode=process`, so restarting the
  service never closes it;
- a dead or wedged USB handle (unplug, suspend) is detected by failed writes and the deck
  is reopened; stopping the service blanks the deck.

It runs as a **systemd user service** (`streamdeck-dashboard.service`) after
`graphical-session.target`, with `~/.local/bin` on its `PATH` for `herdr-app`, `hc`,
`board` and `theme-switch`.

### Why a venv

The daemon runs from a machine-local virtualenv at
`~/.local/share/streamdeck-dashboard/venv` (not committed), created with
`--system-site-packages` so it reuses the system `python-pillow` and only pip-installs the
pure-Python `streamdeck` library, which talks to the system `hidapi`.

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

Everything tunable is the config block at the top of
`streamdeck/.local/bin/streamdeck-dashboard`; edit, then restart the service.

| What | Where |
|---|---|
| Poll interval, brightness | `POLL`, `BRIGHTNESS` |
| Space keys | `SPACE_SLOTS` (keys 0–4) |
| Main-page keys | `MEDIA_KEY`, `WORK_KEY`, `AGENTS_KEY`, `VPS_KEY`, `DESIGN_KEY`, `PICK_KEY`, `THEME_KEY`, `MIC_KEY`, `MUTE_KEY` |
| Sub-page keys | `PAGE_SLOTS` (work + theme, 0–9), `VPS_SLOTS` (6, 8), `AGENT_SLOTS` (all but BACK), `BACK_KEY` (10) |
| Projects | `WORK_PROJECTS` — `(space name, label, logo file, glyph)` |
| Machines | `VPS_HOSTS` — `(hc machine, label, logo file, glyph)` |
| Picker | `PICKER_MOD` — the herdr mod PICK opens |
| herdr window class | `HERDR_CLASS` — what Hyprland focuses after a press |
| Name colours | `NAME_COLORS` — a project's / machine's colour for its name (`accent` = the theme's) |
| Fallback colours | `COLORS` (the status roles and accent are overridden from the theme) |

What each page draws and does is its `page_*` method on `Dashboard`. To give the free key
(12) an action, add a line to `page_main`:

```python
put(12, render_action, G_SEARCH, "TERM", on=lambda: sh("my-script"))
```

`render_action(deck, glyph, label, color=None, border=None)`: a colour tints the glyph
(MIC/MUTE use `COLORS["on"]` when muted).

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
| Keys stay blank, service keeps restarting | Deck not accessible — check the udev rule and **replug**; `journalctl --user -u streamdeck-dashboard` shows the error. |
| `No module named 'StreamDeck'` | venv missing or stale — re-run `streamdeck-dashboard-setup`. |
| Space keys all dim | Compare with `herdr-app ls` (window open) or `hc ls` (closed): the colour is herdr's `status` for the space's agent terminals. A program that doesn't report status to herdr shows nothing. |
| A busy space has no detail / timer / stage strip | The board has no entry for that terminal: check `board list --json` and that the Claude process has `HC_TERMINAL_ID` (it does when started in an hc terminal). Codex / pi agents only ever get herdr's colour. |
| Press does nothing | `journalctl --user -u streamdeck-dashboard` logs every failed `herdr-app do`. Focusing needs `hyprctl` and the `herdr-app` window class. |
| WORK opens a space in the wrong folder | The project's name isn't in herd's `projects.json` or the sessions mod's `projects.json` (logged as `no folder for project …`). |
| Work page shows glyphs, no logos | Logos not stowed — `stow --restow streamdeck`; a missing logo falls back to the glyph. |
| Colours don't match theme | `theme-switch` writes `~/.config/theme/sesh-colors.sh`; the daemon re-reads it each poll. |

---

See the **Stream Deck** section of the [README](../README.md) for the short version.
