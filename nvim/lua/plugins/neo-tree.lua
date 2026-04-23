return {
  -- Disable neo-tree; use snacks.nvim explorer instead
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },
  -- Ensure snacks explorer is enabled
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.explorer = opts.explorer or {}
      opts.explorer.enabled = true
    end,
  },
}
