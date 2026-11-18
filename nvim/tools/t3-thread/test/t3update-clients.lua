-- B-R1-08: after an update, name both the running and the not-running client
-- processes (process liveness only), and touch none of them.
local F = dofile("nvim/tools/t3-thread/test/support/t3update-fixture.lua")
local U = F.U
U.config.poll_ms = 30
U.config.start_timeout_ms = 1000
U.config.timeout_ms = 2000

local function update_with(clients, setup)
  F.reset()
  F.server(true)
  F.set_runtime(1000, "1.0.0")
  F.feed.live, F.feed.snapshot = true, { type = "snapshot", projects = {}, threads = {} }
  F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
  for name, state in pairs(clients) do
    F.client(name, state)
  end
  if setup then
    setup()
  end
  local before = vim.deepcopy(F.core.terms)
  U.update()
  F.until_true(function()
    return U.current() and U.current().timer ~= nil
  end, 1000, "the watch must start")
  F.set_runtime(2000, "1.1.0")
  F.wait_notice("T3 updated")
  F.wait_notice("client process")
  local text = F.last()
  assert(vim.deep_equal(before, F.core.terms), "client facts untouched")
  for _, call in ipairs(F.calls) do
    assert(call.argv[1] == "curl" or call.argv[1] == "osascript", "no client command: " .. call.argv[1])
  end
  assert(not text:find("reconnect") and not text:find("connected"), "process liveness only: " .. text)
  return text
end

F.case("mixed: both names, the running count and the restart hint", function()
  local text = update_with({ ["crt-running"] = "live", ["crt-finished"] = "finished" })
  assert(text:find("1 client process running: crt%-running"), text)
  assert(text:find("not running: crt%-finished"), text)
  assert(text:find(":T3Restart"), text)
end)

F.case("all running: every name and the hint", function()
  local text = update_with({ ["t3-a"] = "live", ["t3-c"] = "live" })
  assert(text:find("2 client processes running: t3%-a, t3%-c"), text)
  assert(not text:find("not running"), text)
  assert(text:find(":T3Restart"), text)
end)

F.case("no clients", function()
  local text = update_with({})
  assert(text:find("0 client processes running"), text)
  local body = text:gsub("^T3: ", "")
  assert(not body:find(":"), "no empty name list or hint: " .. body)
end)

local function shared()
  F.client("shared-client", "live")
  F.client("shared-client", "live")
end

F.case("B-R2-01 status: two viewers of one core client are one process", function()
  F.reset()
  F.server(true)
  F.set_runtime(1000, "1.0.0")
  shared()
  U.status()
  F.wait_notice("client buffers")
  assert(F.last():find("2 client buffers, 1 client process running", 1, true), F.last())
end)

F.case("B-R2-01 after an update: one process, one name", function()
  local text = update_with({}, shared)
  assert(text:find("1 client process running: shared%-client%. "), text)
  assert(select(2, text:gsub("shared%-client", "")) == 1, "one name entry: " .. text)
end)

F.case("B-R2-01 distinct addresses sharing a display name stay distinct", function()
  local text = update_with({}, function()
    F.client("addr-1", "live")
    F.client("addr-2", "live")
    F.core.terms["addr-1"].name, F.core.terms["addr-2"].name = "twin", "twin"
  end)
  assert(text:find("2 client processes running: twin, twin", 1, true), text)
end)

F.done()
