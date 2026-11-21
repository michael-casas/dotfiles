-- WP3: the game's own digit search, on WP1's seam (README: Seams). Contract:
-- features 03 (all), 10 "keeps an accepted search" and "SEARCH cancels", 11 "search
-- dims non-matches"; OPEN-QUESTIONS Q5, Q6 and Q17 defaults.
--
-- NORMAL  /      open the one-digit prompt (game mode "search"; the footer shows "/_")
--         n / N  go to the next / previous tile holding the accepted digit, row-major,
--                wrapping at the board edges; a count skips matches (3n). With no
--                accepted search or no matches the cursor stays, with no message.
-- SEARCH  1-9    type (or replace) the digit: its tiles are highlighted live
--         <BS>   clear the typed digit
--         <CR>   accept the typed digit and return to NORMAL, the cursor staying put
--                (Q5); an empty prompt keeps the previous accepted search
--         <Esc>  cancel: return to NORMAL with the previous accepted search restored
--         0 / n N y and the rest of the board keys are ignored
--
-- While a search is accepted, its tiles (givens and player entries alike, recounted
-- on every render, so edits and undo update them) carry EnviSudokuMatch and, in board
-- NORMAL, the other tiles EnviSudokuDim (Q17); the footer adds "/<d> <n>/9". The
-- search never reads or writes Neovim's "/" register, 'hlsearch' or v:searchforward,
-- and the board's own n/N/<Esc> keep LazyVim's global n/N and <Esc>=:noh out (REC F7).
local sudoku = require("hcmux.sudoku")
local keys = require("hcmux.sudoku.keys")
local render = require("hcmux.sudoku.render")

local M = {}

-- Per-game search state, never part of the puzzle model (so never saved with it):
-- { accepted = digit|nil, typed = digit|nil } (typed only while the prompt is open).
local searches = setmetatable({}, { __mode = "k" })

local function search(game)
  searches[game] = searches[game] or {}
  return searches[game]
end

--- The digit whose tiles are shown: the typed one while the prompt is open, else the accepted one.
function M.digit(game)
  local s = searches[game]
  if not s then
    return nil
  end
  if game.mode == "search" then
    return s.typed
  end
  return s.accepted
end

--- The tiles of `game` holding `digit`, row-major.
function M.matches(game, digit)
  local out = {}
  if digit then
    for r = 1, 9 do
      for c = 1, 9 do
        if game.board[r][c] == digit then
          out[#out + 1] = { r = r, c = c }
        end
      end
    end
  end
  return out
end

local function register(lhs, mode, desc, fn)
  keys.register({ lhs = lhs, mode = mode, desc = "Sudoku: " .. desc, fn = fn })
end

register("/", "normal", "search a digit (/1-9, <Enter> accepts)", function(game)
  search(game).typed = nil
  game.mode = "search"
end)

-- Step `count` matches from the cursor in row-major order (dir = 1 next, -1 previous), wrapping.
local function step(game, dir, count)
  local found = M.matches(game, searches[game] and searches[game].accepted)
  if #found == 0 then
    return
  end
  local here = (game.cursor.r - 1) * 9 + game.cursor.c
  -- The index of the first match after (dir = 1) or before (dir = -1) the cursor.
  local i
  if dir == 1 then
    i = #found + 1
    for k, cell in ipairs(found) do
      if (cell.r - 1) * 9 + cell.c > here then
        i = k
        break
      end
    end
  else
    i = 0
    for k = #found, 1, -1 do
      local cell = found[k]
      if (cell.r - 1) * 9 + cell.c < here then
        i = k
        break
      end
    end
  end
  -- i is the first step; each further step moves one more match along.
  local target = (i - 1 + dir * (count - 1)) % #found + 1
  game.cursor = { r = found[target].r, c = found[target].c }
end

register("n", "normal", "next tile with the searched digit [count]", function(game, ctx)
  step(game, 1, ctx.count1)
end)
register("N", "normal", "previous tile with the searched digit [count]", function(game, ctx)
  step(game, -1, ctx.count1)
end)

for d = 1, 9 do
  register(tostring(d), "search", "search for " .. d, function(game)
    search(game).typed = d
  end)
end

local function leave(game)
  search(game).typed = nil
  game.mode = "normal"
end

register("<CR>", "search", "accept the searched digit", function(game)
  local s = search(game)
  s.accepted = s.typed or s.accepted
  leave(game)
end)
register("<Esc>", "search", "cancel the search, restoring the previous one", leave)
register("<BS>", "search", "clear the searched digit", function(game)
  search(game).typed = nil
end)
for _, lhs in ipairs({ "0", "/", "n", "N", "y" }) do
  register(lhs, "search", ("only 1-9 in the search prompt (%s)"):format(lhs), function() end)
end
-- Neovim's own pattern searches would set the "/" register and 'hlsearch' highlights.
for _, lhs in ipairs({ "?", "*", "#", "g*", "g#", "gn", "gN" }) do
  register(lhs, "*", ("the board searches digits with / (%s)"):format(lhs), function() end)
end

-- Leaving the board (:q, a close) with the prompt open cancels it, as <Esc> does.
sudoku.on("close", function(game)
  if game and game.mode == "search" then
    leave(game)
  end
end)

render.layer({
  name = "search-match",
  group = "EnviSudokuMatch",
  priority = 130,
  cells = function(game)
    return M.matches(game, M.digit(game))
  end,
})

-- Q17: while a search is accepted, board NORMAL dims everything else. INSERT has its
-- own guides and dim (WP4), above which the matches still show (130 > 120 > 110).
render.layer({
  name = "search-dim",
  group = "EnviSudokuDim",
  priority = 110,
  cells = function(game)
    local digit = game.mode == "normal" and M.digit(game)
    if not digit then
      return {}
    end
    local out = {}
    for r = 1, 9 do
      for c = 1, 9 do
        if game.board[r][c] ~= digit then
          out[#out + 1] = { r = r, c = c }
        end
      end
    end
    return out
  end,
})

render.footer_segment(function(game)
  if game.mode == "search" then
    local typed = search(game).typed
    return typed and ("/%d %d/9"):format(typed, #M.matches(game, typed)) or "/_"
  end
  local digit = M.digit(game)
  return digit and ("/%d %d/9"):format(digit, #M.matches(game, digit)) or nil
end)

sudoku.extend_state(function(state, game)
  if not game then
    return
  end
  local s = searches[game]
  if game.mode == "search" then
    local typed = s and s.typed
    state.search = { digit = typed, accepted = false, matches = M.matches(game, typed) }
  elseif s and s.accepted then
    state.search = { digit = s.accepted, accepted = true, matches = M.matches(game, s.accepted) }
  end
end)

return M
