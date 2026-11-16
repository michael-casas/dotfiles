-- Built-in runtime only. No plugin manager, service, provider or project config.
vim.opt.loadplugins = false
vim.opt.modeline = false
vim.opt.exrc = false
vim.opt.swapfile = false
vim.opt.undofile = false
vim.opt.shadafile = "NONE"
vim.opt.clipboard = ""
vim.opt.termguicolors = false -- pilot must validate RGB through the full transport
vim.opt.number = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.hlsearch = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.mouse = ""
vim.g.loaded_python3_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.mapleader = " "
vim.cmd("syntax enable")
-- ANSI/256 fallback; no palette-changing OSC and no clipboard provider.
for name, attrs in pairs({
  Normal = { ctermfg = 252, ctermbg = 236 },
  Comment = { ctermfg = 244, italic = true },
  String = { ctermfg = 150 },
  Statement = { ctermfg = 110, bold = true },
  Search = { ctermfg = 236, ctermbg = 180 },
  Visual = { ctermbg = 60 },
  LineNr = { ctermfg = 244 },
}) do
  vim.api.nvim_set_hl(0, name, attrs)
end
vim.keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "Save" })
vim.keymap.set("n", "<leader>/", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
vim.keymap.set("n", "<leader>v", "<cmd>vsplit<cr>", { desc = "Vertical split" })
vim.keymap.set("n", "<leader>s", "<cmd>split<cr>", { desc = "Horizontal split" })
