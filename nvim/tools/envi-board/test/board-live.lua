-- Real private worker and native float; no servers or GUI automation.
local api = vim.api
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local path = dir .. "/demo.wb.md"
local fixture = vim.fn.readfile("nvim/tools/envi-board/test/fixtures/example.wb.md", "b")
vim.fn.writefile(fixture, path, "b")
local hub = vim.fn.json_decode(table.concat(vim.fn.readfile("theme/theme.json"), "\n"))
local theme_file = dir .. "/theme.json"
vim.fn.writefile({ vim.json.encode(hub) }, theme_file)
vim.env.ENVI_THEME_FILE = theme_file
local M = dofile("nvim/lua/hcmux/board.lua")
local before, draft = api.nvim_get_current_win(), api.nvim_get_current_buf()
api.nvim_buf_set_lines(draft, 0, -1, false, { "unsaved draft" })
local function wait(fn, reason)
  assert(vim.wait(6000, fn, 20), reason)
end
M.open(path)
local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
local function text()
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
wait(function()
  return text():find("approximate text", 1, true)
end, "real worker renders")
assert(text():find("flowchart LR", 1, true) and text():find("attached", 1, true))
assert(not vim.bo[buf].modified and not vim.bo[buf].modifiable)
M.open(path)
assert(api.nvim_get_current_win() == win)
hub.active = "gruvbox-dark"
vim.fn.writefile({ vim.json.encode(hub) }, theme_file .. ".tmp")
assert(vim.uv.fs_rename(theme_file .. ".tmp", theme_file))
wait(function()
  return api.nvim_get_hl(0, { name = "EnviBoardNormal", link = false }).bg == 0x282828
end, "live theme repaint")
vim.fn.writefile({ "broken" }, path)
wait(function()
  return api.nvim_win_get_config(win).title[1][1]:find("STALE", 1, true)
end, "invalid save visibly stale")
assert(text():find("File-first", 1, true), "last good retained")
vim.fn.writefile(fixture, path .. ".tmp", "b")
assert(vim.uv.fs_rename(path .. ".tmp", path))
wait(function()
  return not api.nvim_win_get_config(win).title[1][1]:find("STALE", 1, true)
end, "atomic recovery")
local edit
for _, map in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
  if map.lhs == "e" then
    edit = map.callback
  end
end
assert(edit)
edit()
assert(
  not M.active and vim.uv.fs_realpath(api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(path),
  "explicit board source opens"
)
assert(
  api.nvim_buf_get_lines(draft, 0, 1, false)[1] == "unsaved draft" and vim.bo[draft].modified,
  "invoker draft preserved"
)
api.nvim_set_current_win(before)
M.open(path)
M.close()
assert(not M.active and api.nvim_get_current_win() == before)
vim.wait(600, function()
  return false
end)
vim.fn.delete(dir, "rf")
print("board real worker/theme/watch/source checks passed")
