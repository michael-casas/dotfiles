-- features/07-empty-tile-cycling.feature (WP2).
local H = require("hcmux.sudoku.test.harness")
H.boot()

local function cursor_on(column)
  H.eq(H.state().cursor, { r = 1, c = column }, "cursor box")
end

H.scenario("} walks right through the empty tiles of the current row and wraps", function()
  H.background()
  H.type("}")
  cursor_on(3)
  H.type("}")
  cursor_on(4)
  for _ = 1, 4 do
    H.type("}")
  end
  cursor_on(9)
  H.type("}")
  cursor_on(3)
end)

H.scenario("{ walks left and wraps", function()
  H.background()
  H.place(1, 3)
  H.type("{")
  cursor_on(9)
  H.type("{")
  cursor_on(8)
end)

H.scenario("a count skips empty tiles", function()
  H.background()
  H.type("3}")
  cursor_on(6)
end)

H.scenario("a row with no other empty tile keeps the cursor", function()
  H.background()
  for _, column in ipairs({ 4, 6, 7, 8, 9 }) do
    H.enter(1, column, 6)
  end
  H.place(1, 3)
  vim.v.errmsg = ""
  H.type("}")
  cursor_on(3)
  H.eq(vim.v.errmsg, "", "no error message")
  H.eq(vim.fn.maparg("}", "n", false, true).buffer, 1, "the Sudoku buffer owns the cycle")
end)

H.scenario("tiles filled by entries are skipped", function()
  H.background()
  H.enter(1, 4, 6)
  H.place(1, 3)
  H.type("}")
  cursor_on(6)
end)

H.finish()
