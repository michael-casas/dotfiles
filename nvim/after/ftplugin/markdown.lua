vim.keymap.set("i", "<C-g>e", function()
  require("envi.markdown_emmet").expand()
end, { buffer = 0, desc = "Expand Markdown Emmet abbreviation" })

local undo = "silent! iunmap <buffer> <C-g>e"
vim.b.undo_ftplugin = vim.b.undo_ftplugin and (vim.b.undo_ftplugin .. " | " .. undo) or undo
