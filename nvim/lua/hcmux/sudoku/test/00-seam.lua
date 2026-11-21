-- The extension seam (README: Seams): an ext/*.lua module loads with the core and
-- its key, layer and state field take effect without editing a core file.
local H = require("hcmux.sudoku.test.harness")
local api = vim.api
local dir = assert(vim.uv.fs_mkdtemp(vim.fn.tempname() .. "-XXXXXX"))
vim.fn.mkdir(dir .. "/lua/hcmux/sudoku/ext", "p")
vim.fn.writefile({
  'local sudoku, keys, render = require("hcmux.sudoku"), require("hcmux.sudoku.keys"), require("hcmux.sudoku.render")',
  "_G.seam_loaded = (_G.seam_loaded or 0) + 1",
  'keys.register({ lhs = "l", mode = "normal", desc = "Sudoku: right", fn = function(g, ctx)',
  "  g.cursor.c = math.min(9, g.cursor.c + ctx.count1) end })",
  'render.layer({ name = "seam-dim", group = "EnviSudokuDim", priority = 110, cells = function(g)',
  "  return { { r = 9, c = 9 } } end })",
  'render.footer_segment(function() return "SEAM" end)',
  "sudoku.extend_state(function(s) s.undo = 7 end)",
  "sudoku.on('before_new', function(ctx) _G.seam_new = ctx if _G.seam_veto then return false end end)",
}, dir .. "/lua/hcmux/sudoku/ext/zz_seam.lua")
vim.opt.rtp:append(dir)
H.boot()

H.scenario("an ext module extends keys, layers, footer and state() without core edits", function()
  H.eq(_G.seam_loaded, 1, "the extension loaded once with the core")
  H.background()
  H.type("3l")
  local s = H.state()
  H.eq(s.cursor, { r = 1, c = 4 }, "its key ran with the count")
  H.eq(s.hl.dim, { { r = 9, c = 9 } }, "its layer is in state().hl")
  H.ok(H.groups(9, 9).EnviSudokuDim, "its layer is drawn")
  H.eq(H.footer(), "NORMAL  R1C4  00:00 RUNNING  SEAM", "its footer segment is appended")
  H.eq(s.undo, 7, "its state field is filled")
  H.ok(vim.fn.maparg("l", "n", false, true).desc == "Sudoku: right", "its map carries its desc")
  api.nvim_set_current_win(H.grid)
end)

-- The pre-new veto (CRT S1-06; WP5 builds Q19's confirmation on it).
H.scenario("a before_new hook can decline :EnviSudoku new before anything changes", function()
  H.background()
  H.place(4, 5)
  H.advance(2000)
  local game, win = H.sudoku().game(), H.state().win
  _G.seam_veto, _G.seam_new = true, nil
  -- Exercise the second leg of an async confirmation. Other listeners must
  -- still be able to veto after the confirmation listener allows it.
  H.sudoku().open({ new = true, puzzle = "classic", confirmed = true })
  H.ok(_G.seam_new, "the hook ran")
  H.eq(_G.seam_new.puzzle, "classic", "it was told the requested puzzle")
  H.ok(_G.seam_new.game == game, "and given the current game")
  local s = H.state()
  H.ok(H.sudoku().game() == game, "declined: the game is unchanged")
  H.eq(s.cursor, { r = 4, c = 5 }, "the cursor is unchanged")
  H.eq(s.timer, { status = "running", elapsed_ms = 2000 }, "the timer is unchanged")
  H.ok(s.win == win and s.focused, "the window and focus are unchanged")
  _G.seam_veto = false
  H.sudoku().open({ new = true, puzzle = "classic", confirmed = true })
  s = H.state()
  H.ok(H.sudoku().game() ~= game, "allowed: a new game")
  H.eq(s.cursor, { r = 1, c = 1 }, "at R1C1")
  H.eq(s.timer, { status = "running", elapsed_ms = 0 }, "with a fresh timer")
end)

H.scenario("a before_new hook can decline when no game is in memory", function()
  H.layout()
  _G.seam_veto, _G.seam_new = true, nil
  H.type(":EnviSudoku new classic<CR>")
  H.ok(_G.seam_new and _G.seam_new.game == nil, "the hook ran with no current game")
  H.ok(H.sudoku().game() == nil, "no game was created")
  H.ok(not H.state().open, "no board opened")
  H.eq(api.nvim_get_current_win(), H.grid, "focus stays in grid.txt")
  _G.seam_veto = false
end)

H.finish()
