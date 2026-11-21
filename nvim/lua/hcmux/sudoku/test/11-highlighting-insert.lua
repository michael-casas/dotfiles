-- features/11-highlighting-opacity.feature: "insert mode draws the row and column
-- guides", "in insert with an accepted search, matches stay brighter" (insert side;
-- gated on WP3's search) and "conflicting entries are flagged" (WP4).
local H = require("hcmux.sudoku.test.harness")
local W = require("hcmux.sudoku.test.wp4")
H.boot()
local search_stand_in = W.search_stand_ins()

-- Independent oracle: the cells of row r and column c other than (r, c), and the rest.
local function cross(r, c)
  local guide, rest = {}, {}
  for rr = 1, 9 do
    for cc = 1, 9 do
      if not (rr == r and cc == c) then
        table.insert((rr == r or cc == c) and guide or rest, { r = rr, c = cc })
      end
    end
  end
  return guide, rest
end

H.scenario("insert mode draws the row and column guides and dims the rest", function()
  H.background()
  H.place(4, 5)
  H.eq({ H.state().hl.guide, H.state().hl.dim }, { {}, {} }, "setup: no guide or dim in NORMAL")
  H.type("i")
  local s = H.state()
  local guide, rest = cross(4, 5)
  H.eq(#guide, 16, "oracle: 16 guide tiles")
  H.eq(s.hl.guide, guide, "the 16 other tiles of row 4 and column 5 carry EnviSudokuGuide")
  H.eq(s.hl.dim, rest, "the remaining 64 tiles carry EnviSudokuDim")
  for _, cell in ipairs(guide) do
    local g = H.groups(cell.r, cell.c)
    H.ok(g.EnviSudokuGuide and not g.EnviSudokuDim, ("R%dC%d is drawn as a guide, not dimmed"):format(cell.r, cell.c))
  end
  for _, cell in ipairs(rest) do
    local g = H.groups(cell.r, cell.c)
    H.ok(g.EnviSudokuDim and not g.EnviSudokuGuide, ("R%dC%d is drawn dimmed"):format(cell.r, cell.c))
  end
  -- R4C5 keeps its own, distinct outline.
  H.eq(s.hl.cursor, { { r = 4, c = 5 } }, "R4C5 keeps the EnviSudokuCursor outline")
  local own = H.groups(4, 5)
  H.ok(not own.EnviSudokuGuide and not own.EnviSudokuDim, "R4C5 is neither guide nor dim")
  -- The cell border above R4C5 is line 6 (rules on even lines, 0-based: 2*(r-1)).
  local cursor_on_6 = 0
  for _, sp in ipairs(H.spans("EnviSudokuCursor")) do
    cursor_on_6 = cursor_on_6 + (sp:find("^6:") and 1 or 0)
  end
  H.ok(cursor_on_6 > 0, "the outline is still drawn on R4C5's top border")
  -- Above the dim: every guide extmark outranks every dim extmark.
  local guide_p, dim_p = W.priorities(4, 1).EnviSudokuGuide, W.priorities(1, 1).EnviSudokuDim
  H.ok(guide_p and dim_p and guide_p > dim_p, ("the guide (%s) renders above the dim (%s)"):format(guide_p, dim_p))
  H.type("<Esc>")
  s = H.state()
  H.eq({ s.hl.guide, s.hl.dim }, { {}, {} }, "no tile carries EnviSudokuGuide or EnviSudokuDim")
  H.eq({ H.spans("EnviSudokuGuide"), H.spans("EnviSudokuDim") }, { {}, {} }, "and none is drawn")
end)

H.scenario("in insert with an accepted search, matches stay brighter than the dimmed tiles", function()
  H.background()
  H.type("/9<CR>")
  H.place(4, 5)
  H.type("i")
  local s = H.state()
  local matched = {}
  for _, cell in ipairs(s.hl.match) do
    matched[cell.r .. ":" .. cell.c] = true
  end
  H.ok(matched["2:5"] and matched["8:6"], "R2C5 and R8C6 keep EnviSudokuMatch: " .. vim.inspect(s.hl.match))
  H.ok(H.groups(2, 5).EnviSudokuMatch and H.groups(8, 6).EnviSudokuMatch, "and are drawn with it")
  H.ok(
    vim.tbl_contains(vim.tbl_map(vim.inspect, s.hl.guide), vim.inspect({ r = 2, c = 5 })),
    "R2C5 is also on the column guide"
  )
  H.eq(W.top_group(8, 6), "EnviSudokuMatch", "the match renders above EnviSudokuDim on R8C6")
  H.eq(W.top_group(2, 5), "EnviSudokuMatch", "the match is not hidden by the guide on R2C5")
  H.ok(W.priorities(2, 5).EnviSudokuGuide > W.priorities(1, 1).EnviSudokuDim, "the guide renders above the dim")
  if search_stand_in then
    io.stdout:write("\nNOTE gated on WP3: the search above is the test stand-in\n")
  end
end)

H.scenario("conflicting entries are flagged", function()
  H.background()
  H.eq(H.state().conflicts, {}, "setup: the fixture has no conflicts")
  H.place(1, 3)
  H.type("i5")
  H.type("<CR>")
  local s = H.state()
  H.eq(s.board[1][3], 5, "the conflicting 5 is committed, not blocked")
  H.ok(H.groups(1, 3).EnviSudokuConflict, "R1C3 carries EnviSudokuConflict")
  H.eq(W.top_group(1, 3), "EnviSudokuConflict", "and it shows over the entry style")
  H.ok(
    vim.tbl_contains(vim.tbl_map(vim.inspect, s.conflicts), vim.inspect({ r = 1, c = 3 })),
    "state().conflicts contains R1C3"
  )
  H.ok(
    vim.tbl_contains(vim.tbl_map(vim.inspect, s.conflicts), vim.inspect({ r = 1, c = 1 })),
    "and the 5 it clashes with"
  )
  H.ok(not H.groups(1, 2).EnviSudokuConflict, "an unrelated given is not flagged")
  -- Column and box conflicts count too; undo clears the flag.
  H.type("u")
  H.eq(H.state().conflicts, {}, "undo clears the conflict")
  H.place(2, 2)
  H.type("i9")
  H.type("<CR>")
  local keys = vim.tbl_map(vim.inspect, H.state().conflicts)
  H.ok(vim.tbl_contains(keys, vim.inspect({ r = 3, c = 2 })), "a column (and box) clash with R3C2's 9 is flagged")
  H.ok(vim.tbl_contains(keys, vim.inspect({ r = 2, c = 5 })), "a row clash with R2C5's 9 is flagged")
  H.type("u")
  H.place(1, 3)
  H.type("i9")
  H.type("<CR>")
  keys = vim.tbl_map(vim.inspect, H.state().conflicts)
  H.eq(
    keys,
    { vim.inspect({ r = 1, c = 3 }), vim.inspect({ r = 3, c = 2 }) },
    "a box-only clash flags exactly the pair"
  )
end)

H.finish()
