-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Buffer cycling with Option+[ and Option+]
-- Note: M-[ can conflict with terminal escape sequences on some terminals.
-- If you experience issues, switch to M-( and M-) or M-p/M-n.
vim.keymap.set("n", "<M-[>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
vim.keymap.set("n", "<M-]>", "<cmd>bnext<cr>", { desc = "Next buffer" })
