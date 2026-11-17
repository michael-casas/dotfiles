-- BATDD-T3STRIKE-01/02/03/06/07 (L2, headless). Each scenario runs in a fresh
-- embedded Neovim with an RGB UI: real hcmux.t3/term/core/agent code, real
-- popover float, real terminal buffer and PTY, real keys (nvim_input), and
-- numeric cell colours read from the float's grid (nvim__inspect_cell).
-- External processes are substituted (test/support/strike-child.lua); the
-- viewer is test/support/fake-viewer.mjs, a synthetic model of the unproven
-- core replay boundary. No hc, T3 server or real thread is touched.
local root = vim.fn.getcwd()
local support = root .. "/nvim/tools/t3-thread/test/support/strike-child.lua"
local fixture = root .. "/nvim/tools/t3-thread/test/fixtures/threads-snapshot.json"

local hub = vim.json.decode(table.concat(vim.fn.readfile(root .. "/theme/theme.json"), "\n"))
local function token(theme_name, group, name)
  local theme = hub.themes[theme_name]
  local v = theme.tokens[group][name]
  return (v:sub(1, 1) == "#" and v or theme.palette[v]):lower()
end
local NORD = {
  popover = token("nord", "ui", "popover"),
  fg = token("nord", "ui", "fg"),
  code = token("nord", "chat", "code_bg"),
  bubble = token("nord", "chat", "user_bubble"),
}
local GRUVBOX_POPOVER = token("gruvbox-dark", "ui", "popover")
local O = {
  normal_fg = "#ffffff",
  normal_bg = "#101010",
  cursor = "#ff00ff",
  code_bg = NORD.code,
  bubble_bg = NORD.bubble,
  logdir = vim.fn.tempname(),
}
assert(hub.active == "nord", "fixture expectation: the hub's active theme is nord")
assert(NORD.popover ~= O.normal_bg and GRUVBOX_POPOVER ~= O.normal_bg, "popover must differ from the editor background")
vim.fn.mkdir(O.logdir, "p")

local function hex(n)
  return n and ("#%06x"):format(n) or "default"
end
local function rgb(color)
  local n = tonumber(color:sub(2), 16)
  local r, g, b = bit.rshift(n, 16), bit.band(bit.rshift(n, 8), 0xff), bit.band(n, 0xff)
  return ("rgb:%02x%02x/%02x%02x/%02x%02x"):format(r, r, g, g, b, b)
end

-- Every violated requirement is collected and reported together.
local failures = {}
local scenario = "?"
local function check(ok, msg)
  if not ok then
    failures[#failures + 1] = scenario .. ": " .. msg
  end
  return ok
end

local children = {}
local function spawn()
  local ch = vim.fn.jobstart({ "nvim", "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
  assert(ch > 0, "could not start an embedded nvim")
  children[#children + 1] = ch
  vim.rpcrequest(ch, "nvim_ui_attach", 120, 40, { rgb = true })
  local c = { ch = ch }
  function c.lua(code, ...)
    return vim.rpcrequest(ch, "nvim_exec_lua", code, { ... })
  end
  function c.state()
    return c.lua("vim.cmd.redraw() return STRIKE.state()")
  end
  function c.wait(pred, ms, what)
    local ok = vim.wait(ms or 3000, pred, 20)
    assert(ok, scenario .. ": timed out waiting for " .. what)
  end
  -- Real typed keys, processed by the child's input loop and mappings. Stay
  -- silent while they are consumed: an RPC request during the 'ttimeoutlen'
  -- wait after <Esc> restarts that wait.
  function c.input(keys)
    vim.rpcrequest(ch, "nvim_input", keys)
    vim.wait(200)
  end
  function c.ready(marker)
    assert(
      c.lua("return STRIKE.ready(...)", marker),
      scenario .. ": viewer " .. marker .. " never finished its history"
    )
  end
  assert(c.lua("return dofile(...)(select(2, ...))", support, root, O))
  return c
end

local function float_grid(c, width)
  for g = 2, 400 do
    local ok, tl = pcall(vim.rpcrequest, c.ch, "nvim__inspect_cell", g, 0, 0)
    if ok and tl[1] == "╭" then
      local ok2, tr = pcall(vim.rpcrequest, c.ch, "nvim__inspect_cell", g, 0, width + 1)
      if ok2 and tr[1] == "╮" then
        return g
      end
    end
  end
end

-- COMMAND, then scroll to the top of the terminal history.
local function scroll_top(c)
  vim.wait(250) -- let scheduled startinsert/auto-insert land first
  if c.lua("return vim.api.nvim_get_mode().mode") ~= "nt" then
    c.input("<Esc>")
  end
  c.wait(function()
    return c.lua("return vim.api.nvim_get_mode().mode") == "nt"
  end, 2000, "COMMAND mode")
  c.input("gg")
  c.wait(function()
    return c.state().topline == 1
  end, 2000, "scrolling to the top")
  return c.state()
end

-- Numeric cell backgrounds of every visible row: canvas, separators, erased
-- cells and margins are the popover background; code/bubble keep theirs.
local function check_cells(c, s, label, theme)
  assert(s.win and #s.lines > s.height, label .. ": history must exceed the window (real scrollback)")
  local g = assert(float_grid(c, s.width), label .. ": popover grid not found")
  local seen, bad = {}, {}
  for r = 0, s.height - 1 do
    local text = s.lines[s.topline + r] or ""
    local kind = vim.trim(text):match("^(%u+)_") or (vim.trim(text) == "" and "blank" or "text")
    seen[kind] = true
    for _, col in ipairs({ 0, 5, 40, s.width - 1 }) do
      local want, what = theme.popover, "canvas"
      if text:match("^  CODE_") and col < #text then
        want, what = theme.code, "code"
      elseif text:match("^  BUBBLE_") and col < #text then
        want, what = theme.bubble, "bubble"
      end
      local cell = vim.rpcrequest(c.ch, "nvim__inspect_cell", g, r + 1, col + 1)
      local bg = hex(cell[2].background)
      if bg ~= want then
        bad[#bad + 1] = ("row %d col %d %s %q bg %s, want %s"):format(r, col, what, vim.trim(text), bg, want)
      end
    end
  end
  assert(seen.PRE and seen.POST and seen.CODE and seen.BUBBLE, label .. ": visible history lacks a fixture row kind")
  local shown = vim.list_slice(bad, 1, 4)
  if #bad > 4 then
    shown[#shown + 1] = ("… %d more"):format(#bad - 4)
  end
  check(#bad == 0, label .. " cell backgrounds:\n    " .. table.concat(shown, "\n    "))
end

local function check_once_in_order(lines, marker, label)
  local last, problems = 0, {}
  for _, part in ipairs({ "PRE", "CODE", "BUBBLE", "OSC", "POST" }) do
    for i = 0, (part == "PRE" or part == "POST") and 11 or 0 do
      local key = (part == "PRE" or part == "POST") and ("%s_%s_%d"):format(part, marker, i) or (part .. "_" .. marker)
      local hits = {}
      for n, line in ipairs(lines) do
        local t = vim.trim(line)
        if t == key or t:find("^" .. key .. " ") then
          hits[#hits + 1] = n
        end
      end
      if #hits ~= 1 then
        problems[#problems + 1] = ("%s x%d"):format(key, #hits)
      elseif hits[1] < last then
        problems[#problems + 1] = key .. " out of order"
      else
        last = hits[1]
      end
    end
  end
  check(#problems == 0, label .. " committed items once in order: " .. table.concat(problems, ", "))
end

local function osc_line(lines, marker)
  for _, line in ipairs(lines) do
    local fg, bg, cursor = line:match("^OSC_" .. marker .. " fg=(#%x+) bg=(#%x+) cursor=(#%x+)")
    if fg then
      return { fg = fg, bg = bg, cursor = cursor }
    end
  end
end

-- The colours the client is told: terminal.run display (first byte) and the
-- production OSC 10/11/12 answers the viewer received after attach.
local function check_negotiation(c, s, marker, want, label)
  local run =
    c.lua("for _, f in ipairs(STRIKE.runs) do if f.marker == ... then return f.params.display end end", marker)
  check(
    run and run.bg == want.bg and run.fg == want.fg,
    ("%s terminal.run display %s/%s, want %s/%s"):format(label, run and run.fg, run and run.bg, want.fg, want.bg)
  )
  local osc = osc_line(s.lines, marker)
  check(
    osc and osc.bg == want.bg and osc.fg == want.fg and osc.cursor == want.cursor,
    ("%s OSC answers %s, want fg=%s bg=%s cursor=%s"):format(label, vim.inspect(osc), want.fg, want.bg, want.cursor)
  )
end

local T3_COLORS = { fg = NORD.fg, bg = NORD.popover, cursor = O.cursor }
local GLOBAL = { fg = O.normal_fg, bg = O.normal_bg, cursor = O.cursor }

local function read_history(c, marker, label, theme)
  local s = scroll_top(c)
  check(
    s.popover_hl.bg and hex(s.popover_hl.bg) == theme.popover,
    label .. " popover highlight " .. hex(s.popover_hl.bg)
  )
  check_cells(c, s, label, theme)
  check_once_in_order(s.lines, marker, label)
  return s
end

local scenarios = {}

scenarios["BATDD-T3STRIKE-01 AGENT slot 9"] = function()
  local c = spawn()
  c.lua(
    [[local fx = vim.json.decode(table.concat(vim.fn.readfile(...), "\n"))
      require("hcmux.t3side").update(fx)
      require("hcmux.agent").open("board")]],
    fixture
  )
  c.input("m9") -- mark the selected thread in slot 9 (AGENT's own key)
  local id
  c.wait(function()
    id = c.lua('local d = STRIKE.docs["envi-agent.strike-test"] return d and d.value.slots["9"] or false')
    return type(id) == "string"
  end, 3000, "slot 9 mark")
  c.lua('require("hcmux.agent").open()')
  c.input("9")
  local marker = id:gsub("[^%w]", "")
  c.ready(marker)
  local s = read_history(c, marker, "slot 9", NORD)
  check_negotiation(c, s, marker, T3_COLORS, "slot 9")
  check(s.runs == 1, "only the slot thread was started, runs=" .. s.runs)
  check(c.lua("return STRIKE.runs[1].labels['t3.thread']") == id, "the started client is the slot 9 thread")
  check(c.lua("return vim.tbl_count(STRIKE.attaches)") == 1, "no other thread viewer was attached")
end

scenarios["BATDD-T3STRIKE-02 direct route"] = function()
  local c = spawn()
  -- The public target behind <leader>hi, with an owned synthetic id.
  c.lua('require("hcmux.t3").toggle("owned-direct")')
  c.ready("owneddirect")
  local s = read_history(c, "owneddirect", "direct", NORD)
  check_negotiation(c, s, "owneddirect", T3_COLORS, "direct")
  check(s.runs == 1 and c.lua("return vim.tbl_count(STRIKE.attaches)") == 1, "no other thread opened")
end

scenarios["BATDD-T3STRIKE-03 resize, reopen, switch"] = function()
  local c = spawn()
  c.lua('require("hcmux.t3").toggle("owned-a")')
  c.ready("owneda")
  local first = c.state()
  for _, size in ipairs({ { 100, 30 }, { 80, 24 }, { 100, 30 } }) do
    c.lua(
      "vim.api.nvim_win_set_config(STRIKE.popover(), { width = select(1, ...), height = select(2, ...) })",
      size[1],
      size[2]
    )
    vim.wait(250)
    local label = ("resize %dx%d"):format(size[1], size[2])
    local s = read_history(c, "owneda", label, NORD)
    check(s.width == size[1] and s.height == size[2], label .. " applied")
    check(
      s.win == first.win and s.buf == first.buf and s.job == first.job and s.alive,
      label .. " same window/buffer/process"
    )
  end
  c.input("q") -- COMMAND q hides
  c.wait(function()
    return c.state().win == nil
  end, 2000, "q to hide the popover")
  check(c.lua("return STRIKE.job_alive(...)", first.addr), "hidden client keeps running")
  c.lua('require("hcmux.t3").toggle("owned-a")')
  local reopened = c.state()
  check(reopened.buf == first.buf and reopened.job == first.job and reopened.alive, "reopen reuses buffer and process")
  check(
    reopened.runs == 1 and c.lua("return STRIKE.attaches[...]", first.addr) == 1,
    "reopen starts no client or viewer"
  )
  c.lua('require("hcmux.t3").toggle("owned-b")')
  c.ready("ownedb")
  local b = c.state()
  check(b.win == reopened.win and b.buf ~= first.buf, "switching keeps the popover window and shows B")
  c.lua('require("hcmux.t3").toggle("owned-a")')
  local back = read_history(c, "owneda", "after switch", NORD)
  check(
    back.win == reopened.win and back.buf == first.buf and back.job == first.job,
    "switching back keeps window, buffer, process"
  )
  check(c.lua("return STRIKE.job_alive(...)", b.addr), "switching away keeps B running")
  check(back.runs == 2, "two clients in total, runs=" .. back.runs)
  c.lua('require("hcmux.t3").toggle("owned-b")')
  read_history(c, "ownedb", "client B", NORD)
end

scenarios["BATDD-T3STRIKE-06 modes and hide"] = function()
  local c = spawn()
  c.lua('require("hcmux.t3").toggle("owned-keys")')
  c.ready("ownedkeys")
  local log = O.logdir .. "/ownedkeys.log"
  local function typed()
    local bytes = vim.uv.fs_stat(log) and table.concat(vim.fn.readfile(log, "b"), "\n") or ""
    -- Automatic geometry diagnostics are not user key input; assert the
    -- original dismiss contract independently of action-9 settle timing.
    return (bytes:gsub("\27%[>777;9;%d+u", ""))
  end
  local first = c.state()
  check(first.mode == "t", "opens in INSERT, mode=" .. first.mode)
  c.input("draft")
  c.wait(function()
    return typed():find("draft", 1, true) ~= nil
  end, 2000, "draft text to reach the client")
  c.input("<Esc>")
  c.wait(function()
    return c.lua("return vim.api.nvim_get_mode().mode") == "nt"
  end, 2000, "Esc to enter COMMAND")
  vim.wait(150)
  check(typed() == "draft\27[>777;6u", "INSERT Esc sends only dismiss, got " .. vim.inspect(typed()))
  c.input("<Esc>")
  vim.wait(150)
  local s = c.state()
  check(s.mode == "nt" and s.win == first.win, "COMMAND Esc stays in COMMAND and visible")
  c.input("<C-]>")
  c.wait(function()
    return c.lua("return vim.api.nvim_get_mode().mode") == "t"
  end, 2000, "COMMAND <C-]> to enter INSERT")
  c.input("q")
  vim.wait(150)
  check(typed():sub(-1) == "q" and c.state().win == first.win, "INSERT q is draft text, not hide")
  c.input("<C-]>")
  c.wait(function()
    return c.lua("return vim.api.nvim_get_mode().mode") == "nt"
  end, 2000, "INSERT <C-]> to COMMAND")
  c.input("q")
  c.wait(function()
    return c.state().win == nil
  end, 2000, "COMMAND q to hide")
  check(c.lua("return STRIKE.job_alive(...)", first.addr), "hide keeps the client (and its draft) running")
  check(not typed():find("\27[>777;5u", 1, true) and not typed():find("\3", 1, true), "no interrupt was sent")
  c.lua('require("hcmux.t3").toggle("owned-keys")')
  local again = c.state()
  check(again.buf == first.buf and again.job == first.job and again.alive, "reopen shows the same client")
end

scenarios["BATDD-T3STRIKE-07 ordinary terminal isolation"] = function()
  local c = spawn()
  c.lua('require("hcmux.term").open(nil, { where = "split" })')
  c.ready("ORD1")
  local ord = c.lua("return { buf = vim.api.nvim_get_current_buf(), addr = vim.b.hcmux_addr }")
  local before = c.state()
  local ord_lines = c.lua("return vim.api.nvim_buf_get_lines(...)", ord.buf, 0, -1, false)
  check_negotiation(c, { lines = ord_lines }, "ORD1", GLOBAL, "ordinary")
  c.lua('require("hcmux.t3").toggle("owned-x")')
  c.ready("ownedx")
  c.lua("vim.api.nvim_win_set_config(STRIKE.popover(), { width = 80, height = 24 })")
  c.lua('require("hcmux.t3").toggle("owned-y")')
  c.ready("ownedy")
  scroll_top(c)
  local want = {}
  for _, pair in ipairs({ { "10", O.normal_fg }, { "11", O.normal_bg }, { "12", O.cursor } }) do
    want[#want + 1] = ("\27]%s;%s\27\\"):format(pair[1], rgb(pair[2]))
  end
  -- The ordinary terminal may query while the themed popover is focused.
  local focused = c.lua("vim.cmd.redraw() return STRIKE.osc(...)", ord.buf)
  check(vim.deep_equal(focused, want), "ordinary OSC answers while the popover is focused: " .. vim.inspect(focused))
  c.input("q")
  c.wait(function()
    return c.state().win == nil
  end, 2000, "hiding the popover")
  local after = c.state()
  local answers = c.lua("return STRIKE.osc(...)", ord.buf)
  check(vim.deep_equal(answers, want), "ordinary OSC answers changed: " .. vim.inspect(answers))
  check(vim.deep_equal(before.normal, after.normal), "global Normal changed")
  check(vim.deep_equal(before.cursor, after.cursor), "global Cursor changed")
  check(c.lua("return STRIKE.job_alive(...)", ord.addr), "ordinary client still running")
  check(after.runs == 3 and c.lua("return STRIKE.attaches[...]", ord.addr) == 1, "no client recreated")
end

scenarios["adversarial: other theme and invalid hub fallback"] = function()
  local c = spawn()
  local missing = O.logdir .. "/missing-theme.json"
  -- A missing hub on first open: the existing global fallback, still usable.
  c.lua('vim.env.ENVI_THEME_FILE = ... require("hcmux.t3").toggle("owned-bad")', missing)
  c.ready("ownedbad")
  local bad = c.state()
  check(bad.win and bad.alive, "missing hub still opens the client in the popover")
  check_negotiation(c, bad, "ownedbad", GLOBAL, "missing hub")
  -- Gruvbox selected, switching in place: its popover colours, not the editor's.
  c.lua('vim.env.ENVI_THEME_FILE = nil vim.env.ENVI_THEME = "gruvbox-dark" require("hcmux.t3").toggle("owned-gruv")')
  c.ready("ownedgruv")
  local gruv = c.state()
  local GRUVBOX = { fg = token("gruvbox-dark", "ui", "fg"), bg = GRUVBOX_POPOVER, cursor = O.cursor }
  check(hex(gruv.popover_hl.bg) == GRUVBOX_POPOVER, "gruvbox popover highlight")
  check_negotiation(c, gruv, "ownedgruv", GRUVBOX, "gruvbox")
  -- The hub breaks again: the window keeps its gruvbox look, so does the client.
  c.lua('vim.env.ENVI_THEME_FILE = ... require("hcmux.t3").toggle("owned-bad2")', missing)
  c.ready("ownedbad2")
  local again = c.state()
  check(again.win == gruv.win and again.alive, "broken hub switch keeps the popover")
  check(hex(again.popover_hl.bg) == GRUVBOX_POPOVER, "existing popover appearance left alone")
  check_negotiation(c, again, "ownedbad2", GRUVBOX, "broken hub after gruvbox")
end

local order = {
  "BATDD-T3STRIKE-01 AGENT slot 9",
  "BATDD-T3STRIKE-02 direct route",
  "BATDD-T3STRIKE-03 resize, reopen, switch",
  "BATDD-T3STRIKE-06 modes and hide",
  "BATDD-T3STRIKE-07 ordinary terminal isolation",
  "adversarial: other theme and invalid hub fallback",
}
local function stop_children()
  for _, ch in ipairs(children) do
    pcall(vim.rpcrequest, ch, "nvim_exec_lua", "STRIKE.stop_all()", {})
    pcall(vim.rpcnotify, ch, "nvim_command", "qa!")
  end
  vim.wait(100)
  for _, ch in ipairs(children) do
    pcall(vim.fn.jobstop, ch)
  end
  children = {}
end
local ran = 0
for _, name in ipairs(order) do
  scenario = name
  local ok, err = pcall(scenarios[name])
  if not ok then
    failures[#failures + 1] = name .. ": " .. tostring(err)
  end
  ran = ran + 1
  stop_children()
end
vim.fn.delete(O.logdir, "rf")
assert(ran == #order, "every scenario must run")
if #failures > 0 then
  error(("%d failure(s) in %d scenarios:\n  %s"):format(#failures, ran, table.concat(failures, "\n  ")), 0)
end
print(("T3 scrollback strike scenarios passed: %d"):format(ran))
