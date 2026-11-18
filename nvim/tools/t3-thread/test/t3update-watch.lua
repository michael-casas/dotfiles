-- B-R1-01/02: the watch is bounded on every path (probes rate-limited, one
-- deadline, handles closed, late results ignored), and completion and stall
-- are decided on observations re-read at the probe-result boundary.
local F = dofile("nvim/tools/t3-thread/test/support/t3update-fixture.lua")
local U = F.U
U.config.poll_ms = 50
U.config.start_timeout_ms = 5000
U.config.timeout_ms = 300

local function start()
  F.reset()
  F.server(true)
  F.set_runtime(1000, "1.0.0")
  F.feed.live, F.feed.snapshot = true, { type = "snapshot", projects = {}, threads = {} }
  F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
  U.update()
  F.until_true(function()
    return U.current() and U.current().timer ~= nil
  end, 1000, "the watch must start")
  local run = U.current()
  return run, #F.of("curl")
end

-- Probes after the trigger, the watch's own.
local function watch_probes(before)
  return #F.of("curl") - before
end

local function bounded(run, before, what)
  F.until_true(function()
    return U.current() == nil
  end, 1500, what .. ": the deadline must end the run")
  assert(F.count("timed out") == 1, what .. ": one timeout notice")
  assert(run.timer:is_closing() and run.fs:is_closing(), what .. ": handles closed")
  -- 300 ms at a 50 ms cadence: at most one probe per slot, plus the first.
  local n = watch_probes(before)
  assert(n <= 8, what .. ": " .. n .. " probes in a 300 ms watch")
  local calls, notices = #F.calls, #F.notices
  vim.wait(250)
  assert(#F.calls == calls and #F.notices == notices, what .. ": nothing after the deadline")
end

F.case("B-R1-01 permanently unreachable new pid: capped probes, one timeout", function()
  local run, before = start()
  F.server(false)
  F.set_runtime(2000, "1.1.0")
  bounded(run, before, "unreachable new pid")
  assert(not F.has("T3 updated") and not F.has("restarted"))
end)

F.case("B-R1-01 expired marker over the reachable old pid: capped probes, one timeout", function()
  local run, before = start()
  F.set_marker(55)
  F.wait_notice("T3 is updating")
  F.set_marker(-1)
  bounded(run, before, "reachable old pid")
  assert(not F.has("stalled") and not F.has("T3 updated") and not F.has("restarted"))
end)

F.case("B-R1-01 fs-event bursts do not multiply probes", function()
  local run, before = start()
  F.server(false)
  F.set_runtime(2000, "1.1.0")
  for i = 1, 40 do
    F.write(F.home .. "/runtime/noise", tostring(i))
    vim.wait(5)
  end
  os.remove(F.home .. "/runtime/noise")
  bounded(run, before, "fs burst")
end)

F.case("B-R1-01 recovery before the deadline still succeeds", function()
  local run = start()
  F.server(false)
  F.set_runtime(2000, "1.1.0")
  vim.wait(120)
  assert(U.current() == run, "not yet")
  F.server(true)
  F.wait_notice("T3 updated: 1%.0%.0 → 1%.1%.0", 1000)
  assert(U.current() == nil and run.timer:is_closing() and run.fs:is_closing())
end)

F.case("B-R1-02 old pid and a new marker return during the probe: no success", function()
  U.config.timeout_ms = 2000
  local run = start()
  local once = true
  F.reply.curl = function()
    if once then
      once = false
      F.set_marker(45)
      F.set_runtime(1000, "1.0.0")
    end
    return { code = 0, stdout = "200" }
  end
  F.set_runtime(2000, "1.1.0")
  vim.wait(250)
  assert(not F.has("T3 updated") and not F.has("restarted"), "stale probe observation closed the watch")
  assert(U.current() == run, "the watch continues")
  os.remove(F.marker)
  F.set_runtime(2001, "1.1.0")
  F.wait_notice("T3 updated: 1%.0%.0 → 1%.1%.0", 1500)
  U.config.timeout_ms = 300
end)

F.case("B-R1-02 the pid changes again during the probe: success names the current server", function()
  U.config.timeout_ms = 2000
  start()
  local once = true
  F.reply.curl = function()
    if once then
      once = false
      F.set_runtime(3000, "1.2.0")
    end
    return { code = 0, stdout = "200" }
  end
  F.set_runtime(2000, "1.1.0")
  F.wait_notice("T3 updated", 1500)
  assert(F.has("T3 updated: 1.0.0 → 1.2.0"), F.last())
  assert(F.count("T3 updated") == 1)
  U.config.timeout_ms = 300
end)

F.case("B-R1-02 expired marker without a readable runtime is not a stall", function()
  U.config.timeout_ms = 2000
  local run = start()
  F.set_marker(55)
  F.wait_notice("T3 is updating")
  F.server(false)
  os.remove(F.runtime)
  F.set_marker(-1)
  vim.wait(250)
  assert(not F.has("stalled"), "unknown pid must not claim the old pid")
  assert(U.current() == run)
  F.set_runtime(1000, "1.0.0")
  F.wait_notice("update stalled: the marker expired, the server is still pid 1000 and unreachable", 1000)
  vim.wait(150)
  assert(F.count("update stalled") == 1, "stall reported once")
  F.set_runtime(2000, "1.1.0")
  F.server(true)
  F.wait_notice("T3 updated: 1%.0%.0 → 1%.1%.0", 1500)
  U.config.timeout_ms = 300
end)

F.case("B-R1-02 a stall needs the probe to fail on the re-read state", function()
  U.config.timeout_ms = 2000
  local run = start()
  F.set_marker(55)
  F.wait_notice("T3 is updating")
  local once = true
  F.reply.curl = function()
    if once then
      once = false
      F.set_marker(50) -- a new install began while the probe ran
    end
    return { code = 7, stdout = "000" }
  end
  F.set_marker(-1)
  vim.wait(250)
  assert(not F.has("stalled"), "a marker back in progress is not a stall")
  assert(U.current() == run)
  U.config.timeout_ms = 300
end)

F.done()
