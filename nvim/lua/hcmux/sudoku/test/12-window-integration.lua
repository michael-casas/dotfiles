-- features/12-window-integration.feature: z-order ×2, <C-h/j/k/l>, orphan focus,
-- close returns focus, recentre, mksession, keybinder discoverability, lualine (WP1).
-- ":Reload auto-saves" and ":qd and reattach" are @live and belong to WP5.
local H = require("hcmux.sudoku.test.harness")
local api = vim.api
H.boot()

local function others_floats(except)
  local out = {}
  for _, w in ipairs(api.nvim_list_wins()) do
    local cfg = api.nvim_win_get_config(w)
    if w ~= except and cfg.relative ~= "" then
      out[#out + 1] = { win = w, zindex = cfg.zindex or 50, snacks = vim.w[w].snacks_win ~= nil }
    end
  end
  return out
end

local function explorer_list()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(w)].filetype == "snacks_picker_list" then
      return w
    end
  end
end

-- The real lualine mode formatter from plugins/hcmux.lua.
local function lualine_mode(label)
  for _, spec in ipairs(require("plugins.hcmux")) do
    if spec[1] == "nvim-lualine/lualine.nvim" then
      local opts = { sections = { lualine_a = { "mode" } } }
      spec.opts(nil, opts)
      return opts.sections.lualine_a[1].fmt(label)
    end
  end
  error("plugins/hcmux.lua has no lualine spec")
end

-- A real Snacks picker (default layout, centred over the board), left in NORMAL.
local function open_picker()
  local picker = Snacks.picker({
    source = "sudoku_test",
    items = { { text = "alpha" }, { text = "beta" } },
    format = "text",
    layout = { preset = "default" },
  })
  H.ok(
    H.wait(function()
      return picker.list and picker.list.win and picker.list.win:valid()
    end, 2000),
    "the picker opens"
  )
  vim.cmd.stopinsert()
  H.drain()
  return picker
end

-- The board must be above every Snacks window it overlaps, and must overlap one.
local function above_snacks(label)
  local s = H.state()
  H.eq(s.zindex, api.nvim_win_get_config(s.win).zindex, label .. ": state().zindex is the window's")
  local board, overlapped = H.rect(s.win), 0
  for _, f in ipairs(others_floats(s.win)) do
    if f.snacks and H.overlap(board, H.rect(f.win)) then
      overlapped = overlapped + 1
      H.ok(
        s.zindex > f.zindex,
        ("%s: zindex %d is above Snacks window %d (%d)"):format(label, s.zindex, f.win, f.zindex)
      )
    end
  end
  H.ok(overlapped > 0, label .. ": the board overlaps a Snacks window")
  H.ok(s.zindex < 100, label .. ": below Neovim's reserved layers (popupmenu 100 and up)")
end

-- Stand-in for Snacks on VimResized: its layout updates at once and its explorer
-- picker rebuilds in a scheduled callback, each moving focus with noautocmd (seen
-- live in the Herdr app; the headless explorer keeps its layout, so it never does).
-- Installed before the board opens, so it runs first, as Snacks' handler does.
local function snacks_resize_standin()
  local group = api.nvim_create_augroup("sudoku_test_snacks_resize", { clear = true })
  local function steal()
    vim.cmd("noautocmd call nvim_set_current_win(" .. H.grid .. ")")
  end
  api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      steal()
      vim.schedule(steal)
    end,
  })
  return function()
    api.nvim_del_augroup_by_id(group)
  end
end

local function resize(cols, lines)
  vim.o.columns, vim.o.lines = cols, lines
  vim.wait(300, function()
    return false
  end)
end

H.scenario("the popover draws above the explorer and the terminal", function()
  H.layout()
  H.type(":EnviSudoku new classic<CR>")
  local s = H.state()
  local board = H.rect(s.win)
  local list = explorer_list()
  H.ok(list, "the explorer list is open")
  H.ok(H.overlap(board, H.rect(list)), "the board overlaps the explorer list area")
  H.ok(H.overlap(board, H.rect(H.term)), "the board overlaps the terminal split")
  H.ok(s.zindex >= 60, "zindex >= 60")
  H.eq(api.nvim_win_get_config(s.win).zindex, s.zindex, "state().zindex is the window's")
  local snacks = 0
  for _, f in ipairs(others_floats(s.win)) do
    snacks = snacks + (f.snacks and 1 or 0)
    H.ok(s.zindex > f.zindex, ("zindex %d is above window %d (zindex %d)"):format(s.zindex, f.win, f.zindex))
  end
  H.ok(snacks > 0, "Snacks layout windows were compared")
end)

H.scenario("opening from the explorer still draws above it and focuses the board", function()
  H.layout()
  local list = explorer_list()
  api.nvim_set_current_win(list)
  H.type(":EnviSudoku new classic<CR>")
  local s = H.state()
  H.ok(s.focused, "the popover is focused")
  for _, f in ipairs(others_floats(s.win)) do
    H.ok(s.zindex > f.zindex, "above every explorer window")
  end
  local r = H.rect(s.win)
  H.ok(r[1] >= 0 and r[2] >= 0 and r[3] <= vim.o.lines - vim.o.cmdheight and r[4] <= vim.o.columns, "fully visible")
  H.type(":q<CR>")
  H.eq(api.nvim_get_current_win(), list, ":q returns to the explorer list")
end)

-- 12 z-order / orphan focus, both opening orders (CRT S1-01).
H.scenario("a board opened after a Snacks picker draws above it", function()
  H.layout()
  local picker = open_picker()
  H.type(":EnviSudoku new classic<CR>")
  H.ok(H.state().focused, "the board is focused")
  above_snacks("board after picker")
  picker:close()
end)

H.scenario("a board refocused under a later Snacks picker comes back on top", function()
  H.background()
  local picker = open_picker()
  H.ok(not H.state().focused, "the picker took focus")
  H.type(":EnviSudoku<CR>")
  H.ok(H.state().focused, ":EnviSudoku focuses the board")
  above_snacks("board refocused over the picker")
  picker:close()
end)

for _, key in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
  H.scenario("<C-h/j/k/l> inside the popover never latch focus onto a hidden window: " .. key, function()
    H.background()
    H.place(5, 5)
    local win = H.state().win
    H.type(key)
    H.eq(api.nvim_get_current_win(), win, key .. ": the popover still has focus")
    H.eq(H.state().cursor, { r = 5, c = 5 }, key .. ": the cursor box has not moved")
  end)
end

H.scenario("if focus does leave by other means, the board is not left as an orphan", function()
  H.background()
  H.place(3, 7)
  api.nvim_set_current_win(H.term) -- a click in the terminal split
  H.drain()
  local s = H.state()
  H.ok(s.open and api.nvim_win_is_valid(s.win), "the popover stays visible")
  H.ok(not s.focused and api.nvim_get_current_win() == H.term, "focus is in the terminal")
  H.ok(lualine_mode("NORMAL") ~= "SUDOKU", "lualine does not read the game's mode")
  H.type(":EnviSudoku<CR>")
  s = H.state()
  H.ok(s.focused, ":EnviSudoku focuses the popover again")
  H.eq(s.cursor, { r = 3, c = 7 }, "on the same cell")
end)

-- Not a feature scenario: guards the orphan rule against buffer switches (LazyVim's H/L, ]b).
H.scenario("buffer switches never replace the board in its window", function()
  H.background()
  local s = H.state()
  for _, keys in ipairs({ "H", "L", "]b", "[b", ":bnext<CR>" }) do
    H.type(keys)
    H.eq(api.nvim_win_get_buf(s.win), s.buf, keys .. " leaves the board in its window")
    H.ok(H.state().open and H.state().focused, keys .. " keeps the board open and focused")
  end
end)

H.scenario("closing the popover returns focus to the invoking window, not a ghost buffer", function()
  H.layout()
  local wins, bufs = #api.nvim_list_wins(), #api.nvim_list_bufs()
  H.type(":EnviSudoku new classic<CR>")
  H.type(":q<CR>")
  H.eq(api.nvim_get_current_win(), H.grid, "the current window is grid.txt")
  H.eq(#api.nvim_list_wins(), wins, "no new window")
  H.eq(#api.nvim_list_bufs(), bufs, "no new buffer")
end)

-- The invoker is the window that created the board (CRT S1-05).
H.scenario("closing after a refocus from another window still returns to the invoking window", function()
  H.background() -- opened from grid.txt
  api.nvim_set_current_win(H.term) -- a click in the terminal
  H.drain()
  H.type(":EnviSudoku<CR>")
  H.ok(H.state().focused, "refocused from the terminal")
  H.type(":q<CR>")
  H.eq(api.nvim_get_current_win(), H.grid, "focus returns to grid.txt, which opened the board")
end)

H.scenario("a board newly opened from the terminal returns to the terminal", function()
  H.layout()
  api.nvim_set_current_win(H.term)
  H.drain()
  H.type(":EnviSudoku new classic<CR>")
  H.type(":q<CR>")
  H.eq(api.nvim_get_current_win(), H.term, "focus returns to the terminal")
end)

H.scenario("closing falls back natively when the invoking window is gone", function()
  H.layout()
  vim.cmd.split()
  local split = api.nvim_get_current_win()
  H.type(":EnviSudoku new classic<CR>")
  api.nvim_win_close(split, true)
  local wins = #api.nvim_list_wins()
  vim.v.errmsg = ""
  H.type(":q<CR>")
  H.ok(not H.state().open, "the board closes")
  H.ok(api.nvim_win_is_valid(api.nvim_get_current_win()), "focus is in a valid window")
  H.eq(#api.nvim_list_wins(), wins - 1, "only the board window went away")
  H.eq(vim.v.errmsg, "", "no error")
end)

H.scenario("the popover recentres on resize", function()
  local undo = snacks_resize_standin()
  H.background()
  local function check(label, kind)
    local s = H.state()
    local r = H.rect(s.win)
    local top, bottom = H.usable()
    local cols = vim.o.columns
    H.ok(
      r[1] >= top and r[2] >= 0 and r[3] <= bottom and r[4] <= cols,
      label .. ": the whole board is on screen, clear of the statusline and command line"
    )
    H.ok(math.abs(r[2] - (cols - r[4])) <= 1, label .. ": centred horizontally")
    H.ok(math.abs((r[1] - top) - (bottom - r[3])) <= 1, label .. ": centred vertically")
    H.ok(api.nvim_win_get_height(s.win) >= api.nvim_buf_line_count(s.buf), label .. ": every line is visible")
    for _, line in ipairs(H.lines()) do
      H.ok(vim.fn.strdisplaywidth(line) <= api.nvim_win_get_width(s.win), label .. ": no line is cut off")
    end
    H.eq(H.kind(), kind, label .. ": layout")
    for row = 1, 9 do
      for c = 1, 9 do
        local d = s.board[row][c]
        H.eq(H.digit(row, c), d == 0 and " " or tostring(d), ("%s: R%dC%d is readable"):format(label, row, c))
      end
    end
    H.eq(H.char_spans("EnviSudokuCursor"), H.outline(1, 1), label .. ": the R1C1 outline is whole")
    local footer = kind == "full" and "^NORMAL  R1C1  %d%d:%d%d RUNNING$" or "^NORMAL R1C1 %d%d:%d%d RUNNING$"
    H.ok(H.footer():find(footer), label .. ": the footer reads in full (" .. H.footer() .. ")")
    -- Live finding: Snacks rebuilds the explorer on VimResized and focuses it with
    -- noautocmd. The board keeps focus, and the hidden caret never leaks elsewhere.
    H.ok(s.focused, label .. ": the board keeps focus")
    H.ok(vim.o.guicursor:find("EnviSudokuCaret", 1, true), label .. ": the caret stays hidden on the board")
  end
  check("80x40", "full")
  resize(132, 30)
  check("132x30", "full")
  resize(36, 21) -- the minimum supported viewport (README): the compact layout
  check("36x21", "compact")
  resize(80, 40)
  check("back to 80x40", "full")
  undo()
end)

-- The resize recovery is scoped to Snacks' own transition (CRT S1-02).
H.scenario("a deliberate focus change after a resize is not undone", function()
  local undo = snacks_resize_standin()
  H.background()
  vim.o.columns = 100
  vim.wait(40, function()
    return false
  end) -- Snacks' moves and the immediate recovery have run; the delayed one is pending
  H.ok(H.state().focused, "the board recovered from Snacks' focus move")
  api.nvim_set_current_win(H.term) -- the user focuses the terminal 40 ms later
  local cursor = api.nvim_win_get_cursor(H.term)
  vim.wait(300, function()
    return false
  end)
  H.eq(api.nvim_get_current_win(), H.term, "the terminal keeps focus")
  H.eq(api.nvim_win_get_cursor(H.term), cursor, "and its cursor")
  H.ok(not vim.o.guicursor:find("EnviSudokuCaret", 1, true), "the caret is visible in the terminal")
  H.ok(H.state().open and not H.state().focused, "the board stays shown, unfocused")
  -- A pending recovery dies with the board.
  H.type(":EnviSudoku<CR>")
  vim.o.columns = 80
  H.type(":q<CR>")
  api.nvim_set_current_win(H.term)
  vim.wait(300, function()
    return false
  end)
  H.eq(api.nvim_get_current_win(), H.term, "no recovery runs after :q")
  H.ok(not vim.o.guicursor:find("EnviSudokuCaret", 1, true), "and the caret stays visible")
  undo()
end)

-- The board never scrolls (CRT S1-04).
H.scenario("the board viewport stays fixed under scroll keys and the wheel", function()
  H.background()
  local s = H.state()
  local function fixed(label)
    local v = api.nvim_win_call(s.win, vim.fn.winsaveview)
    H.eq({ v.topline, v.leftcol }, { 1, 0 }, label .. ": topline 1, leftcol 0")
    H.eq(#H.lines(), api.nvim_win_get_height(s.win), label .. ": every row is in view")
    H.ok(H.footer():find("^NORMAL  R1C1  "), label .. ": the footer is in view")
    H.eq(H.char_spans("EnviSudokuCursor"), H.outline(1, 1), label .. ": the R1C1 outline is whole")
  end
  local scrolls = { "<C-e>", "<C-d>", "<C-f>", "<C-y>", "<C-u>", "<C-b>", "zt", "zz", "zb", "z<CR>", "zl" }
  vim.list_extend(scrolls, { "<ScrollWheelDown>", "<ScrollWheelUp>", "<ScrollWheelRight>", "<PageDown>" })
  for _, key in ipairs(scrolls) do
    H.type(key)
    fixed(key)
    H.ok(H.state().focused, key .. ": the board keeps focus")
  end
  -- A scroll that never reaches the board's keys (the wheel over an unfocused float).
  api.nvim_win_call(s.win, function()
    vim.cmd("normal! 3\5")
  end)
  H.ok(
    H.wait(function()
      return api.nvim_win_call(s.win, vim.fn.winsaveview).topline == 1
    end),
    "a native scroll is undone"
  )
  fixed("after a native scroll")
  -- Ordinary scrolling elsewhere is untouched.
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(("line\n"):rep(100), "\n"))
  local other = api.nvim_open_win(buf, true, { split = "below", win = H.grid })
  H.type("<C-e>")
  H.eq(api.nvim_win_call(other, vim.fn.winsaveview).topline, 2, "<C-e> still scrolls an ordinary window")
  api.nvim_win_close(other, true)
end)

-- Not a feature scenario: a focus move that skips autocmds (as Snacks' layout does)
-- must not leave the caret hidden in another window.
H.scenario("the hidden caret follows focus even without autocmds", function()
  H.layout()
  local caret = vim.o.guicursor
  H.ok(not caret:find("EnviSudokuCaret", 1, true), "the caret is visible before the board opens")
  H.type(":EnviSudoku new classic<CR>")
  H.ok(vim.o.guicursor:find("EnviSudokuCaret", 1, true), "the caret is hidden on the board")
  vim.cmd("noautocmd wincmd p")
  H.ok(not H.state().focused, "focus left the board without autocmds")
  H.ok(
    vim.wait(1000, function()
      return vim.o.guicursor == caret
    end, 20),
    "the caret is restored"
  )
  H.type(":EnviSudoku<CR>")
  H.ok(vim.o.guicursor:find("EnviSudokuCaret", 1, true), "and hidden again on the board")
end)

H.scenario("the popover buffer is never written into the herdr-core session layout", function()
  H.background()
  local buf = H.state().buf
  H.eq(vim.bo[buf].buftype, "nofile", "nofile")
  H.eq(vim.bo[buf].bufhidden, "wipe", "bufhidden=wipe")
  H.eq(vim.bo[buf].buflisted, false, "unlisted")
  package.loaded["hcmux.core"] = package.loaded["hcmux.core"] or {}
  local layout = assert(require("hcmux.session").serialize(), "mksession runs")
  H.ok(layout:find("grid.txt", 1, true), "the saved layout has the editor")
  H.ok(not layout:lower():find("sudoku", 1, true), "the saved layout contains no Sudoku buffer")
end)

H.scenario("Sudoku keys are discoverable to keybinder", function()
  H.background()
  local buf, count = H.state().buf, 0
  for _, mode in ipairs({ "n", "v", "x", "s", "o", "i", "c", "t" }) do
    for _, map in ipairs(api.nvim_buf_get_keymap(buf, mode)) do
      count = count + 1
      H.ok(
        type(map.desc) == "string" and map.desc:find("^Sudoku: "),
        ("%s %s has a desc starting 'Sudoku: '"):format(mode, map.lhs)
      )
    end
  end
  H.ok(count > 0, "the popover has mappings")
  local rows = 0
  for _, line in ipairs(vim.fn.readfile(H.root .. "/nvim/ENVI.md")) do
    if line:match("^|") and line:find(":EnviSudoku", 1, true) and line:find("Sudoku", 1, true) then
      rows = rows + 1
    end
  end
  H.eq(rows, 1, "ENVI.md's key table has a Sudoku row")
end)

H.scenario("lualine shows a SUDOKU mode label while the popover is focused", function()
  H.background()
  H.eq(lualine_mode("NORMAL"), "SUDOKU", "lualine's mode section reads SUDOKU")
  H.type(":q<CR>")
  H.eq(lualine_mode("NORMAL"), "NORMAL", "lualine's mode section reads NORMAL")
end)

H.finish()
