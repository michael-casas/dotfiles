-- Connection-string shapes libpq accepts, each as { shape, with a password,
-- password-free twin }. "S" stands for the scheme (postgresql or postgres).
-- The password is synthetic. Used by dadbod-password.lua and by the Dadbod
-- headless suite in the envi design folder.
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
  {
    "userinfo password with an unencoded slash",
    "S://demo:" .. PW .. "/x@127.0.0.1:1/demo",
    "S://demo@127.0.0.1:1/demo",
  },
  {
    "key/value service with a password",
    "S:service=dadbod_demo password=" .. PW,
    "S:service=dadbod_demo connect_timeout=1",
  },
  {
    "URI dbname parameter holding a URI with a password",
    "S://demo@127.0.0.1:1/demo?dbname=postgresql%3A%2F%2Fdemo%3A" .. PW .. "%40h%2Fx",
    "S://demo@127.0.0.1:1/demo?dbname=demo",
  },
  {
    "conninfo dbname holding conninfo with a password",
    "S:host=127.0.0.1 dbname='host=h password=" .. PW .. "'",
    "S:host=127.0.0.1 dbname='host=h port=1'",
  },
}

return { password = PW, shapes = shapes }
