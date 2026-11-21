-- WP4: digit entry, undo/redo, yank/paste, clear and conflicts, on WP1's seam
-- (README: Seams). Contract: features 04, 05, 06, 10 "INSERT discards" and 11
-- (insert guides, conflicts); OPEN-QUESTIONS Q3, Q4, Q11, Q15, Q16, Q18 defaults.
--
-- NORMAL  i      enter INSERT on the selected tile (row/column guides, the rest dimmed)
--         u      undo [count] board edits; the cursor goes to the changed tile
--         <C-r>  redo [count]; a new edit clears redo
--         y      yank the tile's digit into the unnamed register (and the clipboard
--                register 'clipboard' names); an empty tile leaves it intact
--         p      paste a single 1-9 from that register into an editable tile
--         x      clear an editable entry
-- INSERT  1-9    stage a draft (a later digit replaces it); givens refuse it
--         <CR>   commit the draft (none: change nothing) and return to NORMAL
--         <Esc>  discard the draft and return to NORMAL
--         other board keys (hjkl, 0, …) are ignored, never typed or moved
--
-- Givens are immutable. Every committed change is one undo step; navigation,
-- search, canceled drafts and no-op edits are not. Conflicts (a repeated digit in
-- a row, column or box) are flagged live, not blocked. `solved(board)` and
-- `on_edit(fn)` are what WP5's SOLVED timer reads; a solved timer refuses edits.
local api = vim.api
local sudoku = require("hcmux.sudoku")
local keys = require("hcmux.sudoku.keys")
local render = require("hcmux.sudoku.render")

local M = { ns = api.nvim_create_namespace("envi_sudoku_draft") }

-- Per-game state that is not part of the puzzle model (and never saved with it).
local history = setmetatable({}, { __mode = "k" }) -- game -> { undo = {}, redo = {} }
local drafts = setmetatable({}, { __mode = "k" }) -- game -> staged digit
local edit_listeners = {}

local function hist(game)
  history[game] = history[game] or { undo = {}, redo = {} }
  return history[game]
end

local function notice(msg)
  vim.notify("Sudoku: " .. msg, vim.log.levels.INFO)
end

local function cell_name(game)
  return ("R%dC%d"):format(game.cursor.r, game.cursor.c)
end

local function on_given(game)
  return game.givens[game.cursor.r][game.cursor.c]
end

--- The cells (row-major) whose digit repeats in their row, column or 3x3 box.
function M.conflicts(board)
  local out = {}
  for r = 1, 9 do
    for c = 1, 9 do
      local d, hit = board[r][c], false
      if d ~= 0 then
        local br, bc = r - (r - 1) % 3, c - (c - 1) % 3
        for k = 1, 9 do
          local rr, cc = br + math.floor((k - 1) / 3), bc + (k - 1) % 3
          hit = hit
            or (k ~= c and board[r][k] == d)
            or (k ~= r and board[k][c] == d)
            or ((rr ~= r or cc ~= c) and board[rr][cc] == d)
        end
      end
      if hit then
        out[#out + 1] = { r = r, c = c }
      end
    end
  end
  return out
end

--- A full board with no conflicts (Q4).
function M.solved(board)
  for r = 1, 9 do
    for c = 1, 9 do
      if board[r][c] == 0 then
        return false
      end
    end
  end
  return #M.conflicts(board) == 0
end

--- fn(game, change) after every committed edit, undo and redo; change =
--- { r, c, before, after, kind = "edit"|"undo"|"redo" }. Returns an unsubscribe.
function M.on_edit(fn)
  edit_listeners[#edit_listeners + 1] = fn
  return function()
    for i, f in ipairs(edit_listeners) do
      if f == fn then
        return table.remove(edit_listeners, i)
      end
    end
  end
end

local function changed(game, change)
  for _, fn in ipairs(vim.list_slice(edit_listeners)) do
    fn(game, change)
  end
end

local function locked(game)
  if game.timer.status == "solved" then
    notice("solved; start a new puzzle with :EnviSudoku new")
    return true
  end
  return false
end

--- Set the selected tile to `digit` (0 clears) as one undo step. Givens, a solved
--- board and no-op edits change nothing and record nothing.
local function edit(game, digit)
  local r, c = game.cursor.r, game.cursor.c
  if game.givens[r][c] then
    return notice(cell_name(game) .. " is a given")
  end
  local before = game.board[r][c]
  if before == digit or locked(game) then
    return
  end
  local h = hist(game)
  h.undo[#h.undo + 1] = { r = r, c = c, before = before, after = digit }
  h.redo = {}
  game.board[r][c] = digit
  changed(game, { r = r, c = c, before = before, after = digit, kind = "edit" })
end

-- Move up to `count` steps from one stack to the other; the cursor follows.
local function travel(game, count, from, to, field, kind, none)
  local h = hist(game)
  if #h[from] == 0 then
    return notice(none)
  end
  if locked(game) then
    return
  end
  for _ = 1, count do
    local step = table.remove(h[from])
    if not step then
      break
    end
    h[to][#h[to] + 1] = step
    game.board[step.r][step.c] = step[field]
    game.cursor = { r = step.r, c = step.c }
    changed(game, { r = step.r, c = step.c, before = step.before, after = step.after, kind = kind })
  end
end

-- The register `y`/`p` use: the unnamed one, which 'clipboard' (unnamedplus in
-- envi) points at the system clipboard, as Vim's own y and p do (Q18).
local function clipboard_reg()
  local cb = vim.o.clipboard
  return cb:find("unnamedplus", 1, true) and "+" or (cb:find("unnamed", 1, true) and "*") or nil
end

local function yank(digit)
  local text = tostring(digit)
  local reg = clipboard_reg()
  if reg then
    pcall(vim.fn.setreg, reg, text, "v")
  end
  vim.fn.setreg('"', text, "v")
  vim.fn.setreg("0", text, "v")
end

local function register_digit()
  local reg, text = clipboard_reg(), nil
  if reg then
    local ok, value = pcall(vim.fn.getreg, reg)
    text = ok and value ~= "" and value or nil
  end
  text = (text or vim.fn.getreg('"')):gsub("\n$", "")
  return text:match("^[1-9]$") and tonumber(text) or nil
end

local function set_mode(game, mode)
  game.mode, drafts[game] = mode, nil
end

local function key(lhs, mode, desc, fn)
  keys.register({ lhs = lhs, mode = mode, desc = "Sudoku: " .. desc, fn = fn })
end

-- NORMAL
key("i", "normal", "enter a digit on the selected tile", function(game)
  if not locked(game) then
    set_mode(game, "insert")
  end
end)
key("u", "normal", "undo [count] board edits", function(game, ctx)
  travel(game, ctx.count1, "undo", "redo", "before", "undo", "Already at oldest change")
end)
key("<C-r>", "normal", "redo [count] board edits", function(game, ctx)
  travel(game, ctx.count1, "redo", "undo", "after", "redo", "Already at newest change")
end)
key("y", "normal", "yank the tile's digit", function(game)
  local d = game.board[game.cursor.r][game.cursor.c]
  if d ~= 0 then
    yank(d)
  end
end)
key("p", "normal", "paste a digit 1-9 from the register", function(game)
  local d = register_digit()
  if not d then
    return notice(on_given(game) and cell_name(game) .. " is a given" or "the register holds no single digit 1-9")
  end
  edit(game, d)
end)
key("x", "normal", "clear the tile's entry", function(game)
  if game.board[game.cursor.r][game.cursor.c] ~= 0 then
    edit(game, 0)
  end
end)

-- INSERT
for d = 1, 9 do
  key(tostring(d), "insert", ("stage the draft %d"):format(d), function(game)
    if on_given(game) then
      return notice(cell_name(game) .. " is a given")
    end
    drafts[game] = d
  end)
end
key("<CR>", "insert", "commit the draft", function(game)
  local d = drafts[game]
  set_mode(game, "normal")
  if d then
    edit(game, d)
  end
end)
key("<Esc>", "insert", "discard the draft", function(game)
  set_mode(game, "normal")
end)
-- Q15: nothing else is typed, moves or starts a native command while drafting
-- (`:` stays available for Ex commands).
local IGNORED =
  [[0 h j k l w b e W B E G g { } ( ) [ ] $ ^ + - _ M n N f F t T ; , % y Y / ? * # q @ m ' ` " Z z <BS> <Space> <Tab> <Left> <Right> <Up> <Down> <C-e> <C-y> <C-d> <C-u> <C-f> <C-b> <C-o>]]
for _, lhs in ipairs(vim.split(IGNORED, " ")) do
  key(lhs, "insert", ("ignored while drafting (%s)"):format(lhs), function() end)
end

-- Highlights: dim 110 < guide 120 < (WP3 match 130) < conflict 140 < draft 150 < cursor 200.
local function insert_cells(on_guide)
  return function(game)
    local out = {}
    if game.mode ~= "insert" then
      return out
    end
    local r0, c0 = game.cursor.r, game.cursor.c
    for r = 1, 9 do
      for c = 1, 9 do
        if not (r == r0 and c == c0) and ((r == r0 or c == c0) == on_guide) then
          out[#out + 1] = { r = r, c = c }
        end
      end
    end
    return out
  end
end
render.layer({ name = "insert-dim", group = "EnviSudokuDim", priority = 110, cells = insert_cells(false) })
render.layer({ name = "insert-guide", group = "EnviSudokuGuide", priority = 120, cells = insert_cells(true) })
render.layer({
  name = "insert-guide-outline",
  group = "EnviSudokuGuide",
  priority = 120,
  outline = true,
  cells = insert_cells(true),
})
render.layer({
  name = "conflict",
  group = "EnviSudokuConflict",
  priority = 140,
  cells = function(game)
    return M.conflicts(game.board)
  end,
})
render.layer({
  name = "draft",
  group = "EnviSudokuDraft",
  priority = 150,
  cells = function(game)
    return (game.mode == "insert" and drafts[game]) and { { r = game.cursor.r, c = game.cursor.c } } or {}
  end,
})

-- The draft digit itself, drawn over the (unchanged) board text of its tile.
sudoku.on("render", function(game)
  local buf = sudoku.state().buf
  if not buf then
    return
  end
  api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  local d = game.mode == "insert" and drafts[game]
  if d then
    local row, s = render.span(game.cursor.r, game.cursor.c)
    api.nvim_buf_set_extmark(buf, M.ns, row, s + 1, {
      virt_text = { { tostring(d), "EnviSudokuDraft" } },
      virt_text_pos = "overlay",
      priority = 150,
    })
  end
end)

-- Leaving the board any way other than <Enter> discards the draft (as <Esc> does).
sudoku.on("close", function(game)
  if game and game.mode == "insert" then
    set_mode(game, "normal")
  end
end)

render.footer_segment(function(game)
  return (game.mode == "insert" and on_given(game)) and "GIVEN" or nil
end)

sudoku.extend_state(function(s, game)
  if not game then
    return
  end
  local h = hist(game)
  s.draft = drafts[game]
  s.undo, s.redo = #h.undo, #h.redo
  s.conflicts = M.conflicts(game.board)
end)

return M
