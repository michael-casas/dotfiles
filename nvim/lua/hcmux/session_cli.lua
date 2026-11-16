-- nvim-session's non-interactive commands, run as
--   nvim --clean --headless -l session_cli.lua <command> [args]
-- (no config, no plugins: fast). See nvim/bin/nvim-session.
local here = debug.getinfo(1, "S").source:sub(2):match("(.*)/hcmux/session_cli%.lua$")
package.path = here .. "/?.lua;" .. here .. "/?/init.lua;" .. package.path

local session = require("hcmux.session")
local cmd = arg[1] or "ls"

local function out(s)
  io.stdout:write(s, "\n")
end

local function age(ms)
  if not ms or ms == 0 then
    return "never"
  end
  local s = os.time() - math.floor(ms / 1000)
  if s < 60 then
    return "now"
  elseif s < 3600 then
    return math.floor(s / 60) .. "m ago"
  elseif s < 86400 then
    return math.floor(s / 3600) .. "h ago"
  end
  return math.floor(s / 86400) .. "d ago"
end

if cmd == "ls" or cmd == "list" then
  local list = session.list()
  if #list == 0 then
    return out("no sessions yet (run nvim in a folder, or nvim-session attach <name>)")
  end
  local home = os.getenv("HOME") or ""
  out(("%-24s %-9s %-6s %-9s %s"):format("NAME", "SAVED", "TERMS", "ATTACHED", "FOLDER"))
  for _, s in ipairs(list) do
    local attached = s.attached and ("pid " .. tostring(s.holder.pid)) or "-"
    local root = (s.root or ""):gsub("^" .. vim.pesc(home), "~")
    out(("%-24s %-9s %-6d %-9s %s"):format(s.name, age(s.saved_ms), #session.terminals(s.name), attached, root))
  end
elseif cmd == "name" then
  -- the session name `attach` would use: arg, or this folder's default
  out(arg[2] and arg[2] ~= "" and session.sanitize(arg[2]) or session.default_name())
elseif cmd == "root" then
  local value = session.read(session.sanitize(arg[2] or ""))
  out(type(value) == "table" and value.root or "")
elseif cmd == "kill" or cmd == "rm" then
  local name = arg[2] and session.sanitize(arg[2])
  if not name then
    out("usage: nvim-session kill <name>")
    os.exit(2)
  end
  local value = session.read(name)
  if not value then
    out("no session " .. name)
    os.exit(3)
  end
  if type(value) == "table" and session.holder_alive(value.holder) and arg[3] ~= "-f" then
    out(("%s is attached (pid %s); quit that nvim first, or add -f"):format(name, tostring(value.holder.pid)))
    os.exit(9)
  end
  local n = #session.terminals(name)
  session.kill(name)
  out(("ended %s and %d terminal(s)"):format(name, n))
else
  out("unknown command: " .. cmd)
  os.exit(2)
end
