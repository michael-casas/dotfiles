if vim.bo.filetype ~= "markdown" then
  return
end

local plug = "<Plug>(emmet-md-expand)"
local ns = vim.api.nvim_create_namespace("envi-emmet-md-chord")
local mouse_move = vim.keycode("<MouseMove>")
local group = "EnviEmmetMdChord" .. vim.api.nvim_get_current_buf()
local function clear_listener()
  vim.on_key(nil, ns)
end

vim.api.nvim_create_autocmd({ "ModeChanged", "BufLeave", "WinLeave" }, {
  group = vim.api.nvim_create_augroup(group, { clear = true }),
  buffer = 0,
  callback = function(event)
    -- Native Ctrl+G can dismiss the popup before reading its second key.
    if event.event ~= "ModeChanged" or vim.fn.mode() ~= "i" then
      clear_listener()
    end
  end,
})

vim.keymap.set("i", "<C-g>", function()
  clear_listener()
  if vim.fn.maparg(plug, "i") == "" then
    return "<C-g>"
  end

  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local reading_second_key = false
  vim.on_key(function(key)
    if key == mouse_move then
      return
    end
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

local undo = ("silent! iunmap <buffer> <C-g> | silent! call luaeval('vim.api.nvim_del_augroup_by_name(_A)', %q)"):format(
  group
)
vim.b.undo_ftplugin = vim.b.undo_ftplugin and (vim.b.undo_ftplugin .. " | " .. undo) or undo
