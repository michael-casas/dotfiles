-- features/02-normal-movement-counts.feature (WP2).
local H = require("hcmux.sudoku.test.harness")
H.boot()

local function moves(title, cases)
  for _, case in ipairs(cases) do
    H.scenario(title .. ": " .. case[3], function()
      local r, c, keys, end_r, end_c = unpack(case)
      H.background()
      H.place(r, c)
      H.type(keys)
      H.eq(H.state().cursor, { r = end_r, c = end_c }, "cursor box")
    end)
  end
end

moves("single-cell moves", {
  { 5, 5, "h", 5, 4 },
  { 5, 5, "j", 6, 5 },
  { 5, 5, "k", 4, 5 },
  { 5, 5, "l", 5, 6 },
})

moves("counts repeat the motion", {
  { 1, 1, "3j", 4, 1 },
  { 1, 1, "4l", 1, 5 },
  { 1, 1, "3j4l", 4, 5 },
  { 1, 1, "12l", 1, 9 },
  { 1, 1, "0l", 1, 2 },
})

for _, case in ipairs({
  { 1, 1, "k", 1, 1 },
  { 1, 1, "h", 1, 1 },
  { 4, 5, "99j", 9, 5 },
  { 4, 5, "99l", 4, 9 },
  { 9, 9, "20k", 1, 9 },
}) do
  H.scenario("moves clamp at the board edge, keeping the other coordinate: " .. case[3], function()
    local r, c, keys, end_r, end_c = unpack(case)
    H.background()
    H.place(r, c)
    vim.v.errmsg = ""
    H.type(keys)
    H.eq(H.state().cursor, { r = end_r, c = end_c }, "cursor box")
    H.eq(vim.v.errmsg, "", "no error message")
    -- At the edge an unbound native motion could leave the model in place too.
    local map = vim.fn.maparg(keys:sub(-1), "n", false, true)
    H.eq(map.buffer, 1, "the Sudoku buffer owns the motion")
  end)
end

H.scenario("movement does not change the board, history or timer state", function()
  H.background()
  local board = H.state().board
  H.type("3j")
  H.type("4l")
  H.type("2k")
  local state = H.state()
  H.eq(state.cursor, { r = 2, c = 5 }, "the motions executed")
  H.eq(state.board, board, "board unchanged")
  H.eq(state.undo, 0, "undo depth")
  H.eq(state.timer.status, "running", "timer still running")
end)

moves("optional row/column jumps with counts", {
  { 4, 5, "0", 4, 1 },
  { 4, 5, "$", 4, 9 },
  { 4, 5, "gg", 1, 5 },
  { 4, 5, "G", 9, 5 },
  { 4, 5, "3gg", 3, 5 },
  { 4, 5, "7G", 7, 5 },
})

H.finish()
