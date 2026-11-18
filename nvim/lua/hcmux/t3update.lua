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

-- The probe destination only. Notices never show it: T3_URL may carry
-- credentials (userinfo, query).
local function base_url()
  local env = vim.env.T3_URL
  return ((env and env ~= "") and env or "http://127.0.0.1:3773"):gsub("/+$", "")
end

-- The endpoint's port (explicit, or the scheme default), ignoring userinfo.
local function url_port()
  local scheme, rest = base_url():match("^(%a[%w+.-]*)://(.*)$")
  if not scheme then
    return nil
  end
  local authority = (rest:match("^[^/?#]*") or ""):gsub("^.*@", "")
  local port = authority:match("^%[.*%]:(%d+)$") or authority:match("^[^%[:]*:(%d+)$")
  return tonumber(port) or ({ http = 80, https = 443 })[scheme:lower()]
end

-- The supported flow is the local desktop: the endpoint and the desktop home
-- describe one backend. A different runtime port means they do not.
local function disagreement(rt)
  local port = url_port()
  if rt and rt.port and port and rt.port ~= port then
    return ("endpoint and desktop home disagree (port %d vs %d)"):format(port, rt.port)
  end
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
-- state records are small: a file larger than MAX_READ is unreadable, never
-- a decoded prefix.
local MAX_READ = 65536
local function read_file(path, cb)
  local uv = vim.uv
  uv.fs_open(path, "r", 420, function(err, fd)
    if not fd then
      return cb(nil, err or "open failed")
    end
    uv.fs_read(fd, MAX_READ + 1, 0, function(rerr, data)
      uv.fs_close(fd, function() end)
      if data and #data > MAX_READ then
        return cb(nil, "EFBIG: larger than a state record")
      end
      cb(rerr == nil and data or nil, rerr)
    end)
  end)
end

-- Only the non-secret fields; nil when absent, false when unreadable.
local function read_runtime(path, cb)
  read_file(path, function(text, err)
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
-- Paths are resolved on the main loop by the caller (vim.env is not
-- available in libuv callbacks).
local function read_marker(path, cb)
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

-- One observation to decide on: [probe] -> marker -> runtime -> marker. The
-- marker is read last, and also before the runtime, so a marker that appears
-- while the runtime is read is seen: `busy` is the in-progress marker either
-- read saw. Every async stage returns through live(), so once the run ended
-- or its deadline passed nothing further runs or prints. cb runs on the main
-- loop with { up, runtime, marker, busy, expired }.
local function observe(run, with_probe, cb)
  local obs, paths = {}, M.paths()
  local function live()
    return run == nil or (M.run == run and not (run.deadline_at and vim.uv.now() >= run.deadline_at))
  end
  local function sample()
    read_marker(paths.marker, function(first)
      if not live() then
        return
      end
      read_runtime(paths.server, function(rt)
        if not live() then
          return
        end
        read_marker(paths.marker, function(last)
          vim.schedule(function()
            if not live() then
              return
            end
            obs.runtime, obs.marker = rt, last
            obs.busy = (in_progress(last) and last) or (in_progress(first) and first) or nil
            obs.expired = first ~= nil and first.ago_ms ~= nil and last ~= nil and last.ago_ms ~= nil
            cb(obs)
          end)
        end)
      end)
    end)
  end
  if not with_probe then
    return sample()
  end
  probe(function(up)
    if live() then
      obs.up = up
      sample()
    end
  end)
end

-- envi T3 client buffers (t3.lua marks them), and the core client processes
-- they view: one per core address, since the popover and the main pane can
-- view the same client.
local function clients()
  local core = package.loaded["hcmux.core"] or {}
  local buffers, procs, seen = 0, {}, {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].hcmux_float == "t3" then
      buffers = buffers + 1
      local addr = vim.b[buf].hcmux_addr
      if addr and not seen[addr] then
        seen[addr] = true
        local fact = core.terms and core.terms[addr]
        procs[#procs + 1] = { name = (fact and fact.name) or addr, live = fact ~= nil and fact.state == "live" }
      end
    end
  end
  return buffers, procs
end

local function processes(n)
  return ("%d client process%s running"):format(n, n == 1 and "" or "es")
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
local function clients_text()
  local buffers, procs = clients()
  local running = 0
  for _, c in ipairs(procs) do
    running = running + (c.live and 1 or 0)
  end
  return ("%d client buffers, %s"):format(buffers, processes(running))
end

function M.status()
  observe(nil, true, function(state)
    local parts = { state.up and "server up" or "server unreachable" }
    local rt = state.runtime
    if rt == nil then
      parts[#parts + 1] = "no server-runtime.json"
    elseif rt == false then
      parts[#parts + 1] = "server-runtime.json unreadable"
    else
      parts[#parts + 1] = ("v%s pid %s since %s"):format(rt.version or "?", rt.pid or "?", rt.started or "?")
    end
    parts[#parts + 1] = disagreement(rt or nil)
    parts[#parts + 1] = marker_text(state.busy or state.marker)
    parts[#parts + 1] = clients_text()
    notify(table.concat(parts, " · "))
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
  for _, handle in pairs({ run.timer, run.fs, run.deadline }) do
    if not handle:is_closing() then
      handle:stop()
      handle:close()
    end
  end
  if text then
    notify(text, level)
  end
end

-- Process liveness only: a running client reconnects by itself, but its
-- websocket state is not visible from here. Nothing is restarted.
local function report_clients()
  local running, gone = {}, {}
  for _, c in ipairs(select(2, clients())) do
    table.insert(c.live and running or gone, c.name)
  end
  table.sort(running)
  table.sort(gone)
  local text = processes(#running)
  if #running > 0 then
    text = text .. ": " .. table.concat(running, ", ")
  end
  if #gone > 0 then
    text = text .. "; not running: " .. table.concat(gone, ", ") .. ". :T3Restart restarts one"
  elseif #running > 0 then
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

-- One watch step: sample without a probe; when the runtime moved (or the
-- marker expired over the baseline pid), probe at most once per poll_ms and
-- decide only from that second, probed observation. One step runs at a time
-- (run.busy). The deadline timer is authoritative; observe() drops any stage
-- that returns after it.
--
-- Success: no marker in progress in either marker read, the same new pid,
-- its port (when published) equal to the endpoint's, and a reachable server.
-- Stall (once): both marker reads expired, the readable pid is the baseline
-- one and the probe failed. Anything else keeps watching.
local function check(run)
  if M.run ~= run or run.busy then
    return
  end
  run.busy = true
  observe(run, false, function(obs)
    run.busy = false
    if obs.busy and not run.saw then
      run.saw = true
      notify("T3 is updating…")
    end
    local pid = not obs.busy and obs.runtime and obs.runtime.pid or nil
    local moved = pid ~= nil and pid ~= run.old.pid
    local stalling = run.saw and not run.stalled and obs.expired and pid == run.old.pid
    if not (moved or stalling) then
      if not run.saw and vim.uv.now() >= run.started + M.config.start_timeout_ms then
        finish(
          run,
          "no update started (Later, already up to date, or only downloaded: run :T3Update again to restart into it)"
        )
      end
      return
    elseif vim.uv.now() < run.next_probe then
      return -- rate limit: the timer comes back within poll_ms
    end
    run.next_probe = vim.uv.now() + M.config.poll_ms
    run.busy = true
    observe(run, true, function(after)
      run.busy = false
      local rt = after.runtime
      local now_pid = not after.busy and rt and rt.pid or nil
      if moved and after.up and now_pid == pid and not disagreement(rt) then
        succeed(run, rt)
      elseif stalling and not after.up and after.expired and now_pid == run.old.pid then
        run.stalled = true
        notify(
          ("update stalled: the marker expired, the server is still pid %d and unreachable; still watching"):format(
            run.old.pid
          ),
          vim.log.levels.WARN
        )
      end
    end)
  end)
end

local function watch(run)
  run.started, run.next_probe = vim.uv.now(), 0
  run.deadline_at = run.started + M.config.timeout_ms
  run.deadline = vim.uv.new_timer()
  run.deadline:start(
    M.config.timeout_ms,
    0,
    vim.schedule_wrap(function()
      finish(run, "update watch timed out; :T3Status shows the current state", vim.log.levels.WARN)
    end)
  )
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

-- nil unless the sidebar's current feed job delivered a valid snapshot
-- (t3side.feed_state); a render seed or a failed feed is unknown.
local function working()
  local side = package.loaded["hcmux.t3side"]
  local state = side and side.feed_state and side.feed_state()
  if not (state and state.live) then
    return nil
  end
  local n = 0
  for _, t in ipairs(state.snapshot.threads or {}) do
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

local function busy_text(m)
  return ("update already in progress (%d s left)"):format(math.ceil(m.left_ms / 1000))
end

local function refuse(run, text, level)
  if M.run == run then
    M.run = nil
  end
  notify(text, level or vim.log.levels.ERROR)
end

-- cb(rt) only when, re-read after a fresh probe, no update is in progress,
-- the server answers and its pid is known; otherwise the run is refused.
-- Admission between processes stays with the desktop.
local function validate(run, cb)
  observe(run, true, function(obs)
    local rt = obs.runtime
    if obs.busy then
      return refuse(run, busy_text(obs.busy), vim.log.levels.WARN)
    elseif not obs.up then
      return refuse(run, "server unreachable; not starting an update")
    elseif not (rt and rt.pid) then
      return refuse(run, "cannot read the server's pid from server-runtime.json; not starting an update")
    elseif disagreement(rt) then
      return refuse(run, disagreement(rt) .. "; not starting an update")
    end
    cb(rt)
  end)
end

function M.update()
  if M.run then
    return notify("T3Update already running", vim.log.levels.WARN)
  end
  local run = {}
  M.run = run
  read_marker(
    M.paths().marker,
    vim.schedule_wrap(function(first)
      if M.run ~= run then
        return
      elseif in_progress(first) then
        return refuse(run, busy_text(first), vim.log.levels.WARN)
      end
      validate(run, function(rt)
        local n = working()
        local question = n == nil and "running threads unknown (sidebar feed not running)."
          or n > 0 and ("%d running thread(s) will be interrupted."):format(n)
        if not question then
          run.old = rt
          return trigger(run)
        elseif not confirm(question) then
          return refuse(run, "update cancelled", vim.log.levels.INFO)
        end
        -- The answer may come much later: validate again and take that baseline.
        validate(run, function(fresh)
          run.old = fresh
          trigger(run)
        end)
      end)
    end)
  )
end

function M.current()
  return M.run
end

function M.setup()
  vim.api.nvim_create_user_command("T3Status", M.status, { desc = "T3 server, update and client state" })
  vim.api.nvim_create_user_command("T3Update", M.update, { desc = "Start T3 Code's own update flow and watch it" })
end

return M
