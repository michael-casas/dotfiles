local H = require("hcmux.sudoku.test.harness")
local keys = require("hcmux.sudoku.keys")
local editing_module = "hcmux.sudoku.ext.editing"
local stub
if #vim.api.nvim_get_runtime_file("lua/hcmux/sudoku/ext/editing.lua", false) == 0 then
  stub = {
    solved = function(board)
      return board[9][1] == 3
    end,
    on_edit = function(fn)
      stub.listener = fn
    end,
  }
  package.loaded[editing_module] = stub
end

H.boot()

if not keys.handler("l", "normal") then
  keys.register({
    lhs = "l",
    desc = "Sudoku: move right (WP2 test stub)",
    fn = function(game, ctx)
      game.cursor.c = math.min(9, game.cursor.c + ctx.count1)
    end,
  })
end

if stub then
  keys.register({
    lhs = "i",
    desc = "Sudoku: edit cell (WP4 test stub)",
    fn = function(game)
      if game.timer.status ~= "solved" then
        game.mode = "insert"
      end
    end,
  })
  keys.register({ lhs = "3", mode = "insert", desc = "Sudoku: stage 3 (WP4 test stub)", fn = function() end })
  keys.register({
    lhs = "<CR>",
    mode = "insert",
    desc = "Sudoku: commit 3 (WP4 test stub)",
    fn = function(game)
      game.board[9][1], game.mode = 3, "normal"
      if stub.listener then
        stub.listener(game)
      end
    end,
  })
end

local function background()
  vim.g.hcmux_session = vim.fn.tempname():match("[^/]+$") .. "-" .. vim.uv.hrtime()
  H.background()
end

H.scenario(":w pauses with the board still visible", function()
  background()
  H.advance(5000)
  H.type(":w<CR>")
  H.ok(H.state().open and H.state().focused, "the board stays open and focused")
  H.eq(H.footer(), "NORMAL  R1C1  00:05 PAUSED")
  H.advance(10000)
  H.eq(H.state().timer, { status = "paused", elapsed_ms = 5000 })
end)

H.scenario("the first board key after :w resumes the timer", function()
  background()
  H.type(":w<CR>")
  H.type(":let g:sudoku_test_command = 1<CR>")
  H.eq(H.state().timer.status, "paused", "Ex command text does not resume")
  H.type("l")
  H.eq(H.footer(), "NORMAL  R1C2  00:00 RUNNING")
end)

H.scenario("the board is hidden or dimmed while paused so time can't be gained", function()
  background()
  H.type(":w<CR>")
  for r = 1, 9 do
    for c = 1, 9 do
      H.ok(H.groups(r, c).EnviSudokuDim, ("R%dC%d is dimmed"):format(r, c))
    end
  end
  H.type("l")
  H.eq(#H.state().hl.dim, 0, "resuming removes pause dimming")
end)

H.scenario("focus leaving the popover pauses the timer, returning resumes it", function()
  background()
  H.advance(5000)
  local board = H.state().win
  vim.api.nvim_set_current_win(H.grid)
  H.advance(10000)
  H.eq(H.state().timer, { status = "paused", elapsed_ms = 5000 })
  vim.api.nvim_set_current_win(board)
  H.advance(1000)
  H.eq(H.state().timer, { status = "running", elapsed_ms = 6000 })
end)

H.scenario("solving the puzzle stops the timer" .. (stub and " (gated on WP4)" or ""), function()
  background()
  local game = H.sudoku().game()
  local solution = {
    "534678912",
    "672195348",
    "198342567",
    "859761423",
    "426853791",
    "713924856",
    "961537284",
    "287419635",
    "345286179",
  }
  for r, row in ipairs(solution) do
    for c = 1, 9 do
      game.board[r][c] = tonumber(row:sub(c, c))
    end
  end
  H.enter(9, 1, 0)
  H.place(9, 1)
  H.advance(9000)
  H.type("i")
  H.type("3")
  H.type("<CR>")
  H.eq(H.footer(), "NORMAL  R9C1  00:09 SOLVED")
  H.advance(10000)
  H.type("i")
  H.eq(H.state().timer, { status = "solved", elapsed_ms = 9000 })
  H.eq(H.state().mode, "normal", "further edits are refused")
  H.eq(H.state().board[9][1], 3)
end)

H.finish()
