-- Two persistent layouts. Global/leader bindings belong to keybinder.
local M = {}
local side = require("hcmux.t3side")
local tab, main, sidebar, empty, editor

local function valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function main_options()
  vim.w[main].envi_t3_main = true
  vim.wo[main].number = false
  vim.wo[main].relativenumber = false
  vim.wo[main].signcolumn = "no"
end

local function placeholder()
  if not empty or not vim.api.nvim_buf_is_valid(empty) then
    empty = vim.api.nvim_create_buf(false, true)
    vim.bo[empty].bufhidden = "hide"
    vim.api.nvim_buf_set_lines(empty, 0, -1, false, { "", "  Select a thread in the sidebar." })
    vim.bo[empty].modifiable = false
  end
  return empty
end

local function ensure_main()
  if valid(main) and main ~= sidebar then
    main_options()
    return
  end
  if valid(sidebar) then
    vim.w[sidebar].envi_t3_main = nil
    vim.api.nvim_set_current_win(sidebar)
    vim.cmd("rightbelow vsplit")
  else
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd("botright vnew")
  end
  main = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(main, placeholder())
  main_options()
  if valid(sidebar) then
    vim.api.nvim_win_set_width(sidebar, 36)
  end
end

local function show_sidebar()
  ensure_main()
  if valid(sidebar) then
    return
  end
  -- Do not enter/leave the terminal: term's BufEnter auto-insert must not
  -- change COMMAND to INSERT when a sidebar is merely shown.
  sidebar = vim.api.nvim_open_win(side.buffer(), false, { split = "left", win = main, width = 36 })
  vim.wo[sidebar].winfixwidth = true
  vim.wo[sidebar].number = false
  vim.wo[sidebar].relativenumber = false
  vim.wo[sidebar].signcolumn = "no"
  vim.wo[sidebar].wrap = false
  vim.wo[sidebar].list = false
  vim.wo[sidebar].cursorline = true
  vim.wo[sidebar].winhl = "CursorLine:EnviT3SideSelected"
  side.render()
end

function M.go(name)
  if name ~= "nvim" and name ~= "T3" then
    return vim.notify("Unknown layout: " .. tostring(name), vim.log.levels.WARN)
  end
  local current = vim.api.nvim_get_current_tabpage()
  if current ~= tab then
    editor = current
    vim.t[current].envi_layout = "nvim"
  end
  if name == "nvim" then
    if editor and vim.api.nvim_tabpage_is_valid(editor) then
      vim.api.nvim_set_current_tabpage(editor)
    else
      vim.cmd("tabnew")
      editor = vim.api.nvim_get_current_tabpage()
      vim.t.envi_layout = "nvim"
    end
    return
  end
  if tab and vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    ensure_main()
    return
  end
  vim.cmd("tabnew")
  tab, main = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
  vim.t.envi_layout, vim.t.hcmux_session_skip = "T3", true
  main_options()
  vim.api.nvim_win_set_buf(main, placeholder())
  sidebar = nil
  show_sidebar()
  vim.api.nvim_set_current_win(sidebar)
  side.start()
end

function M.pick()
  local current = vim.t.envi_layout or "nvim"
  vim.ui.select({ "nvim", "T3" }, {
    prompt = "Layout",
    format_item = function(name)
      return (name == current and "● " or "  ") .. name
    end,
  }, function(name)
    if name then
      M.go(name)
    end
  end)
end

function M.sidebar_toggle()
  if vim.api.nvim_get_current_tabpage() ~= tab then
    return vim.notify("T3 sidebar is only available in the T3 layout", vim.log.levels.INFO)
  end
  ensure_main()
  local focus = vim.api.nvim_get_current_win()
  if valid(sidebar) then
    if focus == sidebar then
      -- Closing the focused sidebar would enter the terminal normally, whose
      -- BufEnter hook schedules startinsert. Hand focus over without that hook.
      vim.cmd(("noautocmd call nvim_set_current_win(%d)"):format(main))
    end
    vim.api.nvim_win_close(sidebar, true)
    sidebar = nil
  else
    show_sidebar()
  end
  if valid(focus) then
    vim.api.nvim_set_current_win(focus)
  end
end

function M.open_thread(id)
  if type(id) ~= "string" or id == "" then
    return
  end
  M.go("T3")
  local buf = require("hcmux.t3").attach_in(main, id)
  if buf then
    main_options()
    side.select(id)
    local title = side.title(id) or id
    vim.api.nvim_set_option_value("winbar", " T3 · " .. title:gsub("%%", "%%%%"):gsub("[%c]", " "), {
      scope = "local",
      win = main,
    })
  end
  return buf
end

-- LazyVim/filetype hooks can re-enable gutters on a buffer transition. The
-- main role belongs to the window, so reapply after those hooks have run.
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  group = vim.api.nvim_create_augroup("envi.t3.main", { clear = true }),
  callback = function()
    if valid(main) and vim.w[main].envi_t3_main then
      vim.schedule(function()
        if valid(main) and main ~= sidebar then
          main_options()
        end
      end)
    end
  end,
})

return M
