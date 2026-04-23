return {
  -- Disable neo-tree; use snacks.nvim explorer instead
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },
  -- Configure snacks.nvim explorer to show hidden files
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            hidden = true,
            ignored = true,
          },
        },
      },
    },
  },
}
