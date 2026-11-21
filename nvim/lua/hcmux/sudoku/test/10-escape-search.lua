-- features/10-escape.feature: "<Esc> in NORMAL keeps an accepted search" and
-- "<Esc> in SEARCH cancels the prompt and returns to NORMAL" (WP3).
local H = require("hcmux.sudoku.test.harness")
local S = require("hcmux.sudoku.test.wp3")
H.boot()

H.scenario("<Esc> in NORMAL keeps an accepted search", function()
  H.background()
  H.type("/9<CR>")
  vim.fn.setreg("/", "foo")
  vim.o.hlsearch = true
  H.eq(vim.v.hlsearch, 1, "setup: Neovim's search highlighting is on")
  for i = 1, 2 do
    H.type("<Esc>")
    S.matches_are(S.NINES, "<Esc> #" .. i .. ": the 4 match highlights are still shown")
    S.footer_ends("/9 4/9", "<Esc> #" .. i .. ': the footer shows "/9 4/9"')
    H.eq(H.state().search.accepted, true, "<Esc> #" .. i .. ": the search is still accepted")
    H.ok(H.state().open and H.state().focused, "<Esc> #" .. i .. ": the popover stays open and focused")
  end
  -- Diverges on purpose from LazyVim's global <Esc> = :noh (REC F7): that never ran.
  H.eq(vim.v.hlsearch, 1, "LazyVim's <Esc> :noh did not run")
end)

H.scenario("<Esc> in SEARCH cancels the prompt and returns to NORMAL", function()
  H.background()
  H.type("/9")
  S.matches_are(S.NINES, "setup: the 9s are highlighted live")
  H.type("<Esc>")
  local s = H.state()
  H.eq(s.mode, "normal", "state().mode")
  H.ok(H.footer():find("^NORMAL "), "the footer mode reads NORMAL: " .. H.footer())
  S.matches_are({}, "no tile carries EnviSudokuMatch")
  H.eq(s.hl.dim, {}, "and nothing is dimmed")
  H.eq(s.search, nil, "no search is accepted")
  S.no_segment("the footer has no search count")
  S.cursor_is(1, 1, "the cursor box has not moved")
  H.ok(s.open and s.focused, "the popover stays open and focused")
  H.type("n")
  S.cursor_is(1, 1, "n after a canceled first search keeps the cursor")
end)

H.finish()
