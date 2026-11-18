-- B-R1-04: running-thread counts come only from a valid frame of the current
-- sidebar feed job. The real t3side is used; jobstart is stubbed, so no
-- feed process ever starts.
local F = dofile("nvim/tools/t3-thread/test/support/t3update-fixture.lua")
local U = F.U
U.config.poll_ms = 30
U.config.start_timeout_ms = 150
U.config.timeout_ms = 1000

package.loaded["hcmux.t3side"] = nil
local jobs, next_id = {}, 4241
vim.fn.jobstart = function(argv, opts)
  next_id = next_id + 1
  jobs[next_id] = { argv = argv, opts = opts }
  return next_id
end
vim.fn.jobstop = function() end
local side = require("hcmux.t3side")

local function frame(id, value)
  jobs[id].opts.on_stdout(id, { vim.json.encode(value), "" })
end
local function snap(...)
  local threads = {}
  for i, status in ipairs({ ... }) do
    threads[i] = { id = "t" .. i, projectId = "p", title = "t" .. i, status = status }
  end
  return { type = "snapshot", projects = { { id = "p", title = "p" } }, threads = threads }
end

local asked, prompt = 0, nil
vim.fn.getcharstr = function()
  asked = asked + 1
  return "n"
end
local echo = vim.api.nvim_echo
vim.api.nvim_echo = function(chunks, ...)
  if chunks[1] and chunks[1][1]:find("y/n", 1, true) then
    prompt = chunks[1][1]
  end
  return echo(chunks, ...)
end

-- Runs :T3Update to its first decision: the question (answered n) or the trigger.
local function decide()
  F.reset()
  F.server(true)
  F.set_runtime(1000, "1.0.0")
  F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
  asked, prompt = 0, nil
  U.update()
  F.until_true(function()
    return F.has("update cancelled") or #F.of("osascript") > 0
  end, 1000, "update decision")
  F.stop(U)
end
local UNKNOWN = "running threads unknown (sidebar feed not running)"

F.case("the real sidebar seeded before its first frame is unknown", function()
  side.buffer()
  local seeded = side.snapshot()
  assert(seeded.type == "snapshot" and #seeded.threads > 0, "the render seed is still shown")
  decide()
  assert(asked == 1 and prompt and prompt:find(UNKNOWN, 1, true), tostring(prompt))
  assert(side.feed_state().live == false, "a render seed is not a live feed")
end)

F.case("a started feed with no frame yet is unknown", function()
  side.start()
  assert(side.feed_state().live == false)
  decide()
  assert(prompt and prompt:find(UNKNOWN, 1, true), tostring(prompt))
end)

F.case("a valid zero-work frame from the current job: no question", function()
  frame(next_id, snap("idle", "done"))
  local state = side.feed_state()
  assert(state.live == true and #state.snapshot.threads == 2)
  decide()
  assert(asked == 0, "no running threads, no question")
  assert(#F.of("osascript") == 1)
end)

F.case("a working frame from the current job counts it", function()
  frame(next_id, snap("working", "idle"))
  decide()
  assert(asked == 1 and prompt and prompt:find("1 running thread(s) will be interrupted", 1, true), tostring(prompt))
end)

F.case("an invalid frame makes the count unknown", function()
  jobs[next_id].opts.on_stdout(next_id, { "{not json", "" })
  assert(side.feed_state().live == false)
  frame(next_id, snap("idle"))
  assert(side.feed_state().live == true, "a later valid frame is live again")
end)

F.case("a failed feed is unknown", function()
  jobs[next_id].opts.on_exit(next_id, 1)
  assert(side.feed_state().live == false)
  decide()
  assert(prompt and prompt:find(UNKNOWN, 1, true), tostring(prompt))
end)

F.case("a replaced feed is unknown until the new job's frame; old frames are ignored", function()
  side.start()
  local old = next_id
  frame(old, snap("idle"))
  side.start(true)
  assert(next_id ~= old)
  assert(side.feed_state().live == false, "restart: unknown")
  frame(old, snap("idle")) -- the replaced job's late output
  assert(side.feed_state().live == false, "old job frames never count")
  frame(next_id, snap("working", "working"))
  assert(side.feed_state().live == true)
  decide()
  assert(prompt and prompt:find("2 running thread(s)", 1, true), tostring(prompt))
end)

F.case("a snapshot set by another caller is not the feed's", function()
  frame(next_id, snap("idle"))
  side.update(snap("idle"))
  assert(side.feed_state().live == false, "only the feed job's own frame is live")
end)

vim.api.nvim_echo = echo
F.done()
