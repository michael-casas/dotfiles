-- Real private worker and native float; no servers or GUI automation.
local api = vim.api
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local path = dir .. "/demo.wb.md"
local fixture = vim.fn.readfile("nvim/tools/envi-board/test/fixtures/example.wb.md", "b")
fixture = vim.split(
  table
    .concat(fixture, "\n")
    :gsub('"author": "reviewer%-demo"', '"author": "reviewer\\ndemo"')
    :gsub('"label": "Existing clipboard option; evidence pin, not board implementation"', '"label": "Evidence\\nlabel"'),
  "\n",
  { plain = true }
)
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
M.open(dir .. "/nosuch/../demo.wb.md")
local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
local errors = {}
local previous_error_handler = vim._on_error
vim._on_error = function(message)
  errors[#errors + 1] = tostring(message)
end
local function text()
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
wait(function()
  return text():find("approximate text", 1, true)
end, "real worker renders")
assert(text():find("flowchart LR", 1, true) and text():find("attached", 1, true))
assert(text():find("reviewer\ndemo:", 1, true), "multiline author paints as separate rows")
assert(text():find("Evidence\nlabel", 1, true), "multiline source label paints as separate rows")
assert(#errors == 0, table.concat(errors, "\n"))
assert(not vim.bo[buf].modified and not vim.bo[buf].modifiable)
M.open(dir .. "/nosuch/../demo.wb.md")
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
local columns = vim.o.columns
vim.o.columns = math.max(40, columns - 10)
api.nvim_exec_autocmds("VimResized", {})
assert(api.nvim_win_get_config(win).title[1][1]:find("STALE", 1, true), "resize preserves STALE title")
vim.wait(150, function()
  return false
end)
assert(api.nvim_win_get_config(win).title[1][1]:find("STALE", 1, true), "STALE title does not depend on worker repaint")
vim.o.columns = columns
api.nvim_exec_autocmds("VimResized", {})

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
assert(#errors == 0, table.concat(errors, "\n"))
vim._on_error = previous_error_handler
print("board real worker/theme/watch/source checks passed")
