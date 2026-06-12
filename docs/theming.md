# Theming — switchable color presets

One palette drives the colors of every app in the rice. Switch the whole desktop
with a single command:

```bash
theme-switch              # list themes (active one marked)
theme-switch dark-nord    # switch
```

## Available themes

| Theme         | Look |
|---------------|------|
| `nord`        | The original Nord palette (Polar Night `#2e3440` background). |
| `dark-nord`   | Nord's Frost/Aurora accents on a near-black `#0a0b0e` background. |
| `vscode-dark` | VS Code "Dark Modern" — neutral greys + `#569cd6` blue. |

## How it works

```
themes/
  palettes/<name>.env     # the single source of truth: ~16 named roles per theme
  templates/*.tmpl        # one per app, with ${role} placeholders
bin/.local/bin/theme-switch
~/.config/theme/          # GENERATED output (not stowed, not in git)
```

`theme-switch <name>` sources the palette, renders every template with `envsubst`
(an explicit variable allow-list keeps unrelated `$names`, e.g. starship's
`$directory`, intact), writes the results to `~/.config/theme/`, records the
choice in `~/.config/theme/active`, then live-reloads the running apps.

Each app's committed config stays static and pulls colors from `~/.config/theme/`:

| App      | Include mechanism                                            | Reload |
|----------|-------------------------------------------------------------|--------|
| ghostty  | `config-file = ?~/.config/theme/ghostty.conf`               | `ctrl+shift+,` (or new window) |
| hyprland | `source = ~/.config/theme/hypr-colors.conf` (`$nordN`)      | live (`hyprctl reload`) |
| hyprlock | `source = ~/.config/theme/hyprlock-colors.conf` (`$lock_*`) | next lock |
| waybar   | GTK CSS `@import` of `gtk-colors.css` (`@define-color`)      | live (`SIGUSR2`) |
| wofi     | GTK CSS `@import` of `gtk-colors.css`                        | next launch |
| mako     | `include=~/.config/theme/mako.conf`                         | live (`makoctl reload`) |
| tmux     | `source-file ~/.config/theme/tmux.conf` (whole style block) | live (`prefix+r`) |
| starship | `$STARSHIP_CONFIG` → `~/.config/theme/starship.toml`        | next prompt |
| fzf      | fish sources `~/.config/theme/fzf.fish`                      | new shell |
| nvim     | reads `~/.config/theme/active`: nord vs `vscode.nvim`        | next launch |

Because the generated files live outside the repo, switching themes never dirties
git. `bat` is intentionally left on its built-in Nord theme.

## Adding a theme

1. Copy a palette: `cp themes/palettes/nord.env themes/palettes/mytheme.env`.
2. Edit the role values (hex **without** the leading `#`).
3. `theme-switch mytheme`.

No template changes needed — every app picks up the new palette automatically.

## Tweaking an existing theme

Edit the role(s) in `themes/palettes/<name>.env`, then re-run `theme-switch <name>`.
For example, `blur` and `opacity` (ghostty's transparency) are per-theme roles.
