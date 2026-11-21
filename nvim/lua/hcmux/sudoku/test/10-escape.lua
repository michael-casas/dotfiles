-- features/10-escape.feature: "NORMAL no-op", "Ex command line cancels" (WP1).
local H = require("hcmux.sudoku.test.harness")
local api = vim.api
H.boot()

H.scenario("<Esc> in NORMAL is a no-op that keeps the popover open", function()
  H.background()
  local win = H.state().win
  for i = 1, 2 do
    H.type("<Esc>")
    local s = H.state()
    H.ok(s.open and s.focused and s.win == win, "<Esc> #" .. i .. ": the popover is still open and focused")
    H.eq(s.mode, "normal", "<Esc> #" .. i .. ": mode")
    H.ok(H.footer():find("^NORMAL  "), "<Esc> #" .. i .. ": the footer mode reads NORMAL")
  end
  local map = vim.fn.maparg("<Esc>", "n", false, true)
  H.ok(map.buffer == 1 and map.desc:find("^Sudoku: "), "the board owns <Esc>, not LazyVim's :noh")
end)

H.scenario("<Esc> in an Ex command line cancels the command and returns to NORMAL", function()
  H.background()
  local save = H.state().save_path
  H.type(":wq<Esc>")
  H.ok(not vim.uv.fs_stat(save), "no save file exists")
  local s = H.state()
  H.ok(s.open and s.focused, "the popover is still open")
  H.eq(s.mode, "normal", "in NORMAL")
  H.eq(vim.fn.mode(), "n", "nvim is in Normal mode")
  H.eq(s.timer.status, "running", "the timer is RUNNING")
  H.eq(api.nvim_get_current_win(), s.win, "focus stays on the board")
end)

H.finish()
