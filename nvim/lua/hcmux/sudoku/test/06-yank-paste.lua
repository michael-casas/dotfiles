-- features/06-yank-paste.feature: every scenario (WP4).
local H = require("hcmux.sudoku.test.harness")
local W = require("hcmux.sudoku.test.wp4")
-- A clipboard provider for the unnamedplus scenario (headless has no system clipboard).
local clip = {}
vim.g.clipboard = {
  name = "sudoku-test",
  copy = {
    ["+"] = function(lines, regtype)
      clip["+"] = { lines, regtype }
    end,
    ["*"] = function(lines, regtype)
      clip["*"] = { lines, regtype }
    end,
  },
  paste = {
    ["+"] = function()
      return clip["+"] or { {}, "v" }
    end,
    ["*"] = function()
      return clip["*"] or { {}, "v" }
    end,
  },
}
H.boot()

local function fresh()
  vim.o.clipboard = ""
  vim.fn.setreg('"', "")
  H.background()
end

H.scenario("y on a given then p on an empty tile copies the digit", function()
  fresh()
  H.type("y")
  H.eq(H.state().register, "5", "state().register is 5 after y")
  H.place(1, 3)
  H.type("p")
  local s = H.state()
  H.eq(s.board[1][3], 5, "state().board[1][3] == 5")
  H.ok(not s.givens[1][3] and H.groups(1, 3).EnviSudokuEntry, "R1C3 holds the entry 5 (styled EnviSudokuEntry)")
  H.eq(s.undo, 1, "state().undo is 1")
  H.eq(s.register, "5", 'state().register == "5"')
end)

H.scenario("y writes the unnamed register (and the clipboard under unnamedplus)", function()
  fresh()
  H.place(2, 5)
  H.type("y")
  H.eq(vim.fn.getreg('"'), "9", "getreg('\"') is 9")
  vim.fn.setreg('"', "")
  clip["+"] = nil
  vim.o.clipboard = "unnamedplus"
  H.type("y")
  H.eq(vim.fn.getreg("+"), "9", 'with clipboard=unnamedplus, getreg("+") is 9')
  H.eq(vim.fn.getreg('"'), "9", "and the unnamed register follows")
  H.place(1, 3)
  H.type("p")
  H.eq(H.state().board[1][3], 9, "p reads it back from the clipboard")
  vim.o.clipboard = ""
end)

H.scenario("y on an empty tile leaves the register intact", function()
  fresh()
  H.type("y")
  H.place(1, 3)
  H.type("y")
  H.eq(vim.fn.getreg('"'), "5", "the empty tile did not overwrite the register")
  H.place(1, 4)
  H.type("p")
  H.eq(H.state().board[1][4], 5, "R1C4 holds 5")
end)

H.scenario("p onto a given changes nothing", function()
  fresh()
  H.type("y")
  H.place(1, 2)
  H.type("p")
  local s = H.state()
  H.eq(s.board[1][2], 3, "R1C2 still holds the given 3")
  H.ok(s.givens[1][2], "and it is still a given")
  H.eq(s.board, H.CLASSIC, "the board equals the fixture")
  H.eq(s.undo, 0, "state().undo is 0")
end)

for _, ex in ipairs({
  { "7", 7 },
  { "7\n", 7 },
  { "0", 0 },
  { "42", 0 },
  { "foo", 0 },
}) do
  H.scenario(("p accepts only a single digit 1-9 from the register: %s"):format(ex[1]:gsub("\n", "\\n")), function()
    fresh()
    vim.fn.setreg('"', ex[1])
    H.place(1, 3)
    H.type("p")
    local s = H.state()
    H.eq(s.board[1][3], ex[2], ("register %q: R1C3"):format(ex[1]))
    H.eq(s.undo, ex[2] == 0 and 0 or 1, "history follows the board")
    if ex[2] == 0 then
      H.eq(s.board, H.CLASSIC, "an invalid register leaves the board intact")
    end
  end)
end

H.scenario("p overwrites an existing entry", function()
  fresh()
  W.commit(1, 3, 4)
  H.place(1, 1)
  H.type("y")
  H.place(1, 3)
  H.type("p")
  local s = H.state()
  H.eq(s.board[1][3], 5, "R1C3 holds 5")
  H.eq(s.undo, 2, "the overwrite is its own step")
end)

H.finish()
