-- Board text, highlight groups and highlight layers (the seam WP2–WP5 extend; see README.md).
--
-- The board is a 9x9 box-drawing grid: a cell is 3 columns (" 5 ") between
-- vertical rules, and rows are separated by horizontal rules, so every cell is
-- enclosed by its own border. The cursor IS that border, drawn in
-- EnviSudokuCursor. Heavy rules mark the 3x3 boxes. Then a blank line and the footer.
local api = vim.api
local Game = require("hcmux.sudoku.game")
local M = { ns = api.nvim_create_namespace("envi_sudoku") }

local PAD = " "
local GRID = 19 -- grid lines: 10 rules + 9 cell rows
M.WIDTH = 2 * #PAD + 37
M.HEIGHT = GRID + 2 -- + blank + footer

-- Rule pieces: left end, horizontal, cell junction, box junction, right end.
local RULES = {
  top = { "┏", "━", "┯", "┳", "┓" },
  box = { "┣", "━", "┿", "╋", "┫" },
  cell = { "┠", "─", "┼", "╂", "┨" },
  bottom = { "┗", "━", "┷", "┻", "┛" },
}
local CHAR = 3 -- bytes of each box-drawing character

-- Byte offset of vertical k (0..9) on a cell line, and of junction k on a rule line.
local function vcol(k)
  return #PAD + k * (CHAR + 3)
end
local function jcol(k)
  return #PAD + k * (CHAR + 3 * CHAR)
end

--- 0-based line and byte range [s, e) of cell (r, c)'s 3-column interior.
function M.span(r, c)
  local s = vcol(c - 1) + CHAR
  return 2 * r - 1, s, s + 3
end

--- The border of cell (r, c) as { line, start, end } byte spans (0-based, end exclusive).
function M.outline(r, c)
  local top, bottom = 2 * r - 2, 2 * r
  local row = 2 * r - 1
  return {
    { top, jcol(c - 1), jcol(c) + CHAR },
    { row, vcol(c - 1), vcol(c - 1) + CHAR },
    { row, vcol(c), vcol(c) + CHAR },
    { bottom, jcol(c - 1), jcol(c) + CHAR },
  }
end

local function rule(kind)
  local p = RULES[kind]
  local out = { PAD, p[1] }
  for c = 1, 9 do
    out[#out + 1] = p[2]:rep(3)
    out[#out + 1] = c == 9 and p[5] or (c % 3 == 0 and p[4] or p[3])
  end
  return table.concat(out)
end

local function cells_line(row)
  local out = { PAD, "┃" }
  for c = 1, 9 do
    out[#out + 1] = row[c] ~= 0 and (" " .. row[c] .. " ") or "   "
    out[#out + 1] = (c % 3 == 0) and "┃" or "│"
  end
  return table.concat(out)
end

-- Footer segments after the core "MODE  RrCc  MM:SS STATUS" (e.g. WP3's "/9 4/9").
local segments = {}

--- fn(game) -> string|nil, appended to the footer after two spaces.
function M.footer_segment(fn)
  segments[#segments + 1] = fn
end

function M.footer(game)
  local parts = {
    game.mode:upper(),
    string.format("R%dC%d", game.cursor.r, game.cursor.c),
    Game.format(game.timer:elapsed()) .. " " .. game.timer.status:upper(),
  }
  for _, fn in ipairs(segments) do
    local text = fn(game)
    if text and text ~= "" then
      parts[#parts + 1] = text
    end
  end
  return PAD .. table.concat(parts, "  ")
end

function M.lines(game)
  local lines = { rule("top") }
  for r = 1, 9 do
    lines[#lines + 1] = cells_line(game.board[r])
    lines[#lines + 1] = r == 9 and rule("bottom") or rule(r % 3 == 0 and "box" or "cell")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = M.footer(game)
  return lines
end

-- Layers: { name, group, priority, cells = fn(game) -> { {r=,c=}, … }, outline = bool }.
-- A layer styles each listed cell's digit (or, with outline = true, its border)
-- with `group`. Several layers may share a group (e.g. dim from search, insert
-- and pause); state().hl reports the union per group. Higher priority wins.
local layers = {}

--- Add or replace (same name) a layer.
function M.layer(spec)
  assert(spec.name and spec.group and spec.priority and spec.cells, "layer: name, group, priority, cells")
  for i, l in ipairs(layers) do
    if l.name == spec.name then
      table.remove(layers, i)
      break
    end
  end
  layers[#layers + 1] = spec
  table.sort(layers, function(a, b)
    return a.priority < b.priority
  end)
end

local function each_cell(game, pred)
  local out = {}
  for r = 1, 9 do
    for c = 1, 9 do
      if pred(r, c) then
        out[#out + 1] = { r = r, c = c }
      end
    end
  end
  return out
end

M.layer({
  name = "given",
  group = "EnviSudokuGiven",
  priority = 100,
  cells = function(game)
    return each_cell(game, function(r, c)
      return game.givens[r][c]
    end)
  end,
})
M.layer({
  name = "entry",
  group = "EnviSudokuEntry",
  priority = 100,
  cells = function(game)
    return each_cell(game, function(r, c)
      return not game.givens[r][c] and game.board[r][c] ~= 0
    end)
  end,
})
M.layer({
  name = "cursor",
  group = "EnviSudokuCursor",
  priority = 200,
  outline = true,
  cells = function(game)
    return { { r = game.cursor.r, c = game.cursor.c } }
  end,
})

local HL_KEYS =
  { EnviSudokuCursor = "cursor", EnviSudokuMatch = "match", EnviSudokuGuide = "guide", EnviSudokuDim = "dim" }

--- state().hl: the cells per group, de-duplicated, in row-major order.
function M.summary(game)
  local hl = { cursor = {}, match = {}, guide = {}, dim = {} }
  if not game then
    return hl
  end
  local seen = {}
  for _, layer in ipairs(layers) do
    local key = HL_KEYS[layer.group]
    if key then
      seen[key] = seen[key] or {}
      for _, cell in ipairs(layer.cells(game)) do
        seen[key][(cell.r - 1) * 9 + cell.c] = true
      end
    end
  end
  for key, set in pairs(seen) do
    for i = 1, 81 do
      if set[i] then
        hl[key][#hl[key] + 1] = { r = math.floor((i - 1) / 9) + 1, c = (i - 1) % 9 + 1 }
      end
    end
  end
  return hl
end

local function set_lines(buf, first, last, lines)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, first, last, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

--- Redraw the whole board into `buf`.
function M.draw(buf, game)
  set_lines(buf, 0, -1, M.lines(game))
  api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, layer in ipairs(layers) do
    for _, cell in ipairs(layer.cells(game)) do
      local spans = layer.outline and M.outline(cell.r, cell.c) or { { M.span(cell.r, cell.c) } }
      for _, sp in ipairs(spans) do
        api.nvim_buf_set_extmark(buf, M.ns, sp[1], sp[2], {
          end_col = sp[3],
          hl_group = layer.group,
          priority = layer.priority,
        })
      end
    end
  end
end

--- Rewrite only the footer (the timer tick). Returns true if it changed.
function M.draw_footer(buf, game)
  local text = M.footer(game)
  if api.nvim_buf_get_lines(buf, -2, -1, false)[1] == text then
    return false
  end
  set_lines(buf, -2, -1, { text })
  return true
end

local function color(names, fallback, avoid)
  for _, name in ipairs(names) do
    local fg = api.nvim_get_hl(0, { name = name, link = false }).fg
    if fg and fg ~= avoid then
      return fg
    end
  end
  return fallback
end

--- (Re)define the highlight groups from the colorscheme. `default`, so a user's
--- own definitions win. Dimming is foreground-only: the window keeps winblend 0.
function M.define_hl()
  local set = function(name, spec)
    spec.default = true
    api.nvim_set_hl(0, name, spec)
  end
  local given = color({ "Normal" }, 0xd8dee9)
  set("EnviSudokuGiven", { fg = given, bold = true })
  set("EnviSudokuEntry", { fg = color({ "Function", "Identifier", "Special" }, 0x7aa2f7, given) })
  set("EnviSudokuDraft", { fg = color({ "DiagnosticHint", "Comment" }, 0x73daca, given), italic = true })
  set("EnviSudokuCursor", { fg = color({ "DiagnosticWarn", "WarningMsg" }, 0xe0af68), bold = true })
  set("EnviSudokuMatch", { fg = color({ "DiagnosticOk", "String" }, 0x9ece6a), bold = true, underline = true })
  set("EnviSudokuGuide", { fg = color({ "Title", "Statement" }, 0x7dcfff) })
  set("EnviSudokuDim", { fg = color({ "Comment", "NonText" }, 0x565f89) })
  set("EnviSudokuConflict", { fg = color({ "DiagnosticError", "ErrorMsg" }, 0xf7768e), bold = true, undercurl = true })
  -- The text caret, hidden through guicursor while the board has focus (tui-cursor-shape).
  set("EnviSudokuCaret", { blend = 100, nocombine = true })
end

return M
