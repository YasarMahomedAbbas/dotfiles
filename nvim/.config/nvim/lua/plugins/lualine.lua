return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    local function git_repo()
      local handle = io.popen("git remote get-url origin 2>/dev/null")
      if not handle then return "" end
      local result = handle:read("*a")
      handle:close()
      if result == "" then return "" end
      -- Extract repo name from URL (handles both https and ssh)
      return result:match("([^/]+)%.git") or result:match("([^/]+)%s*$") or ""
    end

    table.insert(opts.sections.lualine_b, 1, {
      git_repo,
      color = { fg = "#4EC9B0", gui = "bold" },
      icon = { "", color = { fg = "#4EC9B0" } },
    })

    -- Style the branch component yellow
    for i, component in ipairs(opts.sections.lualine_b) do
      if component == "branch" or (type(component) == "table" and component[1] == "branch") then
        opts.sections.lualine_b[i] = {
          "branch",
          color = { fg = "#DCDCAA", gui = "bold" },
          icon = { "", color = { fg = "#DCDCAA" } },
        }
        break
      end
    end
  end,
}
