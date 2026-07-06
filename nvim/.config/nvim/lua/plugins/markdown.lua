return {
  -- Disable the old in-buffer renderer in favor of markview.nvim.
  { "MeanderingProgrammer/render-markdown.nvim", enabled = false },

  {
    "OXY2DEV/markview.nvim",
    -- markview lazy-loads itself; the author recommends loading it eagerly.
    lazy = false,
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-mini/mini.icons",
    },
    opts = {
      preview = {
        icon_provider = "mini",
        -- Show raw markdown only on the line/area you're editing, render the rest.
        hybrid_modes = { "n", "i" },
      },
    },
    config = function(_, opts)
      require("markview").setup(opts)

      -- Keep the transparent theme intact: strip the background off every
      -- markview highlight group (code blocks, inline code, callouts, etc.),
      -- then make headings pop with the per-level palette color + bold instead
      -- of a tinted box. (Terminal text can't be physically larger; bold +
      -- color is how we make them stand out.)
      local function transparent_markview()
        for name in pairs(vim.api.nvim_get_hl(0, {})) do
          if name:find("^Markview") then
            local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
            if hl.bg then
              hl.bg = "NONE"
              vim.api.nvim_set_hl(0, name, hl)
            end
          end
        end
        for i = 1, 6 do
          local fg = vim.api.nvim_get_hl(0, { name = "MarkviewPalette" .. i .. "Fg", link = false }).fg
          vim.api.nvim_set_hl(0, "MarkviewHeading" .. i, { fg = fg, bg = "NONE", bold = true })
        end
      end

      -- markview builds its palette highlights lazily, so run once it attaches
      -- to a buffer (and again on colorscheme swaps), not eagerly at setup.
      vim.api.nvim_create_autocmd("User", {
        pattern = { "MarkviewAttach", "MarkviewEnable" },
        callback = function()
          vim.schedule(transparent_markview)
        end,
      })
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          vim.schedule(transparent_markview)
        end,
      })
    end,
  },
}
