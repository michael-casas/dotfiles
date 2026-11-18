-- B-R1-03: the trigger is authorised only on state validated at the last
-- boundary before osascript: after the probe, and again after a y/n pause.
local F = dofile("nvim/tools/t3-thread/test/support/t3update-fixture.lua")
local U = F.U
U.config.poll_ms = 30
U.config.start_timeout_ms = 250
U.config.timeout_ms = 1000

local working = { type = "snapshot", projects = {}, threads = { { id = "a", status = "working" } } }

local function fresh(feed)
  F.reset()
  F.server(true)
  F.set_runtime(1000, "1.0.0")
  F.feed.live, F.feed.snapshot = true, feed or { type = "snapshot", projects = {}, threads = {} }
  F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
end

local function refused(pattern)
  F.wait_notice(pattern)
  F.until_true(function()
    return U.current() == nil
  end, 1000, "the run must settle")
  vim.wait(100)
  assert(#F.of("osascript") == 0, "no trigger after a failed final check")
end

F.case("a marker appearing during the preflight probe refuses", function()
  fresh()
  F.reply.curl = function()
    F.set_marker(45)
    return { code = 0, stdout = "200" }
  end
  U.update()
  refused("update already in progress")
end)

F.case("a marker appearing while the prompt is open refuses", function()
  fresh(working)
  vim.fn.getcharstr = function()
    F.set_marker(45)
    return "y"
  end
  U.update()
  refused("update already in progress")
end)

F.case("a server going away while the prompt is open refuses", function()
  fresh(working)
  vim.fn.getcharstr = function()
    F.server(false)
    return "y"
  end
  U.update()
  refused("server unreachable")
end)

F.case("the runtime record vanishing while the prompt is open refuses", function()
  fresh(working)
  vim.fn.getcharstr = function()
    os.remove(F.runtime)
    return "y"
  end
  U.update()
  refused("cannot read the server's pid")
end)

F.case("the baseline pid is refreshed after the prompt", function()
  fresh(working)
  vim.fn.getcharstr = function()
    F.set_runtime(1500, "1.0.0") -- restarted while the user read the question
    return "y"
  end
  U.update()
  F.until_true(function()
    return #F.of("osascript") == 1
  end, 1000, "trigger")
  F.wait_notice("no update started")
  assert(not F.has("restarted") and not F.has("T3 updated"), "the refreshed pid is the baseline")
end)

F.case("cancel and the ordinary trigger are unchanged", function()
  fresh(working)
  vim.fn.getcharstr = function()
    return "n"
  end
  U.update()
  F.wait_notice("update cancelled")
  assert(#F.of("osascript") == 0)
  fresh()
  U.update()
  F.until_true(function()
    return #F.of("osascript") == 1
  end, 1000, "trigger")
  F.wait_notice("no update started")
end)

vim.fn.getcharstr = function()
  return "y"
end
F.done()
