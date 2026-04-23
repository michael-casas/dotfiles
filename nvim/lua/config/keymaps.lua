-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Buffer cycling with Option+[ and Option+]
-- Note: M-[ can conflict with terminal escape sequences on some terminals.
-- If you experience issues, switch to M-( and M-) or M-p/M-n.
vim.keymap.set("n", "<M-[>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
vim.keymap.set("n", "<M-]>", "<cmd>bnext<cr>", { desc = "Next buffer" })

-- Terminal mode: Ctrl+. exits to Normal mode
vim.keymap.set("t", "<C-.>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Reload nvim config on the fly (best-effort)
vim.keymap.set("n", "<M-S-r>", function()
  -- Clear Lua cache for user config modules
  for name, _ in pairs(package.loaded) do
    if name:match("^config") or name:match("^plugins") then
      package.loaded[name] = nil
    end
  end
  -- Re-source init.lua
  dofile(vim.env.MYVIMRC)
  vim.notify("Config reloaded", vim.log.levels.INFO)
end, { desc = "Reload Neovim config" })
