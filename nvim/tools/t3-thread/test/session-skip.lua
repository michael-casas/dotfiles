vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
package.loaded["hcmux.core"] = {}
local session = require("hcmux.session")
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
vim.cmd.edit(dir .. "/editor")
vim.cmd.vsplit(dir .. "/editor-two")
local editor = vim.api.nvim_get_current_tabpage()
local editor_wins = vim.api.nvim_tabpage_list_wins(editor)
vim.cmd.tabnew(dir .. "/skip")
vim.t.hcmux_session_skip = true
local skip = vim.api.nvim_get_current_tabpage()
vim.cmd.tabnew(dir .. "/third")
vim.api.nvim_set_current_tabpage(skip)
local before = vim.api.nvim_list_tabpages()
local text = assert(session.serialize())
assert(not text:find(dir .. "/skip", 1, true), "excluded buffer must not be serialized")
assert(vim.deep_equal(before, vim.api.nvim_list_tabpages()), "serialization cannot close/recreate tabs")
assert(vim.api.nvim_get_current_tabpage() == skip, "serialization preserves focus")
assert(vim.deep_equal(editor_wins, vim.api.nvim_tabpage_list_wins(editor)))
vim.cmd("tabonly!")
session.load_layout(text)
assert(#vim.api.nvim_list_tabpages() == 2, "only editor tabs restore")
assert(#vim.api.nvim_tabpage_list_wins(vim.api.nvim_list_tabpages()[1]) == 2, "editor splits restore")
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_get_name(b) == dir .. "/skip" then
    vim.api.nvim_buf_delete(b, { force = true })
  end
end
vim.cmd("tabonly!")
vim.t.hcmux_session_skip = true
local none, err = session.serialize()
assert(none == nil and err, "all-excluded layout must not replace saved editor state")
-- Leading and trailing skipped tabs, and a retained buffer shared with one.
vim.t.hcmux_session_skip = nil
vim.cmd("tabonly!")
vim.cmd.edit(dir .. "/retained")
local shared = vim.api.nvim_get_current_buf()
vim.cmd("0tabnew " .. dir .. "/leading-skip")
vim.t.hcmux_session_skip = true
vim.cmd("tablast")
vim.cmd("tabnew")
vim.api.nvim_set_current_buf(shared)
vim.t.hcmux_session_skip = true
local shared_text = assert(session.serialize())
assert(shared_text:find("retained", 1, true), "shared buffers survive")
assert(not shared_text:find("leading-skip", 1, true))
vim.cmd("tabonly!")
session.load_layout(shared_text)
assert(#vim.api.nvim_list_tabpages() == 1, "leading/trailing excluded tabs are absent")
assert(vim.api.nvim_buf_get_name(0):match("/retained$"))
vim.fn.delete(dir, "rf")
print("Session skip tests passed")
