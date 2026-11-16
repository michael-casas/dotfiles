-- Real child Neovim exit paths, isolated filesystem sink instead of hc.
-- SIGHUP and SIGTERM must flush a pending deletion through VimLeavePre.
local repo = vim.fn.getcwd()
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local child = dir .. "/child.lua"
vim.fn.writefile(
  vim.split(
    [[
vim.opt.rtp:prepend(assert(vim.env.SESSION_TEST_REPO) .. "/nvim")
local dir = assert(vim.env.SESSION_TEST_DIR)
package.loaded["hcmux.core"] = {
  available = function() return false end,
  doc_set = function(_, value, version)
    vim.fn.writefile({vim.json.encode(value)}, dir .. "/saved.json")
    return version + 1
  end,
}
package.loaded["hcmux.term"] = {config = {}}
local s = require("hcmux.session")
s.setup({debounce = 60000})
vim.cmd.edit(dir .. "/keep")
vim.cmd.badd(dir .. "/removed")
s.name, s.state, s.root = "exit-test", "attached", dir
s.save({sync = true})
vim.cmd("bdelete " .. vim.fn.bufnr(dir .. "/removed"))
vim.api.nvim_create_autocmd({"VimLeavePre", "VimLeave"}, {callback = function(e)
  vim.fn.writefile({e.event}, dir .. "/events", "a")
end})
vim.fn.writefile({"ready"}, dir .. "/ready")
]],
    "\n"
  ),
  child
)
local ok, err = pcall(function()
  for _, signal in ipairs({ "SIGHUP", "SIGTERM" }) do
    vim.fn.delete(dir .. "/ready")
    vim.fn.delete(dir .. "/events")
    local p = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-c", "luafile " .. child }, {
      env = { SESSION_TEST_REPO = repo, SESSION_TEST_DIR = dir },
    })
    if not vim.wait(5000, function()
      return vim.fn.filereadable(dir .. "/ready") == 1
    end, 10) then
      p:kill("SIGTERM")
      p:wait(5000)
      error("child failed to become ready")
    end
    assert((vim.uv or vim.loop).kill(p.pid, signal == "SIGHUP" and 1 or 15) == 0)
    local result = p:wait(10000)
    assert(result.code == 1, signal .. ": child must exit via Neovim's signal handler: " .. vim.inspect(result))
    local events = vim.fn.readfile(dir .. "/events")
    assert(vim.deep_equal(events, { "VimLeavePre", "VimLeave" }), signal .. ": exit hooks must fire")
    local saved = vim.json.decode(table.concat(vim.fn.readfile(dir .. "/saved.json"), "\n"))
    assert(saved.layout:find("/keep", 1, true), signal .. ": surviving file saved")
    assert(not saved.layout:find("/removed", 1, true), signal .. ": pending deletion flushed")
    assert(not saved.holder, signal .. ": session released")
    print("PASS " .. signal .. " pending autosave flushed; both exit hooks ran")
  end
end)
vim.fn.delete(dir, "rf")
assert(ok, err)
print("session-save-exit: 2 cases passed")
