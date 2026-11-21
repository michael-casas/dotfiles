-- Dadbod's Postgres adapter (nvim/autoload/envi/dadbod_postgresql.vim) must
-- refuse a connection string exactly where libpq would read a password from
-- what psql receives, and accept everything else libpq accepts (owner ruling,
-- phase 2). Key/value conninfo after the scheme is refused by policy. Each
-- row's expected outcome comes from libpq itself (envi.libpq, PQconninfoParse)
-- and is cross-checked against the hand-checked anchor in the shape table.
--
-- Checked for every row under both schemes:
--   resolve time (what :DBUIAddConnection and rename call before saving):
--     refusal with the right fixed message, or acceptance that is stable
--     when repeated and runs an operand libpq accepts;
--   the interactive, filter and input builders, on the raw URL: refusal
--     exactly when libpq reads a password from (or rejects) the operand,
--     otherwise psql -X with that operand and the original -f path;
--   no message ever shows the synthetic value.
-- Then, with libpq forced unloadable, Postgres URLs are refused (nolib).
-- No psql runs; failures name the case only.
--
-- Needs vim-dadbod at the revision in nvim/lazy-lock.json, installed where
-- envi keeps its plugins (stdpath("data")/lazy), and libpq. Without either,
-- the suite says so and passes: it checks the adapter, not the install.
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
-- Builders prefix `env -u PGPASSWORD` when it is set; check the plain form.
vim.env.PGPASSWORD = nil

local pq = require("envi.libpq")
local _, libpath = pq.load()
if not libpath then
  io.stdout:write("SKIP dadbod-password: libpq could not be loaded\n")
  return
end
io.stdout:write(("dadbod-password: libpq %d from %s\n"):format(pq.version(), libpath))

local S = dofile("nvim/tools/t3-thread/test/support/dadbod-password-shapes.lua")

local MSG = {
  PW = "carries a password",
  KV = "keyword/value conninfo",
  BAD = "libpq can't parse",
  nolib = "couldn't load libpq",
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
local function dbname(cmd)
  for i, a in ipairs(cmd) do
    if a == "--dbname" then
      return cmd[i + 1]
    end
  end
end
local input = vim.fn.tempname() .. "/password=" .. S.password .. ".sql"
local counts = { PW = 0, KV = 0, BAD = 0, OK = 0 }

for _, c in ipairs(S.cases()) do
  local id, scheme, url, anchor = c[1], c[2], c[3], c[4]
  local label = scheme .. ", " .. id
  local truth = S.label(url)
  counts[truth] = counts[truth] + 1
  if anchor then
    expect(truth == anchor, label .. ": libpq's label matches the hand-checked anchor")
  end

  -- Resolve time.
  local ok, res = pcall(vim.fn["db#resolve"], url)
  if truth == "OK" then
    local again_ok, again = pcall(vim.fn["db#resolve"], ok and res or "")
    local run = ok and pq.classify(S.operand(res)) or "-"
    expect(
      ok and again_ok and again == res and (run == "clean" or run == "literal"),
      label .. ": resolve accepts it, stably, and runs an operand libpq accepts"
    )
  else
    expect(
      not ok and tostring(res):find(MSG[truth], 1, true) ~= nil and not leaks(res),
      label .. ": resolve refuses it (" .. truth .. "), with the fixed message only"
    )
  end

  -- Command build, on the raw URL.
  local op_verdict = pq.classify(S.operand(url))
  for _, fn in ipairs({ "interactive", "filter", "input" }) do
    local bok, cmd
    if fn == "input" then
      bok, cmd = pcall(vim.fn["db#adapter#dispatch"], url, fn, input)
    else
      bok, cmd = pcall(vim.fn["db#adapter#dispatch"], url, fn)
    end
    if op_verdict == "password" or op_verdict == "invalid" then
      expect(not bok and not leaks(cmd), label .. ": " .. fn .. " refuses its " .. op_verdict .. " operand")
    else
      local ints = type(cmd) == "table" and cmd or {}
      local x = #vim.tbl_filter(function(a)
        return a == "-X" or a == "--no-psqlrc"
      end, ints)
      expect(
        bok
          and ints[1] == "psql"
          and x == 1
          and dbname(ints) == S.operand(url)
          and (fn ~= "input" or ints[#ints] == input),
        label .. ": " .. fn .. " builds psql -X with the operand unchanged"
      )
    end
  end
end

-- Enough of each kind that a regression can't hide in an empty bucket.
expect(counts.PW >= 40 and counts.KV >= 40 and counts.OK >= 50 and counts.BAD >= 6, "every outcome is exercised")

-- No libpq: Postgres URLs are refused, with the fixed message.
local saved = vim.env.ENVI_LIBPQ
vim.env.ENVI_LIBPQ = vim.fn.tempname() .. "/missing-libpq"
pq.reset()
for _, url in ipairs({
  "postgresql://demo@127.0.0.1:1/demo",
  "postgres:///?service=dadbod_demo",
  "postgresql://demo:" .. S.password .. "@127.0.0.1:1/demo",
}) do
  local ok, err = pcall(vim.fn["db#resolve"], url)
  expect(
    not ok and tostring(err):find(MSG.nolib, 1, true) ~= nil and not leaks(err),
    "nolib: resolve refuses " .. url:gsub(S.password, "<PW>")
  )
  ok, err = pcall(vim.fn["db#adapter#dispatch"], url, "interactive")
  expect(
    not ok and tostring(err):find(MSG.nolib, 1, true) ~= nil and not leaks(err),
    "nolib: interactive refuses " .. url:gsub(S.password, "<PW>")
  )
end
vim.env.ENVI_LIBPQ = saved
pq.reset()

io.stdout:write(
  ("dadbod-password: %d cases (PW %d, KV %d, BAD %d, OK %d), %d failed\n"):format(
    cases,
    counts.PW,
    counts.KV,
    counts.BAD,
    counts.OK,
    #failures
  )
)
assert(#failures == 0, "dadbod-password failures:\n  " .. table.concat(failures, "\n  "))
