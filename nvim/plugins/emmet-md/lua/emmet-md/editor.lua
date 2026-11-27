local M = {}

function M.chord()
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  -- A plain callback keeps scheduled edits legal while waiting for the key.
  local ok, key = pcall(vim.fn.getcharstr)
  if not ok or key == "\3" then
    vim.api.nvim_feedkeys("\3", "in", false)
  elseif
    key == "e"
    and vim.fn.mode() == "i"
    and vim.api.nvim_get_current_win() == win
    and vim.api.nvim_get_current_buf() == buf
  then
    vim.api.nvim_feedkeys(vim.keycode("<Plug>(emmet-md-expand)"), "im", false)
  else
    -- getcharstr already returns encoded keycodes, including special keys.
    vim.api.nvim_feedkeys("\7" .. key, "in", false)
  end
end

local function begin_edit()
  -- Writing undolevels back starts an undo block without changing its value.
  vim.bo.undolevels = vim.bo.undolevels
  vim.snippet.stop()
end

local function refused(config)
  vim.notify("Markdown Emmet could not expand this abbreviation", config.notify_level)
end

local function expand_at_cursor(compile, whole_line)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local line = vim.api.nvim_get_current_line()
  if whole_line then
    col = #line
  end
  local first = line:find("%S")
  if not first or first > col or not line:sub(col + 1):match("^[)}]*$") then
    return false
  end
  local snippet = compile(line:sub(first))
  if not snippet then
    return false
  end

  begin_edit()
  vim.api.nvim_buf_set_text(0, row, first - 1, row, #line, { "" })
  vim.api.nvim_win_set_cursor(0, { row + 1, first - 1 })
  vim.snippet.expand(snippet)
  return true
end

function M.at_cursor(compile, config)
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local function expand()
    if
      vim.api.nvim_get_current_win() == win
      and vim.api.nvim_get_current_buf() == buf
      and vim.fn.mode() == "i"
      and vim.tbl_contains(config.filetypes, vim.bo.filetype)
      and vim.bo.modifiable
    then
      if not expand_at_cursor(compile) then
        refused(config)
      end
    end
  end

  -- Cancel instead of hiding: a selected completion may have inserted a preview.
  local blink = package.loaded["blink.cmp"]
  if not (blink and blink.cancel({ callback = expand })) then
    expand()
  end
end

function M.command(compile, config, abbreviation)
  if not vim.bo.modifiable or not vim.tbl_contains(config.filetypes, vim.bo.filetype) then
    refused(config)
    return
  end
  if abbreviation == "" then
    if not expand_at_cursor(compile, true) then
      refused(config)
    end
    return
  end
  local snippet = compile(abbreviation)
  if not snippet then
    refused(config)
    return
  end
  begin_edit()
  vim.snippet.expand(snippet)
end

return M
