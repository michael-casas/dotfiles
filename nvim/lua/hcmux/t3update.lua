-- hcmux.t3update: T3 server/update state, and the desktop's own update flow.
--
--   :T3Status    one async notice: reachability, runtime, update marker, clients
--   :T3Update    preflight, then click the desktop's "Check for Updates…" menu
--                and watch the desktop's update marker until the new server is
--                up; the user answers the desktop's own dialogs
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
  local env = vim.trim(vim.env.T3CODE_HOME or "")
  return env ~= "" and env or vim.fs.joinpath(vim.uv.os_homedir(), ".t3")
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

local function decode(text)
  local ok, value = pcall(vim.json.decode, text or "")
  return ok and type(value) == "table" and value or nil
end

local function now_ms()
  local sec, usec = vim.uv.gettimeofday()
  return sec * 1000 + math.floor(usec / 1000)
end

local function missing(err)
  return type(err) == "string" and err:match("^ENOENT") ~= nil
end

-- Bounded async read: cb(text, err) on the event loop (fast context). The
-- state records are small; anything larger fails to decode as unreadable.
local MAX_READ = 65536
local function read_file(path, cb)
  local uv = vim.uv
  uv.fs_open(path, "r", 420, function(err, fd)
    if not fd then
      return cb(nil, err or "open failed")
    end
    uv.fs_read(fd, MAX_READ, 0, function(rerr, data)
      uv.fs_close(fd, function() end)
      cb(rerr == nil and data or nil, rerr)
    end)
  end)
end

-- Only the non-secret fields; nil when absent, false when unreadable.
local function read_runtime(cb)
  read_file(M.paths().server, function(text, err)
    if missing(err) then
      return cb(nil)
    end
    local value = decode(text)
    if not value then
      return cb(false)
    end
    cb({
      pid = type(value.pid) == "number" and value.pid or nil,
      port = type(value.port) == "number" and value.port or nil,
      version = type(value.serverVersion) == "string" and value.serverVersion or nil,
      started = type(value.startedAt) == "string" and value.startedAt or nil,
    })
  end)
end

-- The desktop's marker contract (its own waiters use the same TTL):
-- numeric {startedAt, expiresAt} is in progress until expiresAt; malformed or
-- unreadable is in progress until mtime + 60 s; expired counts as absent.
-- cb(nil) absent, cb({ left_ms }) in progress, cb({ ago_ms }) expired.
local TTL_MS = 60000
local function read_marker(cb)
  local path = M.paths().marker
  vim.uv.fs_stat(path, function(serr, stat)
    if not stat then
      return cb(nil) -- absent (or not even stat-able: nothing to honour)
    end
    read_file(path, function(text, err)
      if missing(err) then
        return cb(nil) -- removed between stat and read
      end
      local value = decode(text)
      local deadline
      if value and type(value.startedAt) == "number" and type(value.expiresAt) == "number" then
        deadline = value.expiresAt
      else
        deadline = stat.mtime.sec * 1000 + math.floor(stat.mtime.nsec / 1e6) + TTL_MS
      end
      local left = deadline - now_ms()
      cb(left > 0 and { left_ms = left } or { ago_ms = -left })
    end)
  end)
end

-- cb({ marker, runtime }) on the main loop, after both async reads.
local function read_state(cb)
  local state, pending = {}, 2
  local function done()
    pending = pending - 1
    if pending == 0 then
      vim.schedule(function()
        cb(state)
      end)
    end
  end
  read_marker(function(m)
    state.marker = m
    done()
  end)
  read_runtime(function(rt)
    state.runtime = rt
    done()
  end)
end

local function in_progress(m)
  return m ~= nil and m.left_ms ~= nil
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
  elseif m.ago_ms then
    return ("no update in progress (marker expired %d s ago)"):format(math.floor(m.ago_ms / 1000))
  end
  return ("update in progress (%d s left)"):format(math.ceil(m.left_ms / 1000))
end

-- Process liveness only (the herdr-core terminal); websocket state is not
-- visible from here.
local function clients_text(list)
  local running = 0
  for _, c in ipairs(list) do
    running = running + (c.live and 1 or 0)
  end
  return ("%d client buffers, %d client processes running"):format(#list, running)
end

function M.status()
  probe(function(up)
    read_state(function(state)
      local parts = { up and "server up" or ("server unreachable at " .. base_url()) }
      local rt = state.runtime
      if rt == nil then
        parts[#parts + 1] = "no server-runtime.json"
      elseif rt == false then
        parts[#parts + 1] = "server-runtime.json unreadable"
      else
        parts[#parts + 1] = ("v%s pid %s since %s"):format(rt.version or "?", rt.pid or "?", rt.started or "?")
      end
      parts[#parts + 1] = marker_text(state.marker)
      parts[#parts + 1] = clients_text(clients())
      notify(table.concat(parts, " · "))
    end)
  end)
end

-- ── :T3Update ─────────────────────────────────────────────────────────────
-- preflight -> (confirm) -> trigger -> watch -> done. One run at a time;
-- M.run holds it, and every exit goes through finish(), which closes the
-- watch handles.

-- Clicks the app menu's "Check for Updates…" item. Config values arrive as
-- argv, never spliced into the source. The desktop then shows its own dialogs.
local SCRIPT = [[
on run argv
  set {appName, procName, menuName, itemPrefix} to argv
  tell application appName to activate
  tell application "System Events"
    repeat 40 times
      if exists process procName then exit repeat
      delay 0.25
    end repeat
    tell process procName
      set frontmost to true
      repeat with menuItem in menu items of menu 1 of menu bar item menuName of menu bar 1
        set itemName to name of menuItem
        if itemName is not missing value and itemName starts with itemPrefix then
          click menuItem
          return "clicked " & itemName
        end if
      end repeat
    end tell
  end tell
  error "T3UPD_NO_MENU" number 9001
end run]]

function M.trigger_argv()
  local app = M.config.app
  return { "osascript", "-e", SCRIPT, app.name, app.process, app.menu, app.item }
end

-- One actionable message per osascript failure; the caller never retries.
local function osascript_error(stderr)
  local host = (vim.env.TERM_PROGRAM or "your terminal") .. " (or Herdr)"
  local app = M.config.app
  if stderr:find("-1743", 1, true) or stderr:find("Not authorized to send Apple events", 1, true) then
    return ("Automation permission needed: System Settings → Privacy & Security → Automation → %s → System Events, then run :T3Update again"):format(
      host
    )
  elseif
    stderr:find("-25211", 1, true)
    or stderr:find("-1719", 1, true)
    or stderr:find("assistive access", 1, true)
  then
    return ("Accessibility permission needed: System Settings → Privacy & Security → Accessibility → enable %s, then run :T3Update again"):format(
      host
    )
  elseif stderr:find("T3UPD_NO_MENU", 1, true) then
    return ('menu item "%s…" not found in the "%s" menu of %s'):format(app.item, app.menu, app.process)
  end
  local line = vim.split(vim.trim(stderr), "\n")[1] or ""
  return ("could not open %s's update menu: %s"):format(app.name, line ~= "" and line or "osascript failed")
end

local function finish(run, text, level)
  if M.run ~= run then
    return
  end
  M.run = nil
  for _, handle in ipairs({ run.timer, run.fs }) do
    if not handle:is_closing() then
      handle:stop()
      handle:close()
    end
  end
  if text then
    notify(text, level)
  end
end

local function report_clients()
  local running, gone = {}, {}
  for _, c in ipairs(clients()) do
    table.insert(c.live and running or gone, c.name)
  end
  local text = ("%d client process%s running"):format(#running, #running == 1 and "" or "es")
  if #gone > 0 then
    text = text .. "; not running: " .. table.concat(gone, ", ") .. ". :T3Restart restarts one"
  else
    text = text .. ". A client that stays stuck: :T3Restart"
  end
  notify(text)
end

local function succeed(run, rt)
  local old, new = run.old.version or "?", rt.version or "?"
  finish(
    run,
    old == new and ("T3 restarted (same version %s)"):format(new) or ("T3 updated: %s → %s"):format(old, new)
  )
  report_clients()
end

local observe
local function check(run)
  if M.run ~= run or run.probing then
    return
  end
  run.probing = true
  read_state(function(state)
    run.probing = false
    if M.run == run then
      observe(run, state)
    end
  end)
end

function observe(run, state)
  local elapsed = vim.uv.now() - run.started
  local m = state.marker
  local updating = in_progress(m)
  if updating and not run.saw then
    run.saw = true
    notify("T3 is updating…")
  end
  local rt = not updating and state.runtime
  local moved = rt and rt.pid and rt.pid ~= run.old.pid
  if moved or (run.saw and m and m.ago_ms and not run.stalled) then
    -- Removed or expired: success needs a new pid and a reachable server;
    -- an expired marker over the old, unreachable server is a stall.
    run.probing = true
    probe(function(up)
      run.probing = false
      if M.run ~= run then
        return
      elseif moved and up then
        return succeed(run, rt)
      elseif not moved and not up then
        run.stalled = true
        notify(
          "update stalled: the marker expired, the server is still pid "
            .. run.old.pid
            .. " and unreachable; still watching",
          vim.log.levels.WARN
        )
      end
      check(run)
    end)
    return
  end
  if elapsed >= M.config.timeout_ms then
    finish(run, "update watch timed out; :T3Status shows the current state", vim.log.levels.WARN)
  elseif not run.saw and not moved and elapsed >= M.config.start_timeout_ms then
    finish(
      run,
      "no update started (Later, already up to date, or only downloaded: run :T3Update again to restart into it)"
    )
  end
end

local function watch(run)
  run.started = vim.uv.now()
  run.timer = vim.uv.new_timer()
  run.timer:start(
    M.config.poll_ms,
    M.config.poll_ms,
    vim.schedule_wrap(function()
      check(run)
    end)
  )
  -- The fs watcher only reacts sooner; the timer alone is correct. A missing
  -- runtime dir is left alone (envi never creates the desktop's files).
  run.fs = vim.uv.new_fs_event()
  pcall(run.fs.start, run.fs, M.paths().runtime_dir, {}, function()
    vim.schedule(function()
      check(run)
    end)
  end)
end

local function trigger(run)
  local ok = pcall(vim.system, M.trigger_argv(), { text = true, timeout = 30000 }, function(res)
    vim.schedule(function()
      if M.run ~= run then
        return
      elseif res.code ~= 0 then
        M.run = nil
        return notify(osascript_error(res.stderr or ""), vim.log.levels.ERROR)
      end
      notify(
        ("opened %s → Check for Updates; answer its dialog (Download / Restart / Later). Watching…"):format(
          M.config.app.name
        )
      )
      watch(run)
    end)
  end)
  if not ok then
    M.run = nil
    notify("could not run osascript", vim.log.levels.ERROR)
  end
end

-- nil when the sidebar feed has not delivered a snapshot.
local function working()
  local side = package.loaded["hcmux.t3side"] or select(2, pcall(require, "hcmux.t3side"))
  if type(side) ~= "table" or not side.snapshot then
    return nil
  end
  local snap, err = side.snapshot()
  if err or snap.type ~= "snapshot" then
    return nil
  end
  local n = 0
  for _, t in ipairs(snap.threads or {}) do
    n = n + (t.status == "working" and 1 or 0)
  end
  return n
end

-- Like the T3 Ctrl-C confirm: one key, only "y" continues.
local function confirm(question)
  vim.api.nvim_echo({ { "T3: " .. question .. " Update anyway? y/n", "WarningMsg" } }, false, {})
  vim.cmd.redraw()
  local ok, key = pcall(vim.fn.getcharstr)
  vim.api.nvim_echo({ { "" } }, false, {})
  return ok and key == "y"
end

local preflight
function M.update()
  if M.run then
    return notify("T3Update already running", vim.log.levels.WARN)
  end
  local run = {}
  M.run = run
  read_state(function(first)
    if M.run ~= run then
      return
    elseif in_progress(first.marker) then
      M.run = nil
      return notify(
        ("update already in progress (%d s left)"):format(math.ceil(first.marker.left_ms / 1000)),
        vim.log.levels.WARN
      )
    end
    probe(function(up)
      read_state(function(state)
        preflight(run, up, state)
      end)
    end)
  end)
end

function preflight(run, up, state)
  if M.run ~= run then
    return
  elseif not up then
    M.run = nil
    return notify("server unreachable at " .. base_url() .. "; not starting an update", vim.log.levels.ERROR)
  end
  local rt = state.runtime
  if not (rt and rt.pid) then
    M.run = nil
    return notify("cannot read the server's pid from server-runtime.json; not starting an update", vim.log.levels.ERROR)
  end
  run.old = rt
  local n = working()
  local question = n == nil and "running threads unknown (sidebar feed not running)."
    or n > 0 and ("%d running thread(s) will be interrupted."):format(n)
  if question and not confirm(question) then
    M.run = nil
    return notify("update cancelled")
  end
  trigger(run)
end

function M.current()
  return M.run
end

function M.setup()
  vim.api.nvim_create_user_command("T3Status", M.status, { desc = "T3 server, update and client state" })
  vim.api.nvim_create_user_command("T3Update", M.update, { desc = "Start T3 Code's own update flow and watch it" })
end

return M
