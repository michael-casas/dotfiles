if vim.bo.filetype ~= "markdown" then
  return
end

local plug = "<Plug>(emmet-md-expand)"
local ns = vim.api.nvim_create_namespace("envi-emmet-md-chord")
local function clear_listener()
  vim.on_key(nil, ns)
end

vim.api.nvim_create_autocmd({ "ModeChanged", "BufLeave", "WinLeave" }, {
  group = vim.api.nvim_create_augroup("EnviEmmetMdChord", { clear = true }),
  callback = clear_listener,
})

vim.keymap.set("i", "<C-g>", function()
  clear_listener()
  if vim.fn.maparg(plug, "i") == "" then
    return "<C-g>"
  end

  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local reading_second_key = false
  vim.on_key(function(key)
    if not reading_second_key then
      reading_second_key = true
      return -- The native Ctrl+G returned by this map.
    end
    clear_listener()
    if
      key == "e"
      and vim.fn.mode() == "i"
      and vim.api.nvim_get_current_win() == win
      and vim.api.nvim_get_current_buf() == buf
    then
      vim.api.nvim_feedkeys(vim.keycode(plug), "im", false)
    end
  end, ns)
  return "<C-g>"
end, { buffer = 0, expr = true, desc = "Insert Ctrl+g commands and Markdown Emmet (e)" })

local undo = "silent! iunmap <buffer> <C-g>"
vim.b.undo_ftplugin = vim.b.undo_ftplugin and (vim.b.undo_ftplugin .. " | " .. undo) or undo
