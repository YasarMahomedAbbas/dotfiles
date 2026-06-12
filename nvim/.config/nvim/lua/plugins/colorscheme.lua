-- Colorscheme follows the desktop theme written by `theme-switch` to
-- ~/.config/theme/active. nord / dark-nord both use nord.nvim (transparent, so
-- the themed near-black terminal background shows through); vscode-dark uses
-- vscode.nvim. Changing the desktop theme applies to nvim on next launch.
local function active_theme()
  local f = io.open(vim.fn.expand("~/.config/theme/active"), "r")
  if not f then
    return "nord"
  end
  local name = f:read("l")
  f:close()
  return name or "nord"
end

local colorscheme = active_theme() == "vscode-dark" and "vscode" or "nord"

return {
  {
    "gbprod/nord.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent = true,
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
