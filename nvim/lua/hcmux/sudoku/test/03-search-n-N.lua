-- features/03-search-n-N.feature: every scenario (WP3). OPEN-QUESTIONS Q5 (<Enter>
-- keeps the cursor) and Q6 (row-major, wrapping, counts skip) defaults.
-- "player entries count as matches…" needs WP4's i/<Enter>/u: with WP4 present it
-- types them; without it, it edits the model through the harness and says GATED.
local H = require("hcmux.sudoku.test.harness")
local S = require("hcmux.sudoku.test.wp3")
local api = vim.api
H.boot()

S.each_layout("typing a digit after / highlights all matching tiles live", function()
  H.type("/")
  local s = H.state()
  H.eq(s.mode, "search", "state().mode")
  H.ok(H.footer():find("^SEARCH "), "the footer mode reads SEARCH: " .. H.footer())
  S.footer_ends("/_", "a one-digit prompt is visible")
  S.matches_are({}, "an empty prompt")
  S.board_visible()
  H.type("9")
  H.eq(H.state().search, { digit = 9, accepted = false, matches = S.NINES }, "state().search while typing")
  S.matches_are(S.NINES, "R2C5, R3C2, R8C6 and R9C9 (and no other cell)")
  H.eq(H.state().mode, "search", "still in SEARCH until <Enter>")
  S.board_visible()
end)

S.each_layout("<Enter> accepts the search, keeps the cursor and shows the count", function()
  H.type("/9<CR>")
  local s = H.state()
  H.eq(s.mode, "normal", "state().mode")
  H.ok(H.footer():find("^NORMAL "), "the footer mode reads NORMAL: " .. H.footer())
  S.cursor_is(1, 1, "the cursor box is still on R1C1")
  H.eq(api.nvim_win_get_cursor(s.win)[1] - 1, (H.cell(1, 1)), "Neovim's cursor stays on R1C1's line")
  S.footer_ends("/9 4/9", 'the footer shows "/9 4/9"')
  H.eq(s.search, { digit = 9, accepted = true, matches = S.NINES }, "state().search once accepted")
  S.matches_are(S.NINES, "the 4 matching tiles stay highlighted")
end)

H.scenario("n and N step through matches in row-major order and wrap", function()
  H.background()
  H.type("/9<CR>")
  S.cursor_is(1, 1, "Given: /9 accepted at R1C1")
  for _, want in ipairs({ { 2, 5 }, { 3, 2 }, { 8, 6 }, { 9, 9 }, { 2, 5 } }) do
    H.type("n")
    S.cursor_is(want[1], want[2])
  end
  H.type("N")
  S.cursor_is(9, 9, "N wraps back to R9C9")
  H.type("N")
  S.cursor_is(8, 6, "N steps to the previous match")
  H.eq(H.state().mode, "normal", "n/N stay in NORMAL")
  S.footer_ends("/9 4/9", "the count stays")
end)

H.scenario("a count on n skips matches", function()
  H.background()
  H.type("/9<CR>")
  H.type("3n")
  S.cursor_is(8, 6)
  H.type("2N")
  S.cursor_is(2, 5, "2N skips back over R3C2")
  H.type("5n")
  S.cursor_is(3, 2, "a count past the last match wraps (5 steps from R2C5)")
end)

H.scenario("player entries count as matches and the count updates after edits", function()
  H.background()
  H.type("/9<CR>")
  H.place(1, 9) -- "I move to R1C9": WP2's motions, positioned through the harness
  local wp4 = S.is_real("i", "normal") and S.is_real("u", "normal")
  if wp4 then
    H.type("i9")
    H.type("<CR>")
  else
    H.enter(1, 9, 9)
  end
  H.eq(H.state().board[1][9], 9, "R1C9 holds a player 9")
  H.ok(not H.state().givens[1][9], "R1C9 is a player entry, not a given")
  local with = vim.list_extend({ { r = 1, c = 9 } }, S.NINES)
  S.matches_are(with, "R1C9 carries EnviSudokuMatch")
  S.footer_ends("/9 5/9", 'the footer shows "/9 5/9"')
  H.type("n")
  S.cursor_is(2, 5, "n steps on from the new match")
  H.place(1, 9)
  if wp4 then
    H.type("u")
  else
    H.enter(1, 9, 0)
  end
  H.eq(H.state().board[1][9], 0, "the entry is gone")
  S.footer_ends("/9 4/9", 'after u the footer shows "/9 4/9"')
  S.matches_are(S.NINES, "after u")
  if not wp4 then
    io.stdout:write("\nSCENARIO GATED on WP4: i9<Enter> and u were model edits (H.enter), not WP4's keys\n")
  end
end)

H.scenario("<Esc> in the search prompt restores the previous accepted search", function()
  H.background()
  H.type("/9<CR>")
  H.type("/8")
  H.eq(H.state().mode, "search", "the prompt is open")
  S.matches_are(S.cells_of(8), "the 8-tiles are highlighted live")
  H.ok(H.footer():find("^SEARCH "), "the footer reads SEARCH while typing")
  H.type("<Esc>")
  H.eq(H.state().mode, "normal", "state().mode")
  H.ok(H.footer():find("^NORMAL "), "the footer mode reads NORMAL: " .. H.footer())
  S.matches_are(S.NINES, "the 9-tiles are highlighted again")
  S.footer_ends("/9 4/9", 'the footer shows "/9 4/9"')
  H.eq(H.state().search, { digit = 9, accepted = true, matches = S.NINES }, "the accepted search is restored")
  S.cursor_is(1, 1, "the cursor box has not moved")
  H.type("n")
  S.cursor_is(2, 5, "n follows the restored 9s, not the 8s")
  H.type("/<CR>")
  H.eq(H.state().search, { digit = 9, accepted = true, matches = S.NINES }, "an empty prompt's <Enter> keeps the 9s")
end)

H.scenario("n with no accepted search or no matches keeps the cursor", function()
  H.background()
  vim.fn.setreg("/", "") -- no Neovim search either, so a native n would raise E35
  vim.v.errmsg = ""
  vim.cmd("messages clear")
  H.type("n")
  S.cursor_is(1, 1, "n: the cursor box is still on R1C1")
  H.type("N")
  S.cursor_is(1, 1, "N: the cursor box is still on R1C1")
  H.eq(vim.v.errmsg, "", "no error message is shown")
  H.eq(api.nvim_exec2("messages", { output = true }).output, "", "no message at all")
  -- No matches: the only digits are the givens, so an empty board has none.
  local g = H.sudoku().game()
  for r = 1, 9 do
    for c = 1, 9 do
      g.board[r][c] = 0
    end
  end
  H.sudoku().refresh()
  H.type("/9<CR>")
  S.footer_ends("/9 0/9", "an accepted search with no matches")
  H.type("n")
  S.cursor_is(1, 1, "n with no matches keeps the cursor")
  H.type("3N")
  S.cursor_is(1, 1, "3N with no matches keeps the cursor")
  H.eq(vim.v.errmsg, "", "still no error")
end)

H.scenario("non-digit input in the search prompt is ignored", function()
  H.background()
  H.type("/x")
  H.eq(H.state().mode, "search", "still in the prompt")
  S.footer_ends("/_", "the prompt is still empty")
  H.eq(H.state().search.digit, nil, "state().search.digit == nil")
  S.matches_are({}, "no tile is highlighted")
  H.type("0")
  S.footer_ends("/_", "0: the prompt is still empty")
  H.eq(H.state().search.digit, nil, "0: state().search.digit == nil")
  for _, k in ipairs({ "/", "n", "N", "j", "l", "<BS>" }) do
    H.type(k)
    H.eq(H.state().mode, "search", k .. ": still in the prompt")
    H.eq(H.state().search.digit, nil, k .. ": the prompt is still empty")
    H.eq(vim.fn.mode(), "n", k .. ": no command line opened")
  end
  S.cursor_is(1, 1, "the ignored keys did not move the cursor box")
  -- A typed digit can be replaced, and <BS> clears it again.
  H.type("8")
  H.type("9")
  H.eq(H.state().search.digit, 9, "a second digit replaces the first")
  H.type("<BS>")
  H.eq(H.state().search.digit, nil, "<BS> clears the typed digit")
  S.matches_are({}, "<BS>: no tile is highlighted")
  H.type("<CR>")
  H.eq({ H.state().mode, H.state().search }, { "normal", nil }, "<Enter> on an empty prompt accepts nothing")
end)

H.scenario("the game search is independent of Neovim's search register", function()
  H.background()
  vim.fn.setreg("/", "foo")
  local global = {}
  for _, map in ipairs(api.nvim_get_keymap("n")) do
    if map.lhs == "n" or map.lhs == "N" then
      global[map.lhs] = map
    end
  end
  H.ok(global.n and global.N, "setup: LazyVim's global n and N are installed")
  -- Spy on LazyVim's global n/N: replace them with recorders for the scenario.
  local ran = {}
  for _, lhs in ipairs({ "n", "N" }) do
    vim.keymap.set("n", lhs, function()
      ran[#ran + 1] = lhs
    end, { desc = "test spy for LazyVim's " .. lhs })
  end
  local ok, err = xpcall(function()
    H.type("/9<CR>")
    H.eq(vim.fn.getreg("/"), "foo", 'getreg("/") is still "foo"')
    H.type("n")
    H.type("N")
    H.type("/8")
    H.type("n")
    H.type("<Esc>")
    H.eq(ran, {}, "LazyVim's global n/N mappings do not run inside the popover")
    S.cursor_is(9, 9, "the board's n then N went R1C1 -> R2C5 -> R9C9")
    H.eq(vim.fn.getreg("/"), "foo", 'getreg("/") is still "foo" after n/N')
    for _, k in ipairs({ "*", "#", "?" }) do
      H.type(k)
      H.eq(vim.fn.mode(), "n", k .. ": no pattern search opens")
      H.eq(vim.fn.getreg("/"), "foo", k .. ': getreg("/") is still "foo"')
    end
    for _, lhs in ipairs({ "/", "n", "N" }) do
      local map = vim.fn.maparg(lhs, "n", false, true)
      H.ok(map.buffer == 1 and map.desc:find("^Sudoku: "), lhs .. " is the board's own map")
    end
  end, debug.traceback)
  for _, lhs in ipairs({ "n", "N" }) do
    vim.fn.mapset(global[lhs])
  end
  H.ok(ok, err)
end)

-- Not a contract scenario: leaving the board with the prompt open cancels it (as <Esc>).
H.scenario("extra: :q with the prompt open cancels it; :EnviSudoku resumes in NORMAL", function()
  H.background()
  H.type("/9<CR>")
  H.type("/8")
  H.type(":q<CR>")
  H.ok(not H.state().open, "setup: :q closed the board")
  H.type(":EnviSudoku<CR>")
  local s = H.state()
  H.eq(s.mode, "normal", "the board reopens in NORMAL")
  H.eq(s.search, { digit = 9, accepted = true, matches = S.NINES }, "with the accepted search restored")
  S.footer_ends("/9 4/9", 'the footer shows "/9 4/9"')
end)

H.finish()
