-- Polished AGENT chrome in real windows; no live process or thread.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 80, 24
package.loaded["hcmux.session"] = { root = "/project" }
package.loaded["hcmux.core"] = {}
package.loaded["hcmux.t3"] = { open = function() end }
vim.fn.jobstart = function()
  return 1
end
vim.fn.jobstop = function() end
local side = require("hcmux.t3side")
side.update({
  type = "snapshot",
  projects = { { id = "p", name = "Project", cwd = "/project" } },
  threads = {
    { id = "a", projectId = "p", title = "Alpha", status = "working" },
    { id = "b", projectId = "p", title = "Beta", status = "idle" },
  },
})
local agent = require("hcmux.agent")
local base = #vim.api.nvim_list_wins()
local function key(lhs, mode)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, mode or "n")) do
    if m.lhs:lower() == lhs:lower() then
      m.callback()
      return
    end
  end
  error("missing " .. lhs)
end
local function marks()
  return vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()["envi.agent"], 0, -1, { details = true })
end
local function has_virtual(text)
  for _, m in ipairs(marks()) do
    if vim.inspect(m[4]):find(text, 1, true) then
      return true
    end
  end
end
local function groups()
  local groups = {}
  for _, m in ipairs(marks()) do
    groups[m[4].hl_group or "none"] = true
  end
  return groups
end
agent.open("search")
local search_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(search_lines[1]:match("^╭.*╮$") and search_lines[3]:match("^╰.*╯$"), "rounded search box")
assert(vim.fn.strdisplaywidth(search_lines[1]) == vim.api.nvim_win_get_width(0), "search spans width")
assert(has_virtual("Search threads…"), "empty query has visible placeholder")
assert(has_virtual("2/2"), "right-aligned filtered/total count")
assert(groups().EnviAgentSearchFocus, "INSERT box has focused border")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "  Alpha" })
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
assert(has_virtual("1/2") and not has_virtual("Search threads…"), "count and placeholder follow live query")
key("<Esc>", "i")
assert(groups().EnviAgentSearchBorder and not groups().EnviAgentSearchFocus, "NORMAL border muted")
key("?")
assert(vim.bo.filetype == "envi-agent-help", "help opens dedicated float")
local helpwin = vim.api.nvim_get_current_win()
vim.o.columns, vim.o.lines = 200, 60
vim.api.nvim_exec_autocmds("VimResized", {})
assert(vim.api.nvim_win_is_valid(helpwin), "help survives resize")
vim.o.columns, vim.o.lines = 80, 24
vim.api.nvim_exec_autocmds("VimResized", {})
local help = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(help:find("Board", 1, true) and help:find("Search INSERT", 1, true) and help:find("Search NORMAL", 1, true))
for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
  assert(vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(0), "help fits")
end
for _, close in ipairs({ "?", "<Esc>", ":q" }) do
  if vim.bo.filetype ~= "envi-agent-help" then
    key("?")
  end
  if close == ":q" then
    vim.api.nvim_feedkeys(":q\r", "mtx", false)
  else
    key(close)
  end
  assert(agent.active and vim.bo.filetype == "envi-agent", "close only help")
end
vim.api.nvim_feedkeys(":q\r", "mtx", false)
assert(#vim.api.nvim_list_wins() == base)
agent.open()
assert(groups().EnviAgentAuto, "auto labels/borders dim")
vim.api.nvim_feedkeys("9", "n", false)
key("m")
assert(groups().EnviAgentMark, "fixed slot uses emphasised chip")
assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("⚑", 1, true), "marked slot pin glyph")
key("?")
agent.close()
assert(#vim.api.nvim_list_wins() == base, "closing parent cleans help")
for _, view in ipairs({ "board", "search" }) do
  agent.open(view)
  if view == "search" then
    key("<Esc>", "i")
  end
  vim.api.nvim_feedkeys(":q\r", "mtx", false)
  assert(not agent.active and #vim.api.nvim_list_wins() == base, "q leaves no orphan " .. view)
end
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then
    assert(not vim.bo[buf].filetype:match("^envi%-agent"), "no orphan AGENT or help buffers")
  end
end
print("AGENT search/help/card polish tests passed")
