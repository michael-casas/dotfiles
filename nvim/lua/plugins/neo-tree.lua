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
  -- Disable mini.files so it doesn't fight with neo-tree
  -- NOTE: Plugin renamed from echasnovski/mini.files to nvim-mini/mini.files
  { "nvim-mini/mini.files", enabled = false },
}
