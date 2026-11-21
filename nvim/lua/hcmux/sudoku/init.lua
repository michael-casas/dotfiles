-- Sudoku popover (`:EnviSudoku [new [<puzzle>]]`): the window shell, the model and the timer.
-- Seams for later work (keys, highlight layers, footer, state fields, events): README.md.
local api = vim.api
local panel_close = require("config.panel-close")
local Game = require("hcmux.sudoku.game")
local keys = require("hcmux.sudoku.keys")
local render = require("hcmux.sudoku.render")
local puzzles = require("hcmux.sudoku.puzzles")

local M = {}
local ZINDEX = 60 -- the floor: above Snacks layouts and pickers (50) and the explorer (33)
local ZMAX = 99 -- Neovim's own layers start at 100 (popupmenu, messages, cmdline)
local game -- the in-memory puzzle; it outlives the window (:q pauses, :EnviSudoku resumes)
-- { win, buf, invoker, group, tick, caret, zindex, had_focus, gen } while the popover is shown
local view
local listeners, extenders = {}, {}

local function valid(win)
  return win ~= nil and api.nvim_win_is_valid(win)
end

--- Subscribe to "load" (no puzzle in memory: call M.set_game to supply one), "new",
--- "open", "render" and "close"; fn(game). Returns an unsubscribe function.
--- "before_new" runs before `:EnviSudoku new` changes anything: fn(ctx) with
--- ctx = { puzzle, requested, game, confirmed }; returning false declines (README).
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

local function allowed(ctx)
  for _, fn in ipairs(vim.list_slice(listeners.before_new or {})) do
    if fn(ctx) == false then
      return false
    end
  end
  return true
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

-- The editor rows a float may use (below the tabline, above the statusline and
-- command line) and the columns.
local function viewport()
  local top = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1)) and 1 or 0
  local bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  return top, math.max(top + 1, bottom), vim.o.columns
end

local function rect(win)
  local pos, cfg = api.nvim_win_get_position(win), api.nvim_win_get_config(win)
  local pad = (cfg.relative ~= "" and cfg.border and cfg.border ~= "none") and 2 or 0
  return { pos[1], pos[2], pos[1] + api.nvim_win_get_height(win) + pad, pos[2] + api.nvim_win_get_width(win) + pad }
end

-- One above every Snacks window the board overlaps (Snacks stacks its own new
-- windows the same way), never below ZINDEX and never into Neovim's own layers.
local function zindex_for(r)
  local z = ZINDEX
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local cfg = api.nvim_win_get_config(w)
    local other = cfg.zindex or 0
    if (not view or w ~= view.win) and cfg.relative ~= "" and vim.w[w].snacks_win and other < 100 then
      local o = rect(w)
      if r[1] < o[3] and o[1] < r[3] and r[2] < o[4] and o[2] < r[4] then
        z = math.max(z, other + 1)
      end
    end
  end
  return math.min(z, ZMAX)
end

-- The largest layout that fits the viewport (README: minimum viewport), centred.
-- Below the minimum the window is clamped to the screen and the board is clipped.
local function geometry()
  local top, bottom, cols = viewport()
  local rows = bottom - top
  local full = render.LAYOUTS.full
  render.set_layout((cols >= full.width + 2 and rows >= full.height + 2) and "full" or "compact")
  local w, h = render.size()
  w, h = math.max(1, math.min(w, cols - 2)), math.max(1, math.min(h, rows - 2))
  local cfg = {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " SUDOKU ",
    title_pos = "center",
    width = w,
    height = h,
    row = top + math.max(0, math.floor((rows - h - 2) / 2)),
    col = math.max(0, math.floor((cols - w - 2) / 2)),
  }
  cfg.zindex = zindex_for({ cfg.row, cfg.col, cfg.row + h + 2, cfg.col + w + 2 })
  return cfg
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

-- Focus can move without WinLeave (Snacks' layouts focus with noautocmd), so the
-- caret also follows focus on WinEnter and on every timer tick. view.had_focus is
-- the last focus seen there, i.e. before any such move.
local function sync_caret()
  if not view then
    return
  end
  view.had_focus = M.focused()
  if view.had_focus then
    hide_caret()
  else
    show_caret()
  end
end

-- The board never scrolls: it is exactly as tall as its window (scroll keys are
-- consumed, and a wheel over the unfocused float or any native scroll is undone).
-- A viewport below the minimum clips the board instead, so it may scroll then.
local function keep_view()
  if view and valid(view.win) and api.nvim_win_get_height(view.win) >= api.nvim_buf_line_count(view.buf) then
    local v = api.nvim_win_call(view.win, vim.fn.winsaveview)
    if v.topline ~= 1 or v.leftcol ~= 0 then
      api.nvim_win_call(view.win, function()
        vim.fn.winrestview({ topline = 1, leftcol = 0 })
      end)
    end
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
  keep_view()
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
  {
    "keep the board in view",
    "<C-e> <C-y> <C-d> <C-u> <C-f> <C-b> <PageUp> <PageDown> <S-Up> <S-Down> zt zz zb z<CR> z. z- zh zl zH zL zs ze"
      .. " <ScrollWheelUp> <ScrollWheelDown> <ScrollWheelLeft> <ScrollWheelRight>",
  },
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
  local cfg = geometry()
  local win = api.nvim_open_win(buf, true, cfg)
  -- winfixbuf: buffer switches (LazyVim's [b ]b, :bnext …) never replace the board in its window.
  local wo = { winblend = 0, wrap = false, cursorline = false, scrolloff = 0, sidescrolloff = 0, winfixbuf = true }
  for opt, value in pairs(wo) do
    vim.wo[win][opt] = value
  end
  local group = api.nvim_create_augroup("EnviSudokuView", { clear = true })
  -- The invoker is fixed here, when the board window is created (refocusing keeps it).
  view = { win = win, buf = buf, invoker = invoker, group = group, zindex = cfg.zindex, gen = 0 }
  panel_close.bind(buf, M.close, "Sudoku: pause and close")
  api.nvim_create_autocmd("CursorMoved", { group = group, buffer = buf, callback = place_cursor })
  api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      -- A real focus change (one that runs autocmds) to any window but the board,
      -- Snacks' included: any pending resize recovery is void (view.gen). Snacks'
      -- own rebuild moves use noautocmd, so they never get here.
      if view and not M.focused() then
        view.gen = view.gen + 1
      end
      sync_caret()
      place_cursor()
    end,
  })
  api.nvim_create_autocmd("WinScrolled", { group = group, pattern = tostring(win), callback = keep_view })
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
        local g = geometry()
        api.nvim_win_set_config(win, g)
        view.zindex = g.zindex
        M.refresh()
      end
      -- A resize is not a reason to leave the game. Snacks' own VimResized handlers
      -- (which run first) move focus with noautocmd, at once and again in a scheduled
      -- rebuild (live finding), so decide from the focus seen before the resize, and
      -- only for that transition: a real focus change since then (view.gen) or
      -- closing the board cancels the recovery.
      if view and view.had_focus then
        local gen = view.gen
        local function back()
          if view and view.win == win and view.gen == gen and valid(win) and api.nvim_get_current_win() ~= win then
            api.nvim_set_current_win(win)
          end
        end
        vim.schedule(function()
          vim.schedule(back)
        end)
        vim.defer_fn(back, 100)
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
        sync_caret()
        keep_view()
      end
    end)
  )
  sync_caret()
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
    if not allowed({ puzzle = name, requested = opts.puzzle, game = game, confirmed = opts.confirmed }) then
      return
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
    -- Back on top of any Snacks window opened over it since (e.g. a picker).
    local g = geometry()
    view.zindex = g.zindex
    api.nvim_win_set_config(view.win, g)
    if api.nvim_get_current_win() ~= view.win then
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
    zindex = open and api.nvim_win_get_config(view.win).zindex or ZINDEX,
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
