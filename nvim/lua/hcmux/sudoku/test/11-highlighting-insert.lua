-- features/11-highlighting-opacity.feature: "insert mode draws the row and column
-- guides", "in insert with an accepted search, matches stay brighter" (insert side;
-- gated on WP3's search) and "conflicting entries are flagged" (WP4).
-- Every scenario runs in both of WP1's layouts: "full" (80x40) and "compact"
-- (36x21, README: minimum viewport, where an outline is drawn as "[d]" brackets).
local H = require("hcmux.sudoku.test.harness")
local W = require("hcmux.sudoku.test.wp4")
local api = vim.api
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

local function contains(cells, r, c)
  return vim.tbl_contains(vim.tbl_map(vim.inspect, cells), vim.inspect({ r = r, c = c }))
end

local function at_size(cols, lines)
  vim.o.columns, vim.o.lines = cols, lines
  vim.wait(300, function()
    return false
  end)
end

local LAYOUTS = { { "full", 80, 40 }, { "compact", 36, 21 } }

--- One scenario per layout; the size is restored even when the body fails.
local function each_layout(name, fn)
  for _, l in ipairs(LAYOUTS) do
    H.scenario(("%s [%s layout]"):format(name, l[1]), function()
      H.background()
      at_size(l[2], l[3])
      local ok, err = xpcall(function()
        H.eq(H.kind(), l[1], "setup: the " .. l[1] .. " layout")
        fn(l[1])
      end, debug.traceback)
      at_size(80, 40)
      H.ok(ok, err)
    end)
  end
end

--- Overlay glyphs in the board namespace (compact outlines), as "line:glyph:group".
local function glyphs()
  local out = {}
  local ns = require("hcmux.sudoku.render").ns
  for _, m in ipairs(api.nvim_buf_get_extmarks(H.state().buf, ns, 0, -1, { details = true })) do
    for _, chunk in ipairs(m[4].virt_text or {}) do
      out[#out + 1] = ("%d:%s:%s"):format(m[2], chunk[1], chunk[2])
    end
  end
  table.sort(out)
  return out
end

each_layout("insert mode draws the row and column guides and dims the rest", function(layout)
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
  if layout == "full" then
    -- The border above R4C5 is line 6 (rules on even lines, 0-based: 2*(r-1)).
    local on_6 = vim.tbl_filter(function(sp)
      return sp:find("^6:") ~= nil
    end, H.spans("EnviSudokuCursor"))
    H.ok(#on_6 > 0, "the outline is still drawn on R4C5's top border")
    H.eq(glyphs(), {}, "the full layout draws outlines in place, with no overlay glyphs")
  else
    local line = H.cell(4, 5)
    H.eq(
      glyphs(),
      { ("%d:[:EnviSudokuCursor"):format(line), ("%d:]:EnviSudokuCursor"):format(line) },
      "only R4C5 carries outline brackets, so the cursor stays distinct"
    )
  end
  -- Above the dim: the guide outranks the dim.
  local guide_p, dim_p = W.priorities(4, 1).EnviSudokuGuide, W.priorities(1, 1).EnviSudokuDim
  H.ok(guide_p and dim_p and guide_p > dim_p, ("the guide (%s) renders above the dim (%s)"):format(guide_p, dim_p))
  H.type("<Esc>")
  s = H.state()
  H.eq({ s.hl.guide, s.hl.dim }, { {}, {} }, "no tile carries EnviSudokuGuide or EnviSudokuDim")
  H.eq({ H.spans("EnviSudokuGuide"), H.spans("EnviSudokuDim") }, { {}, {} }, "and none is drawn")
end)

-- Support for feature 04 in both layouts: the draft sits on the tile's digit.
each_layout("the draft is drawn over its tile's digit", function()
  H.place(1, 3)
  H.type("i4")
  H.eq(W.overlay(1, 3), { { "4", "EnviSudokuDraft" } }, "R1C3 shows the draft 4")
  H.eq(W.top_group(1, 3), "EnviSudokuDraft", "styled EnviSudokuDraft over the guide and dim")
  local row, ch = H.cell(1, 3)
  local ns = api.nvim_get_namespaces().envi_sudoku_draft
  local marks = api.nvim_buf_get_extmarks(H.state().buf, ns, 0, -1, {})
  H.eq(#marks, 1, "one draft mark")
  H.eq(
    { marks[1][2], vim.str_utfindex(H.lines()[row + 1], "utf-32", marks[1][3]) },
    { row, ch },
    "at R1C3's digit position"
  )
  H.eq(H.digit(1, 3), " ", "the board text under the draft is still empty")
  H.type("<CR>")
  H.eq(H.digit(1, 3), "4", "the committed 4 is board text")
  H.eq(W.overlay(1, 3), {}, "and the draft overlay is gone")
end)

each_layout("in insert with an accepted search, matches stay brighter than the dimmed tiles", function()
  H.type("/9<CR>")
  H.place(4, 5)
  H.type("i")
  local s = H.state()
  H.ok(contains(s.hl.match, 2, 5) and contains(s.hl.match, 8, 6), "R2C5 and R8C6 keep EnviSudokuMatch")
  H.ok(H.groups(2, 5).EnviSudokuMatch and H.groups(8, 6).EnviSudokuMatch, "and are drawn with it")
  H.ok(contains(s.hl.guide, 2, 5), "R2C5 is also on the column guide")
  H.eq(W.top_group(8, 6), "EnviSudokuMatch", "the match renders above EnviSudokuDim on R8C6")
  H.eq(W.top_group(2, 5), "EnviSudokuMatch", "the match is not hidden by the guide on R2C5")
  H.ok(W.priorities(2, 5).EnviSudokuGuide > W.priorities(1, 1).EnviSudokuDim, "the guide renders above the dim")
  if search_stand_in then
    io.stdout:write("\nNOTE gated on WP3: the search above is the test stand-in\n")
  end
end)

each_layout("conflicting entries are flagged", function()
  H.eq(H.state().conflicts, {}, "setup: the fixture has no conflicts")
  H.place(1, 3)
  H.type("i5")
  H.type("<CR>")
  local s = H.state()
  H.eq(s.board[1][3], 5, "the conflicting 5 is committed, not blocked")
  H.ok(H.groups(1, 3).EnviSudokuConflict, "R1C3 carries EnviSudokuConflict")
  H.eq(W.top_group(1, 3), "EnviSudokuConflict", "and it shows over the entry style")
  H.ok(contains(s.conflicts, 1, 3), "state().conflicts contains R1C3")
  H.ok(contains(s.conflicts, 1, 1), "and the 5 it clashes with")
  H.ok(not H.groups(1, 2).EnviSudokuConflict, "an unrelated given is not flagged")
  -- Column and box conflicts count too; undo clears the flag.
  H.type("u")
  H.eq(H.state().conflicts, {}, "undo clears the conflict")
  H.place(2, 2)
  H.type("i9")
  H.type("<CR>")
  s = H.state()
  H.ok(contains(s.conflicts, 3, 2), "a column (and box) clash with R3C2's 9 is flagged")
  H.ok(contains(s.conflicts, 2, 5), "a row clash with R2C5's 9 is flagged")
  H.type("u")
  H.place(1, 3)
  H.type("i9")
  H.type("<CR>")
  H.eq(H.state().conflicts, { { r = 1, c = 3 }, { r = 3, c = 2 } }, "a box-only clash flags exactly the pair")
end)

H.finish()
