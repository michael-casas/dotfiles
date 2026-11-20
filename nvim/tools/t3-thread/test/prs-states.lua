vim.env.ENVI_PR_NO_BROWSER = "1"
vim.env.ENVI_PR_DRY_RUN = "1"
-- Empty/error/default scopes, cached refresh, navigation, owned-buffer cleanup.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 100, 35
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
vim.env.XDG_CACHE_HOME = temp .. "/cache"
vim.env.PRS_LOG = temp .. "/calls"
local fake = vim.fn.getcwd() .. "/nvim/tools/t3-thread/test/fixtures/prs-tools.py"
for _, name in ipairs({ "gh", "git" }) do
  vim.fn.writefile(
    { "#!/bin/sh", "exec python3 " .. vim.fn.shellescape(fake) .. " " .. name .. ' "$@"' },
    temp .. "/" .. name
  )
  vim.fn.setfperm(temp .. "/" .. name, "rwx------")
end
vim.env.PATH = temp .. ":" .. vim.env.PATH
package.loaded["hcmux.session"] = { root = temp }
local projects = {}
package.loaded["hcmux.t3side"] = {
  snapshot = function()
    return { projects = projects }
  end,
  presentation = {
    clean = function(s)
      return tostring(s or ""):gsub("[%c]", " ")
    end,
    truncate = function(s, w)
      return vim.fn.strcharpart(s, 0, math.max(0, w))
    end,
    age = function()
      return "2h"
    end,
    highlights = function() end,
  },
}
local notices = {}
vim.notify = function(msg)
  notices[#notices + 1] = msg
end
local urls = {}
vim.ui.open = function(url)
  urls[#urls + 1] = url
end
local prs = require("hcmux.prs")
local function text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end
local function wait(fn)
  assert(vim.wait(6000, fn, 10), "condition")
end
local function key(lhs, mode)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, mode or "n")) do
    if m.lhs == lhs then
      m.callback()
      return
    end
  end
  error("missing mapping " .. lhs)
end
local baseline = #vim.api.nvim_list_wins()
local function clean()
  prs.close()
  assert(not prs.active and #vim.api.nvim_list_wins() == baseline, "no orphan windows")
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    assert(not vim.bo[b].filetype:match("^envi%-pr") and vim.bo[b].filetype ~= "markdown", "no orphan PR buffers")
  end
end
vim.env.PRS_EMPTY = "1"
prs.open({ repo = "acme/repo" })
wait(function()
  return text():find("▸ Involved %[3%]")
end)
key("<Tab>")
wait(function()
  return text():find("No open PRs in Repo", 1, true)
end)
key("?")
vim.api.nvim_feedkeys(":q\r", "mtx", false)
clean()
vim.env.PRS_EMPTY = nil
prs.open({ repo = "acme/repo", scope = "Repo" })
wait(function()
  return text():find("Fix build 2", 1, true)
end)
local board = vim.api.nvim_get_current_win()
local function selected()
  return vim.api.nvim_get_current_line()
end
key("j")
assert(selected():find("Zebra"))
key("k")
assert(selected():find("Fix build 2", 1, true))
key("G")
assert(selected():find("Fix build 1", 1, true))
key("gg")
assert(selected():find("Fix build 2", 1, true))
key("<C-D>")
key("<C-U>")
key("c")
key("<CR>")
assert(#urls == 0, "NO_BROWSER prevents ui.open")
assert(table.concat(notices, " "):find("actions/runs/1", 1, true), "suppressed URL notified")
vim.api.nvim_feedkeys(":q\r", "mtx", false)
key("K")
assert(vim.bo.filetype == "markdown" and text():find("APPROVED"))
vim.api.nvim_feedkeys(":q\r", "mtx", false)
key("K")
assert(vim.bo.filetype == "markdown", "K opens again after overlay q")
vim.api.nvim_feedkeys(":q\r", "mtx", false)
local picked
vim.ui.select = function(choices, _, cb)
  picked = choices
  cb("acme/repo")
end
key("R")
wait(function()
  return picked ~= nil
end)
assert(vim.tbl_contains(picked, "acme/repo"))
vim.env.PRS_DELAY = "0.2"
key("r")
assert(
  text():find("Fix build 2", 1, true) and vim.api.nvim_win_get_config(board).title[1][1]:find("refreshing"),
  "cached cards during refresh"
)
vim.env.PRS_DELAY = nil
wait(function()
  return not vim.api.nvim_win_get_config(board).title[1][1]:find("refreshing")
end)
local groups = {}
for _, m in
  ipairs(vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()["envi.prs"], 0, -1, { details = true }))
do
  groups[m[4].hl_group] = true
end
assert(groups.EnviPRPass and groups.EnviPRFail and groups.EnviPRPending and groups.EnviPRDraft)
vim.env.PRS_ERROR = "API rate limit exceeded"
key("r")
wait(function()
  return text():find("rate limited", 1, true)
end)
assert(text():find("Fix build 2", 1, true), "error keeps cached cards")
vim.env.PRS_ERROR = nil
-- hunk absence uses a read-only diff, not another terminal.
local executable = vim.fn.executable
vim.fn.executable = function(name)
  if name == "hunk" then
    return 0
  end
  return executable(name)
end
key("<CR>")
wait(function()
  return vim.bo.filetype == "diff"
end)
assert(not vim.bo.modifiable and text():find("diff %-%-git"))
vim.api.nvim_feedkeys(":q\r", "mtx", false)
vim.fn.executable = executable
key("/")
key("<Esc>", "i")
key("<Esc>")
assert(not prs.active)
clean()
for _, err in ipairs({ "not logged into any GitHub hosts", "error connecting to api.github.com" }) do
  vim.env.PRS_ERROR = err
  prs.open({ repo = "acme/repo", scope = "Repo" })
  wait(function()
    return text():find(err:find("logged") and "not logged in" or "offline", 1, true)
  end)
  clean()
end
vim.env.PRS_ERROR = nil
vim.fn.executable = function(name)
  if name == "gh" then
    return 0
  end
  return executable(name)
end
prs.open({ repo = "acme/repo", scope = "Repo" })
assert(text():find("gh not installed", 1, true))
clean()
vim.fn.executable = executable
print("prs-states: empty, errors, keys, highlights, fallback and cleanup passed")
