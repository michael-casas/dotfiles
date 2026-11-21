-- libpq's own connection-string parser, PQconninfoParse, through LuaJIT FFI.
-- Dadbod's Postgres adapter (autoload/envi/dadbod_postgresql.vim) asks it
-- whether the operand psql will receive carries a password, so the answer is
-- libpq's, not a hand-written grammar's. It only parses: no connection, no
-- service-file or passfile lookup, no environment defaults. The library is
-- loaded on first use.
--
-- Which libpq: $ENVI_LIBPQ if set (then only that file), else the one that
-- belongs to the psql on PATH (pg_config --libdir beside it, then
-- <bin>/../lib/postgresql and <bin>/../lib), then Homebrew's libpq keg. Then,
-- on macOS, /usr/local/lib; on Linux, the multiarch, lib64 and lib
-- directories, and last the dynamic loader's own search (libpq.so.5). Never a
-- bare name on macOS: dlopen() would search the current directory.
--
-- Never surface libpq's error message: it can quote the input, password
-- included.
local M = {}

local ffi
local lib, libpath -- lib: nil = not tried yet, false = not found

local function setup_ffi()
  if ffi then
    return
  end
  ffi = require("ffi")
  -- pcall: a second definition (module reloaded) is an error in LuaJIT.
  pcall(
    ffi.cdef,
    [[
typedef struct {
  char *keyword; char *envvar; char *compiled; char *val; char *label; char *dispchar; int dispsize;
} PQconninfoOption;
PQconninfoOption *PQconninfoParse(const char *conninfo, char **errmsg);
void PQconninfoFree(PQconninfoOption *connOptions);
void PQfreemem(void *ptr);
int PQlibVersion(void);
]]
  )
end

local function candidates()
  if vim.env.ENVI_LIBPQ and vim.env.ENVI_LIBPQ ~= "" then
    return { vim.env.ENVI_LIBPQ }
  end
  local mac = vim.fn.has("mac") == 1
  local names = mac and { "libpq.5.dylib", "libpq.dylib" } or { "libpq.so.5", "libpq.so" }
  local out, seen = {}, {}
  local function add(path)
    if path ~= "" and not seen[path] then
      seen[path] = true
      table.insert(out, path)
    end
  end
  local function add_dir(dir)
    for _, name in ipairs(names) do
      add(dir .. "/" .. name)
    end
  end
  local psql = vim.fn.exepath("psql")
  if psql ~= "" then
    local bin = vim.fn.fnamemodify(vim.fn.resolve(psql), ":h")
    -- The pg_config beside the psql that runs, so parser and client match.
    local pg_config = bin .. "/pg_config"
    if vim.fn.executable(pg_config) == 1 then
      local dir = vim.trim(vim.fn.system({ pg_config, "--libdir" }))
      if vim.v.shell_error == 0 and dir ~= "" then
        add_dir(dir)
      end
    end
    add_dir(bin .. "/../lib/postgresql")
    add_dir(bin .. "/../lib")
  end
  add_dir("/opt/homebrew/opt/libpq/lib")
  add_dir("/usr/local/opt/libpq/lib")
  -- Absolute paths only on macOS: dlopen() of a bare name searches the
  -- current directory there, so a libpq.5.dylib planted in a project would load.
  if mac then
    add_dir("/usr/local/lib")
  else
    for _, dir in ipairs({ "/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu", "/usr/lib64", "/usr/lib" }) do
      add_dir(dir)
    end
    -- ld.so's own search last (custom ld.so.conf directories).
    for _, name in ipairs(names) do
      add(name)
    end
  end
  return out
end

--- The loaded library and the path it came from, or nil when none loads.
function M.load()
  if lib == nil then
    lib = false
    setup_ffi()
    for _, path in ipairs(candidates()) do
      local ok, l = pcall(ffi.load, path)
      if
        ok
        and pcall(function()
          return l.PQconninfoParse, l.PQconninfoFree, l.PQfreemem, l.PQlibVersion
        end)
      then
        lib, libpath = l, path
        break
      end
    end
  end
  return lib or nil, lib and libpath or nil
end

--- Forget the loaded library, so the next call searches again (tests use it
--- after changing $ENVI_LIBPQ).
function M.reset()
  lib, libpath = nil, nil
end

--- libpq's recognized_connection_string(): psql expands a --dbname value only
--- when it starts with a URI designator or contains "=". Anything else is a
--- plain database name.
function M.is_connection_string(s)
  return type(s) == "string"
    and (s:sub(1, 13) == "postgresql://" or s:sub(1, 11) == "postgres://" or s:find("=", 1, true) ~= nil)
end

-- PQconninfoParse into a { keyword = value } table, or nil when libpq rejects
-- the string. The error message is freed unread.
local function parse(l, s)
  local err = ffi.new("char*[1]")
  local opts = l.PQconninfoParse(s, err)
  if opts == nil then
    if err[0] ~= nil then
      l.PQfreemem(err[0])
    end
    return nil
  end
  local t, i = {}, 0
  while opts[i].keyword ~= nil do
    if opts[i].val ~= nil then
      t[ffi.string(opts[i].keyword)] = ffi.string(opts[i].val)
    end
    i = i + 1
  end
  l.PQconninfoFree(opts)
  return t
end

--- How psql would read `s` as its --dbname operand:
---   "literal"  a plain database name; libpq expands nothing
---   "password" libpq reads a non-empty password from it
---   "invalid"  libpq rejects it, or its port isn't a number (list)
---   "clean"    a connection string without a password
---   "nolib"    it needs libpq, and libpq could not be loaded
function M.classify(s)
  if not M.is_connection_string(s) then
    return "literal"
  end
  local l = M.load()
  if not l then
    return "nolib"
  end
  local opts = parse(l, s)
  if not opts then
    return "invalid"
  end
  if opts.password and opts.password ~= "" then
    return "password"
  end
  if opts.port and not opts.port:match("^[%d,]*$") then
    return "invalid"
  end
  return "clean"
end

--- A string that is equal for two operands exactly when libpq reads them the
--- same way (same options, same values). For comparison only: it holds the
--- values, so never show it.
function M.meaning(s)
  if not M.is_connection_string(s) then
    return "literal\1" .. tostring(s)
  end
  local l = M.load()
  local opts = l and parse(l, s)
  if not opts then
    return l and "invalid" or "nolib"
  end
  local keys = vim.tbl_keys(opts)
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    table.insert(out, k .. "=" .. opts[k])
  end
  return table.concat(out, "\1")
end

--- libpq's version number (e.g. 180004), or nil when none loads.
function M.version()
  local l = M.load()
  return l and l.PQlibVersion() or nil
end

return M
