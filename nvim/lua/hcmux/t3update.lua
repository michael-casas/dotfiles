-- hcmux.t3update: T3 server/update state, and the desktop's own update flow.
--
--   :T3Status    one async notice: reachability, runtime, update marker, clients
--   :T3Update    preflight, then click the desktop's "Check for Updates…" menu
--                and watch the desktop's update marker until the new server is up
--   :T3Update!   also click the desktop dialog's Download / Restart button
--
-- envi follows the desktop's protocol and never stands in for it: it never
-- writes or removes the update markers, never stops or restarts the server,
-- and never runs `t3 update` (that is for the CLI/service install).
local M = {}

M.config = {
  -- The desktop app whose own menu starts the update. A Stable app would get
  -- its own entry here. The menu item is matched by prefix, so both
  -- "Check for Updates…" (U+2026, what macOS shows) and "Check for Updates..."
  -- (the label in the desktop's source) match.
  app = {
    name = "T3 Code (Nightly)", -- `tell application`
    process = "T3 Code (Nightly)", -- System Events process
    menu = "T3 Code (Nightly)", -- menu bar item holding the item
    item = "Check for Updates", -- menu item prefix
  },
  probe_timeout_ms = 2000,
  poll_ms = 2000, -- fallback check next to the fs watcher
  start_timeout_ms = 180000, -- no marker this long after the trigger: none started
  timeout_ms = 600000, -- the whole watch
}

local function notify(text, level)
  vim.notify("T3: " .. text, level or vim.log.levels.INFO, { title = "T3" })
end

-- ── state readers (never write) ───────────────────────────────────────────

local function home()
  local env = vim.env.T3CODE_HOME
  return (env and env ~= "") and env or vim.fs.joinpath(vim.uv.os_homedir(), ".t3")
end

function M.paths()
  local base = home()
  return {
    runtime_dir = vim.fs.joinpath(base, "runtime"),
    marker = vim.fs.joinpath(base, "runtime", "desktop-update-in-progress"),
    server = vim.fs.joinpath(base, "userdata", "server-runtime.json"),
  }
end

local function base_url()
  local env = vim.env.T3_URL
  return ((env and env ~= "") and env or "http://127.0.0.1:3773"):gsub("/+$", "")
end

local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return text
end

local function decode(text)
  local ok, value = pcall(vim.json.decode, text or "")
  return ok and type(value) == "table" and value or nil
end

-- Only the non-secret fields; nil when absent, false when unreadable.
local function runtime()
  local text = read(M.paths().server)
  if not text then
    return nil
  end
  local value = decode(text)
  if not value then
    return false
  end
  return { pid = tonumber(value.pid), version = value.serverVersion, started = value.startedAt }
end

-- nil when absent, else { left = seconds or nil }.
local function marker()
  local text = read(M.paths().marker)
  if not text then
    return nil
  end
  local value = decode(text)
  local expires = value and tonumber(value.expiresAt)
  return { left = expires and math.floor((expires - os.time() * 1000) / 1000) or nil }
end

-- cb(up): the server answers its environment endpoint within the timeout.
local function probe(cb)
  local secs = math.max(1, math.ceil(M.config.probe_timeout_ms / 1000))
  local argv = {
    "curl",
    "-sS",
    "-o",
    "/dev/null",
    "-w",
    "%{http_code}",
    "-m",
    tostring(secs),
    base_url() .. "/.well-known/t3/environment",
  }
  local ok = pcall(vim.system, argv, { text = true, timeout = M.config.probe_timeout_ms + 1000 }, function(res)
    vim.schedule(function()
      cb(res.code == 0 and vim.trim(res.stdout or "") == "200")
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb(false)
    end)
  end
end

-- envi T3 client buffers (t3.lua marks them) and their core terminal facts.
local function clients()
  local core = package.loaded["hcmux.core"] or {}
  local list = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].hcmux_float == "t3" then
      local addr = vim.b[buf].hcmux_addr
      local fact = addr and core.terms and core.terms[addr]
      list[#list + 1] = {
        name = (fact and fact.name) or addr or vim.api.nvim_buf_get_name(buf),
        live = fact ~= nil and fact.state == "live",
      }
    end
  end
  return list
end

local function marker_text(m)
  if not m then
    return "no update in progress"
  elseif m.left == nil then
    return "update marker present (unreadable)"
  elseif m.left < 0 then
    return ("update marker expired %d s ago"):format(-m.left)
  end
  return ("update in progress (%d s left)"):format(m.left)
end

function M.status()
  probe(function(up)
    local parts = { up and "server up" or ("server unreachable at " .. base_url()) }
    local rt = runtime()
    if rt == nil then
      parts[#parts + 1] = "no server-runtime.json"
    elseif rt == false then
      parts[#parts + 1] = "server-runtime.json unreadable"
    else
      parts[#parts + 1] = ("v%s pid %s since %s"):format(rt.version or "?", rt.pid or "?", rt.started or "?")
    end
    parts[#parts + 1] = marker_text(marker())
    local list, live = clients(), 0
    for _, c in ipairs(list) do
      live = live + (c.live and 1 or 0)
    end
    parts[#parts + 1] = ("%d clients (%d live)"):format(#list, live)
    notify(table.concat(parts, " · "))
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("T3Status", M.status, { desc = "T3 server, update and client state" })
end

return M
