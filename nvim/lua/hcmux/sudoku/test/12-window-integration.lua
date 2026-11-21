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

H.scenario("closing the popover returns focus to the invoking window, not a ghost buffer", function()
  H.layout()
  local wins, bufs = #api.nvim_list_wins(), #api.nvim_list_bufs()
  H.type(":EnviSudoku new classic<CR>")
  H.type(":q<CR>")
  H.eq(api.nvim_get_current_win(), H.grid, "the current window is grid.txt")
  H.eq(#api.nvim_list_wins(), wins, "no new window")
  H.eq(#api.nvim_list_bufs(), bufs, "no new buffer")
end)

H.scenario("the popover recentres on resize", function()
  H.background()
  local function check(label)
    local s = H.state()
    local r = H.rect(s.win)
    local rows, cols = vim.o.lines - vim.o.cmdheight, vim.o.columns
    H.ok(math.abs(r[2] - (cols - r[4])) <= 1, label .. ": centred horizontally")
    H.ok(math.abs(r[1] - (rows - r[3])) <= 1, label .. ": centred vertically")
    H.ok(api.nvim_win_get_height(s.win) >= api.nvim_buf_line_count(s.buf), label .. ": every line is visible")
    for _, line in ipairs(H.lines()) do
      H.ok(vim.fn.strdisplaywidth(line) <= api.nvim_win_get_width(s.win), label .. ": no line is cut off")
    end
    H.ok(H.footer():find("RUNNING", 1, true), label .. ": the footer is visible")
  end
  check("80x40")
  vim.o.columns, vim.o.lines = 132, 30
  H.drain()
  check("132x30")
  vim.o.columns, vim.o.lines = 80, 40
  H.drain()
  check("back to 80x40")
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
