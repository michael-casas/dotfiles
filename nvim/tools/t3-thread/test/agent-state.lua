-- Project/slot/guard/feed/persistence edges with real windows, no external jobs.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 120, 40
local session = { root = vim.fn.getcwd(), name = string.rep("long-session-", 3) }
package.loaded["hcmux.session"] = session
local docname, stored, conflict, opened
package.loaded["hcmux.core"] = {
  doc_get = function(name)
    docname = name
    return stored, 0
  end,
  doc_set = function(name, value)
    assert(name == docname and #name <= 32)
    if conflict then
      return nil, "conflict"
    end
    stored = vim.deepcopy(value)
    return 1
  end,
}
package.loaded["hcmux.t3"] = {
  open = function(id)
    opened = id
  end,
}
local jobs = 0
vim.fn.jobstart = function()
  jobs = jobs + 1
  return jobs
end
vim.fn.jobstop = function() end
local side = require("hcmux.t3side")
local fixture = {
  type = "snapshot",
  projects = {
    { id = "p", name = "Session project", cwd = session.root },
    { id = "other", name = "Other project", cwd = "/elsewhere" },
  },
  threads = {},
}
for i, status in ipairs({ "idle", "done", "attention", "error", "working", "idle", "idle", "idle", "idle", "idle" }) do
  fixture.threads[i] = {
    id = "t" .. i,
    projectId = "p",
    title = "Thread 世界 " .. i,
    status = status,
    updatedAt = ("2026-11-%02dT00:00:00Z"):format(i),
    unread = i == 2,
    pinned = i == 1,
    branch = vim.NIL,
    worktreePath = "/worktree/世界",
    harness = vim.NIL,
    model = vim.NIL,
  }
end
fixture.threads[11] = { id = "other", projectId = "other", title = "Wrong project", status = "working" }
side.update(fixture)
local notifications = 0
local unsubscribe = side.subscribe(function(value, err)
  notifications = notifications + 1
  assert(value.type == "snapshot")
  if notifications == 2 then
    assert(err == "offline")
  end
end)
side.update({ type = "error", message = "offline" })
unsubscribe()
side.update(fixture)
assert(notifications == 2, "unsubscribe and last valid snapshot on error")
local agent = require("hcmux.agent")
local function key(lhs, mode)
  -- `m` reads its slot digit with getcharstr(); queue the digit first.
  local digit = (mode or "n") == "n" and lhs:match("^m(%d)$")
  if digit then
    vim.api.nvim_feedkeys(digit, "n", false)
    lhs = "m"
  end
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, mode or "n")) do
    if m.lhs:lower() == lhs:lower() then
      m.callback()
      return
    end
  end
  error("missing " .. lhs)
end
local function text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end
local expected = { "t1", "t5", "t4", "t3", "t2", "t10", "t9", "t8", "t7" }
for i, id in ipairs(expected) do
  agent.open()
  assert(not text():find("Wrong project", 1, true))
  key(tostring(i))
  assert(opened == id and not agent.active, "auto slot " .. i .. " = " .. id)
end
assert(jobs == 1, "reopening AGENT shares a single feed job")
agent.open()
local groups = {}
for _, m in
  ipairs(vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()["envi.agent"], 0, -1, { details = true }))
do
  groups[m[4].hl_group] = true
end
for _, status in ipairs({ "working", "attention", "error", "done", "idle" }) do
  assert(groups["EnviT3Side_" .. status], status)
end
assert(groups.EnviT3SideUnread and groups.EnviT3SideSelected)
key("m9")
assert(docname:match("^envi%-agent%.") and #docname == 32 and stored.slots["9"] == "t1")
conflict = true
local notify, warning = vim.notify
vim.notify = function(message)
  warning = message
end
key("m8")
vim.notify = notify
assert(warning:find("not saved", 1, true) and stored.slots["9"] == "t1")
agent.close()
-- No session: memory-only marks survive reopening without any document calls.
session.name, stored, conflict = nil, nil, false
package.loaded["hcmux.core"].doc_get = function()
  error("no-session doc read")
end
agent.open()
key("m9")
agent.close()
agent.open()
key("9")
assert(opened == "t1")
agent.open("search")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "  世界" })
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
local before = text()
vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "corrupt card" })
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
assert(text() == before, "card edits are discarded; query is the only editable line")
vim.api.nvim_win_set_cursor(0, { 5, 0 })
vim.api.nvim_exec_autocmds("CursorMovedI", { buffer = buf })
assert(vim.api.nvim_win_get_cursor(0)[1] == 2, "insert cursor stays on query")
key("<Esc>", "i")
assert(not vim.bo[buf].modifiable)
vim.api.nvim_win_set_cursor(0, { 8, 0 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
assert(vim.api.nvim_win_get_cursor(0)[1] == 6, "normal cursor stays on selected card first line")
key("i")
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "  definitely no match" })
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
key("<Esc>", "i")
key("<CR>")
assert(agent.active and text():find("No matching threads", 1, true))
vim.api.nvim_win_close(0, true)
assert(not agent.active, "external float close clears active/subscription")
session.root = nil
agent.open()
assert(text():find("Thread 世界", 1, true), "without session root resolve git root of cwd")
agent.close()
session.root = "/not/a/project"
agent.open()
assert(not text():find("Thread 世界", 1, true))
agent.close()
print("AGENT ordering/project/persistence/guard edge tests passed")
