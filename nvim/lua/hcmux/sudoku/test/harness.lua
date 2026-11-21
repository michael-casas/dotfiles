-- Headless Sudoku harness: the README's @headless conventions, shared by WP1–WP5.
-- Run a suite through run.sh (isolated XDG homes). A suite file:
--   local H = require("hcmux.sudoku.test.harness")
--   H.boot()
--   H.scenario("title from the .feature", function() H.background() H.type("...") ... end)
--   H.finish()
-- Keys go through nvim_feedkeys(keys, "mtx"), one typed command per H.type call.
local api = vim.api
local H = {}

H.root = vim.fn.getcwd() -- run.sh starts nvim in the repository root
H.now = 0 -- the injected clock, in ms

-- The README's `classic` fixture, written out independently of the module.
H.CLASSIC = {
  { 5, 3, 0, 0, 7, 0, 0, 0, 0 },
  { 6, 0, 0, 1, 9, 5, 0, 0, 0 },
  { 0, 9, 8, 0, 0, 0, 0, 6, 0 },
  { 8, 0, 0, 0, 6, 0, 0, 0, 3 },
  { 4, 0, 0, 8, 0, 3, 0, 0, 1 },
  { 7, 0, 0, 0, 2, 0, 0, 0, 6 },
  { 0, 6, 0, 0, 0, 0, 2, 8, 0 },
  { 0, 0, 0, 4, 1, 9, 0, 0, 5 },
  { 0, 0, 0, 0, 8, 0, 0, 7, 9 },
}

local results, current = { failed = 0, passed = 0 }, nil

function H.sudoku()
  return require("hcmux.sudoku")
end

function H.drain()
  vim.wait(20, function()
    return false
  end)
end

--- Load the worktree config the way envi does, minus the GUI: Snacks, LazyVim's
--- global keymaps (the <C-h/j/k/l> and <Esc> maps the game must override), the
--- :q router, then the Sudoku command. opts.explorer = false skips Snacks' explorer.
function H.boot(opts)
  opts = opts or {}
  vim.o.columns, vim.o.lines = opts.columns or 80, opts.lines or 40
  vim.o.shell = "sh"
  vim.g.mapleader = " "
  local config = H.root .. "/nvim"
  local plugins = assert(vim.env.ENVI_TEST_PLUGIN_ROOT, "run through nvim/lua/hcmux/sudoku/test/run.sh")
  vim.opt.rtp:prepend(config)
  for _, name in ipairs({ "snacks.nvim", "LazyVim", "lazy.nvim" }) do
    assert(vim.uv.fs_stat(plugins .. "/" .. name), "install " .. name .. " or set ENVI_TEST_PLUGIN_ROOT")
    vim.opt.rtp:prepend(plugins .. "/" .. name)
  end
  local snacks_opts = require("plugins.neo-tree")[2].opts
  snacks_opts.terminal = require("lazyvim.plugins.util")[1].opts.terminal
  _G.Snacks = require("snacks")
  Snacks.setup(snacks_opts)
  require("plugins.panel-close")[1].opts(nil, snacks_opts)
  _G.LazyVim = require("lazyvim.util")
  require("lazy.core.handler").init()
  require("lazyvim.config.keymaps")
  require("config.panel-close")
  H.sudoku().setup()
  H.sudoku()._set_clock(function()
    return H.now
  end)
  H.scratch = assert(vim.uv.fs_mkdtemp(vim.fn.tempname() .. "-XXXXXX"))
  vim.fn.writefile({ "the classic puzzle as text" }, H.scratch .. "/grid.txt")
  vim.cmd.cd(H.scratch)
  H.explorer_wanted = opts.explorer ~= false
end

--- The shared Background's layout: "grid.txt" with focus, a shell split below it
--- and (unless disabled) the Snacks explorer on the left. Built through the API.
function H.layout()
  H.sudoku()._reset()
  if not (H.grid and api.nvim_win_is_valid(H.grid)) then
    vim.cmd.edit(H.scratch .. "/grid.txt")
    H.grid = api.nvim_get_current_win()
  end
  if not (H.term and api.nvim_win_is_valid(H.term)) then
    H.term = api.nvim_open_win(api.nvim_create_buf(true, false), false, { split = "below", win = H.grid })
    api.nvim_win_call(H.term, function()
      vim.fn.jobstart({ "sh" }, { term = true })
    end)
  end
  if H.explorer_wanted and not (H.explorer and not H.explorer.closed) then
    api.nvim_set_current_win(H.grid)
    H.explorer = Snacks.explorer({ cwd = H.scratch, git_status = false, diagnostics = false, watch = false })
    assert(
      vim.wait(2000, function()
        return H.explorer:current_win() == "list"
      end, 10),
      "explorer opens on its list"
    )
  end
  api.nvim_set_current_win(H.grid)
  vim.cmd.stopinsert()
  H.now = 0
  H.drain()
end

--- Layout + `:EnviSudoku new classic`: the popover is focused in NORMAL at R1C1.
function H.background()
  H.layout()
  H.type(":EnviSudoku new classic<CR>")
  local s = H.state()
  assert(s.open and s.focused and s.cursor.r == 1 and s.cursor.c == 1, "Background: popover focused at R1C1")
end

--- Type keys as the user would: one command per call, mappings applied.
--- In-process feedkeys never returns to Neovim's main loop, which is where
--- CursorMoved fires after a command, so fire it the same way: once, if the
--- cursor moved within the window that had focus.
function H.type(keys)
  local win = api.nvim_get_current_win()
  local before = api.nvim_win_get_cursor(win)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "mtx", false)
  if api.nvim_get_current_win() == win and not vim.deep_equal(api.nvim_win_get_cursor(win), before) then
    api.nvim_exec_autocmds("CursorMoved", { buffer = api.nvim_get_current_buf() })
  end
  H.drain()
end

--- Advance the injected clock (the footer re-renders as its tick would).
function H.advance(ms)
  H.now = H.now + ms
  H.sudoku().refresh()
end

function H.state()
  return H.sudoku().state()
end

--- Setup for a Given that later WPs' keys would produce: set it on the model.
function H.place(r, c)
  H.sudoku().game().cursor = { r = r, c = c }
  H.sudoku().refresh()
end

function H.enter(r, c, digit)
  H.sudoku().game().board[r][c] = digit
  H.sudoku().refresh()
end

function H.lines()
  return api.nvim_buf_get_lines(H.state().buf, 0, -1, false)
end

function H.footer()
  local lines = H.lines()
  return vim.trim(lines[#lines])
end

--- Highlight groups of the extmarks covering cell (r, c)'s digit.
function H.groups(r, c)
  local render = require("hcmux.sudoku.render")
  local row, s, e = render.span(r, c)
  local found = {}
  for _, m in
    ipairs(api.nvim_buf_get_extmarks(H.state().buf, render.ns, { row, s }, { row, e - 1 }, {
      details = true,
      overlap = true,
    }))
  do
    local d = m[4]
    if d.hl_group and m[2] == row and m[3] < e and (d.end_col or 0) > s then
      found[d.hl_group] = true
    end
  end
  return found
end

--- The extmark spans highlighted with `group`, as "row:start-end" strings.
function H.spans(group)
  local render = require("hcmux.sudoku.render")
  local out = {}
  for _, m in ipairs(api.nvim_buf_get_extmarks(H.state().buf, render.ns, 0, -1, { details = true })) do
    if m[4].hl_group == group then
      out[#out + 1] = string.format("%d:%d-%d", m[2], m[3], m[4].end_col)
    end
  end
  table.sort(out)
  return out
end

function H.eq(actual, expected, what)
  if not vim.deep_equal(actual, expected) then
    error(
      string.format(
        "%s\n  expected: %s\n  actual:   %s",
        what or "values differ",
        vim.inspect(expected),
        vim.inspect(actual)
      ),
      2
    )
  end
end

function H.ok(cond, what)
  if not cond then
    error(what or "assertion failed", 2)
  end
end

--- Screen rectangle {top, left, bottom, right} (exclusive), border included.
function H.rect(win)
  local pos = api.nvim_win_get_position(win)
  local cfg = api.nvim_win_get_config(win)
  local pad = (cfg.relative ~= "" and cfg.border and cfg.border ~= "none") and 2 or 0
  return { pos[1], pos[2], pos[1] + api.nvim_win_get_height(win) + pad, pos[2] + api.nvim_win_get_width(win) + pad }
end

function H.overlap(a, b)
  return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end

function H.scenario(name, fn)
  current = name
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    results.passed = results.passed + 1
    io.stdout:write("\nSCENARIO ok   " .. name .. "\n")
  else
    results.failed = results.failed + 1
    io.stdout:write("\nSCENARIO FAIL " .. name .. "\n" .. tostring(err):gsub("\n", "\n       ") .. "\n")
  end
  current = nil
end

function H.finish()
  pcall(function()
    H.sudoku()._reset()
  end)
  assert(results.passed + results.failed > 0, "no scenarios ran")
  assert(
    results.failed == 0,
    string.format("%d of %d scenarios failed", results.failed, results.passed + results.failed)
  )
end

return H
