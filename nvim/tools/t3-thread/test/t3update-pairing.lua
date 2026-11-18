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

vim.env.T3_URL = "http://127.0.0.1:39999"
F.done()
