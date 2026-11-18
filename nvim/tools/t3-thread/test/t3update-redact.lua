-- B-R1-07: no notice repeats the configured endpoint URL, which may carry
-- credentials; the probe itself still goes to that URL.
local F = dofile("nvim/tools/t3-thread/test/support/t3update-fixture.lua")
local U = F.U
local URL = "http://synthetic-user:synthetic-pass@127.0.0.1:39999/base?token=synthetic-token#frag"
local SECRETS = { "synthetic-user", "synthetic-pass", "synthetic-token", "frag", "@" }

local function clean(what)
  for _, n in ipairs(F.notices) do
    for _, secret in ipairs(SECRETS) do
      assert(not n.text:find(secret, 1, true), what .. " leaked " .. secret .. ": " .. n.text)
    end
  end
end

local function probed_url()
  local curl = F.of("curl")[1]
  return curl and curl.argv[#curl.argv] or ""
end

F.case(":T3Status unreachable notice carries no URL secrets", function()
  F.reset()
  vim.env.T3_URL = URL
  F.server(false)
  F.set_runtime(1000, "1.0.0", { authToken = "SECRET-TOKEN" })
  U.status()
  F.wait_notice("server unreachable")
  vim.wait(50)
  assert(#F.notices == 1, "one notice")
  clean("status")
  assert(not F.last():find("SECRET-TOKEN", 1, true))
  assert(vim.startswith(probed_url(), URL:gsub("/+$", "")), "the probe keeps its real destination")
end)

F.case(":T3Update unreachable refusal carries no URL secrets", function()
  F.reset()
  vim.env.T3_URL = URL
  F.server(false)
  F.set_runtime(1000, "1.0.0")
  U.update()
  F.wait_notice("server unreachable")
  F.until_true(function()
    return U.current() == nil
  end)
  vim.wait(50)
  assert(#F.notices == 1, "one notice")
  clean("update")
  assert(#F.of("osascript") == 0)
end)

vim.env.T3_URL = "http://127.0.0.1:39999"
F.done()
