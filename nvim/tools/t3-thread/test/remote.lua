-- Mock-only: never starts hc, SSH, Mosh, or a real terminal.
local opened, calls, selected, notices = {}, {}, nil, {}
package.loaded["hcmux.term"] = {
  open = function(argv, opts)
    opened[#opened + 1] = { argv = argv, opts = opts }
    return 17, "local-client"
  end,
}
vim.notify = function(msg)
  notices[#notices + 1] = msg
end
local response = { code = 0, stdout = "fixture\nother-fixture\n", stderr = "" }
vim.system = function(argv, opts, cb)
  calls[#calls + 1] = argv
  assert(opts.text == true)
  cb(response)
end
vim.ui.select = function(items, _, cb)
  selected = items
  cb(items[1])
end
local M = dofile("nvim/lua/hcmux/remote.lua")
M.setup()
assert(vim.fn.exists(":EnviRemote") == 2)
vim.cmd.EnviRemote()
vim.wait(100, function()
  return #opened == 1
end)
assert(#calls == 1 and vim.deep_equal(calls[1], { "envi-remote", "hosts" }))
assert(vim.deep_equal(selected, { "fixture", "other-fixture" }))
assert(vim.deep_equal(opened[1].argv, { "envi-remote", "fixture" }))
assert(opened[1].opts.where == "vsplit")
assert(opened[1].opts.cwd == nil, "local cwd must not become a remote command/path")
assert(opened[1].opts.session == nil, "ordinary hcmux restore owns this local client")
assert(opened[1].opts.labels["envi.remote.profile"] == "minimal")
assert(opened[1].opts.labels["envi.remote.transport"] == nil, "do not guess a live transport")
for _, alias in ipairs({ "-option", "x;y", "white space", "bad/../id", "x\n", "", string.rep("a", 65) }) do
  local before = #opened
  M.open(alias)
  assert(#opened == before, "invalid identifier launched")
end
M.open("valid-fixture")
assert(#opened == 2 and opened[2].argv[2] == "valid-fixture")
response = { code = 0, stdout = "fixture\nbad;entry\n", stderr = "" }
M.pick()
vim.wait(100)
assert(#opened == 2, "malformed host list must reject all entries")
response = { code = 20, stdout = "", stderr = "private details must not be displayed" }
M.pick()
vim.wait(100)
assert(#opened == 2)
assert(not table.concat(notices, "\n"):find("private details", 1, true))
M.setup() -- idempotent registration; no mappings
print("EnviRemote mocked argv tests passed")
