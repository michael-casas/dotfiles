local H = require("hcmux.sudoku.test.harness")
local api = vim.api
local notices = {}
local count = 0

H.boot()
vim.notify = function(msg, level)
  notices[#notices + 1] = { msg, level }
end

local function session()
  count = count + 1
  vim.g.hcmux_session = "wp5-test-" .. count
  notices = {}
  return H.sudoku().save_path()
end

local function background()
  local path = session()
  H.background()
  return path
end

local function read_save()
  return vim.json.decode(table.concat(vim.fn.readfile(H.state().save_path), "\n"))
end

local function child(action)
  local result = vim
    .system({
      vim.v.progpath,
      "--headless",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "-n",
      "-l",
      H.root .. "/nvim/lua/hcmux/sudoku/test/wp5-process.lua",
      H.root,
      vim.g.hcmux_session,
      action,
    }, { text = true, env = { HCMUX_NO_SESSION = "1" } })
    :wait()
  H.eq(result.code, 0, result.stdout .. result.stderr)
end

H.scenario(":w writes the save file and pauses", function()
  local path = background()
  H.eq(path, vim.fn.stdpath("state") .. "/envi-sudoku/" .. vim.g.hcmux_session .. ".json")
  H.enter(1, 3, 4)
  H.place(1, 3)
  H.advance(7000)
  H.type(":w<CR>")
  local save = read_save()
  H.eq(save.version, 1)
  H.eq(save.puzzle, "classic")
  H.eq(save.givens, H.state().givens)
  H.eq(save.board, H.state().board)
  H.eq(save.cursor, { r = 1, c = 3 })
  H.eq(save.elapsed_ms, 7000)
  H.eq(H.footer(), "NORMAL  R1C3  00:07 PAUSED")
  H.ok(notices[#notices] and notices[#notices][1]:find("Sudoku saved", 1, true), "success notice")
end)

H.scenario(":wq saves, pauses and closes", function()
  background()
  H.enter(1, 3, 4)
  H.type(":wq<CR>")
  H.eq(read_save().board[1][3], 4)
  H.ok(not H.state().open)
  H.eq(api.nvim_get_current_win(), H.grid)
  H.eq(H.state().timer.status, "paused")
end)

H.scenario("resume from the save in a fresh nvim", function()
  background()
  H.enter(1, 3, 4)
  H.place(1, 3)
  H.advance(7000)
  H.type(":wq<CR>")
  child("resume")
end)

H.scenario("a failed write keeps the board, focus and timer", function()
  local path = background()
  local dir = vim.fs.dirname(path)
  vim.fn.mkdir(dir, "p")
  assert(vim.uv.fs_mkdir(path, 448)) -- a directory at the slot forces an atomic rename to fail
  H.enter(1, 3, 4)
  H.advance(2000)
  for _, cmd in ipairs({ ":w<CR>", ":wq<CR>", ":x<CR>" }) do
    local before = H.state()
    H.type(cmd)
    H.eq(H.state(), before)
    H.eq(notices[#notices][2], vim.log.levels.ERROR)
    H.ok(notices[#notices][1]:find(path, 1, true), "the error names the save path")
  end
  H.advance(1000)
  H.eq(H.state().timer, { status = "running", elapsed_ms = 3000 })
  H.eq(vim.fn.glob(path .. ".*", false, true), {}, "no temp files left behind")
end)

H.scenario(":w routing is scoped to the Sudoku buffer", function()
  local path = background()
  H.type(":q<CR>")
  H.eq(vim.fn.filereadable(path), 0, ":q leaves the slot untouched")
  api.nvim_buf_set_lines(0, 0, -1, false, { "native file contents" })
  H.type(":w<CR>")
  H.eq(vim.fn.readfile(H.scratch .. "/grid.txt"), { "native file contents" })
  H.eq(vim.fn.filereadable(path), 0)
end)

H.scenario("one save slot per envi session; :w overwrites it", function()
  local path = background()
  H.enter(1, 3, 4)
  H.type(":w<CR>")
  H.eq(read_save().board[1][3], 4)
  H.enter(1, 4, 2)
  H.type(":w<CR>")
  H.eq(read_save().board[1][3], 4)
  H.eq(read_save().board[1][4], 2)
  H.eq(vim.fn.glob(path .. "*", false, true), { path })
  local next_path = session()
  H.ok(next_path ~= path and vim.fn.filereadable(next_path) == 0, "other sessions have their own slot")
end)

H.scenario(":EnviSudoku new over an unsaved or saved game asks first", function()
  background()
  H.enter(1, 3, 4)
  local function answer(choice, before)
    local original = vim.fn.confirm
    local prompted
    -- Headless Neovim selects the default without waiting for keyboard input.
    vim.fn.confirm = function(prompt, choices, default)
      prompted = { prompt, choices, default, H.state() }
      return choice
    end
    local ok, err = pcall(H.type, ":EnviSudoku new classic<CR>")
    vim.fn.confirm = original
    assert(ok, err)
    H.eq(prompted, { "Replace the current Sudoku game?", "&Yes\n&No", 2, before })
  end
  for _, saved in ipairs({ false, true }) do
    if saved then
      H.type(":wq<CR>")
      H.sudoku()._reset()
    end
    local before = H.state()
    answer(2, before)
    H.eq(H.state(), before, "declining changes nothing")
  end
  answer(1, H.state())
  H.eq(H.state().board, H.CLASSIC, "yes replaces the game")
  H.eq(H.state().timer, { status = "running", elapsed_ms = 0 })
end)

H.scenario('the board buffer never blocks :qa, :qd or hot reload as "unsaved"', function()
  for _, action in ipairs({ "qa", "qd" }) do
    local path = session()
    child(action)
    local save = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    H.eq(save.board[1][3], 4)
    H.eq(save.elapsed_ms, 9000)
  end
end)

H.scenario("standalone :x saves and closes, canceled and non-standalone writes stay native", function()
  local path = background()
  H.type(":w<Esc>")
  H.type(":w | let g:sudoku_after_write = 1<CR>")
  H.type(":w " .. H.scratch .. "/other.txt<CR>")
  H.eq(vim.fn.filereadable(path), 0)
  H.eq(H.state().timer.status, "running")
  H.type(":x<CR>")
  H.eq(vim.fn.filereadable(path), 1)
  H.ok(not H.state().open)
end)

H.finish()
