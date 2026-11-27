if vim.bo.filetype ~= "markdown" then
  return
end

vim.keymap.set("i", "<C-g>", function()
  -- Read a whole key so the chord does not time out as a mapping prefix.
  local key = vim.fn.getcharstr()
  if key == "e" then
    return "<Cmd>lua require('envi.markdown_emmet').expand()<CR>"
  end
  return "<C-g>" .. key
end, { buffer = 0, expr = true, desc = "Insert Ctrl+g commands and Markdown Emmet (e)" })

local undo = "silent! iunmap <buffer> <C-g>"
vim.b.undo_ftplugin = vim.b.undo_ftplugin and (vim.b.undo_ftplugin .. " | " .. undo) or undo
