-- Sudoku popover (`:EnviSudoku [new [<puzzle>]]`): the window shell, the model and the timer.
-- Seams for later work (keys, highlight layers, footer, state fields, events): README.md.
local api = vim.api
local panel_close = require("config.panel-close")
local Game = require("hcmux.sudoku.game")
local keys = require("hcmux.sudoku.keys")
local render = require("hcmux.sudoku.render")
local puzzles = require("hcmux.sudoku.puzzles")

local M = {}
local ZINDEX = 60 -- above Snacks layouts and pickers (50) and the explorer (33)
local game -- the in-memory puzzle; it outlives the window (:q pauses, :EnviSudoku resumes)
local view -- { win, buf, invoker, group, tick, caret } while the popover is shown
local listeners, extenders = {}, {}

local function valid(win)
  return win ~= nil and api.nvim_win_is_valid(win)
end

--- Subscribe to "load" (no puzzle in memory: call M.set_game to supply one), "new",
--- "open", "render" and "close"; fn(game). Returns an unsubscribe function.
function M.on(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
  return function()
    for i, f in ipairs(listeners[event]) do
      if f == fn then
        return table.remove(listeners[event], i)
      end
    end
  end
end

local function emit(event)
  for _, fn in ipairs(vim.list_slice(listeners[event] or {})) do
    fn(game)
  end
end

--- fn(state, game) adds or fills fields of every state() snapshot (search, undo, …).
function M.extend_state(fn)
  extenders[#extenders + 1] = fn
end

--- The live model (mutable; later WPs edit it, then call M.refresh()). nil if none.
function M.game()
  return game
end

function M.set_game(g)
  game = g
end

function M._set_clock(fn)
  Game.set_clock(fn)
end

function M.focused()
  return view ~= nil and valid(view.win) and api.nvim_get_current_win() == view.win
end

local function geometry()
  local rows, cols = vim.o.lines - vim.o.cmdheight, vim.o.columns
  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " SUDOKU ",
    title_pos = "center",
    zindex = ZINDEX,
    width = render.WIDTH,
    height = render.HEIGHT,
    row = math.max(0, math.floor((rows - render.HEIGHT - 2) / 2)),
    col = math.max(0, math.floor((cols - render.WIDTH - 2) / 2)),
  }
end

-- No text caret: Neovim's cursor sits on the selected digit (inside the outline),
-- and guicursor hides it while the board has focus. The command line keeps its caret.
local function hide_caret()
  if view and not view.caret then
    view.caret = vim.o.guicursor
    vim.o.guicursor = view.caret .. ",n-v-ve-o-i-r-sm:block-EnviSudokuCaret"
  end
end

local function show_caret()
  if view and view.caret then
    vim.o.guicursor, view.caret = view.caret, nil
  end
end

local function place_cursor()
  if M.focused() then
    local row, s = render.span(game.cursor.r, game.cursor.c)
    local want = { row + 1, s + 1 }
    if not vim.deep_equal(api.nvim_win_get_cursor(view.win), want) then
      api.nvim_win_set_cursor(view.win, want)
    end
  end
end

local dispatch

--- Redraw the board, the keys for the current game mode and the cursor.
function M.refresh()
  if not (view and game and api.nvim_buf_is_valid(view.buf)) then
    return
  end
  render.draw(view.buf, game)
  keys.attach(view.buf, game.mode, dispatch)
  place_cursor()
  emit("render")
end

function dispatch(lhs)
  local spec = keys.handler(lhs, game.mode)
  if spec then
    spec.fn(game, { lhs = lhs, count = vim.v.count, count1 = vim.v.count1 })
  end
  M.refresh()
end
keys.on_change = M.refresh

-- The board consumes these in every game mode until a handler claims them, so
-- no native edit, Insert or Visual mode leaks onto the board, <Esc> never closes
-- it (and never runs LazyVim's :noh) and <C-h/j/k/l> never move focus to a split
-- hidden under it (REC F2). Native motions are harmless: the cursor snaps back.
-- H/L are LazyVim's buffer switches (<S-h>/<S-l>).
local CONSUMED = {
  { "no edit here", "i I a A o O s S c C d D x X r R p P u U <C-r> . J ~ v V <C-v> gJ gi gv" },
  { "stay on the board", "<Esc> H L" },
  { "keep focus on the board", "<C-h> <C-j> <C-k> <C-l>" },
}
for _, group in ipairs(CONSUMED) do
  for _, lhs in ipairs(vim.split(group[2], " ")) do
    keys.register({ lhs = lhs, mode = "*", desc = ("Sudoku: %s (%s)"):format(group[1], lhs), fn = function() end })
  end
end

local function teardown()
  local v = view
  if not v then
    return
  end
  show_caret()
  view = nil
  if game then
    game.timer:pause()
  end
  pcall(api.nvim_del_augroup_by_id, v.group)
  if v.tick then
    v.tick:stop()
    v.tick:close()
  end
  keys.detach(v.buf)
  return v
end

--- Pause the timer and close the popover; focus returns to the window that opened it.
function M.close()
  local v = teardown()
  if not v then
    return
  end
  if valid(v.invoker) and v.invoker ~= v.win then
    api.nvim_set_current_win(v.invoker)
  end
  if valid(v.win) then
    pcall(api.nvim_win_close, v.win, true)
  end
  if api.nvim_buf_is_valid(v.buf) then
    pcall(api.nvim_buf_delete, v.buf, { force = true })
  end
  emit("close")
end

local function show()
  local invoker = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true) -- unlisted, nofile: never in a session layout
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "envi-sudoku"
  api.nvim_buf_set_name(buf, "envi-sudoku://board")
  render.define_hl()
  local win = api.nvim_open_win(buf, true, geometry())
  -- winfixbuf: buffer switches (LazyVim's [b ]b, :bnext …) never replace the board in its window.
  local wo = { winblend = 0, wrap = false, cursorline = false, scrolloff = 0, sidescrolloff = 0, winfixbuf = true }
  for opt, value in pairs(wo) do
    vim.wo[win][opt] = value
  end
  local group = api.nvim_create_augroup("EnviSudokuView", { clear = true })
  view = { win = win, buf = buf, invoker = invoker, group = group }
  panel_close.bind(buf, M.close, "Sudoku: pause and close")
  api.nvim_create_autocmd("CursorMoved", { group = group, buffer = buf, callback = place_cursor })
  api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      if M.focused() then
        hide_caret()
        place_cursor()
      end
    end,
  })
  api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      if M.focused() then
        show_caret()
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", { -- closed by other means (:close, <C-w>o …)
    group = group,
    pattern = tostring(win),
    callback = function()
      if teardown() then
        emit("close")
      end
    end,
  })
  api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if valid(win) then
        api.nvim_win_set_config(win, geometry())
      end
    end,
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      render.define_hl()
      M.refresh()
    end,
  })
  view.tick = vim.uv.new_timer()
  view.tick:start(
    250,
    250,
    vim.schedule_wrap(function()
      if view and view.buf == buf and game and api.nvim_buf_is_valid(buf) then
        render.draw_footer(buf, game)
      end
    end)
  )
  hide_caret()
end

--- Open or focus the popover. opts.new starts a fresh puzzle (opts.puzzle names
--- one, else a random bundled one); otherwise the in-memory puzzle resumes.
function M.open(opts)
  opts = opts or {}
  if opts.new then
    local name = opts.puzzle or puzzles.random()
    if not puzzles.board(name) then
      return vim.notify("EnviSudoku: no puzzle named " .. name, vim.log.levels.ERROR)
    end
    if game then
      game.timer:pause()
    end
    game = Game.new(name)
    emit("new")
  elseif not game then
    emit("load")
    game = game or Game.new(puzzles.random())
  end
  if view and valid(view.win) then
    local cur = api.nvim_get_current_win()
    if cur ~= view.win then
      view.invoker = cur
      api.nvim_set_current_win(view.win)
    end
  else
    show()
  end
  game.timer:resume()
  M.refresh()
  emit("open")
end

local function register_value()
  local ok, text = pcall(vim.fn.getreg, '"')
  text = ok and type(text) == "string" and text:gsub("\n$", "") or ""
  return text:match("^[1-9]$") and text or nil
end

function M.save_path()
  local session = tostring(vim.g.hcmux_session or "default"):gsub("[^%w._-]", "_")
  return vim.fn.stdpath("state") .. "/envi-sudoku/" .. session .. ".json"
end

--- Read-only observation (features/README.md): a fresh copy on every call.
function M.state()
  local open = view ~= nil and valid(view.win)
  local s = {
    open = open,
    focused = M.focused(),
    win = open and view.win or nil,
    buf = open and view.buf or nil,
    zindex = ZINDEX,
    mode = game and game.mode or "normal",
    cursor = game and vim.deepcopy(game.cursor) or nil,
    board = game and vim.deepcopy(game.board) or nil,
    givens = game and vim.deepcopy(game.givens) or nil,
    draft = nil,
    search = nil,
    register = register_value(),
    undo = 0,
    redo = 0,
    timer = game and { status = game.timer.status, elapsed_ms = game.timer:elapsed() } or nil,
    conflicts = {},
    save_path = M.save_path(),
    hl = render.summary(open and game or nil),
  }
  for _, fn in ipairs(extenders) do
    fn(s, game)
  end
  return s
end

--- Tests: close without a trace and forget the puzzle.
function M._reset()
  M.close()
  game = nil
end

function M.setup()
  api.nvim_create_user_command("EnviSudoku", function(a)
    local args = a.fargs
    if #args == 0 then
      return M.open()
    elseif args[1] == "new" and #args <= 2 then
      return M.open({ new = true, puzzle = args[2] })
    end
    vim.notify("Usage: :EnviSudoku [new [<puzzle>]]", vim.log.levels.WARN)
  end, {
    nargs = "*",
    desc = "Sudoku: open or focus the popover; `new [<puzzle>]` starts a fresh one",
    complete = function(_, line)
      return line:match("^%s*%S+%s+new%s+") and puzzles.names() or { "new" }
    end,
  })
end

-- Later work packages add modules under lua/hcmux/sudoku/ext/ instead of editing
-- this core; each loads once, in name order, after the core (README: Seams).
package.loaded["hcmux.sudoku"] = M
local ext = {}
for _, path in ipairs(api.nvim_get_runtime_file("lua/hcmux/sudoku/ext/*.lua", true)) do
  ext[vim.fn.fnamemodify(path, ":t:r")] = true
end
local names = vim.tbl_keys(ext)
table.sort(names)
for _, name in ipairs(names) do
  require("hcmux.sudoku.ext." .. name)
end

return M
