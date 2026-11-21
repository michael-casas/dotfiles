-- Colour negotiation at T3 lifecycle boundaries (additive to
-- scrollback-strikes.lua, BATDD-T3STRIKE-01/03/07): reopen into a fallback
-- float, same-buffer theme refresh, fresh attach without a buffer, override
-- of an existing buffer, and :T3Restart. Same harness: an embedded Neovim
-- with real hcmux code and test/support/strike-child.lua substitutes; the
-- observable is the production TermRequest answer (OSC 10/11/12) of the
-- buffer at each transition, or terminal.run's startup display.
local root = vim.fn.getcwd()
local support = root .. "/nvim/tools/t3-thread/test/support/strike-child.lua"
local hub = vim.json.decode(table.concat(vim.fn.readfile(root .. "/theme/theme.json"), "\n"))
local function token(theme_name, group, name)
  local theme = hub.themes[theme_name]
  local v = theme.tokens[group][name]
  return (v:sub(1, 1) == "#" and v or theme.palette[v]):lower()
end
local O = {
  normal_fg = "#ffffff",
  normal_bg = "#101010",
  cursor = "#ff00ff",
  code_bg = token("nord", "chat", "code_bg"),
  bubble_bg = token("nord", "chat", "user_bubble"),
  logdir = vim.fn.tempname(),
}
vim.fn.mkdir(O.logdir, "p")
local MISSING = O.logdir .. "/missing-theme.json"
local NORD = { fg = token("nord", "ui", "fg"), bg = token("nord", "ui", "popover"), cursor = O.cursor }
local GRUVBOX =
  { fg = token("gruvbox-dark", "ui", "fg"), bg = token("gruvbox-dark", "ui", "popover"), cursor = O.cursor }
local GLOBAL = { fg = O.normal_fg, bg = O.normal_bg, cursor = O.cursor }
assert(hub.active == "nord" and NORD.bg ~= GRUVBOX.bg and NORD.bg ~= GLOBAL.bg)
-- Neovim appends terminal defaults (EndOfBuffer:, StatusLine:…) to the value.
local function themed(winhl)
  return type(winhl) == "string" and winhl:find("Normal:EnviT3Normal", 1, true) ~= nil
end

local function rgb(color)
  local n = tonumber(color:sub(2), 16)
  local r, g, b = bit.rshift(n, 16), bit.band(bit.rshift(n, 8), 0xff), bit.band(n, 0xff)
  return ("rgb:%02x%02x/%02x%02x/%02x%02x"):format(r, r, g, g, b, b)
end
local function answers(colors)
  return {
    ("\27]10;%s\27\\"):format(rgb(colors.fg)),
    ("\27]11;%s\27\\"):format(rgb(colors.bg)),
    ("\27]12;%s\27\\"):format(rgb(colors.cursor)),
  }
end

local failures, scenario, children = {}, "?", {}
local function check(ok, msg)
  if not ok then
    failures[#failures + 1] = scenario .. ": " .. msg
  end
end

local function c_spawn()
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
  -- Real keys; stay silent while consumed ('ttimeoutlen' after <Esc>).
  function c.input(keys)
    vim.rpcrequest(ch, "nvim_input", keys)
    vim.wait(200)
  end
  function c.ready(marker)
    assert(c.lua("return STRIKE.ready(...)", marker), scenario .. ": viewer " .. marker .. " never finished")
  end
  function c.open(id, theme_file, theme)
    c.lua(
      "vim.env.ENVI_THEME_FILE = select(2, ...) vim.env.ENVI_THEME = select(3, ...) require('hcmux.t3').toggle(select(1, ...))",
      id,
      theme_file or vim.NIL,
      theme or vim.NIL
    )
  end
  function c.hide()
    vim.wait(250)
    if c.lua("return vim.api.nvim_get_mode().mode") ~= "nt" then
      c.input("<Esc>")
    end
    c.input(":q<CR>")
    assert(
      vim.wait(2000, function()
        return c.state().win == nil
      end, 50),
      scenario .. ": q did not hide the popover"
    )
  end
  function c.osc(buf)
    return c.lua("return STRIKE.osc(...)", buf)
  end
  assert(c.lua("return dofile(...)(select(2, ...))", support, root, O))
  return c
end

local function check_osc(c, buf, want, label)
  local got = c.osc(buf)
  check(vim.deep_equal(got, answers(want)), ("%s: OSC answers %s, want bg %s"):format(label, vim.inspect(got), want.bg))
end

-- The background the popover actually shows for default cells: the rightmost
-- inner column of its grid (blank in every fake-viewer row).
local function canvas_bg(c, s)
  for g = 2, 400 do
    local ok, tl = pcall(vim.rpcrequest, c.ch, "nvim__inspect_cell", g, 0, 0)
    local ok2, tr = pcall(vim.rpcrequest, c.ch, "nvim__inspect_cell", g, 0, s.width + 1)
    if ok and ok2 and tl[1] == "╭" and tr[1] == "╮" then
      local seen = {}
      for r = 1, s.height do
        local cell = vim.rpcrequest(c.ch, "nvim__inspect_cell", g, r, s.width)
        seen[cell[2].background and ("#%06x"):format(cell[2].background) or "default"] = true
      end
      return vim.tbl_keys(seen)
    end
  end
end

-- A client started in the untinted tiled main pane, then opened in the popover
-- too: one client, independent viewer PTYs and per-view colour answers.
local function to_main(c)
  return c.lua([[for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative == "" then
        require("hcmux.t3").attach_in(w, "owned-main")
        return { win = w, buf = vim.api.nvim_win_get_buf(w), winhl = vim.wo[w].winhighlight }
      end
    end]])
end
local function shared(c)
  local main = to_main(c)
  c.ready("ownedmain")
  check(not themed(main.winhl), "main pane is untinted")
  check_osc(c, main.buf, GLOBAL, "main pane start")
  c.open("owned-main")
  local pop = c.state()
  check(pop.buf ~= main.buf and themed(pop.winhl), "independent buffer in the themed popover")
  check(c.lua("return vim.b[...].hcmux_addr", main.buf) == pop.addr, "same core client")
  check_osc(c, pop.buf, NORD, "popover")
  check_osc(c, main.buf, GLOBAL, "main remains untinted while popover is visible")
  check(c.lua("return vim.api.nvim_win_get_buf(...)", main.win) == main.buf, "main pane still shows it")
  return c, main
end
-- The surviving main pane: still showing the same buffer/viewer/client, still
-- untinted, its default cells drawn in the editor's Normal - and the buffer
-- continues answering that, independently of the popover's colours.
local function check_main(c, main, label, runs)
  local now = c.lua(
    [[local w, b = ... return { buf = vim.api.nvim_win_get_buf(w), winhl = vim.wo[w].winhighlight,
      pos = vim.api.nvim_win_get_position(w), width = vim.api.nvim_win_get_width(w),
      height = vim.api.nvim_win_get_height(w), job = vim.b[b].terminal_job_id }]],
    main.win,
    main.buf
  )
  check(now.buf == main.buf and not themed(now.winhl), label .. ": main pane shows the buffer, untinted")
  local cell = vim.rpcrequest(c.ch, "nvim__inspect_cell", 1, now.pos[1] + now.height - 1, now.pos[2] + now.width - 1)
  local bg = cell[2].background and ("#%06x"):format(cell[2].background) or GLOBAL.bg -- grid 1: none = Normal
  check(bg == GLOBAL.bg, label .. ": main pane canvas " .. bg)
  check(c.lua("return #STRIKE.runs") == (runs or 1), label .. ": no client recreated")
  check(
    c.lua("return STRIKE.attaches[STRIKE.facts['t3-owned-main'].address]") == 2,
    label .. ": two viewers, one client"
  )
  check(c.lua("return vim.fn.jobwait({ ... }, 0)[1] == -1", now.job), label .. ": viewer still running")
  check_osc(c, main.buf, GLOBAL, label)
end

local scenarios = {
  {
    "reopen a hidden client into a new float with a missing hub: OSC matches what it shows",
    function()
      local c = c_spawn()
      c.open("owned-reuse")
      c.ready("ownedreuse")
      local first = c.state()
      check_osc(c, first.buf, NORD, "themed")
      c.hide()
      c.open("owned-reuse", MISSING)
      local again = c.state()
      check(again.buf == first.buf and again.job == first.job and again.alive, "same buffer and process")
      check(c.lua("return STRIKE.attaches[...]", first.addr) == 1 and again.runs == 1, "no client or viewer recreated")
      -- Vim restores the buffer's window-local options in the new float, so
      -- it keeps the T3 look; the answer must be whatever is actually shown.
      vim.wait(200)
      local shown = canvas_bg(c, c.state())
      check(shown and #shown == 1, "one canvas colour, got " .. vim.inspect(shown))
      local want = (shown and shown[1] == NORD.bg) and NORD or GLOBAL
      check(shown and shown[1] == want.bg, "canvas " .. vim.inspect(shown) .. " is the popover or editor colour")
      check_osc(c, again.buf, want, "reopened float")
    end,
  },
  {
    "shared with the main pane, hidden with q: the main pane answers its own colours at once",
    function()
      local c, main = shared(c_spawn())
      c.hide() -- COMMAND q
      check_main(c, main, "after q, before any reattach")
      -- Attaching it to the main pane again changes nothing.
      local back = to_main(c)
      check(back.buf == main.buf and back.win == main.win, "same buffer back in the main pane")
      check_osc(
        c,
        back.buf,
        themed(back.winhl) and NORD or GLOBAL,
        "main pane again (" .. (themed(back.winhl) and "tinted" or "untinted") .. ")"
      )
    end,
  },
  {
    "shared with the main pane, popover closed with nvim_win_close: main pane answers its own colours",
    function()
      local c, main = shared(c_spawn())
      c.lua("vim.api.nvim_win_close((STRIKE.popover()), true)")
      check(c.state().win == nil, "popover closed")
      check_main(c, main, "after closing the float, before any reattach")
    end,
  },
  {
    "shared with the main pane, popover switched to another thread: main pane answers its own colours",
    function()
      local c, main = shared(c_spawn())
      c.open("owned-other") -- the popover window now shows another client
      c.ready("ownedother")
      local other = c.state()
      check(other.buf ~= main.buf and themed(other.winhl), "popover shows the other client")
      check_osc(c, other.buf, NORD, "other client in the popover")
      check_main(c, main, "after switching the popover away, before any reattach", 2)
      -- The popover itself keeps answering for what it shows.
      check(c.state().win == other.win, "popover still open")
      check_osc(c, other.buf, NORD, "other client still in the popover")
    end,
  },
  {
    "shown in the popover and the main pane, main pane switched away: popover colours again",
    function()
      local c, main = shared(c_spawn())
      local pop = c.state()
      local again = to_main(c) -- attached last in the untinted main pane: its colours
      check(again.buf == main.buf and not themed(again.winhl), "same buffer, untinted main pane")
      check_osc(c, main.buf, GLOBAL, "attached last in the main pane")
      c.lua("require('hcmux.t3').attach_in(..., 'owned-y')", main.win) -- main pane shows another client
      c.ready("ownedy")
      local still =
        c.lua("local w = ... return { buf = vim.api.nvim_win_get_buf(w), winhl = vim.wo[w].winhighlight }", pop.win)
      check(still.buf == pop.buf and themed(still.winhl), "popover keeps its independent viewer, tinted")
      check(c.lua("return STRIKE.attaches[STRIKE.facts['t3-owned-main'].address]") == 2, "two viewers, no third attach")
      check_osc(c, pop.buf, NORD, "after the main pane switched away, before any reattach")
    end,
  },
  {
    "same-buffer theme refresh follows the selected theme",
    function()
      local c = c_spawn()
      c.open("owned-refresh")
      c.ready("ownedrefresh")
      local first = c.state()
      check_osc(c, first.buf, NORD, "nord")
      c.open("owned-refresh", nil, "gruvbox-dark") -- focus the shown thread: re-themes in place
      local again = c.state()
      check(
        again.buf == first.buf and again.win == first.win and again.job == first.job,
        "same window, buffer, process"
      )
      check_osc(c, again.buf, GRUVBOX, "after refresh")
    end,
  },
  {
    "fresh viewer for a live client without a buffer, in place, broken hub",
    function()
      local c = c_spawn()
      c.open("owned-x")
      c.ready("ownedx")
      c.open("owned-y")
      c.ready("ownedy")
      local y = c.state()
      c.open("owned-x") -- y is now hidden
      c.lua("require('hcmux.term').detach(...)", y.buf)
      assert(
        vim.wait(2000, function()
          return not c.lua("return vim.api.nvim_buf_is_valid(...)", y.buf)
        end, 50),
        "detach did not drop the buffer"
      )
      check(c.lua("return STRIKE.facts[...].state", y.addr) == "live", "client still live in the core")
      c.open("owned-y", MISSING) -- broken hub: the shown window keeps its nord look
      local fresh = c.state()
      check(
        fresh.win == y.win and fresh.buf ~= y.buf and fresh.addr == y.addr,
        "new buffer for the same client, same window"
      )
      check(themed(fresh.winhl), "window keeps its T3 theme: " .. tostring(fresh.winhl))
      check(c.lua("return STRIKE.attaches[...]", y.addr) == 2 and fresh.runs == 2, "a second viewer, no new client")
      check_osc(c, fresh.buf, NORD, "fresh viewer")
    end,
  },
  {
    "existing hidden buffer shown in place takes the window's colours",
    function()
      local c = c_spawn()
      c.open("owned-p")
      c.ready("ownedp")
      local p = c.state()
      c.open("owned-q")
      c.ready("ownedq")
      c.open("owned-q", nil, "gruvbox-dark") -- re-theme the shown window: gruvbox
      c.open("owned-p", MISSING) -- broken hub: window stays gruvbox
      local shown = c.state()
      check(shown.buf == p.buf and shown.job == p.job and themed(shown.winhl), "same buffer, themed window")
      check(c.lua("return STRIKE.attaches[...]", p.addr) == 1, "no new viewer")
      check_osc(c, shown.buf, GRUVBOX, "existing buffer")
    end,
  },
  {
    "term.open{display}: a generic terminal's first byte and OSC answers use it",
    function()
      local c = c_spawn()
      local want = { fg = "#123456", bg = "#654321", cursor = O.cursor }
      local buf = c.lua(
        "require('hcmux.term').open(nil, { where = 'split', display = { fg = '#123456', bg = '#654321' } }) return vim.api.nvim_get_current_buf()"
      )
      c.ready("ORD1")
      local d = c.lua("return STRIKE.runs[1].params.display")
      check(d.fg == want.fg and d.bg == want.bg and d.cursor == O.cursor, "terminal.run display " .. vim.inspect(d))
      check_osc(c, buf, want, "generic terminal")
      local plain = c.lua("require('hcmux.term').open(nil, { where = 'split' }) return vim.api.nvim_get_current_buf()")
      c.ready("ORD2")
      check_osc(c, plain, GLOBAL, "terminal without display")
    end,
  },
  {
    ":T3Restart starts the new client with the popover colours",
    function()
      local c = c_spawn()
      c.open("owned-restart")
      c.ready("ownedrestart")
      c.lua("require('hcmux.t3').restart()")
      local runs = c.lua("return #STRIKE.runs")
      check(runs == 2, "restart started one new client, runs=" .. runs)
      local d = c.lua("return STRIKE.runs[2].params.display")
      check(
        d.fg == NORD.fg and d.bg == NORD.bg,
        ("restart terminal.run display %s/%s, want %s/%s"):format(d.fg, d.bg, NORD.fg, NORD.bg)
      )
      check(c.lua("return STRIKE.runs[2].labels['t3.thread']") == "owned-restart", "same thread")
    end,
  },
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
for _, s in ipairs(scenarios) do
  scenario = s[1]
  local ok, err = pcall(s[2])
  if not ok then
    failures[#failures + 1] = scenario .. ": " .. tostring(err)
  end
  stop_children()
end
vim.fn.delete(O.logdir, "rf")
if #failures > 0 then
  error(("%d failure(s) in %d scenarios:\n  %s"):format(#failures, #scenarios, table.concat(failures, "\n  ")), 0)
end
print(("T3 lifecycle colour scenarios passed: %d"):format(#scenarios))
