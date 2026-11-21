-- hcmux.hotreload: when a commit lands on the checkout this nvim's config comes
-- from, every running nvim picks it up. On by default in every interactive nvim.
--
-- Each nvim watches its own config repo (the git dir's logs/HEAD), so it works
-- for commits by anyone: `dotfiles-sync` fast-forwarding ~/.dotfiles after a
-- merge, REP, workers, the user. Backstops: a check on FocusGained, and a cheap
-- periodic one (`recheck_ms`) that also re-arms the watch if logs/HEAD was
-- replaced.
-- * Only new commits that change files under the config dir count; docs (*.md)
--   alone never reload or toast.
-- * Started by `envi` (the launcher can restart it): reloads itself (`:reload`)
--   once it's safe = normal mode, no unsaved buffers, no key pressed for
--   `idle_ms`. While you type it waits silently. Unsaved buffers make it wait
--   too, with the toast below once per commit.
-- * Any other nvim (a plain `nvim file`) can't restart itself: it shows the
--   toast once per commit and nothing else.
-- The toast (snacks.notifier, top right, `toast_ms` in total):
--   "Your configuration has changed since the last time you reloaded, run :Reload"
--   One at a time: a newer commit while it's on screen is covered by it (see M.toast).
-- :EnviHotReload [on|off|status]. ENVI_HOT_RELOAD_ROOT overrides the watched dir.
local M = {}

M.TOAST = "Your configuration has changed since the last time you reloaded, run :Reload"

M.config = {
  enabled = true,
  idle_ms = 3000, -- no key pressed for this long before an automatic reload
  debounce_ms = 400, -- git writes several files per update
  poll_ms = 500, -- how often a queued reload checks whether it's safe yet
  recheck_ms = 60000, -- periodic backstop check (and watch re-arm)
  toast_ms = 4000, -- total time the toast is on screen
  toast_tail_ms = 250, -- a commit in a toast's last stretch gets its own toast after it
}
-- head: the commit this nvim loaded its config from. seen: the last HEAD checked.
-- pending: { from, to, files } when a newer config commit is waiting.
-- toasted[sha]: that commit was notified, or its toast is on the way.
-- covered[sha]: the commit whose toast, on screen, covers it.
-- reoffered[sha]: its toast was dropped unseen and offered again (once).
-- retired[sha]: how many of its displayed toasts left the screen early; the
-- fresh one is "envi.hotreload.<sha>#<n>", so a retired id never shows again.
-- toasts: how many toasts were handed to snacks. held[sha]: a reload for it
-- was cancelled (a quit prompt said no), so it isn't retried automatically.
M.state = {
  head = nil,
  seen = nil,
  pending = nil,
  watching = nil,
  toasted = {},
  covered = {},
  reoffered = {},
  retired = {},
  held = {},
  toasts = 0,
}

local uv = vim.uv
local root, gitdir
local watcher, watched_ino, debounce, poll, recheck
local checking, recheck_again = false, false
local last_key = uv.now()

local function git(args, cb)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      cb(res.code == 0 and vim.trim(res.stdout or "") or nil)
    end)
  end)
end

local function notify(msg, level)
  vim.notify("envi: " .. msg, level or vim.log.levels.INFO, { title = "hot reload" })
end

local function short(sha)
  return sha and sha:sub(1, 7) or "?"
end

local function reloadable()
  return require("hcmux.session").reloadable()
end

-- ── The config toast ──────────────────────────────────────────────────────
-- Every toast says the same thing, so the logic keeps one invariant:
--   The newest commit not yet notified (`want`) is the only commit that may
--   get a toast. A commit is notified once a toast for it, or for a newer
--   commit, was on screen until its deadline, or once it arrived while a config
--   toast was on screen (covered). A toast that leaves the screen before its
--   deadline (displaced) is retired: hidden by id, never shown again. Its
--   coverage is revoked, and the newest commit, the one it covered or its
--   own, is `want` again.
-- One `pump()` enforces it after every event. State:
--   want:   the newest commit awaiting a toast, or nil.
--   asked:  { id, commit, ms, at } handed to snacks, not on screen yet.
--   shown:  { id, commit, deadline, since, covers } the toast on screen
--           (status() checks snacks still has it there).
--   latest: the newest commit `M.toast` was called for.
local want, asked, shown, latest
local last_hidden = -math.huge
local tick, wake -- the 25 ms watch while a toast is asked or shown; the gap timer
local GAP_MS = 100 -- between one toast hiding and the next showing, so the change is visible

local function now() -- ms, monotonic
  uv.update_time()
  return uv.now()
end

local function realtime() -- snacks' clock: notif.shown is in these seconds
  local t = uv.clock_gettime and uv.clock_gettime("realtime")
  if t then
    return t.sec + t.nsec / 1e9
  end
  local sec, usec = uv.gettimeofday()
  return sec + usec / 1e6
end

-- Run fn after `ms` (every `ms` when `every`). Returns a function that cancels it.
local function timer(ms, fn, every)
  local t = uv.new_timer()
  t:start(
    ms,
    every and ms or 0,
    vim.schedule_wrap(function()
      if not t:is_closing() then
        if not every then
          t:close()
        end
        fn()
      end
    end)
  )
  return function()
    if not t:is_closing() then
      t:stop()
      t:close()
    end
  end
end

local function snacks()
  local s = rawget(_G, "Snacks")
  return s and s.notifier and s or nil
end

-- The newest snacks history entry for `id`, or false when snacks can't tell.
local function entry(s, id)
  local ok, history = pcall(s.notifier.get_history)
  if not ok or type(history) ~= "table" then
    return false
  end
  local found -- history is oldest first
  for _, n in ipairs(history) do
    if n.id == id then
      found = n
    end
  end
  return found
end

-- Where the shown toast `me` is right now: "on" (snacks says shown, not
-- cleared, not hidden, and its window is valid), "displaced" (snacks took it
-- off screen for lack of room: a small terminal, higher-priority
-- notifications; it clears `shown`, puts it back in its queue, and sets a new
-- `shown` if it brings it back, so a `shown` other than `me.since` means it
-- was off screen in between, however briefly), "hidden" (hidden or gone:
-- snacks' own timeout, or dismissed), or nil when snacks can't tell.
local function status(s, me)
  local n = entry(s, me.id)
  if n == false then
    return nil
  end
  if not n or n.hidden then
    return "hidden"
  end
  if not n.shown or (me.since and n.shown ~= me.since) then
    return "displaced"
  end
  if type(n.win) == "table" and type(n.win.win_valid) == "function" then
    local ok, valid = pcall(n.win.win_valid, n.win)
    if ok and valid ~= true then
      return "displaced"
    end
  end
  return "on"
end

local pump

-- Retire the shown toast: hide it by id, so snacks never shows this id again.
-- `how`: "deadline" (it ran its course), "hidden" (snacks or the person hid
-- it: seen), or "displaced" (it left the screen before its deadline: what it
-- stood for isn't delivered). A displaced toast's coverage is revoked, and
-- the newest commit, the one it covered or its own, is awaiting a toast again.
local function drop(s, how)
  local me = shown
  shown, last_hidden = nil, now()
  pcall(s.notifier.hide, me.id)
  if how ~= "displaced" then
    return
  end
  local c = me.covers
  if c then
    M.state.covered[c] = nil
  end
  if me.commit == latest then
    -- Its fresh toast gets an id of its own, so this one never comes back.
    M.state.retired[latest] = (M.state.retired[latest] or 0) + 1
  end
  if not want and (c == latest or me.commit == latest) then
    want = latest
  end
end

-- Follow what snacks did with the asked toast.
local function observe(s)
  if not asked then
    return
  end
  local n = entry(s, asked.id)
  local t = now()
  if n == false or (n and n.shown and not n.hidden) then
    -- On screen (or this snacks can't tell: count from the request). Its own
    -- deadline from now on: snacks' keep rules (the command line) don't
    -- stretch it, and nothing newer cuts it short.
    local left = n and asked.ms - (realtime() - n.shown) * 1000 or asked.ms - (t - asked.at)
    local me = { id = asked.id, commit = asked.commit, deadline = t + math.max(0, left), since = n and n.shown }
    shown, asked = me, nil
    timer(math.max(0, math.floor(left)), function()
      if shown == me then
        -- Reconcile first: displaced since the last watch tick, it's no delivery.
        drop(s, status(s, me) == "displaced" and "displaced" or "deadline")
        pump()
      end
    end)
  elseif n and n.shown then -- shown and hidden before we looked (dismissed)
    asked, last_hidden = nil, t
  elseif not n or n.hidden then -- dropped before it was ever shown
    local c = asked.commit
    asked = nil
    if c == latest and not want and not M.state.reoffered[c] then
      M.state.reoffered[c] = true
      M.state.toasted[c] = nil -- the next check offers it again, once
    end
  end -- else: still queued in snacks, however long
end

local function stop_tick()
  if tick then
    tick()
    tick = nil
  end
end

-- Enforce the invariant after any event.
function pump()
  local s = snacks()
  if not s then
    if want then -- no snacks: a plain notification
      M.state.toasts, want = M.state.toasts + 1, nil
      vim.notify(M.TOAST, vim.log.levels.WARN, { title = "envi", timeout = M.config.toast_ms })
    end
    return
  end
  observe(s)
  if shown then
    local where = status(s, shown)
    if where == "displaced" or where == "hidden" then
      drop(s, where) -- off screen: retired, it covers nothing and never comes back
    end
  end
  if want then
    if asked and asked.commit ~= want then
      pcall(s.notifier.hide, asked.id) -- superseded before it was shown: dismissed
      asked = nil
    end
    if asked then
      -- want's own toast is waiting in snacks' queue
    elseif shown then
      if shown.deadline - now() > M.config.toast_tail_ms then
        M.state.covered[want], shown.covers, want = shown.commit, want, nil -- covered
      end -- else in its tail: want gets its own toast after it hides
    else
      local wait = last_hidden + GAP_MS - now()
      if wait > 0 then
        if wake then
          wake()
        end
        wake = timer(math.ceil(wait), function()
          wake = nil
          pump()
        end)
      else
        local ms = M.config.toast_ms
        local n = M.state.retired[want]
        local id = "envi.hotreload." .. want .. (n and ("#" .. n) or "")
        M.state.toasts = M.state.toasts + 1
        if pcall(s.notifier.notify, M.TOAST, vim.log.levels.WARN, { id = id, title = "envi", timeout = ms }) then
          asked = { id = id, commit = want, ms = ms, at = now() }
        else
          vim.notify(M.TOAST, vim.log.levels.WARN, { title = "envi", timeout = ms })
        end
        want = nil
      end
    end
  end
  if (asked or shown) and not tick then
    tick = timer(25, pump, true)
  elseif not (asked or shown) then
    stop_tick()
  end
end

--- Notify about `commit`, the newest config commit, at most once per commit:
--- top right through snacks.notifier, for `toast_ms` from the moment it's on
--- screen. At most one toast is on screen (see the invariant above):
--- * one on screen covers a newer commit: no second toast; its deadline
---   stays (not cut short, not extended). A commit in its last
---   `toast_tail_ms` gets its own toast after it hides instead, so it isn't
---   swallowed by a toast about to go. If the covering toast leaves the
---   screen early (no room), the coverage is revoked.
--- * one queued in snacks and never shown is dismissed for the newer one.
--- * a toast dropped before it was ever shown is offered again once.
--- A new toast shows at least 100 ms after the last one hid.
function M.toast(commit)
  if M.state.toasted[commit] then
    return
  end
  M.state.toasted[commit] = true
  want, latest = commit, commit
  pump()
end

local function unsaved()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].modified and vim.bo[b].buftype == "" and vim.api.nvim_buf_is_loaded(b) then
      return true
    end
  end
  return false
end

--- Whether reloading now would not interrupt the person.
function M.safe()
  local mode = vim.api.nvim_get_mode()
  if mode.blocking or mode.mode ~= "n" or vim.fn.getcmdwintype() ~= "" then
    return false, "busy"
  end
  if unsaved() then
    return false, "unsaved"
  end
  if uv.now() - last_key < M.config.idle_ms then
    return false, "typing"
  end
  return true
end

local function stop_poll()
  if poll then
    poll:stop()
    poll:close()
    poll = nil
  end
end

local function try_reload()
  local pending = M.state.pending
  if not pending or not M.config.enabled or M.state.held[pending.to] then
    return stop_poll()
  end
  local ok, why = M.safe()
  if not ok then
    if why == "unsaved" then
      M.toast(pending.to) -- typing or busy: wait silently
    end
    return
  end
  stop_poll()
  M.state.pending = nil
  -- The restarted nvim says why it restarted (see M.setup).
  pcall(vim.fn.mkdir, vim.fn.fnamemodify(M.marker(), ":h"), "p")
  pcall(vim.fn.writefile, { short(pending.to), tostring(#pending.files) }, M.marker())
  require("hcmux.session").restart()
  -- Still here: the quit was cancelled. Keep the commit pending, don't retry it
  -- on our own (that would prompt again and again), and say so once.
  os.remove(M.marker())
  M.state.pending = pending
  M.state.held[pending.to] = true
  M.toast(pending.to)
end

--- Act on a pending config commit: queue a reload, or show the toast.
local function act()
  local pending = M.state.pending
  if not pending or not M.config.enabled then
    return
  end
  if not reloadable() or M.state.held[pending.to] then
    return M.toast(pending.to)
  end
  if not poll then
    poll = uv.new_timer()
    poll:start(0, M.config.poll_ms, vim.schedule_wrap(try_reload))
  end
end

-- The config files among NUL-separated paths (git diff -z: exact names, no
-- quoting, so a non-ASCII *.md is still docs).
local function config_files(names)
  local files = {}
  for name in names:gmatch("[^%z]+") do
    if not name:match("%.md$") then
      files[#files + 1] = name
    end
  end
  return files
end

--- Compare HEAD with the last one seen; when the new commits change config
--- files, the newest becomes pending.
function M.check()
  if not root or not gitdir or not M.config.enabled then
    return
  end
  if checking then
    recheck_again = true
    return
  end
  checking = true
  local function done()
    checking = false
    if recheck_again then
      recheck_again = false
      M.check()
    end
  end
  git({ "rev-parse", "HEAD" }, function(head)
    local seen = M.state.seen
    if not head then
      return done()
    end
    if head == seen then
      act() -- nothing new; re-offers a toast that was dropped unseen
      return done()
    end
    if head == M.state.head then -- back on the commit this nvim loaded
      M.state.seen, M.state.pending = head, nil
      stop_poll()
      return done()
    end
    -- `.` is the config dir: git -C runs there, so pathspecs are relative to it.
    -- Only what changed since the last check counts, so a docs-only commit after
    -- a config commit doesn't toast again.
    git({ "diff", "-z", "--name-only", seen, head, "--", "." }, function(names)
      if not names then
        return done() -- git failed: not a verdict. `seen` stays, the next check retries.
      end
      M.state.seen = head
      local files = config_files(names)
      if #files > 0 then
        local before = M.state.pending and M.state.pending.files or {}
        for _, f in ipairs(before) do
          if not vim.tbl_contains(files, f) then
            files[#files + 1] = f
          end
        end
        M.state.pending = { from = M.state.head, to = head, files = files }
        act()
      end
      done()
    end)
  end)
end

local function on_change()
  if debounce then
    debounce:stop()
  else
    debounce = uv.new_timer()
  end
  debounce:start(M.config.debounce_ms, 0, vim.schedule_wrap(M.check))
end

local function close(h)
  if h and not h:is_closing() then
    h:stop()
    h:close()
  end
end

local function target()
  local reflog = gitdir .. "/logs/HEAD"
  local st = uv.fs_stat(reflog)
  if st then
    return reflog, st.ino
  end
  return gitdir, (uv.fs_stat(gitdir) or {}).ino -- no reflog: watch the git dir itself
end

local watch

-- Every event re-arms the watch: git may have replaced logs/HEAD (a new inode),
-- and a kqueue watch on the old one would stay silent forever.
function watch()
  close(watcher)
  local path, ino = target()
  watcher = uv.new_fs_event()
  watcher:start(path, {}, function()
    vim.schedule(function()
      watch()
      on_change()
    end)
  end)
  watched_ino = ino
  M.state.watching = path
end

--- Re-arm the watch if its file changed under it, then check. Cheap: one stat
--- and one `git rev-parse`.
function M.backstop()
  if not gitdir then
    return
  end
  local path, ino = target()
  if path ~= M.state.watching or ino ~= watched_ino then
    watch()
  end
  M.check()
end

--- Drop the file watch only (the backstops re-arm it). For tests.
function M.unwatch()
  close(watcher)
  watcher, M.state.watching = nil, nil
end

function M.stop()
  close(watcher)
  close(debounce)
  close(recheck)
  watcher, debounce, recheck = nil, nil, nil
  stop_poll()
  M.state.watching = nil
end

--- Where `dotfiles-sync` keeps its results (see sync/README.md).
function M.sync_dir()
  return (vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")) .. "/dotfiles-sync"
end

--- The last sync result as one line, from the sync's `last` file.
function M.sync_status()
  local ok, lines = pcall(vim.fn.readfile, M.sync_dir() .. "/last", "", 1)
  if not ok or not lines[1] or lines[1] == "" then
    return "last sync: none recorded (" .. M.sync_dir() .. ")"
  end
  local at, kind, detail = lines[1]:match("^(%S+)%s+(%S+)%s*(.*)$")
  if not kind then
    return "last sync: " .. lines[1]
  end
  if kind == "blocked" then
    return ("sync blocked: %s (%s)"):format(detail, at)
  end
  if kind == "wrongbranch" then
    return ("sync moved the wrong branch: %s (%s)"):format(detail, at)
  end
  return ("last sync: %s %s (%s)"):format(kind, detail, at)
end

function M.status()
  local s = M.state
  local head = root and vim.system({ "git", "-C", root, "rev-parse", "HEAD" }, { text = true }):wait()
  head = head and head.code == 0 and vim.trim(head.stdout) or s.seen
  return table.concat({
    ("hot reload %s · watching %s"):format(M.config.enabled and "on" or "off", s.watching or "nothing"),
    ("loaded %s · HEAD %s · pending %s"):format(
      short(s.head),
      short(head),
      s.pending and ("%s (%d config file(s))"):format(short(s.pending.to), #s.pending.files) or "none"
    ),
    reloadable() and "this nvim can reload itself (started by envi)"
      or "this nvim can't reload itself: close and reopen nvim (or use envi)",
    M.sync_status(),
  }, "\n")
end

--- Per-session file left by a hot reload for the next nvim to report.
function M.marker()
  -- HCMUX_SESSION is what the launcher starts nvim on, known before the session attaches.
  local name = (vim.env.HCMUX_SESSION or require("hcmux.session").name or "none"):gsub("[^%w._-]", "_")
  return vim.fn.stdpath("state") .. "/envi-hotreload." .. name
end

--- False for nvims nobody looks at (scripts, `--headless` jobs).
function M.interactive()
  for _, a in ipairs(vim.v.argv) do
    if a == "--headless" or a == "-es" or a == "-Es" or a == "-l" then
      return false
    end
  end
  return true
end

function M.setup(cfg)
  if type(cfg) == "table" then
    M.config = vim.tbl_extend("force", M.config, cfg)
  end
  vim.defer_fn(function()
    local ok, lines = pcall(vim.fn.readfile, M.marker())
    if ok and lines[1] then
      os.remove(M.marker())
      notify(("reloaded for commit %s (%s config file(s))"):format(lines[1], lines[2] or "?"))
    end
  end, 800)
  root = vim.env.ENVI_HOT_RELOAD_ROOT or vim.fn.resolve(vim.fn.stdpath("config"))
  vim.on_key(function()
    last_key = uv.now()
  end, vim.api.nvim_create_namespace("envi.hotreload"))
  vim.api.nvim_create_user_command("EnviHotReload", function(a)
    if a.args == "off" then
      M.config.enabled = false
      stop_poll()
    elseif a.args == "on" then
      M.config.enabled = true
      act()
      M.check()
    end
    vim.api.nvim_echo({ { M.status() } }, true, {})
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "status" }
    end,
    desc = "envi: reload (or toast) on new config commits",
  })
  -- Without hcmux sessions there is no :Reload; the toast still names one.
  if not vim.api.nvim_get_commands({}).Reload then
    vim.api.nvim_create_user_command("Reload", function()
      if not reloadable() then
        return notify("this nvim can't reload itself: close and reopen nvim (or use envi)", vim.log.levels.WARN)
      end
      require("hcmux.session").restart()
    end, { desc = "Restart envi on this session (picks up config changes)" })
  end
  local group = vim.api.nvim_create_augroup("envi.hotreload", { clear = true })
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = M.backstop })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop })
  git({ "rev-parse", "--absolute-git-dir" }, function(dir)
    if not dir then
      return -- the config isn't in a git checkout: nothing to watch
    end
    gitdir = dir
    git({ "rev-parse", "HEAD" }, function(head)
      M.state.head, M.state.seen = head, head
      watch()
      close(recheck)
      recheck = uv.new_timer()
      recheck:start(M.config.recheck_ms, M.config.recheck_ms, vim.schedule_wrap(M.backstop))
    end)
  end)
end

return M
