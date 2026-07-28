-- Colorscheme follows the desktop theme rendered by `theme-switch`.
-- nord / dark-nord use nord.nvim; vscode-dark uses vscode.nvim.
--
-- nord.nvim ships the *original* Nord Polar Night surfaces (#2e3440 …), which
-- clash under the dark-nord palette, where the desktop surfaces are near-black
-- (#0a0b0e …). Floats — the snacks picker, completion menu, which-key — are
-- opaque, so they painted light Nord grey panels over a near-black editor.
-- on_colors remaps nord.nvim's palette onto the active theme's roles so every
-- derived highlight follows the desktop theme instead.
local palette = require("config.palette").get()

local colorscheme = palette.name == "vscode-dark" and "vscode" or "nord"

return {
  {
    "gbprod/nord.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent = true,
      on_colors = function(c)
        -- Mutated in place: nord.nvim's modules hold a reference to this table.
        c.polar_night.origin = palette.bg0 -- base background
        c.polar_night.bright = palette.bg1 -- CursorLine, Pmenu, elevated surfaces
        c.polar_night.brighter = palette.bg2 -- Visual, PmenuSel, StatusLine
        c.polar_night.brightest = palette.bg3 -- borders, StatusLineNC
        c.polar_night.light = palette.dim -- muted *foreground*: comments, ghost text

        c.snow_storm.origin = palette.fg1
        c.snow_storm.brighter = palette.fg0
        c.snow_storm.brightest = palette.fg0

        c.frost.polar_water = palette.teal
        c.frost.ice = palette.accent
        c.frost.artic_water = palette.blue
        c.frost.artic_ocean = palette.accent2

        c.aurora.red = palette.red
        c.aurora.orange = palette.orange
        c.aurora.yellow = palette.yellow
        c.aurora.green = palette.green
        c.aurora.purple = palette.purple
      end,
      on_highlights = function(hl, c)
        -- The editor itself is transparent, so floats need their own surface to
        -- read as panels. bg1 is the elevated-surface role the other templates
        -- use (fzf bg+, pi selectedBg); bg3 is the border role.
        local float_bg = c.polar_night.bright

        hl.NormalFloat = { fg = c.snow_storm.origin, bg = float_bg }
        hl.FloatBorder = { fg = c.polar_night.brightest, bg = float_bg }
        hl.FloatTitle = { fg = c.frost.ice, bg = float_bg, bold = true }

        hl.Pmenu = { fg = c.snow_storm.origin, bg = float_bg }
        hl.PmenuSel = { fg = c.snow_storm.brightest, bg = c.polar_night.brighter, bold = true }
      end,
    },
  },
  {
    "Mofiqul/vscode.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent = true,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = colorscheme,
    },
  },
}
