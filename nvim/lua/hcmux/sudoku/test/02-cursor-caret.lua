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
local sudoku, keys, render = H.sudoku(), require("hcmux.sudoku.keys"), require("hcmux.sudoku.render")

local function stand_in(lhs, mode, fn)
  if not keys.handler(lhs, mode) then
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
  local want = {}
  for _, span in ipairs(render.outline(r, c)) do
    want[#want + 1] = string.format("%d:%d-%d", span[1], span[2], span[3])
  end
  table.sort(want)
  H.eq(H.spans("EnviSudokuCursor"), want, label .. ": EnviSudokuCursor extmarks are exactly R4C5's outline")
  -- No text caret: the caret is hidden while the board has focus, and Neovim's
  -- cursor sits on the cell's digit, inside the outline.
  H.ok(vim.o.guicursor:find("EnviSudokuCaret", 1, true), label .. ": guicursor hides the caret")
  H.eq(api.nvim_get_hl(0, { name = "EnviSudokuCaret" }).blend, 100, label .. ": the caret group is fully blended")
  local pos = api.nvim_win_get_cursor(s.win)
  local row, cs, ce = render.span(r, c)
  H.ok(pos[1] - 1 == row and pos[2] >= cs and pos[2] < ce, label .. ": Neovim's cursor is inside the outline")
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
  api.nvim_win_set_cursor(0, { 1, 0 })
  H.drain()
  outline_only_on(4, 5, "after a native cursor move")
  H.type("<C-w>p")
  H.eq(vim.o.guicursor, caret, "the caret is restored when focus leaves the board")
end)

H.finish()
