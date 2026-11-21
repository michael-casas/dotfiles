-- Dadbod UI's connection markers (✓/✕) use fixed colours by default. Link them to
-- diagnostic groups so they follow the active colorscheme, and relink after each
-- :colorscheme, which clears them.
local function link_status()
  vim.api.nvim_set_hl(0, "dbui_connection_ok", { link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "dbui_connection_error", { link = "DiagnosticError" })
end

link_status()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("EnviDadbodColors", { clear = true }),
  callback = link_status,
})
