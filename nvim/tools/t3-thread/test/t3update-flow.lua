-- B2/B3 :T3Update: preflight, confirm, trigger, watch, outcome, permissions.
-- osascript and curl are stubbed; the desktop and the real ~/.t3 are never touched.
local F = dofile("nvim/tools/t3-thread/test/support/t3update-fixture.lua")
local U = require("hcmux.t3update")
U.config.poll_ms = 30
U.config.start_timeout_ms = 400
U.config.timeout_ms = 1500

local asked, answer
vim.fn.getcharstr = function()
  asked = asked + 1
  return answer
end
local real_echo = vim.api.nvim_echo
local prompts = {}
local function question()
  for i = #prompts, 1, -1 do
    if prompts[i]:find("y/n", 1, true) then
      return prompts[i]
    end
  end
  return ""
end
vim.api.nvim_echo = function(chunks, history, opts)
  local text = table.concat(vim.tbl_map(function(c)
    return c[1]
  end, chunks))
  prompts[#prompts + 1] = text
  return real_echo(chunks, history, opts)
end

local function fresh(opts)
  F.reset()
  opts = opts or {}
  asked, answer, prompts = 0, opts.answer or "y", {}
  F.server(opts.up ~= false)
  if opts.runtime ~= false then
    F.set_runtime(1000, "1.0.0")
  end
  F.feed.snapshot = opts.feed
    or { type = "snapshot", projects = {}, threads = { { id = "a", status = "idle" }, { id = "b", status = "done" } } }
  -- A typed snapshot stands for a valid frame of the current feed job.
  F.feed.live = F.feed.snapshot.type == "snapshot"
  F.reply.osascript = opts.osascript or { code = 0, stdout = "clicked Check for Updates…\n" }
end

local function settled()
  assert(
    vim.wait(2500, function()
      return U.current() == nil
    end, 10),
    "the run must end"
  )
end

-- Handles of the running watch, to prove they are closed afterwards.
local function handles()
  assert(
    vim.wait(1000, function()
      return U.current() and U.current().timer ~= nil
    end, 5),
    "the watch must start"
  )
  local run = U.current()
  return { run.timer, run.fs }
end
local function closed(list)
  for _, h in ipairs(list) do
    assert(h:is_closing(), "watch handle left open")
  end
end

F.case("preflight refuses an update already in progress", function()
  fresh()
  F.set_marker(40)
  U.update()
  F.wait_notice("update already in progress")
  settled()
  assert(#F.of("osascript") == 0 and #F.of("curl") == 0, "nothing triggered")
end)

F.case("an expired marker does not refuse", function()
  fresh()
  F.set_marker(-5)
  U.update()
  assert(
    vim.wait(1000, function()
      return #F.of("osascript") == 1
    end, 5),
    "expired marker = absent"
  )
  F.wait_notice("no update started")
  settled()
end)

F.case("preflight refuses an unreachable server", function()
  fresh({ up = false })
  U.update()
  F.wait_notice("server unreachable")
  settled()
  assert(#F.of("osascript") == 0, "nothing triggered")
end)

F.case("preflight refuses without a readable server-runtime.json", function()
  fresh({ runtime = false })
  U.update()
  F.wait_notice("server%-runtime%.json")
  settled()
  assert(#F.of("osascript") == 0, "nothing triggered")
end)

local working = {
  type = "snapshot",
  projects = {},
  threads = { { id = "a", status = "working" }, { id = "b", status = "working" }, { id = "c", status = "idle" } },
}

F.case("working threads: n cancels", function()
  fresh({ feed = working, answer = "n" })
  U.update()
  F.wait_notice("cancelled")
  settled()
  assert(asked == 1, "asked once")
  assert(question():find("2 running thread%(s%) will be interrupted"), question())
  assert(question():find("y/n"), question())
  assert(#F.of("osascript") == 0, "n must not trigger")
end)

F.case("working threads: y triggers", function()
  fresh({ feed = working, answer = "y" })
  U.update()
  assert(
    vim.wait(1000, function()
      return #F.of("osascript") == 1
    end, 5),
    "y triggers"
  )
  assert(asked == 1)
  F.wait_notice("no update started")
  settled()
end)

F.case("no feed: running threads unknown, still asks", function()
  fresh({ feed = { projects = {}, threads = {} }, answer = "n" })
  U.update()
  F.wait_notice("cancelled")
  settled()
  assert(asked == 1, "asks without the feed")
  assert(question():find("running threads unknown %(sidebar feed not running%)"), question())
end)

F.case("no working threads: no question", function()
  fresh()
  U.update()
  assert(vim.wait(1000, function()
    return #F.of("osascript") == 1
  end, 5))
  assert(asked == 0, "no prompt without working threads")
  F.wait_notice("no update started")
  settled()
end)

F.case("trigger: the desktop's own menu item through System Events", function()
  fresh()
  U.update()
  assert(vim.wait(1000, function()
    return #F.of("osascript") == 1
  end, 5))
  local argv = F.of("osascript")[1].argv
  assert(argv[2] == "-e", "inline script")
  local script = argv[3]
  assert(script:find('tell application "System Events"', 1, true), script)
  assert(script:find("starts with itemPrefix", 1, true), script)
  assert(script:find("menu bar item menuName of menu bar 1", 1, true), script)
  assert(not script:find("Download") and not script:find("Restart"), "the user clicks the dialog")
  assert(argv[4] == "T3 Code (Nightly)" and argv[5] == "T3 Code (Nightly)" and argv[6] == "T3 Code (Nightly)")
  assert(argv[7] == "Check for Updates", "prefix matches … and ...")
  assert(#argv == 7)
  for _, call in ipairs(F.calls) do
    local line = table.concat(call.argv, " ")
    assert(not line:find("t3 update") and not line:find("kill"), "never stands in for the desktop: " .. line)
  end
  F.wait_notice("Check for Updates")
  F.wait_notice("no update started")
  settled()
end)

F.case("watch: marker appears, is removed, new pid, reachable -> updated", function()
  fresh()
  F.client("t3-a", "live")
  F.client("t3-b", "finished")
  U.update()
  local list = handles()
  F.set_marker(55)
  F.wait_notice("T3 is updating")
  F.server(false)
  os.remove(F.marker)
  F.set_runtime(2000, "1.1.0")
  vim.wait(150)
  assert(U.current(), "unreachable new server is not success yet")
  F.server(true)
  F.wait_notice("T3 updated: 1%.0%.0 → 1%.1%.0")
  settled()
  closed(list)
  F.wait_notice("1 client process running")
  local text = F.last()
  assert(text:find("not running: t3%-b"), text)
  assert(text:find(":T3Restart"), text)
  for _, n in ipairs(F.notices) do
    assert(not n.text:find("reconnected"), "process liveness only")
  end
end)

F.case("watch: expired marker + new pid, same version -> restarted", function()
  fresh()
  U.update()
  local list = handles()
  F.set_marker(55)
  F.wait_notice("T3 is updating")
  F.set_marker(-1)
  F.set_runtime(2001, "1.0.0")
  F.wait_notice("T3 restarted %(same version 1%.0%.0%)")
  settled()
  closed(list)
end)

F.case("watch: expired marker, same pid, unreachable -> stalled, then timeout", function()
  fresh()
  U.update()
  local list = handles()
  F.set_marker(55)
  F.wait_notice("T3 is updating")
  F.server(false)
  F.set_marker(-1)
  F.wait_notice("update stalled")
  assert(U.current(), "a stall keeps watching")
  local stalls = 0
  F.wait_notice("timed out", 2500)
  for _, n in ipairs(F.notices) do
    stalls = stalls + (n.text:find("update stalled") and 1 or 0)
  end
  assert(stalls == 1, "stall reported once")
  settled()
  closed(list)
end)

F.case("watch: expired marker over the same reachable pid is neither success nor stall", function()
  fresh()
  U.update()
  local list = handles()
  F.set_marker(55)
  F.wait_notice("T3 is updating")
  F.set_marker(-1)
  vim.wait(200)
  assert(U.current(), "same pid is not an update")
  for _, n in ipairs(F.notices) do
    assert(not n.text:find("T3 updated") and not n.text:find("restarted") and not n.text:find("stalled"), n.text)
  end
  F.set_runtime(2002, "1.2.0")
  F.wait_notice("T3 updated: 1%.0%.0 → 1%.2%.0")
  settled()
  closed(list)
end)

F.case("no marker within the start timeout -> no update started", function()
  fresh()
  U.update()
  local list = handles()
  F.wait_notice("no update started")
  settled()
  closed(list)
end)

F.case("a second :T3Update while one runs is refused", function()
  fresh()
  U.update()
  handles()
  U.update()
  F.wait_notice("already running")
  assert(#F.of("osascript") == 1)
  F.wait_notice("no update started")
  settled()
end)

for _, permission in ipairs({
  {
    stderr = "execution error: System Events got an error: osascript is not allowed assistive access. (-25211)",
    want = "Accessibility",
  },
  { stderr = "execution error: Not authorized to send Apple events to System Events. (-1743)", want = "Automation" },
}) do
  F.case("permission error names " .. permission.want .. ", once, no watch", function()
    fresh({ osascript = { code = 1, stderr = permission.stderr } })
    U.update()
    F.wait_notice(permission.want)
    settled()
    vim.wait(200)
    assert(#F.of("osascript") == 1, "no retry loop")
    local errors = 0
    for _, n in ipairs(F.notices) do
      errors = errors + (n.level == vim.log.levels.ERROR and 1 or 0)
    end
    assert(errors == 1, "one actionable error")
    assert(F.last():find("Privacy & Security"), F.last())
  end)
end

F.case("missing menu item is reported", function()
  fresh({ osascript = { code = 1, stderr = "execution error: T3UPD_NO_MENU (9001)" } })
  U.update()
  F.wait_notice("Check for Updates.*not found")
  settled()
end)

F.case(":T3Update is registered", function()
  fresh()
  U.setup()
  vim.cmd("T3Update")
  assert(vim.wait(1000, function()
    return #F.of("osascript") == 1
  end, 5))
  F.wait_notice("no update started")
  settled()
  assert(not pcall(vim.cmd, "T3Update!"), "no bang variant")
end)

F.done()
