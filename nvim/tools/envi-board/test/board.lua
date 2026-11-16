-- Native float/stdio harness: fake owned jobs only, no hc/T3/network.
local api = vim.api
local jobs, stopped, sent, next_job = {}, {}, {}, 5000
local real = {
  jobstart = vim.fn.jobstart,
  chansend = vim.fn.chansend,
  chanclose = vim.fn.chanclose,
  jobwait = vim.fn.jobwait,
  jobstop = vim.fn.jobstop,
}
vim.fn.jobstart = function(argv, opts)
  assert(argv[1] == "node" and argv[3] == "worker", "direct non-PTY board worker")
  assert(not opts.pty and not table.concat(argv, " "):find("hc attach", 1, true))
  next_job = next_job + 1
  jobs[next_job] = opts
  return next_job
end
vim.fn.chansend = function(job, data)
  sent[#sent + 1] = { job = job, value = vim.json.decode(data) }
  return #data
end
vim.fn.chanclose = function(job, stream)
  assert(jobs[job] and stream == "stdin")
  stopped[job] = true
end
vim.fn.jobwait = function(list)
  return { stopped[list[1]] and 0 or -1 }
end
vim.fn.jobstop = function(job)
  assert(jobs[job])
  stopped[job] = true
end
local M = dofile("nvim/lua/hcmux/board.lua")
local base = api.nvim_get_current_win()
local global_before = vim.inspect(api.nvim_get_keymap("n"))
local path = vim.fn.fnamemodify("nvim/tools/envi-board/test/fixtures/example.wb.md", ":p")
local created = 0
api.nvim_create_autocmd("User", {
  pattern = "EnviBoard",
  callback = function(ev)
    assert(ev.data.buf)
    created = created + 1
  end,
})
M.open(path)
local win, buf, job = api.nvim_get_current_win(), api.nvim_get_current_buf(), next_job
assert(M.active and created == 1)
M.open(path)
assert(next_job == job and api.nvim_get_current_win() == win and created == 1, "same path focuses/reuses")
api.nvim_set_current_win(base)
M.open(path)
assert(api.nvim_get_current_win() == win, "focus leaves same worker")
local open = sent[#sent].value
assert(open.op == "open" and open.path == path and next(open.bindings) == nil, "no inferred root binding")
local function feed(text)
  jobs[job].on_stdout(job, vim.split(text, "\n", { plain = true }))
  vim.wait(20, function()
    return false
  end)
end
local function message(value)
  return vim.json.encode(vim.tbl_extend("force", { v = 1 }, value)) .. "\n"
end
local function snapshot(seq, rows, opts)
  opts = opts or {}
  local data = vim.json.encode({
    path = path,
    generation = seq,
    hash = "revision",
    stale = false,
    rows = rows,
    mapping = { { id = "title", kind = "heading", line = 1 }, { id = "pin", kind = "wb-source", line = 5 } },
    theme = { id = "demo", tokens = { fg = "#ffffff", bg = "#111111", border = "#444444", title = "#aaaaaa" } },
  })
  return message({ type = "begin", seq = seq, generation = seq, count = 1, bytes = #data })
    .. message({ type = "chunk", seq = seq, index = 0, data = data })
    .. (opts.incomplete and "" or message({ type = "end", seq = seq, generation = seq }))
end
local wire = snapshot(1, { "# Demo 🙂", "source pin" })
local cut = assert(wire:find("🙂", 1, true))
feed(wire:sub(1, cut))
assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "Loading local board…", "partial UTF8 frame not published")
feed(wire:sub(cut + 1))
assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "# Demo 🙂")
assert(not vim.bo[buf].modifiable and not vim.bo[buf].modified and vim.bo[buf].buftype == "nofile")
assert(api.nvim_get_hl(0, { name = "EnviBoardNormal", link = false }).bg == 0x111111)
feed(snapshot(2, { "incomplete" }, { incomplete = true }))
assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "# Demo 🙂", "only complete revisions publish")
feed(
  message({ type = "chunk", seq = 2, index = 99, data = "bad" }) .. message({ type = "end", seq = 2, generation = 2 })
)
feed("not json\n" .. string.rep("x", 256 * 1024 + 1) .. "\n")
feed(snapshot(1, { "late" }))
assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "# Demo 🙂", "late/malformed/oversized ignored")
local maps = {}
for _, map in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
  maps[map.lhs] = map.callback
end
api.nvim_win_set_cursor(win, { 2, 0 })
assert(maps["<CR>"])
maps["<CR>"]()
local req = sent[#sent].value
assert(req.op == "source" and req.block == "pin" and req.expectedHash == "revision")
feed(message({
  type = "source",
  id = req.id,
  hash = "revision",
  block = "pin",
  value = { state = "available", notice = "Immutable", lines = { "pinned bytes" } },
}))
local child = api.nvim_get_current_win()
assert(child ~= win and M.active)
local child_buf = api.nvim_get_current_buf()
assert(not vim.bo[child_buf].modifiable)
for _, map in ipairs(api.nvim_buf_get_keymap(child_buf, "n")) do
  if map.lhs == "q" then
    map.callback()
  end
end
assert(not api.nvim_win_is_valid(child) and api.nvim_get_current_win() == win and M.active)
vim.o.columns = 100
api.nvim_exec_autocmds("VimResized", {})
assert(api.nvim_win_get_config(win).width <= 100)
api.nvim_exec_autocmds("ColorScheme", {})
assert(api.nvim_get_hl(0, { name = "EnviBoardNormal", link = false }).bg == 0x111111)
assert(vim.inspect(api.nvim_get_keymap("n")) == global_before, "no global mappings")
M.close()
M.close()
assert(not M.active and stopped[job] and not api.nvim_win_is_valid(win) and api.nvim_get_current_win() == base)
jobs[job].on_stdout(job, { snapshot(9, { "after close" }) })
vim.wait(20, function()
  return false
end)
M.toggle()
assert(M.active and next_job == job + 1)
local new_win = api.nvim_get_current_win()
api.nvim_win_close(new_win, true)
assert(not M.active and stopped[next_job], "external close idempotently closes exact owned job")
M.open(path)
local new_buf = api.nvim_get_current_buf()
api.nvim_buf_delete(new_buf, { force = true })
assert(not M.active, "wipe closes")
-- Defense in depth: even a malformed worker row cannot inject a physical LF.
M.open(path)
win, buf, job = api.nvim_get_current_win(), api.nvim_get_current_buf(), next_job
feed(snapshot(1, { "malformed\nrow", "source pin" }))
assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "malformed<U+000A>row")
M.close()

-- A terminal invoker is never replaced by board-source editing.
local terminal = api.nvim_create_buf(false, true)
api.nvim_set_current_buf(terminal)
api.nvim_open_term(terminal, {})
assert(vim.bo[terminal].buftype == "terminal" and not vim.bo[terminal].modified)
local terminal_win = api.nvim_get_current_win()
M.open(path)
local edit
for _, map in ipairs(api.nvim_buf_get_keymap(api.nvim_get_current_buf(), "n")) do
  if map.lhs == "e" then
    edit = map.callback
  end
end
assert(edit)
edit()
assert(
  api.nvim_win_is_valid(terminal_win) and api.nvim_win_get_buf(terminal_win) == terminal,
  "terminal invoker retains its terminal"
)
assert(api.nvim_get_current_win() ~= terminal_win, "board source must open in a split beside a terminal")
api.nvim_win_close(api.nvim_get_current_win(), true)
api.nvim_buf_delete(terminal, { force = true })
for k, v in pairs(real) do
  vim.fn[k] = v
end
print("board native checks passed")
