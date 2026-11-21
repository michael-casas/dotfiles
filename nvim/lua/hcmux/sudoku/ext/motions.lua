local keys = require("hcmux.sudoku.keys")

local function motion(lhs, description, fn)
  keys.register({ lhs = lhs, mode = "normal", desc = "Sudoku: " .. description, fn = fn })
end

local function clamp(position)
  return math.max(1, math.min(9, position))
end

motion("h", "left [count] cells", function(game, ctx)
  game.cursor.c = clamp(game.cursor.c - ctx.count1)
end)

motion("j", "down [count] cells", function(game, ctx)
  game.cursor.r = clamp(game.cursor.r + ctx.count1)
end)

motion("k", "up [count] cells", function(game, ctx)
  game.cursor.r = clamp(game.cursor.r - ctx.count1)
end)

motion("l", "right [count] cells", function(game, ctx)
  game.cursor.c = clamp(game.cursor.c + ctx.count1)
end)

motion("0", "first cell in row", function(game)
  game.cursor.c = 1
end)

motion("$", "last cell in row", function(game)
  game.cursor.c = 9
end)

motion("gg", "first row or [count] row", function(game, ctx)
  game.cursor.r = clamp(ctx.count)
end)

motion("G", "last row or [count] row", function(game, ctx)
  game.cursor.r = ctx.count == 0 and 9 or clamp(ctx.count)
end)

local function cycle_empty(direction)
  return function(game, ctx)
    local row = game.board[game.cursor.r]
    local empty = {}
    -- Scan one lap in the motion's direction, including the starting cell last.
    for step = 1, #row do
      local column = (game.cursor.c - 1 + step * direction) % #row + 1
      if row[column] == 0 then
        empty[#empty + 1] = column
      end
    end
    if #empty > 0 then
      game.cursor.c = empty[(ctx.count1 - 1) % #empty + 1]
    end
  end
end

motion("{", "previous [count] empty cells in row", cycle_empty(-1))
motion("}", "next [count] empty cells in row", cycle_empty(1))
