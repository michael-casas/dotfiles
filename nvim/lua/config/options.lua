-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Use system clipboard for all yank/delete/paste operations
vim.opt.clipboard = "unnamedplus"

-- Terminal key sequence timeout: 500ms balance between responsiveness and sequence detection
vim.o.ttimeoutlen = 500
