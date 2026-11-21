-- Dadbod's Postgres adapter (nvim/autoload/envi/dadbod_postgresql.vim) must
-- refuse every connection string that carries a password, in each form libpq
-- accepts, for both the postgresql: and postgres: schemes, at resolve time
-- (what :DBUIAddConnection and rename call before saving) and when it builds
-- a psql command. Each password form has a password-free twin that must keep
-- working. The value is synthetic; no psql runs; failures name the case only.
--
-- Needs vim-dadbod at the revision in nvim/lazy-lock.json, installed where
-- envi keeps its plugins (stdpath("data")/lazy). Without it, the suite says so
-- and passes: it is a check of the adapter, not of the plugin install.
local dadbod = vim.fn.stdpath("data") .. "/lazy/vim-dadbod"
if vim.fn.isdirectory(dadbod) == 0 then
  io.stdout:write("SKIP dadbod-password: vim-dadbod is not installed at " .. dadbod .. "\n")
  return
end
vim.opt.rtp:prepend(dadbod)
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.cmd("runtime plugin/dadbod.vim")
vim.g.db_adapter_postgresql = "envi#dadbod_postgresql#"
vim.g.db_adapter_postgres = "envi#dadbod_postgresql#"

local PW = "SYNTHETIC-PW-123"
local PW_ENC = "SYNTHETIC%2DPW%2D123"

-- { shape, with password, password-free twin }; "S" is the scheme.
local shapes = {
  { "single-host userinfo", "S://demo:" .. PW .. "@127.0.0.1:1/demo", "S://demo@127.0.0.1:1/demo" },
  { "single-host userinfo, encoded value", "S://demo:" .. PW_ENC .. "@127.0.0.1:1/demo", "S://demo@127.0.0.1:1/demo" },
  { "userinfo, empty user", "S://:" .. PW .. "@127.0.0.1:1/demo", "S://@127.0.0.1:1/demo" },
  {
    "multi-host userinfo",
    "S://demo:" .. PW .. "@127.0.0.1:1,127.0.0.2:2/demo",
    "S://demo@127.0.0.1:1,127.0.0.2:2/demo",
  },
  { "multi-host userinfo, no ports", "S://demo:" .. PW .. "@h1,h2/demo", "S://demo@h1,h2/demo" },
  { "IPv6 host userinfo", "S://demo:" .. PW .. "@[::1]:1/demo", "S://demo@[::1]:1/demo" },
  {
    "IPv6 multi-host userinfo",
    "S://demo:" .. PW .. "@[::1]:1,[::2]:2/demo",
    "S://demo@[::1]:1,[::2]:2/demo",
  },
  { "empty host userinfo", "S://demo:" .. PW .. "@/demo", "S://demo@/demo" },
  { "query parameter", "S://demo@127.0.0.1:1/demo?password=" .. PW, "S://demo@127.0.0.1:1/demo?sslmode=disable" },
  {
    "query parameter, mixed case",
    "S://demo@127.0.0.1:1/demo?PassWord=" .. PW,
    "S://demo@127.0.0.1:1/demo?PassFile=x",
  },
  {
    "query parameter, encoded key",
    "S://demo@127.0.0.1:1/demo?pass%77ord=" .. PW,
    "S://demo@127.0.0.1:1/demo?pass%66ile=x",
  },
  {
    "query parameter, mixed-case partly encoded key",
    "S://demo@127.0.0.1:1/demo?P%61sS%57oRd=" .. PW,
    "S://demo@127.0.0.1:1/demo?applic%61tion_name=x",
  },
  {
    "query parameter, fully encoded key",
    "S://demo@127.0.0.1:1/demo?%70%61%73%73%77%6F%72%64=" .. PW,
    "S://demo@127.0.0.1:1/demo?%73%73%6C%6D%6F%64%65=disable",
  },
  {
    "query parameter, repeated keys",
    "S://demo@127.0.0.1:1/demo?sslmode=disable&password=" .. PW .. "&sslmode=require",
    "S://demo@127.0.0.1:1/demo?sslmode=disable&sslmode=require",
  },
  {
    "multi-host with encoded key",
    "S://demo@127.0.0.1:1,127.0.0.2:2/demo?pass%57ord=" .. PW,
    "S://demo@127.0.0.1:1,127.0.0.2:2/demo?connect_timeout=1",
  },
  {
    "service with parameters",
    "S:///?service=dadbod_demo&password=" .. PW,
    "S:///?service=dadbod_demo&application_name=envi",
  },
  {
    "service with encoded key",
    "S:///?service=dadbod_demo&pa%73sword=" .. PW,
    "S:///?service=dadbod_demo&connect_timeout=1",
  },
  { "key/value conninfo", "S:host=127.0.0.1 port=1 password=" .. PW, "S:host=127.0.0.1 port=1 dbname=demo" },
  {
    "key/value conninfo, spaced and quoted",
    "S:host=127.0.0.1 PASSWORD = '" .. PW .. "'",
    "S:host=127.0.0.1 application_name = 'envi app'",
  },
  {
    "key/value conninfo, encoded key",
    "S:host=127.0.0.1 pass%77ord=" .. PW,
    "S:host=127.0.0.1 connect_timeout=1",
  },
  {
    "key/value conninfo in the path",
    "S:///host=127.0.0.1%20password=" .. PW,
    "S:///host=127.0.0.1%20dbname=demo",
  },
}

local failures, cases = {}, 0
local function expect(ok, label)
  cases = cases + 1
  if not ok then
    table.insert(failures, label)
  end
end
local function leaks(err)
  return tostring(err):find("SYNTHETIC", 1, true) ~= nil
end
local input = vim.fn.tempname()

for _, scheme in ipairs({ "postgresql", "postgres" }) do
  for _, shape in ipairs(shapes) do
    local bad = shape[2]:gsub("^S:", scheme .. ":")
    local twin = shape[3]:gsub("^S:", scheme .. ":")
    local label = scheme .. ", " .. shape[1]

    -- Resolve time: db#resolve runs the adapter's canonicalize.
    local ok, err = pcall(vim.fn["db#resolve"], bad)
    expect(not ok and not leaks(err), label .. ": resolve refuses it, without the value")
    expect(pcall(vim.fn["db#resolve"], twin), label .. ": resolve accepts the password-free twin")

    -- Command build: every builder that does not itself run psql.
    for _, fn in ipairs({ "interactive", "filter", "input" }) do
      if fn ~= "input" then
        ok, err = pcall(vim.fn["db#adapter#dispatch"], bad, fn)
      else
        ok, err = pcall(vim.fn["db#adapter#dispatch"], bad, fn, input)
      end
      expect(not ok and not leaks(err), label .. ": " .. fn .. " refuses it, without the value")
      local tok, cmd
      if fn ~= "input" then
        tok, cmd = pcall(vim.fn["db#adapter#dispatch"], twin, fn)
      else
        tok, cmd = pcall(vim.fn["db#adapter#dispatch"], twin, fn, input)
      end
      expect(
        tok and type(cmd) == "table" and cmd[1] == "psql" and vim.tbl_contains(cmd, "-X"),
        label .. ": " .. fn .. " builds psql -X for the twin"
      )
    end
  end
end

io.stdout:write(("dadbod-password: %d cases, %d failed\n"):format(cases, #failures))
assert(#failures == 0, "dadbod-password failures:\n  " .. table.concat(failures, "\n  "))
