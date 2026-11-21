local M = {}

local function reveal(picker, buf)
  local file = vim.api.nvim_buf_get_name(buf)
  local selected = picker:current()
  if
    vim.bo[buf].buftype == ""
    and file ~= ""
    and vim.fs.relpath(picker:cwd(), file)
    and picker.input:get() == ""
    and not picker.input.filter.meta.searching
    and (not selected or selected.file ~= file)
  then
    require("snacks.explorer.actions").update(picker, { target = file })
  end
end

function M.on_show(picker)
  local api = vim.api
  local left_win
  local list = picker.list.win

  -- A native move into the sidebar enters its root split. Snacks immediately
  -- redirects from there to the last picker child, which may be the filter.
  -- Only normalize that route. Clicking or explicitly opening the filter
  -- enters it directly and must still start Insert mode.
  list:on("WinLeave", function()
    left_win = api.nvim_get_current_win()
  end)
  list:on("WinEnter", function()
    if left_win == picker.layout.root.win and picker:is_focused() and list:valid() then
      picker:focus("list")
    end
  end, { nested = true })

  -- A maximized split picker draws editor-relative floats over other splits.
  -- Dock it when a Snacks split terminal takes focus, leaving the terminal
  -- in the native split tree so the existing window navigation still works.
  list:on({ "WinEnter", "BufEnter" }, function()
    local layout = picker.layout
    if
      layout.split
      and layout.opts.fullscreen
      and picker:on_current_tab()
      and vim.bo.filetype == "snacks_terminal"
      and api.nvim_win_get_config(0).relative == ""
    then
      layout:maximize()
    end
  end)

  -- Following a file through Snacks' default hook clears an active search
  -- and focuses the list. Reveal passively, and leave filtered views alone.
  list:on("BufEnter", function(_, ev)
    local win = api.nvim_get_current_win()
    if picker:on_current_tab() and not picker:is_focused() and api.nvim_win_get_config(win).relative == "" then
      vim.schedule(function()
        if not picker.closed and api.nvim_get_current_win() == win and api.nvim_get_current_buf() == ev.buf then
          reveal(picker, ev.buf)
        end
      end)
    end
  end)
  if api.nvim_win_is_valid(picker.main) then
    reveal(picker, api.nvim_win_get_buf(picker.main))
  end
end

function M.leave_filter(picker)
  picker.input:stopinsert()
  picker:focus("list")
end

return M
