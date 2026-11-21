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
  H.ok(H.lines()[2]:find("4", 1, true), "the entry is drawn")
  H.ok(fg("EnviSudokuGiven") and fg("EnviSudokuEntry"), "both groups have a foreground")
  H.ok(fg("EnviSudokuGiven") ~= fg("EnviSudokuEntry"), "the two groups resolve to different foreground colours")
end)

H.scenario("dimming uses highlight groups, not winblend on the board", function()
  H.background()
  H.type("i")
  local s = H.state()
  H.ok(s.open and s.focused, "the board keeps focus")
  H.eq(vim.wo[s.win].winblend, 0, "the popover window's winblend is 0")
  local dim = api.nvim_get_hl(0, { name = "EnviSudokuDim", link = false })
  H.ok(dim.fg ~= nil, "EnviSudokuDim sets a foreground")
  H.ok(dim.bg == nil and dim.blend == nil and dim.reverse == nil, "EnviSudokuDim is foreground-only")
end)

H.finish()
