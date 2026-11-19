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
}
-- head: the commit this nvim loaded its config from. seen: the last HEAD checked.
-- pending: { from, to, files } when a newer config commit is waiting.
-- toasted[sha]: the toast was shown for that commit. held[sha]: a reload for it
-- was cancelled (a quit prompt said no), so it isn't retried automatically.
M.state = { head = nil, seen = nil, pending = nil, watching = nil, toasted = {}, held = {}, toasts = 0 }

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

local toast_id, toast_at -- the toast on screen (one id per commit) and when it was asked for

-- snacks' clock (notif.shown is in these seconds).
local function realtime()
  local t = uv.clock_gettime and uv.clock_gettime("realtime")
  if t then
    return t.sec + t.nsec / 1e9
  end
  local sec, usec = uv.gettimeofday()
  return sec + usec / 1e6
end

-- Where notification `id` is in snacks: "shown" (plus when, on snacks' own
-- clock), "queued" (waiting for room on screen), "dropped" (hidden before it
-- was ever shown, or gone), or nil when this snacks can't tell.
local function snacks_state(snacks, id)
  local ok, history = pcall(snacks.notifier.get_history)
  if not ok or type(history) ~= "table" then
    return nil
  end
  local found -- the newest entry with this id (history is oldest first)
  for _, n in ipairs(history) do
    if n.id == id then
      found = n
    end
  end
  if not found or (found.hidden and not found.shown) then
    return "dropped"
  end
  if found.shown then
    return "shown", found.shown
  end
  return "queued"
end

-- Hide toast `id` `ms` after snacks first shows it. While snacks keeps it
-- queued (other notifications fill the screen) it waits, however long. If it
-- is dropped unseen (e.g. all notifications dismissed), the commit is no
-- longer counted as toasted, so the next check offers it again. Only this id
-- is hidden: other notifications, and the next commit's toast, keep their own
-- lifetimes. This also overrides snacks' keep rules (e.g. it holds toasts
-- while the cmdline is open).
local function expire(snacks, id, ms, commit)
  local asked = uv.now()
  local timer = uv.new_timer()
  local function stop(after_ms)
    timer:stop()
    timer:close()
    if after_ms then
      vim.defer_fn(function()
        pcall(snacks.notifier.hide, id)
      end, math.max(0, math.floor(after_ms)))
    end
  end
  timer:start(
    0,
    25,
    vim.schedule_wrap(function()
      if timer:is_closing() then
        return
      end
      local where, shown = snacks_state(snacks, id)
      if where == "shown" then
        stop(ms - (realtime() - shown) * 1000)
      elseif where == nil then
        stop(ms - (uv.now() - asked)) -- can't see it: count from the request
      elseif toast_id ~= id then
        stop() -- replaced by a newer commit's toast, which carries the notice
      elseif where == "dropped" then
        stop()
        M.state.toasted[commit] = nil
        toast_id = nil
      end
    end)
  )
end

--- Show the toast for `commit`, at most once per commit. Top right through
--- snacks.notifier, for `toast_ms` from the moment it's on screen. A newer
--- commit's toast replaces an older one still showing, after a short gap so
--- the change is visible, and gets its own full `toast_ms`.
function M.toast(commit)
  if M.state.toasted[commit] then
    return
  end
  M.state.toasted[commit] = true
  M.state.toasts = M.state.toasts + 1
  local ms = M.config.toast_ms
  local snacks = rawget(_G, "Snacks")
  if not (snacks and snacks.notifier) then
    return vim.notify(M.TOAST, vim.log.levels.WARN, { title = "envi", timeout = ms })
  end
  local id = "envi.hotreload." .. commit
  local gap = 0
  if toast_id and uv.now() - toast_at < ms + 1000 then
    pcall(snacks.notifier.hide, toast_id)
    gap = 100
  end
  toast_id, toast_at = id, uv.now()
  local function show()
    if toast_id ~= id then
      return -- an even newer commit's toast came first
    end
    local ok = pcall(snacks.notifier.notify, M.TOAST, vim.log.levels.WARN, { id = id, title = "envi", timeout = ms })
    if not ok then
      return vim.notify(M.TOAST, vim.log.levels.WARN, { title = "envi", timeout = ms })
    end
    expire(snacks, id, ms, commit)
  end
  if gap > 0 then
    vim.defer_fn(show, gap)
  else
    show()
  end
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
