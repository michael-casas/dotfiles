-- Real windows/maps with mocked hc: no external terminal or thread is touched.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 120, 40
local started, attached, detached = 0, 0, {}
local facts, bufs = {}, {}
package.loaded["hcmux.core"] = {
  get = function(name)
    return facts[name]
  end,
  list = function(filter)
    local result = {}
    for name, fact in pairs(facts) do
      if name == fact.address and filter(fact) then
        result[#result + 1] = fact
      end
    end
    return result
  end,
}
local function buffer(addr)
  if not bufs[addr] or not vim.api.nvim_buf_is_valid(bufs[addr]) then
    bufs[addr] = vim.api.nvim_create_buf(false, true)
    vim.b[bufs[addr]].hcmux_addr = addr
  end
  return bufs[addr]
end
package.loaded["hcmux.term"] = {
  addr_of = function(buf)
    return vim.b[buf].hcmux_addr
  end,
  buf_of = function(addr)
    return bufs[addr]
  end,
  attach = function(addr)
    attached = attached + 1
    local buf = buffer(addr)
    vim.api.nvim_set_current_buf(buf)
    return buf
  end,
  detach = function(buf)
    detached[#detached + 1] = vim.b[buf].hcmux_addr
    vim.api.nvim_buf_delete(buf, { force = true })
  end,
  open = function(argv, opts)
    started = started + 1
    local addr = "mock-" .. started
    local fact = { address = addr, state = "live", labels = opts.labels }
    facts[addr], facts[opts.name] = fact, fact
    local buf = buffer(addr)
    if opts.where == "float" then
      vim.api.nvim_open_win(buf, true, { relative = "editor", width = 40, height = 10, row = 0, col = 0 })
    else
      vim.api.nvim_set_current_buf(buf)
    end
    return buf, addr
  end,
}
-- Feed lifecycle/parser tested separately, never start the real feed in units.
local side = require("hcmux.t3side")
side.start = function() end
local layout = require("hcmux.layout")
local editor, editor_win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
layout.go("T3")
local tab = vim.api.nvim_get_current_tabpage()
assert(tab ~= editor and vim.t.envi_layout == "T3" and vim.t.hcmux_session_skip)
local function main_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.w[win].envi_t3_main then
      return win
    end
  end
end
local main = assert(main_win())
local sidebar
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
  if win ~= main then
    sidebar = win
  end
end
assert(sidebar and vim.bo[vim.api.nvim_win_get_buf(sidebar)].filetype == "envi-t3-sidebar")
layout.go("nvim")
assert(vim.api.nvim_get_current_tabpage() == editor and vim.api.nvim_get_current_win() == editor_win)
local select = vim.ui.select
vim.ui.select = function(items, opts, cb)
  assert(#items == 2 and opts.format_item("nvim"):find("●", 1, true))
  cb("T3")
end
layout.pick()
vim.ui.select = select
assert(vim.api.nvim_get_current_tabpage() == tab and #vim.api.nvim_list_tabpages() == 2)
layout.open_thread("A")
assert(started == 1 and vim.api.nvim_get_current_win() == main)
local addr_a = vim.b.hcmux_addr
layout.open_thread("B")
assert(started == 2 and vim.api.nvim_get_current_win() == main and detached[1] == addr_a)
layout.open_thread("A")
assert(started == 2 and attached == 1 and vim.b.hcmux_addr == addr_a)
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
vim.api.nvim_win_set_cursor(main, { 2, 0 })
local width = vim.api.nvim_win_get_width(main)
layout.sidebar_toggle()
assert(vim.api.nvim_win_is_valid(main) and vim.api.nvim_win_get_width(main) > width)
assert(vim.api.nvim_win_get_buf(main) == buf and vim.api.nvim_win_get_cursor(main)[1] == 2)
layout.sidebar_toggle()
assert(vim.api.nvim_win_get_width(main) == width and vim.api.nvim_win_get_buf(main) == buf)
assert(vim.fn.maparg("q", "n") == "", "q is available for macros")
-- :q detaches this layout's view, leaving any shared popover and its core client alive.
local float = vim.api.nvim_open_win(buf, true, { relative = "editor", width = 30, height = 5, row = 0, col = 0 })
vim.api.nvim_set_current_win(main)
vim.api.nvim_feedkeys(":q\r", "mtx", false)
assert(vim.api.nvim_win_is_valid(main) and vim.api.nvim_tabpage_is_valid(tab))
assert(vim.api.nvim_win_get_buf(main) ~= buf and vim.api.nvim_win_is_valid(float))
vim.api.nvim_set_current_win(float)
vim.api.nvim_feedkeys(":q\r", "mtx", false)
assert(not vim.api.nvim_win_is_valid(float) and vim.api.nvim_win_is_valid(main))
-- Reuse label even when name differs (and deterministic name collides).
facts["t3-labelled"] = { address = "unrelated", state = "live", labels = { ["t3.thread"] = "other" } }
facts["unrelated"] = facts["t3-labelled"]
facts["label-client"] = { address = "label-client", state = "live", labels = { ["t3.thread"] = "labelled" } }
layout.open_thread("labelled")
assert(started == 2 and vim.b.hcmux_addr == "label-client")
layout.go("nvim")
local notify = vim.notify
vim.notify = function() end
layout.sidebar_toggle()
vim.notify = notify
assert(vim.api.nvim_get_current_tabpage() == editor)
layout.go("T3")
assert(main_win() == main)
print("T3 layout tests passed")
-- Closing the main must never turn the sidebar into the terminal window.
local function sidebar_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "envi-t3-sidebar" then
      return w
    end
  end
end
assert(
  not vim.wo[main].number and not vim.wo[main].relativenumber and vim.wo[main].signcolumn == "no",
  "main has no gutter"
)
vim.api.nvim_win_close(main, true)
layout.go("T3")
local replacement = assert(main_win())
assert(
  replacement ~= sidebar_win() and #vim.api.nvim_tabpage_list_wins(tab) == 2,
  "closed main recreated beside sidebar"
)
assert(vim.bo[vim.api.nvim_win_get_buf(sidebar_win())].filetype == "envi-t3-sidebar")
-- Force the stale-main-equals-sidebar state using module upvalues.
vim.api.nvim_win_close(replacement, true)
local sidewin = assert(sidebar_win())
for i = 1, 30 do
  local n = debug.getupvalue(layout.go, i)
  if n == "main" then
    debug.setupvalue(layout.go, i, sidewin)
  end
end
layout.go("T3")
assert(main_win() ~= sidewin and #vim.api.nvim_tabpage_list_wins(tab) == 2, "main==sidebar recreated safely")
layout.open_thread("A")
local restored = main_win()
assert(not vim.wo[restored].number and not vim.wo[restored].relativenumber and vim.wo[restored].signcolumn == "no")
print("T3 closed-main recovery tests passed")
-- Sidebar show must not leave/re-enter a terminal (term BufEnter auto-inserts).
vim.api.nvim_set_current_win(restored)
layout.sidebar_toggle()
local entries = 0
vim.api.nvim_create_autocmd("BufEnter", {
  buffer = vim.api.nvim_win_get_buf(restored),
  callback = function()
    entries = entries + 1
  end,
})
layout.sidebar_toggle()
assert(
  vim.api.nvim_get_current_win() == restored and entries == 0,
  "show sidebar preserves main focus without terminal re-entry"
)
print("T3 sidebar non-entering split test passed")
-- Hiding from sidebar must focus main without triggering its auto-insert hook.
local side_focus = assert(sidebar_win())
vim.api.nvim_set_current_win(side_focus)
vim.wait(10, function()
  return false
end)
local auto_insert = 0
vim.api.nvim_create_autocmd("BufEnter", {
  buffer = vim.api.nvim_win_get_buf(restored),
  callback = function()
    vim.schedule(function()
      auto_insert = auto_insert + 1
    end)
  end,
})
layout.sidebar_toggle()
vim.wait(10, function()
  return false
end)
assert(vim.api.nvim_get_current_win() == restored, "hide from sidebar focuses main")
assert(auto_insert == 0, "hide from sidebar must bypass terminal auto-insert on entry")
assert(vim.fn.mode() == "n", "hide from sidebar lands in COMMAND")
print("T3 sidebar hide-to-COMMAND test passed")
-- Thread title is local to main; new floats must not inherit its winbar.
assert(vim.go.winbar == "", "main title must not set the global winbar")
local set_option = vim.api.nvim_set_option_value
local winbar_scope
vim.api.nvim_set_option_value = function(name, value, opts)
  if name == "winbar" then
    winbar_scope = opts
  end
  return set_option(name, value, opts)
end
layout.open_thread("A")
vim.api.nvim_set_option_value = set_option
local titled_main = vim.api.nvim_get_current_win()
assert(
  winbar_scope and winbar_scope.scope == "local" and winbar_scope.win == titled_main,
  "winbar must use explicit local scope"
)
assert(vim.wo[editor_win].winbar == "", "editor must not inherit main title")
assert(vim.wo[titled_main].winbar:find("T3 · ", 1, true), "main retains its thread title")
assert(vim.go.winbar == "", "open_thread leaves global winbar empty")
local clean_float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
  relative = "editor",
  width = 30,
  height = 5,
  row = 0,
  col = 0,
})
assert(vim.wo[clean_float].winbar == "", "new popover float must have no main-pane winbar")
vim.api.nvim_win_close(clean_float, true)
print("T3 window-local winbar test passed")
