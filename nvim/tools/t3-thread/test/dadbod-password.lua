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
-- Source the adapter now. S.label() switches envi's adapter off to ask
-- upstream; vim-dadbod then counts "postgresql" as loaded and, until something
-- autoloads envi's file, db#adapter#call() would skip its canonicalize. In envi
-- the variables are set at startup, so the first lookup sources it.
vim.cmd("runtime autoload/envi/dadbod_postgresql.vim")
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
-- $DADBOD_MATRIX_DUMP: write one line per case (ids and outcomes, never the
-- URL), to compare the classification across platforms and libpq builds.
local dump = {}

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
  table.insert(dump, table.concat({ scheme, id, truth, op_verdict, ok and "accepted" or "refused" }, "|"))
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

if vim.env.DADBOD_MATRIX_DUMP and vim.env.DADBOD_MATRIX_DUMP ~= "" then
  vim.fn.writefile(dump, vim.env.DADBOD_MATRIX_DUMP)
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

-- A libpq planted in the current directory never loads (F8). On macOS,
-- dlopen() of a bare name searches the current directory, so the loader must
-- use absolute paths only. Simulate a machine where no absolute candidate
-- holds libpq: ffi.load fails for every absolute path and passes bare names
-- to the real loader. A stub library with a constructor sits in a temporary
-- current directory; it must not load, and its constructor must not run.
-- Counted apart from the matrix cases. Needs a C compiler; without one, it
-- says so.
local planted_failures = {}
local cc = vim.fn.exepath("cc")
if cc == "" then
  io.stdout:write("SKIP dadbod-password planted libpq: no C compiler\n")
else
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local marker = dir .. "/CONSTRUCTOR-RAN"
  local mac = vim.fn.has("mac") == 1
  local name = mac and "libpq.5.dylib" or "libpq.so.5"
  vim.fn.writefile({
    "#include <stdio.h>",
    "__attribute__((constructor)) static void ran(void) {",
    '  FILE *f = fopen("' .. marker .. '", "w");',
    '  if (f) { fputs("planted\\n", f); fclose(f); }',
    "}",
    "void *PQconninfoParse(const char *s, char **e) { if (e) *e = 0; return 0; }",
    "void PQconninfoFree(void *p) {}",
    "void PQfreemem(void *p) {}",
    "int PQlibVersion(void) { return 666; }",
  }, dir .. "/fake.c")
  vim.fn.system({ cc, "-shared", "-fPIC", "-o", dir .. "/" .. name, dir .. "/fake.c" })
  if vim.v.shell_error ~= 0 then
    table.insert(planted_failures, "planted: the stub library did not build")
  else
    local ffi = require("ffi")
    local real_load = ffi.load
    ffi.load = function(path, ...)
      if path:find("/", 1, true) then
        error("simulated: no libpq at " .. path)
      end
      return real_load(path, ...)
    end
    local env_saved, cwd = vim.env.ENVI_LIBPQ, vim.fn.getcwd()
    vim.env.ENVI_LIBPQ = nil
    vim.fn.chdir(dir)
    pq.reset()
    local _, path = pq.load()
    local version = pq.version()
    vim.fn.chdir(cwd)
    ffi.load = real_load
    vim.env.ENVI_LIBPQ = env_saved
    pq.reset()
    io.stdout:write(
      ("dadbod-password planted libpq: loaded=%s version=%s constructor=%s\n"):format(
        tostring(path),
        tostring(version),
        tostring(vim.uv.fs_stat(marker) ~= nil)
      )
    )
    if version == 666 or vim.uv.fs_stat(marker) then
      table.insert(planted_failures, "planted: a libpq in the current directory was loaded")
    end
    if mac and path ~= nil then
      table.insert(planted_failures, "planted: macOS loaded a bare-name libpq instead of nolib")
    end
  end
  vim.fn.delete(dir, "rf")
end

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
assert(#planted_failures == 0, table.concat(planted_failures, "\n"))
