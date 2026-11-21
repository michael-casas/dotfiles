-- The bundled puzzles (Q2): `classic` matches the README, and every puzzle has
-- exactly one solution (counted here by an independent backtracking solver).
local H = require("hcmux.sudoku.test.harness")
local puzzles = require("hcmux.sudoku.puzzles")

local function solutions(cells, limit)
  local function ok(i, d)
    local r, c = math.floor(i / 9), i % 9
    for k = 0, 8 do
      if cells[r * 9 + k] == d or cells[k * 9 + c] == d then
        return false
      end
      local br, bc = r - r % 3 + math.floor(k / 3), c - c % 3 + k % 3
      if cells[br * 9 + bc] == d then
        return false
      end
    end
    return true
  end
  local function count()
    local i
    for k = 0, 80 do
      if cells[k] == 0 then
        i = k
        break
      end
    end
    if not i then
      local digits = {}
      for k = 0, 80 do
        digits[k + 1] = cells[k]
      end
      return 1, table.concat(digits)
    end
    local n, first = 0, nil
    for d = 1, 9 do
      if ok(i, d) then
        cells[i] = d
        local m, s = count()
        n, first = n + m, first or s
        cells[i] = 0
        if n >= limit then
          break
        end
      end
    end
    return n, first
  end
  return count()
end

local function flat(board)
  local cells = {}
  for r = 1, 9 do
    for c = 1, 9 do
      cells[(r - 1) * 9 + c - 1] = board[r][c]
    end
  end
  return cells
end

H.scenario("classic is the README fixture with its unique solution", function()
  H.eq(puzzles.board("classic"), H.CLASSIC, "classic fixture")
  local n, solution = solutions(flat(H.CLASSIC), 2)
  H.eq(n, 1, "classic has one solution")
  H.eq(
    solution,
    ("534678912 672195348 198342567 859761423 426853791 713924856 961537284 287419635 345286179"):gsub(" ", ""),
    "README solution"
  )
end)

H.scenario("every bundled puzzle has exactly one solution", function()
  H.ok(#puzzles.names() >= 5, "a bundled set, not just the fixture")
  for _, name in ipairs(puzzles.names()) do
    H.eq((solutions(flat(puzzles.board(name)), 2)), 1, name .. " has one solution")
  end
end)

H.finish()
