vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns = 80
local event, events
vim.api.nvim_create_autocmd("User", {
  pattern = "EnviT3Sidebar",
  callback = function(ev)
    event = ev.data.buf
    events = (events or 0) + 1
  end,
})
local side = require("hcmux.t3side")
local buf = side.buffer()
assert(event == buf and events == 1)
assert(side.buffer() == buf and events == 1)
vim.cmd("vsplit")
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_win_set_width(0, 36)
local fixture =
  vim.json.decode(table.concat(vim.fn.readfile("nvim/tools/t3-thread/test/fixtures/threads-snapshot.json"), "\n"))
fixture.projects[1].name = "michael-casas/dotfiles"
fixture.projects[1].cwd = vim.fn.getcwd()
for i, t in ipairs(fixture.threads) do
  t.pinned = false
  t.settled = false
  t.unread = false
  t.branch = nil
  t.worktreePath = nil
end
local a = fixture.threads[1]
a.title = "Unread long 世界 title " .. string.rep("x", 80)
a.status = "working"
a.unread = true
a.branch = "feature/long-branch"
a.model = "gpt-test"
a.harness = "claudeAgent"
local b = fixture.threads[2]
b.title = "Pinned example"
b.pinned = true
b.status = "done"
b.model = "gpt-6.1-sol"
b.harness = "codex"
local c = fixture.threads[3]
c.title = "Hidden settled"
c.settled = true
fixture.threads[4].status = "attention"
fixture.threads[5].status = "error"
fixture.threads[6].status = "idle"
fixture.threads[6].branch = vim.NIL
fixture.threads[6].worktreePath = "/worktrees/null-branch-fallback"
fixture.threads[7].harness = "pi"
fixture.threads[7].title = "Other working"
fixture.threads[7].status = "working"
local function lines()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
local function find(text)
  for i, line in ipairs(lines()) do
    if line:find(text, 1, true) then
      return i, line
    end
  end
end
local function enter(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if m.lhs == "<CR>" then
      m.callback()
      return
    end
  end
  error("missing Enter")
end
side.update(fixture)
assert(lines()[1] == " PINNED", "pinned section first")
assert(find("Pinned example") and not find("Hidden settled"))
assert(lines()[#lines()]:match("Settled%s+1%s+›$"), "settled count at bottom")
local header, headertext = find("DS ")
assert(header and headertext:match("⌄$"), "two-letter badge and expanded chevron")
local row, text = find("Unread long")
assert(text:find("…", 1, true) and text:match("◌ Working$"), "truncated title and right status")
assert(vim.fn.strdisplaywidth(text) == 36, "status aligned at right edge")
assert(
  lines()[row + 1]:find("feature/long-branch", 1, true) and lines()[row + 1]:match("✳$"),
  "muted branch line with harness"
)
assert(not table.concat(lines(), "\n"):find("✎", 1, true), "no invented draft metadata")
assert(find("null-branch-fallback"), "JSON null branch falls back to worktree")
local ns = vim.api.nvim_get_namespaces()["envi.t3side"]
local function marks()
  local found = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    found[m[4].hl_group or m[4].line_hl_group or "none"] = true
  end
  return found
end
local hl = marks()
for _, name in ipairs({ "working", "attention", "done", "idle", "error" }) do
  assert(hl["EnviT3Side_" .. name], name)
end
assert(hl.EnviT3SideUnread and hl.EnviT3SideBranch and hl.EnviT3SideBadge1)
assert(hl.EnviT3SideClaude and hl.EnviT3SidePi and find(""), "feed harness takes priority over model")
assert(vim.api.nvim_get_hl(0, { name = "EnviT3SideUnread", link = false }).bold)
side.select(a.id)
assert(marks().EnviT3SideSelected)
vim.api.nvim_win_set_cursor(0, { find("feature/long-branch"), 0 })
fixture.projects[1].cwd = "/elsewhere"
fixture.projects[1].name = "zzz-dotfiles"
side.update(fixture)
assert(vim.api.nvim_get_current_line():find("feature/long-branch", 1, true), "cursor follows branch subrow")
-- Collapse header, keep selected and any currently working threads visible.
header = find("ZD ")
assert(header)
enter(header)
assert(select(2, find("ZD ")):match("● %d+ ›$"))
assert(find("Unread long"))
-- Settled disclosure does not attach a client; Enter on either thread line does.
enter(find("Settled"))
assert(find("Hidden settled") and lines()[#lines()]:match("Settled%s+1%s+⌄$"))
local opened = {}
package.loaded["hcmux.layout"] = {
  open_thread = function(id)
    opened[#opened + 1] = id
  end,
}
enter(find("feature/long-branch"))
assert(opened[1] == a.id)
side.update({ type = "error", message = "offline\nquiet" })
assert(lines()[1]:find("T3 unavailable: offline", 1, true))
side.update(fixture)
assert(not lines()[1]:find("unavailable", 1, true))
for _, line in ipairs(lines()) do
  assert(vim.fn.strdisplaywidth(line) <= 36, "all rows fit 36 columns")
end
-- Newest within a tier, active/unseen first, with narrow-window bounds.
side.update({
  type = "snapshot",
  projects = { { id = "p", name = "Order", cwd = vim.fn.getcwd() } },
  threads = {
    { id = "old", projectId = "p", title = "Old idle", status = "idle", updatedAt = "2026-01-01T00:00:00Z" },
    { id = "new", projectId = "p", title = "New idle", status = "idle", updatedAt = "2026-11-15T00:00:00Z" },
    { id = "active", projectId = "p", title = "Active first", status = "working", updatedAt = "2025-01-01T00:00:00Z" },
    {
      id = "unseen",
      projectId = "p",
      title = "Done unseen",
      status = "done",
      unread = true,
      updatedAt = "2024-01-01T00:00:00Z",
    },
  },
})
assert(
  find("Active first") < find("Done unseen")
    and find("Done unseen") < find("New idle")
    and find("New idle") < find("Old idle")
)
side.select("new")
enter(find("Order"))
assert(
  find("Active first") and find("New idle") and not find("Old idle"),
  "collapsed: active/selected retained; idle hidden"
)
enter(find("Order"))
vim.api.nvim_win_set_width(0, 20)
side.render()
for _, line in ipairs(lines()) do
  assert(vim.fn.strdisplaywidth(line) <= 20, "narrow sidebar fits")
end
-- Desktop listing applies uniformly, including selected/active, pins and settled.
vim.api.nvim_win_set_width(0, 36)
side.select("child")
side.update({
  type = "snapshot",
  projects = {
    { id = "visible", name = "Visible", cwd = vim.fn.getcwd() },
    {
      id = "children",
      name = "Children only",
      cwd = "/children",
    },
  },
  threads = {
    { id = "legacy", projectId = "visible", title = "Legacy row", status = "idle" },
    { id = "listed", projectId = "visible", title = "Listed row", status = "idle", listed = true },
    {
      id = "child",
      projectId = "children",
      title = "Hidden active child",
      status = "working",
      listed = false,
      relationship = "subagent",
    },
    {
      id = "pin-child",
      projectId = "children",
      title = "Hidden pinned child",
      status = "idle",
      listed = false,
      pinned = true,
    },
    {
      id = "settled-child",
      projectId = "children",
      title = "Hidden settled child",
      status = "idle",
      listed = false,
      settled = true,
    },
    {
      id = "settled-visible",
      projectId = "visible",
      title = "Listed settled",
      status = "idle",
      listed = true,
      settled = true,
    },
  },
})
assert(find("Legacy row") and find("Listed row"), "missing listed defaults true")
assert(
  not find("Hidden") and not find("Children only") and not find("PINNED"),
  "unlisted rows and empty groups are omitted"
)
assert(lines()[#lines()]:match("Settled%s+1%s+⌄$"), "settled count excludes unlisted rows")
assert(find("Listed settled"), "settled disclosure includes listed row")
print("T3 catalogue sidebar tests passed")
