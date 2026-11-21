-- Connection strings for the tests of Dadbod's Postgres adapter
-- (dadbod-password.lua here, and the Dadbod headless suite in the envi
-- design folder). Each row is { id, string, anchor }. "S" stands for the
-- scheme; rows starting with "S:" run under both postgresql: and postgres:.
-- The password is synthetic.
--
-- label() computes each row's expected outcome from libpq itself (envi.libpq,
-- PQconninfoParse) applied to what psql would receive. The anchor, where
-- present, is the outcome checked by hand against libpq's documented grammar;
-- a row whose libpq label disagrees with its anchor fails the suite, so the
-- labels are not only self-referential.
--   PW   libpq reads a password from the string, an operand psql would get
--        from it, or its canonical form: refuse it
--   KV   key/value conninfo after the scheme (postgresql:host=... ...): never
--        connected through Dadbod, refused with a pointer to the URL form
--   BAD  libpq rejects what would run (or its port is not a number): refuse
--   OK   accept it
-- libpq reads secrets other than `password` too: sslpassword (the client
-- key's passphrase) and, from libpq 18, oauth_client_secret. Both count as a
-- password. libpq before 18 doesn't know oauth_* options and rejects them, so
-- those rows' anchors depend on the version: "PW>=18:BAD" means PW with
-- libpq 18 or later, BAD before.
local PW = "SYNTHETIC-PW-123"

local rows = {
  -- Userinfo, in every host form libpq accepts.
  { "userinfo, single host", "S://demo:" .. PW .. "@127.0.0.1:1/demo", "PW" },
  { "userinfo, encoded value", "S://demo:SYNTHETIC%2DPW%2D123@127.0.0.1:1/demo", "PW" },
  { "userinfo, empty user", "S://:" .. PW .. "@127.0.0.1:1/demo", "PW" },
  { "userinfo, multi-host", "S://demo:" .. PW .. "@127.0.0.1:1,127.0.0.2:2/demo", "PW" },
  { "userinfo, multi-host without ports", "S://demo:" .. PW .. "@h1,h2/demo", "PW" },
  { "userinfo, IPv6", "S://demo:" .. PW .. "@[::1]:1/demo", "PW" },
  { "userinfo, IPv6 multi-host", "S://demo:" .. PW .. "@[::1]:1,[::2]:2/demo", "PW" },
  { "userinfo, empty host", "S://demo:" .. PW .. "@/demo", "PW" },
  { "userinfo, encoded @ in the user", "S://demo%40x:" .. PW .. "@127.0.0.1:1/demo", "PW" },
  -- libpq looks for the userinfo `@` before the query: a `?` inside the
  -- password does not end it.
  { "userinfo with ?, single host", "S://demo:" .. PW .. "?x@127.0.0.1:1/demo", "PW" },
  { "userinfo with ?, multi-host", "S://demo:" .. PW .. "?x@127.0.0.1:1,127.0.0.2:2/demo", "PW" },
  { "userinfo with ?, empty host", "S://demo:" .. PW .. "?x@/demo", "PW" },
  { "userinfo with %3F", "S://demo:" .. PW .. "%3Fx@127.0.0.1:1/demo", "PW" },
  -- An unencoded `/` ends libpq's authority first, so the password lands in
  -- the port, which is not a number.
  { "userinfo with an unencoded slash", "S://demo:" .. PW .. "/x@127.0.0.1:1/demo", "BAD" },
  -- Query parameters: keys are case-sensitive and percent-decoded once.
  { "query password", "S://demo@127.0.0.1:1/demo?password=" .. PW, "PW" },
  { "query password, once-encoded key", "S://demo@127.0.0.1:1/demo?pass%77ord=" .. PW, "PW" },
  { "query password, fully encoded key", "S://demo@127.0.0.1:1/demo?%70%61%73%73%77%6F%72%64=" .. PW, "PW" },
  {
    "query password between repeated keys",
    "S://demo@127.0.0.1:1/demo?sslmode=disable&password=" .. PW .. "&sslmode=require",
    "PW",
  },
  { "query password, multi-host, encoded key", "S://demo@127.0.0.1:1,127.0.0.2:2/demo?pass%77ord=" .. PW, "PW" },
  -- %57 is "W": "passWord" is not a libpq keyword (keys are case-sensitive).
  { "query passWord, multi-host", "S://demo@127.0.0.1:1,127.0.0.2:2/demo?pass%57ord=" .. PW, "BAD" },
  { "query password, empty host", "S://?password=" .. PW, "PW" },
  { "query password beside host", "S:///demo?host=127.0.0.1&password=" .. PW, "PW" },
  { "query password, mixed-case key", "S://demo@127.0.0.1:1/demo?PassWord=" .. PW, "BAD" },
  { "query password, encoded mixed-case key", "S://demo@127.0.0.1:1/demo?P%61sS%57oRd=" .. PW, "BAD" },
  { "query password, empty value", "S://demo@127.0.0.1:1/demo?password=", "OK" },
  { "userinfo, empty password", "S://demo:@127.0.0.1:1/demo", "OK" },
  -- libpq has no fragments: everything after `?` is the query.
  { "fragment then ?password", "S://demo@127.0.0.1:1/demo#?password=" .. PW, "PW" },
  { "fragment, text, then ?password", "S://demo@127.0.0.1:1/demo#x?password=" .. PW, "PW" },
  -- A service with parameters.
  { "service and password", "S:///?service=dadbod_demo&password=" .. PW, "PW" },
  { "service and encoded password key", "S:///?service=dadbod_demo&pa%73sword=" .. PW, "PW" },
  { "service and application_name", "S:///?service=dadbod_demo&application_name=envi", "OK" },
  { "service and connect_timeout", "S:///?service=dadbod_demo&connect_timeout=1", "OK" },
  -- Data that only looks like a password keyword.
  { "service, password=... as data", "S:///?service=dadbod_demo&application_name=password%3D" .. PW, "OK" },
  { "double-encoded key as data", "S://demo@127.0.0.1:1/demo?application_name=pass%2577ord%3D" .. PW, "OK" },
  { "encoded ; and @ in a value", "S://demo@127.0.0.1:1/demo?application_name=" .. PW .. "%3Bright%40end", "OK" },
  { "@ in the dbname, no userinfo", "S://127.0.0.1:1/demo@" .. PW, "OK" },
  { "dbname that reads password=x", "S://demo@127.0.0.1:1/password=x", "OK" },
  { "user named password", "S://password@127.0.0.1:1/demo", "OK" },
  {
    "nested URI in a dbname parameter",
    "S://demo@127.0.0.1:1/demo?dbname=postgresql%3A%2F%2Fdemo%3A" .. PW .. "%40h%2Fx",
    "OK",
  },
  { "conninfo text in the path", "S:///host=127.0.0.1%20password=" .. PW, "OK" },
  { "encoded conninfo text in the path", "S:///host=127.0.0.1%20password%3D" .. PW, "OK" },
  { "options value naming password", "S://demo@127.0.0.1:1/demo?options=-c%20search_path%3Dpassword" },
  { "application_name with spaces and =", "S://demo@127.0.0.1:1/demo?application_name=my%20password%20=%20none" },
  -- Password-free forms that must keep working.
  { "single host", "S://demo@127.0.0.1:1/demo", "OK" },
  { "empty user", "S://@127.0.0.1:1/demo", "OK" },
  { "multi-host", "S://demo@127.0.0.1:1,127.0.0.2:2/demo", "OK" },
  { "multi-host without ports", "S://demo@h1,h2/demo", "OK" },
  { "IPv6", "S://demo@[::1]:1/demo", "OK" },
  { "IPv6 multi-host", "S://demo@[::1]:1,[::2]:2/demo", "OK" },
  { "empty host", "S://demo@/demo", "OK" },
  { "sslmode", "S://demo@127.0.0.1:1/demo?sslmode=disable", "OK" },
  { "repeated sslmode", "S://demo@127.0.0.1:1/demo?sslmode=disable&sslmode=require", "OK" },
  { "once-encoded key", "S://demo@127.0.0.1:1/demo?applic%61tion_name=x", "OK" },
  { "fully encoded key", "S://demo@127.0.0.1:1/demo?%73%73%6C%6D%6F%64%65=disable", "OK" },
  { "passfile parameter", "S://demo@127.0.0.1:1/demo?passfile=/tmp/pgpass", "OK" },
  { "mixed-case passfile key", "S://demo@127.0.0.1:1/demo?PassFile=x", "BAD" },
  { "target_session_attrs after a host list", "S://demo@h1,h2/demo?target_session_attrs=any", "OK" },
  { "short dbname", "S:demo", "OK" },
  { "triple-slash dbname", "S:///demo", "OK" },
  { "fragment", "S://demo@127.0.0.1:1/demo#frag" },
  { "plus sign in a value", "S://demo@127.0.0.1:1/demo?application_name=a+b" },
  { "non-numeric port", "S://demo@127.0.0.1:abc/demo", "BAD" },
  -- Key/value conninfo after the scheme: refused whatever it holds.
  { "kv with password", "S:host=127.0.0.1 port=1 password=" .. PW, "KV" },
  { "kv spaced and quoted password", "S:host=127.0.0.1 PASSWORD = '" .. PW .. "'", "KV" },
  { "kv encoded key", "S:host=127.0.0.1 pass%77ord=" .. PW, "KV" },
  { "kv VT before =", "S:host=127.0.0.1 password\v=" .. PW, "KV" },
  { "kv FF before =", "S:host=127.0.0.1 password\f=" .. PW, "KV" },
  { "kv CR before =", "S:host=127.0.0.1 password\r=" .. PW, "KV" },
  { "kv LF before =", "S:host=127.0.0.1 password\n=" .. PW, "KV" },
  { "kv space before =", "S:host=127.0.0.1 password =" .. PW, "KV" },
  { "kv tab before =", "S:host=127.0.0.1 password\t=" .. PW, "KV" },
  { "kv VT separator", "S:host=127.0.0.1\vpassword=" .. PW, "KV" },
  { "kv service with password", "S:service=dadbod_demo password=" .. PW, "KV" },
  { "kv dbname and password", "S:dbname=demo password=" .. PW, "KV" },
  { "kv leading space", "S: password=" .. PW, "KV" },
  { "kv quoted keyword", "S:host=127.0.0.1 'password'=" .. PW, "KV" },
  { "kv quoted data", "S:host=127.0.0.1 application_name='x password=" .. PW .. "'", "KV" },
  { "kv backslash data", "S:host=127.0.0.1 application_name=a\\ password=" .. PW, "KV" },
  { "kv nested URI dbname", "S:host=127.0.0.1 dbname=postgresql://demo:" .. PW .. "@h/x", "KV" },
  { "kv nested kv dbname", "S:host=127.0.0.1 dbname='host=h password=" .. PW .. "'", "KV" },
  { "kv without password", "S:host=127.0.0.1 port=1 dbname=demo", "KV" },
  { "kv quoted value", "S:host=127.0.0.1 application_name = 'envi app'", "KV" },
  { "kv service", "S:service=dadbod_demo connect_timeout=1", "KV" },
  { "kv value with =", "S:host=127.0.0.1 application_name=password=x", "KV" },
  -- Opaque forms with a query: upstream rewrites them to postgresql:///..., so
  -- they are URLs, not key/value conninfo.
  { "opaque dbname with query", "S:demo?sslmode=disable", "OK" },
  { "opaque service query", "S:?service=dadbod_demo", "OK" },
  { "opaque single-slash with query", "S:/demo?application_name=x", "OK" },
  { "opaque query password", "S:demo?password=" .. PW, "PW" },
  { "opaque service and password", "S:?service=dadbod_demo&password=" .. PW, "PW" },
  { "opaque query, conninfo text in a value", "S:demo?application_name=x password=" .. PW },
  { "opaque kv before a query", "S:host=h password=" .. PW .. "?sslmode=disable", "KV" },
  -- Not a libpq URI designator (case-sensitive): psql reads a literal name.
  -- Other libpq secrets, refused like password (owner ruling F10).
  { "query sslpassword", "S://demo@127.0.0.1:1/demo?sslpassword=" .. PW, "PW" },
  { "query sslpassword, once-encoded key", "S://demo@127.0.0.1:1/demo?ss%6Cpassword=" .. PW, "PW" },
  { "query sslpassword, multi-host", "S://demo@127.0.0.1:1,127.0.0.2:2/demo?sslpassword=" .. PW, "PW" },
  { "short URL sslpassword", "S:demo?sslpassword=" .. PW, "PW" },
  { "short URL service, encoded sslpassword key", "S:?service=dadbod_demo&ssl%70assword=" .. PW, "PW" },
  { "query sslpassword, empty value", "S://demo@127.0.0.1:1/demo?sslpassword=", "OK" },
  { "query sslkey path, no secret", "S://demo@127.0.0.1:1/demo?sslkey=/tmp/client.key", "OK" },
  { "short URL sslcert path, no secret", "S:demo?sslcert=/tmp/client.crt", "OK" },
  { "query oauth_client_secret", "S://demo@127.0.0.1:1/demo?oauth_client_secret=" .. PW, "PW>=18:BAD" },
  {
    "query oauth_client_secret, once-encoded key",
    "S://demo@127.0.0.1:1/demo?oauth%5Fclient%5Fsecret=" .. PW,
    "PW>=18:BAD",
  },
  { "short URL oauth_client_secret", "S:demo?oauth_client_secret=" .. PW, "PW>=18:BAD" },
  {
    "short URL service, encoded oauth_client_secret key",
    "S:?service=dadbod_demo&oauth_client_%73ecret=" .. PW,
    "PW>=18:BAD",
  },
  { "query oauth_client_id, no secret", "S://demo@127.0.0.1:1/demo?oauth_client_id=envi", "OK>=18:BAD" },
  { "upper-case scheme with userinfo", "POSTGRESQL://demo:" .. PW .. "@127.0.0.1:1/demo", "OK" },
}

local M = { password = PW, rows = rows }

--- Each row as { id, scheme, url, anchor }, under both schemes where it
--- starts with "S:".
function M.cases()
  local out = {}
  for _, row in ipairs(rows) do
    if vim.startswith(row[2], "S:") then
      for _, scheme in ipairs({ "postgresql", "postgres" }) do
        table.insert(out, { row[1], scheme, scheme .. row[2]:sub(2), row[3] })
      end
    else
      table.insert(out, { row[1], "-", row[2], row[3] })
    end
  end
  return out
end

--- Key/value conninfo after a Postgres scheme (the adapter's policy, not
--- libpq's): the part after the scheme doesn't start with // and holds = or
--- whitespace.
function M.is_keyword_value(url)
  local rest = url:match("^[Pp][Oo][Ss][Tt][Gg][Rr][Ee][Ss]:(.*)$")
    or url:match("^[Pp][Oo][Ss][Tt][Gg][Rr][Ee][Ss][Qq][Ll]:(.*)$")
  return rest ~= nil and rest:sub(1, 2) ~= "//" and rest:match("^[^?#]*"):find("[=%s]") ~= nil
end

local function is_uri(s)
  return s:sub(1, 13) == "postgresql://" or s:sub(1, 11) == "postgres://"
end

--- The --dbname operand vim-dadbod's own Postgres adapter builds for a URL.
function M.operand(url)
  local ok, cmd = pcall(vim.fn["db#adapter#postgresql#interactive"], url)
  return ok and cmd[#cmd] or nil
end

--- vim-dadbod's own canonical form of a URL (envi's adapter switched off).
function M.upstream_resolve(url)
  local a, b = vim.g.db_adapter_postgresql, vim.g.db_adapter_postgres
  vim.g.db_adapter_postgresql, vim.g.db_adapter_postgres = nil, nil
  local ok, canon = pcall(vim.fn["db#resolve"], url)
  vim.g.db_adapter_postgresql, vim.g.db_adapter_postgres = a, b
  return ok and canon or nil
end

--- The expected outcome for a URL, from libpq: see the header.
function M.label(url)
  if M.is_keyword_value(url) then
    return "KV"
  end
  local pq = require("envi.libpq")
  local raw_op = M.operand(url)
  local canon = M.upstream_resolve(url)
  local canon_op = canon and M.operand(canon) or nil
  -- false, not nil, for an absent entry: ipairs stops at the first nil.
  for _, s in ipairs({ is_uri(url) and url or false, raw_op or false, canon_op or false }) do
    if s and pq.classify(s) == "password" then
      return "PW"
    end
  end
  if not canon then
    return "BAD"
  end
  -- What runs: the canonical operand, unless canonicalization changed
  -- libpq's reading of a URI, in which case the original's.
  local run = canon_op
  if is_uri(url) and pq.meaning(canon_op) ~= pq.meaning(raw_op) then
    run = raw_op
  end
  local v = pq.classify(run)
  return (v == "clean" or v == "literal") and "OK" or "BAD"
end

return M
