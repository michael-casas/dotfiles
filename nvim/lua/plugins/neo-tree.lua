local explorer = require("config.explorer")

return {
  -- Disable neo-tree; use snacks.nvim explorer instead
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },
  -- Configure the Snacks explorer sidebar
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            hidden = true,
            ignored = true,
            layout = { layout = { width = 30, min_width = 30 } }, -- fixed 30-column sidebar
            follow_file = false, -- the sidebar follows without taking focus from the editor
            on_show = explorer.on_show,
            actions = { explorer_leave_filter = explorer.leave_filter },
            win = {
              input = { keys = { ["<Esc>"] = { "explorer_leave_filter", mode = { "i", "n" } } } },
              list = { keys = { ["<Esc>"] = false } },
            },
          },
        },
      },
    },
  },
}
