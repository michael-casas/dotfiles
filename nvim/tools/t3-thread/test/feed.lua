vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local jobs, stopped = {}, {}
local oldstart, oldstop = vim.fn.jobstart, vim.fn.jobstop
vim.fn.jobstart = function(argv, opts)
  assert(argv[1] == "node" and argv[2]:match("/threads.mjs$") and #argv == 2, "all projects, no filter")
  jobs[#jobs + 1] = opts
  return #jobs
end
vim.fn.jobstop = function(id)
  stopped[#stopped + 1] = id
end
local side = require("hcmux.t3side")
local buf = side.buffer()
vim.api.nvim_set_current_buf(buf)
side.start()
side.start()
assert(#jobs == 1, "single lazy feed")
local snapshot = {
  type = "snapshot",
  projects = { { id = "p", name = "Live", cwd = "/tmp" } },
  threads = { { id = "a", projectId = "p", title = "From live feed", status = "working" } },
}
local line = vim.json.encode(snapshot)
jobs[1].on_stdout(1, { line:sub(1, 20) })
jobs[1].on_stdout(1, { line:sub(21), "", "" })
assert(
  table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("From live feed", 1, true),
  "fragmented NDJSON parsed"
)
-- Full shell-sized snapshot fragmented mid-line and inside Unicode bytes.
local big = { type = "snapshot", projects = {}, threads = {} }
for i = 1, 15 do
  big.projects[i] = { id = "p" .. i, name = "Project " .. i, cwd = "/project" .. i }
end
for i = 1, 500 do
  big.threads[i] = {
    id = "large-" .. i,
    projectId = "p" .. ((i % 15) + 1),
    title = "Large 世界 thread " .. i,
    status = "idle",
    archived = false,
    parentId = vim.NIL,
  }
end
local large = vim.json.encode(big) .. "\n"
for i = 1, #large, 997 do
  jobs[1].on_stdout(1, vim.split(large:sub(i, i + 996), "\n", { plain = true }))
end
local rendered = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
local count = 0
for _ in rendered:gmatch("Large 世界 thread") do
  count = count + 1
end
assert(count == 500, "all 500 threads from 15 projects survive multi-chunk NDJSON, decode, update and render")
jobs[1].on_stdout(1, { "not JSON", "" })
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:find("T3 unavailable:", 1, true))
side.start(true)
assert(stopped[1] == 1 and #jobs == 2)
jobs[1].on_exit(1, 1)
assert(not vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:find("exited", 1, true), "stale exit ignored")
jobs[2].on_stdout(2, { line, "" })
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:find("Live", 1, true))
jobs[2].on_exit(2, 1)
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:find("T3 unavailable:", 1, true))
side.start()
vim.api.nvim_exec_autocmds("VimLeavePre", {})
assert(stopped[#stopped] == 3, "feed stopped on leave")
vim.fn.jobstart, vim.fn.jobstop = oldstart, oldstop
print("T3 feed lifecycle tests passed")
