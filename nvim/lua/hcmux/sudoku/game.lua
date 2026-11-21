-- The puzzle model and its timer. Pure Lua: no windows, no buffers.
-- The clock is injectable (`set_clock`) so headless tests control time.
local puzzles = require("hcmux.sudoku.puzzles")
local M = {}

local function default_clock()
  return vim.uv.hrtime() / 1e6
end
local clock = default_clock

--- fn() -> milliseconds (monotonic). nil restores the real clock.
function M.set_clock(fn)
  clock = fn or default_clock
end

local Timer = {}
Timer.__index = Timer

--- status: "running" | "paused" | "solved". Starts paused.
function M.timer(elapsed_ms)
  return setmetatable({ status = "paused", acc = elapsed_ms or 0 }, Timer)
end

function Timer:elapsed()
  local live = self.since and (clock() - self.since) or 0
  return math.floor(self.acc + live)
end

function Timer:resume()
  if self.status == "paused" then
    self.status, self.since = "running", clock()
  end
end

function Timer:pause()
  if self.status == "running" then
    self.acc, self.since, self.status = self.acc + clock() - self.since, nil, "paused"
  end
end

--- Freeze the time for good (a solved puzzle).
function Timer:stop()
  self:pause()
  self.status = "solved"
end

--- "MM:SS", or "H:MM:SS" past an hour.
function M.format(ms)
  local s = math.floor(ms / 1000)
  local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s % 60)
  end
  return string.format("%02d:%02d", m, s % 60)
end

--- A fresh game on bundled puzzle `name`, cursor on R1C1, NORMAL, timer paused.
function M.new(name)
  local board = assert(puzzles.board(name), "no such puzzle: " .. tostring(name))
  local givens = {}
  for r = 1, 9 do
    givens[r] = {}
    for c = 1, 9 do
      givens[r][c] = board[r][c] ~= 0
    end
  end
  return { puzzle = name, board = board, givens = givens, cursor = { r = 1, c = 1 }, mode = "normal", timer = M.timer() }
end

return M
