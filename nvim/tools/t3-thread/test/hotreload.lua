-- Headless check for hcmux.hotreload against a throwaway git repo.
--   nvim --headless -u NONE '+luafile nvim/tools/t3-thread/test/hotreload.lua' +qa
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.rtp:prepend(vim.fn.fnamemodify(here, ":h:h:h"))

local repo = vim.fn.tempname()
local cfg = repo .. "/nvim"
vim.fn.mkdir(cfg .. "/lua", "p")
local function sh(cmd)
  local out = vim.fn.system({ "sh", "-c", cmd })
  assert(vim.v.shell_error == 0, cmd .. ": " .. out)
end
local function commit(file, text)
  vim.fn.writefile({ text }, repo .. "/" .. file)
  sh(("cd %s && git add -A && git -c user.email=t@t -c user.name=t commit -qm %q"):format(repo, file))
end
sh("cd " .. repo .. " && git init -q")
commit("nvim/lua/a.lua", "return 1")

local restarts, reloadable = 0, true
package.loaded["hcmux.session"] = {
  restart = function()
    restarts = restarts + 1
  end,
  reloadable = function()
    return reloadable
  end,
}
vim.env.ENVI_HOT_RELOAD_ROOT = cfg
local hot = require("hcmux.hotreload")
hot.setup({ idle_ms = 50, debounce_ms = 20, poll_ms = 20 })
assert(
  vim.wait(3000, function()
    return hot.state.watching ~= nil
  end),
  "watcher started"
)
assert(hot.state.watching:match("logs/HEAD$"), "watches the reflog: " .. hot.state.watching)

-- Docs only: no reload, HEAD advances.
commit("nvim/README.md", "docs")
vim.wait(1500, function()
  return false
end)
assert(restarts == 0, "markdown-only commit must not reload")

-- Files outside the config dir don't count either.
commit("other.txt", "x")
vim.wait(800, function()
  return false
end)
assert(restarts == 0, "commit outside the config dir must not reload")

-- An unsaved buffer holds the reload until it's saved.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "draft" })
commit("nvim/lua/a.lua", "return 2")
assert(
  vim.wait(3000, function()
    return hot.state.pending ~= nil
  end),
  "config commit queues a reload"
)
vim.wait(400, function()
  return false
end)
assert(restarts == 0, "unsaved buffer blocks reload")
vim.bo.modified = false
assert(
  vim.wait(3000, function()
    return restarts == 1
  end),
  "reloads once safe"
)
assert(hot.state.pending == nil, "pending cleared")

-- Off switch.
vim.cmd("EnviHotReload off")
commit("nvim/lua/b.lua", "return 3")
vim.wait(800, function()
  return false
end)
assert(restarts == 1, "off: no reload")
vim.cmd("EnviHotReload on")
assert(
  vim.wait(3000, function()
    return restarts == 2
  end),
  "on again: catches up with the missed commit"
)

-- Not started by envi: notice only.
reloadable = false
commit("nvim/lua/c.lua", "return 4")
vim.wait(800, function()
  return false
end)
assert(restarts == 2, "no launcher: never restarts")

-- A reload leaves a marker naming the commit for the next nvim; remove ours.
assert(vim.fn.filereadable(hot.marker()) == 1, "reload marker written")
os.remove(hot.marker())
hot.stop()
vim.fn.delete(repo, "rf")
print("hot reload tests passed")
