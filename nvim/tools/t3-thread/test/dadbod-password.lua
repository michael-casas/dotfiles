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

local M = dofile("nvim/tools/t3-thread/test/support/dadbod-password-shapes.lua")
local shapes = M.shapes

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
