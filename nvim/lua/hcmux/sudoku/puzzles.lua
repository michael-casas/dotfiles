-- Bundled puzzles (OPEN-QUESTIONS Q2): each has exactly one solution, which
-- test/00-puzzles.lua checks. 81 digits in row-major order, 0 = empty.
-- `classic` is the deterministic fixture from features/README.md.
local M = {}

local SET = {
  classic = "530070000600195000098000060800060003400803001700020006060000280000419005000080079",
  lantern = "000024800003000000008351004500000073000608905000000002200003000350010009090500000",
  harbor = "009001700105800009000940000002400070000070000900500802200000030000000600470036000",
  meadow = "006001020000600004103000060000702800000000200809000040004070000980400030700260000",
  quarry = "030200098006000000000039020000800041710000080080103000800027000000400005054001060",
  willow = "050603040000087000000001053000300000002090380080400005010000000500004000900000237",
  summit = "600740000000009000083600054000002000070010900004000320020500010507000008008060000",
}

function M.names()
  local names = vim.tbl_keys(SET)
  table.sort(names)
  return names
end

--- A fresh 9x9 board for `name`, or nil if there is no such puzzle.
function M.board(name)
  local digits = SET[name]
  if not digits then
    return nil
  end
  local board = {}
  for r = 1, 9 do
    board[r] = {}
    for c = 1, 9 do
      local i = (r - 1) * 9 + c
      board[r][c] = tonumber(digits:sub(i, i))
    end
  end
  return board
end

function M.random()
  local names = M.names()
  return names[math.random(#names)]
end

return M
