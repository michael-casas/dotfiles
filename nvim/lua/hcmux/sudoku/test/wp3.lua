-- Shared setup for the WP3 suites (03-search-n-N, 10-escape-search, 11-highlighting-search):
-- an independent match oracle, both of WP1's layouts, and a check that nothing covers the board.
local api = vim.api
local H = require("hcmux.sudoku.test.harness")
local S = {}

--- The cells of `board` (default: the README's classic fixture) holding `digit`, row-major.
function S.cells_of(digit, board)
  board = board or H.CLASSIC
  local out = {}
  for r = 1, 9 do
    for c = 1, 9 do
      if board[r][c] == digit then
        out[#out + 1] = { r = r, c = c }
      end
    end
  end
  return out
end

--- Every cell not in `cells`, row-major.
function S.others(cells)
  local seen, out = {}, {}
  for _, cell in ipairs(cells) do
    seen[(cell.r - 1) * 9 + cell.c] = true
  end
  for r = 1, 9 do
    for c = 1, 9 do
      if not seen[(r - 1) * 9 + c] then
        out[#out + 1] = { r = r, c = c }
      end
    end
  end
  return out
end

-- The README's own list, so the oracle itself is checked against the contract.
S.NINES = { { r = 2, c = 5 }, { r = 3, c = 2 }, { r = 8, c = 6 }, { r = 9, c = 9 } }
assert(vim.deep_equal(S.cells_of(9), S.NINES), "oracle: the classic 9s are R2C5 R3C2 R8C6 R9C9")

--- The footer ends with the accepted-search segment `text` (two spaces before it in
--- the full layout, one in the compact layout).
function S.footer_ends(text, what)
  local sep = H.kind() == "full" and "  " or " "
  local footer = H.footer()
  H.ok(footer:sub(-#(sep .. text)) == sep .. text, (what or "footer") .. (": %q ends with %q"):format(footer, text))
end

--- The footer carries no search segment at all.
function S.no_segment(what)
  H.ok(not H.footer():find("/", 1, true), (what or "footer") .. ": no search segment in " .. H.footer())
end

function S.cursor_is(r, c, what)
  H.eq(H.state().cursor, { r = r, c = c }, what or ("the cursor box is on R%dC%d"):format(r, c))
  H.ok(H.footer():find((" R%dC%d "):format(r, c), 1, true), ("the footer reads R%dC%d"):format(r, c))
  H.eq(H.char_spans("EnviSudokuCursor"), H.outline(r, c), ("the outline is drawn on R%dC%d"):format(r, c))
end

--- Exactly `cells` carry EnviSudokuMatch, in state() and in the drawn extmarks.
function S.matches_are(cells, what)
  what = what or "matches"
  H.eq(H.state().hl.match, cells, what .. ": state().hl.match")
  for _, cell in ipairs(cells) do
    H.ok(H.groups(cell.r, cell.c).EnviSudokuMatch, ("%s: R%dC%d is drawn EnviSudokuMatch"):format(what, cell.r, cell.c))
  end
  for _, cell in ipairs(S.others(cells)) do
    H.ok(
      not H.groups(cell.r, cell.c).EnviSudokuMatch,
      ("%s: R%dC%d is not drawn EnviSudokuMatch"):format(what, cell.r, cell.c)
    )
  end
end

--- Nothing covers the board: no command line or other window above it, every digit drawn.
function S.board_visible()
  local s = H.state()
  H.eq(vim.fn.mode(), "n", "no command line is open over the board")
  H.eq(api.nvim_get_current_win(), s.win, "the board keeps focus")
  H.ok(api.nvim_win_get_height(s.win) >= api.nvim_buf_line_count(s.buf), "the whole board fits its window")
  local board = H.rect(s.win)
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local cfg = api.nvim_win_get_config(w)
    if w ~= s.win and cfg.relative ~= "" and not cfg.hide then
      H.ok(
        (cfg.zindex or 50) < s.zindex or not H.overlap(H.rect(w), board),
        "no window covers the board (" .. vim.bo[api.nvim_win_get_buf(w)].filetype .. ")"
      )
    end
  end
  for r = 1, 9 do
    for c = 1, 9 do
      local d = s.board[r][c]
      H.eq(H.digit(r, c), d == 0 and " " or tostring(d), ("R%dC%d is drawn"):format(r, c))
    end
  end
end

local function at_size(cols, lines)
  vim.o.columns, vim.o.lines = cols, lines
  vim.wait(300, function()
    return false
  end)
end

S.LAYOUTS = { { "full", 80, 40 }, { "compact", 36, 21 } }

--- One scenario per layout, from the shared Background; the size is restored even on failure.
function S.each_layout(name, fn)
  for _, l in ipairs(S.LAYOUTS) do
    H.scenario(("%s [%s layout]"):format(name, l[1]), function()
      H.background()
      at_size(l[2], l[3])
      local ok, err = xpcall(function()
        H.eq(H.kind(), l[1], "setup: the " .. l[1] .. " layout")
        fn(l[1])
      end, debug.traceback)
      at_size(80, 40)
      H.ok(ok, err)
    end)
  end
end

--- Is (lhs, mode) handled by a real work package, not the core's "*" no-op or a test stand-in?
function S.is_real(lhs, mode)
  local spec = require("hcmux.sudoku.keys").handler(lhs, mode)
  return spec ~= nil and spec.mode ~= "*" and not spec.desc:find("test stand-in", 1, true)
end

return S
