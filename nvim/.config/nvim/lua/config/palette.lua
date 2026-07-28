-- Reads the palette that `theme-switch` renders to ~/.config/theme/nvim-colors.lua,
-- so nvim's colors come from the same source as ghostty/tmux/waybar/starship
-- instead of whatever the colorscheme plugin happens to hardcode.
--
-- Falls back to Nord if theme-switch has never run on this machine, which keeps
-- a fresh clone looking right before the first `theme-switch <name>`.
local fallback = {
  name = "nord",

  bg0 = "#2e3440",
  bg1 = "#3b4252",
  bg2 = "#434c5e",
  bg3 = "#4c566a",

  fg0 = "#eceff4",
  fg1 = "#d8dee9",
  fg2 = "#4c566a",

  accent = "#88c0d0",
  accent2 = "#5e81ac",
  blue = "#81a1c1",
  teal = "#8fbcbb",
  red = "#bf616a",
  orange = "#d08770",
  yellow = "#ebcb8b",
  green = "#a3be8c",
  purple = "#b48ead",

  muted = "#616e88",
  dim = "#6c7a96",
}

local M = {}

local cached

---@return table
function M.get()
  if cached then
    return cached
  end

  local path = vim.fn.expand("~/.config/theme/nvim-colors.lua")
  local ok, palette = pcall(dofile, path)
  cached = (ok and type(palette) == "table") and palette or fallback

  return cached
end

return M
