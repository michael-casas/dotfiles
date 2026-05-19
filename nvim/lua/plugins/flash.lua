-- Rebind flash.nvim from 's' to <S-M-/> to preserve native 's' behavior.
-- <S-M-/> is unclaimed in both nvim and tmux keymaps.
return {
  "folke/flash.nvim",
  optional = true,
  keys = {
    -- Restore native 's' (substitute char + insert mode)
    { "s", mode = { "n" }, "cl", desc = "Substitute character" },
    -- Flash jump-to-char on Shift+Option+/
    {
      "<S-M-/>",
      mode = { "n", "x", "o" },
      function()
        require("flash").jump()
      end,
      desc = "Flash",
    },
    -- Flash Treesitter node jump on Shift+Option+?
    {
      "<S-M-?>",
      mode = { "n", "x", "o" },
      function()
        require("flash").treesitter()
      end,
      desc = "Flash Treesitter",
    },
  },
}
