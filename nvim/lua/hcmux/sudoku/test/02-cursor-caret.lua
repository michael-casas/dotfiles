-- features/02-normal-movement-counts.feature: "the cursor never shows a text caret
-- outside the outline" (WP1). The other 02 scenarios belong to WP2.
--
-- WP1 ships no motions or modes. Until WP2–WP4 bind them, this suite registers
-- stand-ins for j/l (with counts), i, / and <Esc> through the public key seam,
-- so the scenario's keys are typed verbatim. A real handler, once registered,
-- is used instead of the stand-in.
local H = require("hcmux.sudoku.test.harness")
local api = vim.api
H.boot()
local keys = require("hcmux.sudoku.keys")

local function stand_in(lhs, mode, fn)
  local real = keys.handler(lhs, mode)
  if not real or real.mode == "*" then -- "*" is the core's no-op fallback
    keys.register({ lhs = lhs, mode = mode, desc = "Sudoku: test stand-in " .. lhs, fn = fn })
  end
end
local function move(dr, dc)
  return function(game)
    local n = vim.v.count1
    game.cursor.r = math.max(1, math.min(9, game.cursor.r + dr * n))
    game.cursor.c = math.max(1, math.min(9, game.cursor.c + dc * n))
  end
end
stand_in("j", "normal", move(1, 0))
stand_in("l", "normal", move(0, 1))
stand_in("i", "normal", function(game)
  game.mode = "insert"
end)
stand_in("/", "normal", function(game)
  game.mode = "search"
end)
for _, mode in ipairs({ "insert", "search" }) do
  stand_in("<Esc>", mode, function(game)
    game.mode = "normal"
  end)
end

local function outline_only_on(r, c, label)
  local s = H.state()
  H.eq(s.hl.cursor, { { r = r, c = c } }, label .. ": exactly one cell carries the outline")
  H.eq(
    H.char_spans("EnviSudokuCursor"),
    H.outline(r, c),
    label .. ": EnviSudokuCursor extmarks are exactly R4C5's outline"
  )
  -- No text caret: the caret is hidden while the board has focus, and Neovim's
  -- cursor sits on the cell's digit, inside the outline.
  H.ok(vim.o.guicursor:find("EnviSudokuCaret", 1, true), label .. ": guicursor hides the caret")
  H.eq(api.nvim_get_hl(0, { name = "EnviSudokuCaret" }).blend, 100, label .. ": the caret group is fully blended")
  local pos = api.nvim_win_get_cursor(s.win)
  local row, ch = H.cell(r, c)
  local at = vim.str_utfindex(H.lines()[pos[1]], "utf-32", pos[2])
  H.ok(pos[1] - 1 == row and at == ch, label .. ": Neovim's cursor is on the digit, inside the outline")
end

H.scenario("the cursor never shows a text caret outside the outline", function()
  local caret = vim.o.guicursor
  H.background()
  H.type("3j4l")
  H.eq(H.state().cursor, { r = 4, c = 5 }, "3j4l lands on R4C5")
  outline_only_on(4, 5, "NORMAL")
  H.ok(H.footer():find("^NORMAL"), "footer NORMAL")
  H.type("i")
  H.ok(H.footer():find("^INSERT"), "footer INSERT")
  outline_only_on(4, 5, "INSERT")
  H.type("<Esc>")
  H.type("/")
  H.ok(H.footer():find("^SEARCH"), "footer SEARCH")
  outline_only_on(4, 5, "SEARCH")
  H.type("<Esc>")
  -- Native motions never leave a caret elsewhere: the cursor snaps back.
  for _, native in ipairs({ "+", "-", "M", "w", "gg" }) do
    H.type(native)
    outline_only_on(4, 5, "after the native motion " .. native)
  end
  H.type("<C-w>p")
  H.eq(vim.o.guicursor, caret, "the caret is restored when focus leaves the board")
end)

H.finish()
