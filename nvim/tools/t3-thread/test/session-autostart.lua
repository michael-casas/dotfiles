-- Plain nvim without herdr-core stays silent; suppressed folders get no automatic session.
--   nvim/tools/t3-thread/test/run-lua.sh session-autostart
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local available = false
package.loaded["hcmux.core"] = {
  available = function()
    return available
  end,
}
local session = require("hcmux.session")
local notices, attached = {}, {}
vim.notify = function(msg, level)
  notices[#notices + 1] = { msg = msg, level = level }
end
session.default_name = function()
  return "project"
end
local roots = {}
session.attach = function(name, o)
  attached[#attached + 1] = name
  roots[#roots + 1] = o and o.root
end
-- autostart only runs with a UI; pretend there is one.
local list_uis = vim.api.nvim_list_uis
vim.api.nvim_list_uis = function()
  return { {} }
end
vim.env.HCMUX_SESSION = nil

-- No hc: nothing attaches, nothing is reported.
session.autostart()
assert(#attached == 0, "no hc: no attach")
assert(#notices == 0, "no hc: no notification, got " .. vim.inspect(notices))

-- With hc: a project folder attaches; home, / and /tmp don't.
available = true
local project = vim.fn.tempname()
vim.fn.mkdir(project .. "/.git", "p")
local home = vim.fn.expand("~")
for _, case in ipairs({
  { dir = project, attach = true },
  { dir = home, attach = false },
  { dir = "/", attach = false },
  { dir = "/tmp", attach = false },
}) do
  attached = {}
  vim.fn.argv = function()
    return { case.dir }
  end
  vim.fn.isdirectory = function()
    return 1
  end
  session.autostart()
  assert((#attached == 1) == case.attach, ("%s: attach=%s, got %d"):format(case.dir, case.attach, #attached))
end
-- `nvim <dir>` from an unrelated cwd: the new session's root is that dir's project, not the cwd.
roots, attached = {}, {}
local sub = project .. "/sub"
vim.fn.mkdir(sub, "p")
vim.cmd.cd(vim.fn.fnameescape(home))
vim.fn.argv = function()
  return { sub }
end
session.autostart()
assert(
  roots[1] == session.root_of(sub) and roots[1] == vim.fn.fnamemodify(project, ":p"):gsub("/$", ""),
  "root " .. tostring(roots[1])
)
-- An explicit session name (envi, ENVI_SESSION) is never suppressed.
attached = {}
vim.env.HCMUX_SESSION = "explicit"
session.autostart()
assert(attached[1] == "explicit", "explicit session attaches")

vim.api.nvim_list_uis = list_uis
vim.fn.delete(project, "rf")
print("session autostart tests passed")
