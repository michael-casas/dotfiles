-- Shared setup for the WP4 suites (04, 05, 06, 10-escape-insert, 11-highlighting-insert):
-- typed entries, notices, the draft overlay, and stand-ins for keys other WPs own.
local api = vim.api
local H = require("hcmux.sudoku.test.harness")
local W = {}

--- Commit `digit` at (r, c) the way a player does: position (setup), then i, digit, <Enter>.
function W.commit(r, c, digit)
  H.place(r, c)
  H.type("i")
  H.type(tostring(digit))
  H.type("<CR>")
  H.eq(H.state().board[r][c], digit, ("setup: R%dC%d holds %d"):format(r, c, digit))
end

--- Record vim.notify calls from now on: returns the list it fills.
function W.notices()
  local seen = {}
  local orig = vim.notify
  vim.notify = function(msg, level, opts)
    seen[#seen + 1] = { msg = tostring(msg), level = level or vim.log.levels.INFO }
    return orig(msg, level, opts)
  end
  return seen
end

--- The virtual text drawn over cell (r, c)'s digit by the draft namespace, as
--- { text, group } pairs (independent of the extension's code: found by namespace name).
function W.overlay(r, c)
  local ns = api.nvim_get_namespaces().envi_sudoku_draft
  if not ns then
    return {}
  end
  local render = require("hcmux.sudoku.render")
  local row, s, e = render.span(r, c)
  local out = {}
  for _, m in ipairs(api.nvim_buf_get_extmarks(H.state().buf, ns, { row, s }, { row, e - 1 }, { details = true })) do
    for _, chunk in ipairs(m[4].virt_text or {}) do
      out[#out + 1] = { chunk[1], chunk[2] }
    end
  end
  return out
end

--- Every extmark in the board namespace over cell (r, c)'s digit: { group = priority }.
function W.priorities(r, c)
  local render = require("hcmux.sudoku.render")
  local row, s, e = render.span(r, c)
  local out = {}
  for _, m in
    ipairs(api.nvim_buf_get_extmarks(H.state().buf, render.ns, { row, s }, { row, e - 1 }, {
      details = true,
      overlap = true,
    }))
  do
    local d = m[4]
    if d.hl_group and m[2] == row and m[3] < e and (d.end_col or 0) > s then
      out[d.hl_group] = math.max(out[d.hl_group] or 0, d.priority or 0)
    end
  end
  return out
end

--- The group that wins over cell (r, c)'s digit (the highest-priority extmark).
function W.top_group(r, c)
  local best, top = -1, nil
  for group, p in pairs(W.priorities(r, c)) do
    if p > best then
      best, top = p, group
    end
  end
  return top
end

local function is_real(lhs, mode)
  local spec = require("hcmux.sudoku.keys").handler(lhs, mode)
  return spec and spec.mode ~= "*" and not spec.desc:find("test stand-in", 1, true)
end
W.is_real = is_real

--- Register `fn` for (lhs, mode) unless another work package already handles it.
function W.stand_in(lhs, mode, fn)
  if not is_real(lhs, mode) then
    require("hcmux.sudoku.keys").register({ lhs = lhs, mode = mode, desc = "Sudoku: test stand-in " .. lhs, fn = fn })
  end
end

--- WP2's motions, as "*" stand-ins: a worst case that would move in every mode
--- unless a mode claims the key. Real WP2 handlers win when present.
function W.motion_stand_ins()
  local function move(dr, dc)
    return function(game, ctx)
      game.cursor.r = math.max(1, math.min(9, game.cursor.r + dr * ctx.count1))
      game.cursor.c = math.max(1, math.min(9, game.cursor.c + dc * ctx.count1))
    end
  end
  if not is_real("j", "normal") then
    W.stand_in("h", "*", move(0, -1))
    W.stand_in("j", "*", move(1, 0))
    W.stand_in("k", "*", move(-1, 0))
    W.stand_in("l", "*", move(0, 1))
  end
end

--- WP3's digit search, as stand-ins (`/`, a digit, <Enter>, and a match layer).
--- Real WP3 handlers win when present. Returns true if the stand-in is in use.
function W.search_stand_ins()
  if is_real("/", "normal") then
    return false
  end
  W.stand_in("/", "normal", function(game)
    game.mode, game._test_search = "search", nil
  end)
  for d = 1, 9 do
    W.stand_in(tostring(d), "search", function(game)
      game._test_search = d
    end)
  end
  W.stand_in("<CR>", "search", function(game)
    game.mode = "normal"
  end)
  W.stand_in("<Esc>", "search", function(game)
    game.mode, game._test_search = "normal", nil
  end)
  require("hcmux.sudoku.render").layer({
    name = "test-search-match",
    group = "EnviSudokuMatch",
    priority = 130,
    cells = function(game)
      local out = {}
      for r = 1, 9 do
        for c = 1, 9 do
          if game._test_search and game.mode ~= "search" and game.board[r][c] == game._test_search then
            out[#out + 1] = { r = r, c = c }
          end
        end
      end
      return out
    end,
  })
  return true
end

return W
