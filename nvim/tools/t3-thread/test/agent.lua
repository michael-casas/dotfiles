-- Real AGENT windows and keys; mocked core/T3/feed process, never touches live threads.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 120, 40
vim.g.mapleader = " "
local docs, writes, opens, jobs, refreshes = {}, 0, {}, 0, 0
package.loaded["hcmux.session"] = { name = "agent-test", root = "/projects/project-3" }
package.loaded["hcmux.core"] = {
  doc_get = function(name)
    local d = docs[name]
    return d and vim.deepcopy(d.value), d and d.version or 0
  end,
  doc_set = function(name, value, version)
    assert(#name <= 32)
    assert(version == (docs[name] and docs[name].version or 0))
    writes = writes + 1
    docs[name] = { value = vim.deepcopy(value), version = version + 1 }
    return version + 1
  end,
}
package.loaded["lualine"] = {
  refresh = function()
    refreshes = refreshes + 1
  end,
}
package.loaded["hcmux.t3"] = {
  open = function(id, opts)
    opens[#opens + 1] = { id = id, opts = opts }
  end,
}
vim.fn.jobstart = function()
  jobs = jobs + 1
  return jobs
end
vim.fn.jobstop = function() end
local side = require("hcmux.t3side")
local fixture =
  vim.json.decode(table.concat(vim.fn.readfile("nvim/tools/t3-thread/test/fixtures/threads-snapshot.json"), "\n"))
for _, t in ipairs(fixture.threads) do
  t.pinned = false
end
fixture.threads[4].pinned = true
fixture.threads[5].archived = true
fixture.threads[6].title = "Zebra newest"
fixture.threads[6].updatedAt = "2026-11-16T00:00:00Z"
fixture.threads[8].title = "Zebra oldest"
fixture.threads[8].updatedAt = "2025-01-01T00:00:00Z"
local settled = vim.deepcopy(fixture.threads[6])
settled.id, settled.title, settled.settled = "settled", "Zebra settled", true
fixture.threads[#fixture.threads + 1] = settled
side.update(fixture)
local agent = require("hcmux.agent")
assert(type(agent.open) == "function", "AGENT replaces the global scaffold with a float API")
local function key(lhs, mode)
  -- `m` reads its slot digit with getcharstr(); queue the digit first.
  local digit = (mode or "n") == "n" and lhs:match("^m(%d)$")
  if digit then
    vim.api.nvim_feedkeys(digit, "n", false)
    lhs = "m"
  end
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, mode or "n")) do
    if m.lhs:lower() == lhs:lower() then
      assert(m.callback, "expected Lua mapping " .. lhs)
      m.callback()
      return
    end
  end
  error("missing mapping " .. lhs)
end
local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end
local function text()
  return table.concat(lines(), "\n")
end
local function cursor()
  return vim.api.nvim_win_get_cursor(0)
end
local function groups()
  local found = {}
  for _, mark in
    ipairs(vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()["envi.agent"], 0, -1, { details = true }))
  do
    found[mark[4].hl_group or "none"] = true
  end
  return found
end
agent.open("board")
assert(lines()[#lines()]:find(":q/Esc", 1, true), "board footer advertises :q")
assert(agent.active and jobs == 1 and text():find("Zebra newest", 1, true))
assert(not text():find("Example thread 7", 1, true) and not text():find("Example thread 5", 1, true))
assert(not text():find("Zebra settled", 1, true))
assert(text():find("empty", 1, true) and text():find("auto", 1, true))
for i = 1, 9 do
  assert(text():find(" " .. i .. " ", 1, true), "slot " .. i)
end
local first = cursor()
key("l")
assert(cursor()[2] > first[2])
key("h")
assert(vim.deep_equal(cursor(), first))
key("j")
assert(cursor()[1] > first[1])
key("k")
assert(vim.deep_equal(cursor(), first))
key("m9")
assert(writes == 1 and docs["envi-agent.agent-test"].value.slots["9"] == "thread-4")
key("j")
key("j")
key("l")
key("l")
key("m8")
key("k")
key("k")
key("h")
key("h")
assert(docs["envi-agent.agent-test"].value.slots["9"] == nil, "mark moves")
key("R")
assert(jobs == 2)
for _, size in ipairs({ { 80, 24 }, { 200, 60 } }) do
  vim.o.columns, vim.o.lines = unpack(size)
  vim.api.nvim_exec_autocmds("VimResized", {})
  local width = vim.api.nvim_win_get_width(0)
  local boxes = 0
  for _, line in ipairs(lines()) do
    assert(vim.fn.strdisplaywidth(line) <= width, "line fits resized float")
    for _ in line:gmatch("┌") do
      boxes = boxes + 1
    end
  end
  assert(boxes == 9, "nine intact cards")
end
agent.close()
assert(not agent.active)
package.loaded["hcmux.agent"] = nil
agent = require("hcmux.agent")
agent.open()
assert(text():find("mark", 1, true), "persistence round trip")
key("9")
assert(agent.active, "empty slot does not close")
key("8")
assert(not agent.active and opens[#opens].id == "thread-4")
agent.open()
key("<CR>")
assert(opens[#opens].id == "thread-3" and not agent.active)
agent.open()
key("i")
assert(not agent.active and opens[#opens].id == "new" and opens[#opens].opts.mode == "command")
assert(opens[#opens].opts.cwd == "/projects/project-3")
agent.open()
key("/")
local buf = vim.api.nvim_get_current_buf()
assert(vim.bo[buf].modifiable, "search insertion enabled")
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "  Zebra" })
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
assert(text():find("Zebra newest", 1, true) < text():find("Zebra oldest", 1, true))
assert(text():find("Zebra oldest", 1, true) < text():find("Zebra settled", 1, true))
assert(not text():find("Example thread", 1, true) and groups().Search, "live fuzzy filter and highlights")
key("<C-n>", "i")
key("<Esc>", "i")
assert(agent.active and not vim.bo[buf].modifiable)
key("m2")
assert(docs["envi-agent.agent-test"].value.slots["2"] == "thread-8")
key("x")
assert(docs["envi-agent.agent-test"].value.slots["2"] == nil)
key("j")
key("k")
key("gg")
key("G")
key("<Esc>")
assert(agent.active)
key("<Tab>")
assert(text():find("auto", 1, true))
key("<Tab>")
assert(lines()[2] == "  Zebra" and not vim.bo[buf].modifiable)
key("gg")
key("<CR>")
assert(opens[#opens].id == "thread-6" and not agent.active)
agent.open()
fixture.threads[4].archived = true
side.update(fixture)
assert(text():find("gone", 1, true), "missing marked thread keeps slot")
key("j")
key("j")
key("l")
key("x")
assert(docs["envi-agent.agent-test"].value.slots["8"] == nil)
assert(groups().EnviT3Side_done)
agent.close()
agent.toggle()
assert(agent.active)
agent.toggle()
assert(not agent.active)
agent.open("search")
key("<CR>", "i")
assert(not agent.active)
agent.open("search")
key("<Esc>", "i")
assert(lines()[#lines()]:find("· :q", 1, true), "search footer advertises :q")
vim.api.nvim_feedkeys(":q\r", "mtx", false)
assert(not agent.active)
assert(refreshes >= 10)
local sb = side.buffer()
side.render()
assert(vim.api.nvim_buf_is_valid(sb), "sidebar still renders")
print("AGENT board/search/marks/key/feed tests passed")
