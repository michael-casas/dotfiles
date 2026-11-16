-- Mouse contract through real sidebar maps, stub getmousepos; no hc/T3 jobs.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 120, 40
vim.o.mouse = "a"
local main = vim.api.nvim_get_current_win()
local side = require("hcmux.t3side")
local buf = side.buffer()
local bar = vim.api.nvim_open_win(buf, false, {split = "left", win = main, width = 36})
local opened = {}
package.loaded["hcmux.layout"] = { open_thread = function(id)
  opened[#opened + 1] = id
  side.select(id)
  vim.api.nvim_set_current_win(main)
end }
local function snapshot()
  side.update({type = "snapshot", projects = {{id = "p", name = "Project"}}, threads = {
    {id = "a", projectId = "p", title = "Alpha", status = "idle", branch = "alpha-branch"},
    {id = "b", projectId = "p", title = "Beta", pinned = true, status = "idle", branch = "beta-branch"},
    {id = "c", projectId = "p", title = "Gamma", settled = true, status = "idle"},
  }})
end
local function find(text)
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(text, 1, true) then return i end
  end
end
local function click(line, opts)
  opts = opts or {}
  local release
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if map.lhs == "<LeftRelease>" then release = map.callback end
    assert(map.lhs ~= "<ScrollWheelDown>" and map.lhs ~= "<ScrollWheelUp>" and map.lhs ~= "<LeftDrag>", "native scroll/drag preserved")
  end
  assert(release, "bar has a buffer-local LeftRelease handler")
  -- Like the real getmousepos(): a click below the text reports the last line,
  -- with a window row past that line's screen rows.
  local win = opts.win or bar
  local last = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  local top = vim.fn.getwininfo(win)[1].topline
  local winrow = opts.below and vim.api.nvim_win_get_height(win)
    or vim.api.nvim_win_text_height(win, {start_row = top - 1, end_row = math.min(line, last) - 1}).all
  vim.fn.getmousepos = function()
    return {winid = win, line = math.min(line, last), column = 2, winrow = winrow}
  end
  release()
end
local cases = {
  {"G7 title, pin/project metadata and branch open and select same card", function()
    snapshot()
    for _, entry in ipairs({{"Alpha", "a"}, {"alpha-branch", "a"}, {"📌", "b"}, {"Beta", "b"}, {"beta-branch", "b"}}) do
      vim.api.nvim_set_current_win(bar)
      click(assert(find(entry[1])))
      assert(opened[#opened] == entry[2])
      assert(vim.api.nvim_get_current_win() == main, "same focus as Enter/o")
      local line = vim.api.nvim_win_get_cursor(bar)[1]
      assert(vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]:find(entry[2] == "a" and "Alpha" or "Beta", 1, true), "cursor on card title")
      local ns = vim.api.nvim_create_namespace("envi.t3side")
      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, {line - 1, 0}, {line - 1, -1}, {details = true})
      assert(vim.iter(marks):any(function(m) return m[4].line_hl_group == "EnviT3SideSelected" end), "selection highlight follows click")
    end
  end},
  {"G8 project/Settled headers toggle", function()
    click(assert(find("⌄")))
    assert(not find("Alpha"), "collapsed project hides idle nonselected card")
    click(assert(find("›")))
    assert(find("Alpha"), "project expands")
    click(assert(find("Settled")))
    assert(find("Gamma"), "settled expands")
    click(assert(find("Settled")))
    assert(not find("Gamma"), "settled collapses")
  end},
  {"G9 blanks, below last row, foreign window do nothing", function()
    local count = #opened
    local blank
    for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do if line == "" then blank = i; break end end
    click(assert(blank))
    local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert(before[#before]:find("Settled", 1, true), "fixture: Settled is the final row")
    click(#before + 5, {below = true}) -- real getmousepos clamps to the last line
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), before), "below-text click toggles nothing")
    click(assert(find("Alpha")), {win = main})
    assert(#opened == count)
  end},
  {"G10 click from main resolves mouse window, not current cursor", function()
    vim.api.nvim_set_current_win(main)
    click(assert(find("Alpha")))
    assert(opened[#opened] == "a" and vim.api.nvim_get_current_win() == main)
    assert(#vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(main), "t") == 0, "no main-terminal mouse map")
  end},
  {"drag and mouse-off never activate", function()
    vim.api.nvim_set_current_win(bar)
    local count = #opened
    -- Dispatch the drag map if present; it must preserve native dragging and suppress release activation.
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if map.lhs == "<LeftDrag>" then map.callback() end
    end
    vim.o.mouse = ""
    click(assert(find("Alpha")))
    assert(#opened == count)
    vim.o.mouse = "a"
  end},
}
local failures = {}
for _, case in ipairs(cases) do
  local ok, err = pcall(case[2]); print((ok and "PASS " or "FAIL ") .. case[1])
  if not ok then failures[#failures + 1] = case[1] .. ": " .. tostring(err) end
end
assert(#failures == 0, table.concat(failures, "\n"))
print("T3 sidebar-click: " .. #cases .. " cases passed")
