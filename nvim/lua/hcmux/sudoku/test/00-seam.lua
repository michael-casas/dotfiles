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

H.finish()
