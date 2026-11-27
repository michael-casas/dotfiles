if vim.bo.filetype ~= "markdown" then
  return
end

vim.keymap.set("i", "<C-g>", function()
  require("emmet-md.editor").chord()
end, { buffer = 0, desc = "Insert Ctrl+g commands and Markdown Emmet (e)" })

local undo = "silent! iunmap <buffer> <C-g>"
vim.b.undo_ftplugin = vim.b.undo_ftplugin and (vim.b.undo_ftplugin .. " | " .. undo) or undo
