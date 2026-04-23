return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      window = {
        width = 34, -- default is 40; ~15% reduction
      },
      filesystem = {
        window = {
          mappings = {
            -- Explicit split keymaps for clarity
            ["s"] = "open_split",
            ["v"] = "open_vsplit",
          },
        },
      },
    },
  },
  -- Disable snacks.nvim explorer so only neo-tree shows
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.explorer = opts.explorer or {}
      opts.explorer.enabled = false
    end,
  },
}
