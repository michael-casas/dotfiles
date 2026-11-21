-- features/11-highlighting-opacity.feature: "an accepted search dims non-matching
-- tiles" (WP3; OPEN-QUESTIONS Q17), in both of WP1's layouts.
local H = require("hcmux.sudoku.test.harness")
local S = require("hcmux.sudoku.test.wp3")
local api = vim.api
H.boot()

--- The priority of every board-namespace extmark over cell (r, c)'s digit: { group = priority }.
local function priorities(r, c)
  local render = require("hcmux.sudoku.render")
  local row, ch = H.cell(r, c)
  local text = H.lines()[row + 1]
  local byte = vim.str_byteindex(text, "utf-32", ch)
  local out = {}
  for _, m in
    ipairs(api.nvim_buf_get_extmarks(H.state().buf, render.ns, { row, 0 }, { row, -1 }, {
      details = true,
      overlap = true,
    }))
  do
    local d = m[4]
    if d.hl_group and m[2] == row and m[3] <= byte and byte < (d.end_col or m[3]) then
      out[d.hl_group] = math.max(out[d.hl_group] or 0, d.priority or 0)
    end
  end
  return out
end

S.each_layout("an accepted search dims non-matching tiles", function()
  H.eq(H.state().hl.dim, {}, "setup: nothing is dimmed before the search")
  H.type("/9")
  H.eq(H.state().hl.dim, {}, "the live prompt does not dim (Q17: while a search is accepted)")
  H.type("<CR>")
  local s = H.state()
  local rest = S.others(S.NINES)
  H.eq(#rest, 77, "oracle: 77 other tiles")
  S.matches_are(S.NINES, "the 4 matching tiles carry EnviSudokuMatch")
  H.eq(s.hl.dim, rest, "the other 77 tiles carry EnviSudokuDim")
  for _, cell in ipairs(rest) do
    local g = H.groups(cell.r, cell.c)
    H.ok(g.EnviSudokuDim and not g.EnviSudokuMatch, ("R%dC%d is drawn dimmed"):format(cell.r, cell.c))
  end
  for _, cell in ipairs(S.NINES) do
    local p = priorities(cell.r, cell.c)
    H.ok(not p.EnviSudokuDim, ("R%dC%d is not dimmed"):format(cell.r, cell.c))
    H.ok(p.EnviSudokuMatch > p.EnviSudokuGiven, ("R%dC%d: the match shows over the given style"):format(cell.r, cell.c))
  end
  local given = priorities(1, 1)
  H.ok(given.EnviSudokuDim > given.EnviSudokuGiven, "R1C1: the dim shows over the given style")
  H.eq(H.char_spans("EnviSudokuCursor"), H.outline(1, 1), "the cursor box outline is still drawn on R1C1")
  H.ok(H.state().hl.cursor[1].r == 1 and H.state().hl.cursor[1].c == 1, "state().hl.cursor is R1C1")
  H.ok(H.groups(1, 1).EnviSudokuDim, "R1C1's digit is dimmed under the outline")
  H.eq(vim.wo[s.win].winblend, 0, "dimming leaves the window's winblend at 0")
  -- The dim follows the cursor's moves and goes with a canceled-to-nothing state only.
  H.type("n")
  H.eq(H.char_spans("EnviSudokuCursor"), H.outline(2, 5), "the outline moves with n, above the dim")
  H.eq(H.state().hl.dim, rest, "the dim is unchanged by n")
  H.type("/")
  H.eq(H.state().hl.dim, {}, "a new prompt shows only what it types")
  H.type("<Esc>")
  H.eq(H.state().hl.dim, rest, "<Esc> restores the accepted search's dim")
end)

H.finish()
