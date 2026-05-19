-- Lualine statusline customization
-- Adds a 12-hour clock to the rightmost section (lualine_z).
return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  opts = function(_, opts)
    opts.sections = opts.sections or {}
    opts.sections.lualine_z = opts.sections.lualine_z or { "location" }

    -- Append 12-hour clock after the default location component
    table.insert(opts.sections.lualine_z, {
      function()
        return os.date("%I:%M %p")
      end,
    })
  end,
}
