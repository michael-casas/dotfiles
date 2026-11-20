local M = {}
local api = vim.api

function M.native_quit(opts)
  vim.cmd.quit({ bang = opts.bang })
end

-- Command history records the routed command. Replay in an ordinary buffer
-- should quit natively, while a buffer-local action takes precedence.
api.nvim_create_user_command("EnviClose", M.native_quit, { bang = true, desc = "Quit or close an envi view" })

-- Scope the interactive Ex command to buffers that have a view owner.
-- Ordinary edit buffers and commands like :qa, :wq, and :normal q stay native.
api.nvim_create_autocmd("CmdlineLeave", {
  group = api.nvim_create_augroup("envi_panel_close", { clear = true }),
  pattern = ":",
  callback = function()
    if vim.v.event.abort then
      return
    end
    local line = vim.trim(vim.fn.getcmdline())
    local command = line:match("^(qu?i?t?)!?$")
    if command and vim.startswith("quit", command) and api.nvim_buf_get_commands(0, {}).EnviClose then
      local bang = line:sub(-1) == "!" and "!" or ""
      vim.fn.setcmdline("EnviClose" .. bang)
    end
  end,
})

function M.bind(buf, close, desc)
  api.nvim_buf_create_user_command(buf, "EnviClose", close, { bang = true, desc = desc or "Close this view" })
end

local function last_split(win)
  if api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  return not vim.iter(api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(win))):any(function(other)
    -- A picker root can remain briefly while Snacks schedules its teardown.
    return other ~= win and api.nvim_win_get_config(other).relative == "" and not vim.w[other].snacks_layout
  end)
end

function M.close_window()
  local win = api.nvim_get_current_win()
  if last_split(win) then
    api.nvim_win_set_buf(win, api.nvim_create_buf(true, false))
  else
    api.nvim_win_close(win, false)
  end
end

-- A plugin that closes its own window needs a replacement split if its
-- window is the only tiled one. Create it without changing focus.
function M.keep_editor(win)
  if win and api.nvim_win_is_valid(win) and last_split(win) then
    api.nvim_open_win(api.nvim_create_buf(true, false), false, { split = "below", win = win })
  end
end

-- Adopt the plugin's close action after it installs its buffer-local q.
function M.adopt(buf, before_close)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  for _, map in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
    if map.lhs == "q" then
      vim.keymap.del("n", "q", { buffer = buf })
      M.bind(buf, function(opts)
        if vim.bo[buf].buftype == "" then
          return M.native_quit(opts)
        end
        if before_close then
          before_close()
        end
        if map.callback then
          map.callback()
        else
          local rhs = api.nvim_replace_termcodes(map.rhs, true, false, true)
          api.nvim_feedkeys(rhs, map.noremap == 1 and "nx" or "mx", false)
        end
      end, map.desc)
      return
    end
  end
end

return M
