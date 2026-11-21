local api, uv = vim.api, vim.uv
local sudoku = require("hcmux.sudoku")
local Game = require("hcmux.sudoku.game")
local puzzles = require("hcmux.sudoku.puzzles")
local render = require("hcmux.sudoku.render")

local VERSION = 1
local group = api.nvim_create_augroup("EnviSudokuPersistence", { clear = true })

local function write_snapshot(path, game)
  local data = vim.json.encode({
    version = VERSION,
    puzzle = game.puzzle,
    givens = game.givens,
    board = game.board,
    cursor = game.cursor,
    elapsed_ms = game.timer:elapsed(),
    solved = game.timer.status == "solved",
  })
  vim.fn.mkdir(vim.fs.dirname(path), "p", 448)
  local fd, tmp = uv.fs_mkstemp(path .. ".XXXXXX")
  if not fd then
    return nil, tmp
  end
  local written, err = uv.fs_write(fd, data, 0)
  local synced
  if written == #data then
    synced, err = uv.fs_fsync(fd)
  else
    err = err or "short write"
  end
  local closed, close_err = uv.fs_close(fd)
  local renamed
  if synced and closed then
    renamed, err = uv.fs_rename(tmp, path)
  end
  if not renamed then
    uv.fs_unlink(tmp)
    return nil, err or close_err
  end
  return true
end

local function integer(n, min, max)
  return type(n) == "number" and n >= min and n <= max and n % 1 == 0
end

local function decode_game(path)
  local saved = vim.json.decode(table.concat(vim.fn.readfile(path, "b"), "\n"))
  assert(type(saved) == "table" and saved.version == VERSION, "unsupported Sudoku save version")
  assert(type(saved.puzzle) == "string" and puzzles.board(saved.puzzle), "unknown saved puzzle")
  local game = Game.new(saved.puzzle)
  local cursor = saved.cursor
  assert(type(cursor) == "table" and integer(cursor.r, 1, 9) and integer(cursor.c, 1, 9), "invalid saved cursor")
  assert(integer(saved.elapsed_ms, 0, 2 ^ 53 - 1), "invalid saved time")
  assert(type(saved.solved) == "boolean", "invalid solved state")
  assert(vim.deep_equal(saved.givens, game.givens), "invalid saved givens")
  assert(vim.islist(saved.board) and #saved.board == 9, "invalid saved board")
  for r, row in ipairs(saved.board) do
    assert(vim.islist(row) and #row == 9, "invalid saved board row")
    for c, digit in ipairs(row) do
      assert(integer(digit, 0, 9) and (not game.givens[r][c] or digit == game.board[r][c]), "invalid saved digit")
    end
  end
  game.board = saved.board
  game.cursor = { r = cursor.r, c = cursor.c }
  game.timer = Game.timer(saved.elapsed_ms)
  if saved.solved then
    game.timer:stop()
  end
  return game
end

local function save(game, manual)
  local path = sudoku.save_path()
  local ok, written, err = pcall(write_snapshot, path, game)
  if not (ok and written) then
    vim.notify(("Sudoku could not save %s: %s"):format(path, ok and err or written), vim.log.levels.ERROR)
    return false
  end
  game.timer:pause()
  if manual then
    vim.notify("Sudoku saved", vim.log.levels.INFO)
  end
  return true
end

local function load()
  local path = sudoku.save_path()
  local _, err, code = uv.fs_stat(path)
  if code == "ENOENT" then
    return
  end
  if err then
    vim.notify(("Sudoku could not read %s: %s"):format(path, err), vim.log.levels.WARN)
    return
  end
  local ok, game = pcall(decode_game, path)
  if ok then
    sudoku.set_game(game)
  else
    vim.notify(("Sudoku could not read %s: %s"):format(path, game), vim.log.levels.WARN)
  end
end

sudoku.on("load", load)

sudoku.on("before_new", function(ctx)
  local path = sudoku.save_path()
  if ctx.confirmed or (not ctx.game and not uv.fs_stat(path)) then
    return
  end
  if vim.fn.confirm("Replace the current Sudoku game?", "&Yes\n&No", 2) == 1 then
    vim.schedule(function()
      if sudoku.game() == ctx.game and sudoku.save_path() == path then
        sudoku.open({ new = true, puzzle = ctx.puzzle, confirmed = true })
      end
    end)
  end
  return false
end)

sudoku.on("open", function()
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_create_user_command(buf, "EnviWrite", function(opts)
    if opts.args ~= "w" and opts.args ~= "wq" and opts.args ~= "x" then
      return vim.notify("Sudoku: expected w, wq, or x", vim.log.levels.ERROR)
    end
    if save(sudoku.game(), true) then
      if opts.args == "w" then
        sudoku.refresh()
      else
        sudoku.close()
      end
    end
  end, { bang = true, nargs = 1, desc = "Sudoku: save the game, then pause or close" })
end)

api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    local game = sudoku.game()
    if game then
      save(game)
    end
  end,
})

api.nvim_create_autocmd({ "WinLeave", "WinEnter" }, {
  group = group,
  callback = function(ev)
    if sudoku.focused() then
      local timer = sudoku.game().timer
      if ev.event == "WinLeave" then
        timer:pause()
      else
        timer:resume()
      end
      sudoku.refresh()
    end
  end,
})

vim.on_key(function(_, typed)
  if typed == "" or not sudoku.focused() or vim.fn.mode() ~= "n" then
    return
  end
  local game = sudoku.game()
  if game.timer.status == "paused" then
    -- Look up the installed mapping so key aliases and modifier spelling
    -- follow Neovim's parsing. The existing mapping redraws after dispatch.
    local map = vim.fn.maparg(vim.fn.keytrans(typed), "n", false, true)
    if map.buffer == 1 and vim.startswith(map.desc or "", "Sudoku: ") then
      game.timer:resume()
    end
  end
end, api.nvim_create_namespace("EnviSudokuPersistence"))

local cells = {}
for r = 1, 9 do
  for c = 1, 9 do
    cells[#cells + 1] = { r = r, c = c }
  end
end

-- Pause overrides transient digit styling while preserving the cell outline.
render.layer({
  name = "pause-dim",
  group = "EnviSudokuDim",
  priority = 160,
  cells = function(game)
    return game.timer.status == "paused" and cells or {}
  end,
})

-- WP4 owns conflict checks and refuses edits once the timer is solved.
-- Its module can be absent when WP5 is tested against the WP1 shell alone.
local function connect_editing()
  local editing = package.loaded["hcmux.sudoku.ext.editing"]
  if editing then
    editing.on_edit(function(game)
      if game.timer.status ~= "solved" and editing.solved(game.board) then
        game.timer:stop()
      end
    end)
    return true
  end
end

local connected
sudoku.on("open", function()
  if not connected then
    connected = connect_editing()
  end
end)
