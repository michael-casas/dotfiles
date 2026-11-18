-- B-R1-11: the probed endpoint and the desktop home must describe the same
-- backend. A runtime port that differs from the endpoint's port is reported
-- by :T3Status and refused by :T3Update.
local F = dofile("nvim/tools/t3-thread/test/support/t3update-fixture.lua")
local U = F.U
U.config.poll_ms = 30
U.config.start_timeout_ms = 200
U.config.timeout_ms = 1000

local function status(url, port)
  F.reset()
  vim.env.T3_URL = url
  F.server(true)
  F.set_runtime(1000, "1.0.0", { port = port })
  U.status()
  F.until_true(function()
    return #F.notices > 0
  end, 1000, "status notice")
  return F.last()
end

local function update(url, port)
  F.reset()
  vim.env.T3_URL = url
  F.server(true)
  F.set_runtime(1000, "1.0.0", { port = port })
  F.feed.live, F.feed.snapshot = true, { type = "snapshot", projects = {}, threads = {} }
  F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
  U.update()
  F.until_true(function()
    return U.current() == nil or (U.current().timer ~= nil)
  end, 1000, "update decision")
  local triggered = #F.of("osascript") > 0
  F.stop(U)
  return triggered
end

F.case(":T3Status reports a port disagreement", function()
  local text = status("http://127.0.0.1:39999", 3773)
  assert(text:find("endpoint and desktop home disagree (port 39999 vs 3773)", 1, true), text)
  text = status("http://127.0.0.1:39999", 39999)
  assert(not text:find("disagree"), text)
end)

F.case(":T3Update refuses a port disagreement", function()
  assert(not update("http://127.0.0.1:39999", 3773), "mismatch must not trigger")
  assert(F.has("endpoint and desktop home disagree (port 39999 vs 3773)"), F.last())
  assert(update("http://127.0.0.1:39999", 39999), "matching ports trigger")
end)

F.case("a disagreement appearing while the prompt is open refuses", function()
  F.reset()
  vim.env.T3_URL = "http://127.0.0.1:39999"
  F.server(true)
  F.set_runtime(1000, "1.0.0", { port = 39999 })
  F.feed.live, F.feed.snapshot = false, { projects = {}, threads = {} }
  F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
  vim.fn.getcharstr = function()
    F.set_runtime(1000, "1.0.0", { port = 3773 })
    return "y"
  end
  U.update()
  F.wait_notice("disagree")
  F.until_true(function()
    return U.current() == nil
  end)
  assert(#F.of("osascript") == 0)
  vim.fn.getcharstr = function()
    return "y"
  end
end)

F.case("default ports, userinfo and IPv6 hosts parse", function()
  assert(not status("http://127.0.0.1", 80):find("disagree"), F.last())
  assert(status("http://127.0.0.1/", 3773):find("(port 80 vs 3773)", 1, true), F.last())
  assert(status("https://localhost", 3773):find("(port 443 vs 3773)", 1, true), F.last())
  assert(not status("http://u:p@[::1]:39999/x?y=1", 39999):find("disagree"), F.last())
  local text = status("http://u:p@[::1]:39999/x?y=1", 3773)
  assert(text:find("(port 39999 vs 3773)", 1, true) and not text:find("u:p", 1, true), text)
end)

F.case("an unknown runtime port is not a disagreement", function()
  assert(not status("http://127.0.0.1:39999", nil):find("disagree"), F.last())
  assert(update("http://127.0.0.1:39999", nil), "no port: the pid check alone applies")
end)

F.case("B-R2-02 the watch never certifies a backend on another port", function()
  U.config.start_timeout_ms, U.config.timeout_ms = 2000, 2000
  F.reset()
  vim.env.T3_URL = "http://127.0.0.1:39999"
  F.server(true)
  F.set_runtime(1000, "1.0.0", { port = 39999 })
  F.feed.live, F.feed.snapshot = true, { type = "snapshot", projects = {}, threads = {} }
  F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
  U.update()
  F.until_true(function()
    return U.current() and U.current().timer ~= nil
  end, 1000, "the watch must start")
  local run = U.current()
  F.set_marker(45)
  F.wait_notice("T3 is updating")
  F.set_runtime(2000, "1.1.0", { port = 39998 })
  os.remove(F.marker)
  vim.wait(300)
  assert(not F.has("T3 updated") and not F.has("restarted"), "a 200 from the old port is not the new backend")
  assert(U.current() == run, "keeps watching")
  F.set_runtime(2000, "1.1.0", { port = 39999 })
  F.wait_notice("T3 updated: 1%.0%.0 → 1%.1%.0", 1000)
  assert(F.count("T3 updated") == 1)
  U.config.start_timeout_ms, U.config.timeout_ms = 200, 1000
end)

-- B-R2-02 (critic r3): the endpoint is switched while a probe's reply is in
-- flight. The probe asked 39999; the runtime and the configuration now name
-- 39998. A decision pairs the runtime with the port that answered, never with
-- a later read of T3_URL.
local OLD_BASE, NEW_BASE = "http://127.0.0.1:39999", "http://127.0.0.1:39998"
local OLD_URL, NEW_URL = OLD_BASE .. "/.well-known/t3/environment", NEW_BASE .. "/.well-known/t3/environment"

F.case("B-R2-02 :T3Status pairs the runtime with the probed port", function()
  F.reset()
  vim.env.T3_URL = OLD_BASE
  F.set_runtime(1000, "1.0.0", { port = 39999 })
  F.reply.curl = function(argv)
    assert(argv[#argv] == OLD_URL, argv[#argv])
    F.set_runtime(1000, "1.0.0", { port = 39998 })
    vim.env.T3_URL = NEW_BASE
    return { code = 0, stdout = "200" }
  end
  U.status()
  F.until_true(function()
    return #F.notices > 0
  end, 1000, "status notice")
  assert(F.last():find("server up", 1, true), F.last())
  assert(F.last():find("endpoint and desktop home disagree (port 39999 vs 39998)", 1, true), F.last())
  vim.env.T3_URL = OLD_BASE
end)

F.case("B-R2-02 a stale 200 never completes the watch; the paired one does, once", function()
  U.config.start_timeout_ms, U.config.timeout_ms = 2000, 2000
  F.reset()
  vim.env.T3_URL = OLD_BASE
  F.server(true)
  F.set_runtime(1000, "1.0.0", { port = 39999 })
  F.feed.live, F.feed.snapshot = true, { type = "snapshot", projects = {}, threads = {} }
  F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
  U.update()
  F.until_true(function()
    return U.current() and U.current().timer ~= nil
  end, 1000, "the watch must start")
  local run = U.current()
  F.set_marker(45)
  F.wait_notice("T3 is updating")
  local asked, switched = {}, false
  F.reply.curl = function(argv)
    local url = argv[#argv]
    asked[#asked + 1] = url
    if url == OLD_URL and not switched then
      switched = true
      vim.env.T3_URL = NEW_BASE -- after the argv was built: the reply is in flight
      return { code = 0, stdout = "200" }
    end
    assert(url == NEW_URL, "unexpected watch destination " .. url)
    return { code = 7, stdout = "000" }
  end
  F.set_runtime(2000, "1.1.0", { port = 39998 })
  os.remove(F.marker)
  F.until_true(function()
    return switched
  end, 1000, "the stale probe must run")
  vim.wait(300)
  assert(asked[1] == OLD_URL, "the first watch probe asks the old port")
  assert(not F.has("T3 updated") and not F.has("restarted"), "a 200 from 39999 is not the backend on 39998")
  assert(U.current() == run, "keeps watching after the stale 200")
  local before = #asked
  F.reply.curl = function(argv)
    assert(argv[#argv] == NEW_URL, "recovery probes the configured port " .. argv[#argv])
    asked[#asked + 1] = argv[#argv]
    return { code = 0, stdout = "200" }
  end
  F.wait_notice("T3 updated: 1%.0%.0 → 1%.1%.0", 1000)
  vim.wait(100)
  assert(#asked > before, "completion follows a probe of 39998")
  assert(F.count("T3 updated") == 1, "completes exactly once")
  assert(U.current() == nil, "the run ended")
  assert(run.timer:is_closing() and run.fs:is_closing() and run.deadline:is_closing(), "all watch handles closed")
  vim.env.T3_URL = OLD_BASE
  U.config.start_timeout_ms, U.config.timeout_ms = 200, 1000
end)

F.case("B-R2-02 a stale 200 admits no trigger in either confirm branch", function()
  for _, confirm in ipairs({ false, true }) do
    F.reset()
    vim.env.T3_URL = OLD_BASE
    F.set_runtime(1000, "1.0.0", { port = 39999 })
    F.feed.live = true
    F.feed.snapshot = { projects = {}, threads = confirm and { { status = "working" } } or {} }
    F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
    local probes = 0
    F.reply.curl = function(argv)
      probes = probes + 1
      assert(argv[#argv] == OLD_URL, argv[#argv])
      if probes == (confirm and 2 or 1) then -- the final admission probe
        F.set_runtime(1000, "1.0.0", { port = 39998 })
        vim.env.T3_URL = NEW_BASE
      end
      return { code = 0, stdout = "200" }
    end
    U.update()
    F.until_true(function()
      return U.current() == nil or #F.of("osascript") > 0
    end, 1000, "preflight decision")
    local label = confirm and "after y" or "no prompt"
    assert(#F.of("osascript") == 0, label .. ": a stale 200 must not trigger")
    assert(probes == (confirm and 2 or 1), label .. ": probes " .. probes)
    assert(F.has("endpoint and desktop home disagree (port 39999 vs 39998)"), label .. ": " .. F.last())
    -- A paired probe of the configured port now succeeds: admitted.
    F.reply.curl = function(argv)
      assert(argv[#argv] == NEW_URL, argv[#argv])
      return { code = 0, stdout = "200" }
    end
    U.update()
    F.until_true(function()
      return U.current() == nil or #F.of("osascript") > 0
    end, 1000, "paired preflight decision")
    assert(#F.of("osascript") == 1, label .. ": the paired probe admits one trigger")
    F.stop(U)
  end
  vim.env.T3_URL = OLD_BASE
end)

vim.env.T3_URL = "http://127.0.0.1:39999"
F.done()
