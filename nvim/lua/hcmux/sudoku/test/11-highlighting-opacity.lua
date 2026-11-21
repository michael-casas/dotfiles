-- features/11-highlighting-opacity.feature: "givens and entries distinct",
-- "dimming uses highlight groups, not winblend" (WP1).
local H = require("hcmux.sudoku.test.harness")
local api = vim.api
H.boot()

local function fg(name)
  return api.nvim_get_hl(0, { name = name, link = false }).fg
end

H.scenario("givens and entries are visually distinct", function()
  H.background()
  H.enter(1, 3, 4)
  H.ok(H.groups(1, 1).EnviSudokuGiven, "R1C1 is styled EnviSudokuGiven")
  H.ok(H.groups(1, 3).EnviSudokuEntry and not H.groups(1, 3).EnviSudokuGiven, "R1C3 is styled EnviSudokuEntry")
  H.eq(H.digit(1, 3), "4", "the entry is drawn at R1C3")
  H.eq(H.digit(1, 1), "5", "the given is drawn at R1C1")
  H.ok(fg("EnviSudokuGiven") and fg("EnviSudokuEntry"), "both groups have a foreground")
  H.ok(fg("EnviSudokuGiven") ~= fg("EnviSudokuEntry"), "the two groups resolve to different foreground colours")
end)

-- WP1 has no INSERT mode. Until WP4 binds `i`, a stand-in `i`/<Esc> and an insert
-- dim layer (everything off the cursor's row and column) go through the public
-- seams, so the scenario's `i` really dims tiles. WP4's own `i` replaces them, and
-- the integrated INSERT regression stays with WP4 (11 "insert mode draws the guides").
local keys, render = require("hcmux.sudoku.keys"), require("hcmux.sudoku.render")
local real = keys.handler("i", "normal")
if not real or real.mode == "*" then
  keys.register({
    lhs = "i",
    mode = "normal",
    desc = "Sudoku: test stand-in i",
    fn = function(g)
      g.mode = "insert"
    end,
  })
  keys.register({
    lhs = "<Esc>",
    mode = "insert",
    desc = "Sudoku: test stand-in <Esc>",
    fn = function(g)
      g.mode = "normal"
    end,
  })
  render.layer({
    name = "test-insert-dim",
    group = "EnviSudokuDim",
    priority = 110,
    cells = function(g)
      local out = {}
      for r = 1, 9 do
        for c = 1, 9 do
          if g.mode == "insert" and r ~= g.cursor.r and c ~= g.cursor.c then
            out[#out + 1] = { r = r, c = c }
          end
        end
      end
      return out
    end,
  })
end

H.scenario("dimming uses highlight groups, not winblend on the board", function()
  H.background()
  H.place(4, 5)
  H.type("i")
  local s = H.state()
  H.ok(s.open and s.focused, "the board keeps focus")
  H.eq(s.mode, "insert", "INSERT")
  H.eq(#s.hl.dim, 64, "64 tiles are dimmed")
  H.ok(H.groups(9, 9).EnviSudokuDim and H.groups(1, 1).EnviSudokuDim, "dimmed tiles carry EnviSudokuDim extmarks")
  H.ok(not H.groups(4, 1).EnviSudokuDim and not H.groups(1, 5).EnviSudokuDim, "the row and column are not dimmed")
  H.eq(vim.wo[s.win].winblend, 0, "the popover window's winblend is 0")
  local dim = api.nvim_get_hl(0, { name = "EnviSudokuDim", link = false })
  H.ok(dim.fg ~= nil, "EnviSudokuDim sets a foreground")
  H.ok(dim.bg == nil and dim.blend == nil and dim.reverse == nil, "EnviSudokuDim is foreground-only")
  H.ok(fg("EnviSudokuDim") ~= fg("EnviSudokuGiven"), "a dimmed given looks different from a plain one")
  H.type("<Esc>")
  H.eq(#H.state().hl.dim, 0, "<Esc> leaves INSERT and the dim goes")
end)

H.finish()
