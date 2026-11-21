-- Fresh-process assertions share the parent suite's isolated XDG_STATE_HOME.
local root, session, action = unpack(arg)
vim.opt.rtp:prepend(root .. "/nvim")
vim.g.hcmux_session = session
vim.o.lines, vim.o.columns = 40, 80
local sudoku = require("hcmux.sudoku")
sudoku.setup()
local now = 0
sudoku._set_clock(function()
  return now
end)

local function type_keys(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "mtx", false)
end

if action == "resume" then
  type_keys(":EnviSudoku<CR>")
  local s = sudoku.state()
  assert(s.board[1][3] == 4 and s.givens[1][1] and not s.givens[1][3], "saved board and givens restored")
  assert(s.cursor.r == 1 and s.cursor.c == 3, "saved cursor restored")
  assert(s.timer.status == "running" and s.timer.elapsed_ms == 7000, "running at saved elapsed time")
  vim.cmd.qa()
else
  require("hcmux.session").setup()
  type_keys(":EnviSudoku new classic<CR>")
  sudoku.game().board[1][3] = 4
  now = 9000
  assert(vim.bo.buftype == "nofile" and not vim.bo.modified, "Sudoku is not counted as unsaved")
  type_keys(":" .. action .. "<CR>")
  error(":" .. action .. " did not exit")
end
