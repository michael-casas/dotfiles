-- features/01-open-close.feature (all scenarios; WP1).
local H = require("hcmux.sudoku.test.harness")
local api = vim.api
H.boot()

H.scenario(":EnviSudoku new classic opens a focused popover on the fixture", function()
  H.layout()
  H.eq(api.nvim_get_current_win(), H.grid, "grid.txt has focus")
  H.type(":EnviSudoku new classic<CR>")
  local s = H.state()
  H.ok(s.open and s.focused, "a popover window is open and focused")
  H.eq(api.nvim_get_current_win(), s.win, "the current window is the popover")
  H.ok(api.nvim_win_get_config(s.win).relative ~= "", "the popover is a float")
  H.eq(s.board, H.CLASSIC, "the board shows the classic fixture")
  for r = 1, 9 do
    for c = 1, 9 do
      if H.CLASSIC[r][c] ~= 0 then
        H.ok(H.groups(r, c).EnviSudokuGiven, ("R%dC%d is rendered as EnviSudokuGiven"):format(r, c))
        H.ok(H.lines()[2 * r]:find(tostring(H.CLASSIC[r][c]), 1, true), "the given digit is drawn")
      end
    end
  end
  H.eq(s.cursor, { r = 1, c = 1 }, "the cursor box outlines R1C1")
  H.eq(s.hl.cursor, { { r = 1, c = 1 } }, "the outline is on R1C1")
  H.eq(H.footer(), "NORMAL  R1C1  00:00 RUNNING", "footer")
end)

H.scenario(":EnviSudoku focuses an already open popover without restarting", function()
  H.background()
  H.place(4, 5)
  H.advance(4000)
  H.type("<C-w>p")
  H.eq(api.nvim_get_current_win(), H.grid, "<C-w>p puts focus in grid.txt")
  H.ok(H.state().open and not H.state().focused, "the popover is still shown")
  local before = H.state().timer.elapsed_ms
  H.advance(1000)
  H.type(":EnviSudoku<CR>")
  local s = H.state()
  H.ok(s.focused, "the popover has focus")
  H.eq(s.cursor, { r = 4, c = 5 }, "the cursor box is still on R4C5")
  H.ok(s.timer.elapsed_ms >= before and s.timer.elapsed_ms == 5000, "the elapsed time did not reset")
  H.eq(H.footer(), "NORMAL  R4C5  00:05 RUNNING", "footer")
end)

H.scenario(":q pauses the timer and closes the popover, restoring the invoking window", function()
  H.background()
  local explorer = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.w[w].snacks_win then
      explorer[w] = api.nvim_win_get_buf(w)
    end
  end
  H.ok(next(explorer), "the explorer is open")
  local term_buf = api.nvim_win_get_buf(H.term)
  H.advance(10000)
  H.eq(H.footer(), "NORMAL  R1C1  00:10 RUNNING", "running at 00:10")
  H.type(":q<CR>")
  local s = H.state()
  H.ok(not s.open, "the popover window is closed")
  H.eq(api.nvim_get_current_win(), H.grid, "focus is back in grid.txt")
  for w, b in pairs(explorer) do
    H.ok(api.nvim_win_is_valid(w) and api.nvim_win_get_buf(w) == b, "the explorer is unchanged")
  end
  H.ok(api.nvim_win_is_valid(H.term) and api.nvim_win_get_buf(H.term) == term_buf, "the terminal split is unchanged")
  H.eq(s.timer, { status = "paused", elapsed_ms = 10000 }, "the timer is paused")
  H.advance(2000)
  H.eq(H.state().timer, { status = "paused", elapsed_ms = 10000 }, "elapsed_ms is frozen across 2 s")
end)

for _, cmd in ipairs({ ":q", ":qu", ":quit", ":q!" }) do
  H.scenario("quit abbreviations route the same way: " .. cmd, function()
    H.background()
    H.advance(3000)
    H.type(cmd .. "<CR>")
    local s = H.state()
    H.ok(not s.open, cmd .. " closes the popover")
    H.eq(s.timer, { status = "paused", elapsed_ms = 3000 }, cmd .. " pauses the timer")
    H.eq(api.nvim_get_current_win(), H.grid, "focus returns to grid.txt")
  end)
end

H.scenario("reopening after :q resumes the same puzzle and timer", function()
  H.background()
  H.place(1, 3)
  H.enter(1, 3, 4)
  H.advance(20000)
  H.type(":q<CR>")
  H.ok(not H.state().open, "closed")
  H.advance(7000)
  H.type(":EnviSudoku<CR>")
  local s = H.state()
  H.ok(s.open and s.focused, "the popover is open")
  H.eq(s.board[1][3], 4, "the same board with 4 at R1C3")
  H.eq(s.cursor, { r = 1, c = 3 }, "the cursor box is on the cell it was on when I closed")
  H.eq(s.timer, { status = "running", elapsed_ms = 20000 }, "the timer is RUNNING from 00:20")
  H.eq(H.footer(), "NORMAL  R1C3  00:20 RUNNING", "footer")
  H.advance(1500)
  H.eq(H.state().timer.elapsed_ms, 21500, "and increasing")
end)

H.scenario("a canceled command line does not close the popover", function()
  H.background()
  H.type(":q<Esc>")
  local s = H.state()
  H.ok(s.open and s.focused, "the popover is still open and focused")
  H.eq(s.mode, "normal", "in NORMAL")
  H.eq(vim.fn.mode(), "n", "nvim is in Normal mode")
  H.eq(s.timer.status, "running", "the timer is still RUNNING")
end)

H.scenario(":q in an ordinary buffer is unaffected by the game", function()
  H.layout()
  local closes = 0
  local off = H.sudoku().on("close", function()
    closes = closes + 1
  end)
  vim.cmd.split()
  local split = api.nvim_get_current_win()
  H.eq(vim.fn.fnamemodify(api.nvim_buf_get_name(0), ":t"), "grid.txt", "grid.txt has focus in a split")
  local count = #api.nvim_tabpage_list_wins(0)
  H.type(":q<CR>")
  off()
  H.ok(not api.nvim_win_is_valid(split), "the grid.txt window closes natively")
  H.eq(#api.nvim_tabpage_list_wins(0), count - 1, "one window fewer")
  H.eq(closes, 0, "no EnviSudoku handler ran")
end)

H.finish()
