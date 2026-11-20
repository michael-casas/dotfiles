-- Headless check for hcmux.hotreload against a throwaway git repo.
--   nvim/tools/t3-thread/test/run-lua.sh hotreload
-- snacks.notifier is stubbed here (the real toast is measured in a TUI); the
-- session module is stubbed so "restart" only counts.
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.rtp:prepend(vim.fn.fnamemodify(here, ":h:h:h"))

local tmp = vim.fn.tempname()
local repo = tmp .. "/repo"
local cfg = repo .. "/nvim"
vim.fn.mkdir(cfg .. "/lua", "p")
local function sh(cmd)
  local out = vim.fn.system({ "sh", "-c", cmd })
  assert(vim.v.shell_error == 0, cmd .. ": " .. out)
  return vim.trim(out)
end
local function commit(file, text)
  vim.fn.mkdir(vim.fn.fnamemodify(repo .. "/" .. file, ":h"), "p")
  vim.fn.writefile({ text }, repo .. "/" .. file)
  sh(("cd %s && git add -A && git -c user.email=t@t -c user.name=t commit -qm %q"):format(repo, file))
  return sh("git -C " .. repo .. " rev-parse HEAD")
end
local function sleep(ms)
  vim.wait(ms, function()
    return false
  end)
end
local function until_(ms, fn, what)
  assert(vim.wait(ms, fn, 10), what)
end
sh("cd " .. repo .. " && git init -q")
commit("nvim/lua/a.lua", "return 1")

-- Stubs: session (restart only counts; returning = the quit was cancelled),
-- snacks.notifier (records toasts), vim.notify (records messages).
local restarts, reloadable, marker_at_restart = 0, true, nil
vim.env.HCMUX_SESSION = "hotreload-test-" .. vim.fn.getpid()
package.loaded["hcmux.session"] = {
  restart = function()
    restarts = restarts + 1
    marker_at_restart = vim.fn.filereadable(require("hcmux.hotreload").marker()) == 1
  end,
  reloadable = function()
    return reloadable
  end,
}
-- A snacks.notifier stand-in: a notification shows `display_ms` after it's
-- asked for (snacks waits for room on screen), history reports `shown`.
-- display_ms = false: it stays queued until show_now() (a full screen).
local toasts, display_ms = {}, 30
local function realtime()
  local t = vim.uv.clock_gettime("realtime")
  return t.sec + t.nsec / 1e9
end
local function show_now(n)
  n.shown, n.shown_ms = realtime(), vim.uv.now()
end
local function by_id(id)
  for i = #toasts, 1, -1 do
    if toasts[i].id == id then
      return toasts[i]
    end
  end
end
_G.Snacks = {
  notifier = {
    notify = function(msg, level, opts)
      local n = { id = opts.id, msg = msg, level = level, opts = opts, at = vim.uv.now() }
      toasts[#toasts + 1] = n
      if display_ms then
        vim.defer_fn(function()
          if not n.hidden then
            n.shown, n.shown_ms = realtime(), vim.uv.now()
          end
        end, display_ms)
      end
    end,
    hide = function(id)
      local n = by_id(id)
      assert(n, "hides a toast it showed: " .. tostring(id))
      n.hidden = n.hidden or vim.uv.now()
    end,
    get_history = function()
      return toasts
    end,
  },
}
local messages = {}
vim.notify = function(msg)
  messages[#messages + 1] = msg
end
vim.env.XDG_STATE_HOME = tmp .. "/state"
vim.env.ENVI_HOT_RELOAD_ROOT = cfg

local hot = require("hcmux.hotreload")
assert(hot.config.toast_ms == 4000, "the toast lasts 4 s by default")
assert(hot.TOAST == "Your configuration has changed since the last time you reloaded, run :Reload", "toast text")
assert(hot.interactive() == false, "a --headless nvim is not interactive (init.lua skips setup)")
hot.setup({ idle_ms = 50, debounce_ms = 20, poll_ms = 20, toast_ms = 200, recheck_ms = 300 })
until_(3000, function()
  return hot.state.watching ~= nil
end, "watcher started")
assert(hot.state.watching:match("logs/HEAD$"), "watches the reflog: " .. hot.state.watching)

local function quiet(ms, what)
  local r, t = restarts, #toasts
  sleep(ms)
  assert(restarts == r, what .. ": no reload")
  assert(#toasts == t, what .. ": no toast")
end

-- ── launcher-started nvim (envi) ─────────────────────────────────────────
-- Docs only, or outside the config dir: nothing at all.
local docs = commit("nvim/README.md", "docs")
quiet(600, "markdown-only commit")
assert(hot.state.seen == docs, "docs-only commit is still seen")
commit("other.txt", "x")
quiet(600, "commit outside the config dir")

-- Typing: in INSERT (or a terminal) it waits silently; right after keys too.
-- Headless can't sit in INSERT, so the mode is faked for that part.
local get_mode = vim.api.nvim_get_mode
vim.api.nvim_get_mode = function()
  return { mode = "i", blocking = false }
end
local c1 = commit("nvim/lua/a.lua", "return 2")
until_(3000, function()
  return hot.state.pending ~= nil
end, "config commit queues a reload")
quiet(400, "INSERT")
vim.api.nvim_get_mode = get_mode
hot.config.idle_ms = 1500
vim.api.nvim_feedkeys("ihello\27", "xt", false) -- typed keys, back in normal mode
vim.bo.modified = false
quiet(700, "keys pressed less than idle_ms ago")
until_(3000, function()
  return restarts == 1
end, "reloads once you stop typing")
hot.config.idle_ms = 50
assert(marker_at_restart, "the reload leaves a marker for the next nvim")
-- The stub returned, as a cancelled quit does: the commit stays pending, isn't
-- retried on its own, and the toast says so once.
assert(hot.state.pending and hot.state.held[c1], "cancelled reload: held")
until_(1000, function()
  return #toasts == 1
end, "cancelled reload: toast")
quiet(300, "held commit: no retry")
assert(vim.fn.filereadable(hot.marker()) == 0, "cancelled reload removes its marker")

-- Unsaved buffer: toast once per commit, keep waiting; reload after saving.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "draft" })
local c2 = commit("nvim/lua/b.lua", "return 3")
until_(3000, function()
  return hot.state.pending and hot.state.pending.to == c2
end, "second config commit pending")
until_(1000, function()
  return #toasts == 2
end, "unsaved: toast")
quiet(400, "unsaved, after the toast")
assert(vim.tbl_contains(hot.state.pending.files, "nvim/lua/a.lua"), "pending keeps earlier files")
-- A docs-only commit on top: no new toast.
commit("nvim/NOTES.md", "more docs")
quiet(500, "docs-only commit while one is pending")
-- Several config commits in a row: one toast for the newest.
commit("nvim/lua/c.lua", "return 4")
local c3 = commit("nvim/lua/d.lua", "return 5")
until_(3000, function()
  return hot.state.pending.to == c3
end, "newest commit pending")
until_(1000, function()
  return #toasts == 3
end, "toast for the newest commit")
sleep(200)
assert(#toasts == 3, "one toast for a burst of commits, got " .. #toasts)
vim.bo.modified = false
until_(3000, function()
  return restarts == 2
end, "reloads once saved")

-- logs/HEAD replaced (a new inode): the watch follows it.
local reflog = hot.state.watching
local ino = vim.uv.fs_stat(reflog).ino
sh(("cp %q %q.new && mv %q.new %q"):format(reflog, reflog, reflog, reflog))
assert(vim.uv.fs_stat(reflog).ino ~= ino, "reflog replaced")
sleep(100)
local c4 = commit("nvim/lua/e.lua", "return 6")
until_(3000, function()
  return restarts == 3
end, "replaced reflog: still sees commits")
assert(hot.state.pending.to == c4)

-- Backstops: with no file watch, FocusGained and the periodic check find it.
local function restart_module(recheck_ms)
  hot.stop()
  hot.state.pending, hot.state.held = nil, {}
  hot.setup({ idle_ms = 50, debounce_ms = 20, poll_ms = 20, toast_ms = 200, recheck_ms = recheck_ms })
  until_(3000, function()
    return hot.state.watching ~= nil
  end, "watching again")
end
restart_module(60000)
hot.unwatch() -- as if the watch broke silently
local c5 = commit("nvim/lua/f.lua", "return 7")
sleep(300)
assert(not hot.state.pending, "no watch: nothing yet")
vim.api.nvim_exec_autocmds("FocusGained", {})
until_(3000, function()
  return restarts == 4
end, "FocusGained finds the commit")
assert(hot.state.pending.to == c5)
assert(hot.state.watching, "FocusGained re-arms the watch")
restart_module(300)
hot.unwatch()
local c6 = commit("nvim/lua/g.lua", "return 8")
until_(3000, function()
  return restarts == 5
end, "the periodic check finds the commit and reloads")
assert(hot.state.pending.to == c6)
assert(hot.state.watching and hot.state.watching:match("logs/HEAD$"), "periodic check re-armed the watch")

-- Off switch, and catching up when it's back on.
hot.state.held, hot.state.pending = {}, nil
sleep(200) -- let the held commit's toast (shown after a 100 ms gap) land first
vim.cmd("EnviHotReload off")
commit("nvim/lua/h.lua", "return 9")
quiet(500, "off")
vim.cmd("EnviHotReload on")
until_(3000, function()
  return restarts == 6
end, "on again: catches up with the missed commit")

-- ── plain nvim (not started by envi) ─────────────────────────────────────
reloadable = false
hot.state.held, hot.state.pending = {}, nil
sleep(200)
local before = #toasts
local p1 = commit("nvim/lua/i.lua", "return 10")
until_(3000, function()
  return #toasts == before + 1
end, "plain nvim: toast")
sleep(400) -- idle, saved: still no restart
assert(restarts == 6, "plain nvim: never restarts")
vim.api.nvim_exec_autocmds("FocusGained", {})
sleep(300)
assert(#toasts == before + 1, "plain nvim: once per commit")
assert(hot.state.pending.to == p1)
commit("nvim/doc.md", "docs")
quiet(400, "plain nvim, docs-only")
commit("nvim/lua/j.lua", "return 11")
until_(3000, function()
  return #toasts == before + 2
end, "plain nvim: a new commit toasts again")

-- The toast itself: exact text, one id per commit, 4 s (here 200 ms) from the
-- moment snacks shows it.
local t = toasts[#toasts]
assert(t.msg == hot.TOAST, "exact text: " .. t.msg)
assert(t.opts.timeout == 200 and t.opts.id == "envi.hotreload." .. hot.state.pending.to, "timeout and id")
until_(1000, function()
  return t.hidden ~= nil
end, "hidden after toast_ms")
local function lasted(n)
  return n.hidden - n.shown_ms
end
assert(lasted(t) >= 190 and lasted(t) <= 260, "on screen ~toast_ms: " .. lasted(t))

-- Shown late (snacks had no room): the budget starts when it's on screen.
display_ms = 300
local nk = #toasts
commit("nvim/lua/k.lua", "return 12")
until_(3000, function()
  return #toasts == nk + 1 and toasts[#toasts].hidden ~= nil
end, "late toast hidden")
t = toasts[#toasts]
assert(t.shown_ms - t.at >= 290, "shown late: " .. (t.shown_ms - t.at))
assert(lasted(t) >= 190 and lasted(t) <= 260, "late toast still gets toast_ms on screen: " .. lasted(t))
display_ms = 30

-- One notice at a time (Amendment B-2). Here toast_ms = 1500, then 600, and
-- the tail (the last stretch of a toast's life in which a newer commit gets
-- its own toast after it) is 150 ms; in real use 4000 and 250.
hot.config.toast_ms, hot.config.toast_tail_ms = 1500, 150
local function full(n)
  local ms = hot.config.toast_ms
  return n.hidden and lasted(n) >= ms - 10 and lasted(n) <= ms + 70
end
-- Two commits close together: the toast on screen covers the newer commit.
-- It keeps its own deadline (not cut short, not extended), no second toast
-- comes, and the newer commit counts as notified. An unrelated notification
-- keeps its own lifetime too.
Snacks.notifier.notify("unrelated", vim.log.levels.INFO, { id = "unrelated", timeout = 3000 })
local n0 = #toasts
local l_commit = commit("nvim/lua/l.lua", "return 13")
until_(3000, function()
  return #toasts == n0 + 1 and toasts[#toasts].shown_ms
end, "first toast shown")
local first = toasts[#toasts]
sleep(100)
local m_commit = commit("nvim/lua/m.lua", "return 14")
until_(3000, function()
  return hot.state.seen == m_commit
end, "second commit seen while the first toast shows")
assert(vim.uv.now() - first.shown_ms < 1500 - 150, "the second commit landed before the tail (slow git?)")
assert(first.hidden == nil, "the toast on screen isn't cut short by a newer commit")
until_(3000, function()
  return first.hidden ~= nil
end, "the toast hides at its own deadline")
assert(full(first), "one toast on screen for its full toast_ms: " .. lasted(first))
sleep(300)
assert(#toasts == n0 + 1, "no second toast for a commit the visible one covered: " .. (#toasts - n0))
assert(hot.state.toasted[m_commit] and hot.state.covered[m_commit] == l_commit, "the newer commit counts as notified")
vim.api.nvim_exec_autocmds("FocusGained", {})
sleep(300)
assert(#toasts == n0 + 1, "a covered commit isn't offered again")
assert(by_id("unrelated").hidden == nil, "an unrelated notification is never hidden by hot reload")
hot.config.toast_ms = 600

-- A commit in the visible toast's last toast_tail_ms isn't swallowed: the old
-- toast still keeps its deadline, then one fresh toast follows after a gap.
-- (hot.toast directly, to land precisely in the tail.)
local nt = #toasts
hot.toast("tail-a")
until_(1000, function()
  return #toasts == nt + 1 and toasts[#toasts].shown_ms
end, "tail case: first toast shown")
local ta = toasts[#toasts]
until_(1000, function()
  return vim.uv.now() - ta.shown_ms >= 500
end, "into the tail")
hot.toast("tail-b")
hot.toast("tail-c") -- an even newer one in the tail: it, not tail-b, follows
until_(2000, function()
  return #toasts == nt + 2 and toasts[#toasts].hidden ~= nil
end, "tail case: the fresh toast shows and expires")
local tc = toasts[#toasts]
assert(full(ta), "tail case: the older toast keeps its deadline: " .. lasted(ta))
assert(tc.id == "envi.hotreload.tail-c", "the newest commit in the tail gets the fresh toast: " .. tc.id)
assert(tc.at >= ta.hidden, "the fresh toast waits for the older one to hide")
assert(tc.shown_ms - ta.hidden >= 90, "a visible gap between the two: " .. (tc.shown_ms - ta.hidden))
assert(full(tc), "the fresh toast gets its own full toast_ms: " .. lasted(tc))
assert(hot.state.toasted["tail-b"], "a superseded waiting toast still counts as notified")

-- A commit just after the toast hid gets its own full toast, after a gap.
local nx = #toasts
hot.toast("after-a")
until_(2000, function()
  return #toasts == nx + 1 and toasts[#toasts].hidden ~= nil
end, "after case: first toast expires")
local xa = toasts[#toasts]
hot.toast("after-b")
until_(2000, function()
  return #toasts == nx + 2 and toasts[#toasts].hidden ~= nil
end, "after case: its own toast")
local xb = toasts[#toasts]
assert(full(xa) and full(xb), ("both full: %d, %d"):format(lasted(xa), lasted(xb)))
assert(xb.shown_ms - xa.hidden >= 90, "a visible gap after expiry: " .. (xb.shown_ms - xa.hidden))
assert(hot.state.covered["after-b"] == nil, "not covered: the older toast was gone")

-- Displaced: snacks can take a shown toast off screen again (no room: a small
-- terminal, higher-priority notifications) and clear its `shown`. Only a toast
-- on screen right now covers a commit.
local function displace(n)
  display_ms = false -- the screen stays full
  n.shown = nil
end
sleep(150)
local nd0 = #toasts
hot.toast("disp-a")
until_(1000, function()
  return #toasts == nd0 + 1 and toasts[#toasts].shown_ms
end, "displaced case: first toast shown")
local da = toasts[#toasts]
sleep(100)
displace(da)
sleep(60)
hot.toast("disp-b") -- no config toast on screen: not covered
assert(hot.state.covered["disp-b"] == nil, "a displaced toast doesn't cover a newer commit")
until_(1000, function()
  return #toasts == nd0 + 2
end, "the newer commit's toast is asked for")
local db = toasts[#toasts]
assert(db.id == "envi.hotreload.disp-b" and not db.shown, "it waits in the queue: " .. db.id)
assert(da.hidden, "the displaced older toast is dropped, so the two never show together")
sleep(800) -- past the displaced toast's own deadline: still queued
assert(db.hidden == nil, "the queued newer toast isn't expired unseen")
display_ms = 30
show_now(db) -- room returns
until_(1000, function()
  return db.hidden ~= nil
end, "the newer toast expires")
assert(full(db), "the newer toast gets its full toast_ms from its display: " .. lasted(db))
assert(#toasts == nd0 + 2, "exactly one toast for the newer commit")

-- Displaced after covering: the commit it covered is shown once room returns.
sleep(150)
local nc0 = #toasts
hot.toast("disp-c")
until_(1000, function()
  return #toasts == nc0 + 1 and toasts[#toasts].shown_ms
end, "covering toast shown")
local dc = toasts[#toasts]
hot.toast("disp-d")
assert(hot.state.covered["disp-d"] == "disp-c", "covered while it is on screen")
sleep(100)
displace(dc)
until_(1000, function()
  return #toasts == nc0 + 2
end, "coverage lost: the covered commit's toast is asked for")
local dd = toasts[#toasts]
assert(dd.id == "envi.hotreload.disp-d" and hot.state.covered["disp-d"] == nil, "no longer covered: " .. dd.id)
assert(dc.hidden, "the displaced covering toast is dropped")
sleep(800)
assert(dd.hidden == nil and not dd.shown, "it waits for room")
display_ms = 30
show_now(dd)
until_(1000, function()
  return dd.hidden ~= nil
end, "the covered commit's toast expires")
assert(full(dd), "the covered commit's toast gets its full toast_ms: " .. lasted(dd))
vim.api.nvim_exec_autocmds("FocusGained", {})
sleep(300)
assert(#toasts == nc0 + 2, "shown once, not again")

-- Never two config toasts on screen at once.
for i, a in ipairs(toasts) do
  for j = i + 1, #toasts do
    local b = toasts[j]
    if a.shown_ms and b.shown_ms and a.msg == hot.TOAST and b.msg == hot.TOAST then
      local a_end, b_end = a.hidden or math.huge, b.hidden or math.huge
      assert(a_end <= b.shown_ms or b_end <= a.shown_ms, ("two toasts on screen at once: %s, %s"):format(a.id, b.id))
    end
  end
end
hot.config.toast_ms = 200

-- Queued for a long time (the screen is full): never expired unseen; once
-- shown it gets its full toast_ms. (The TUI probe holds it for over 60 s.)
display_ms = false
local nq = #toasts
commit("nvim/lua/q.lua", "return 15")
until_(3000, function()
  return #toasts == nq + 1
end, "queued toast asked for")
local queued = toasts[#toasts]
sleep(1500) -- 7x toast_ms, still queued
assert(queued.hidden == nil, "a queued toast is not expired by elapsed time")
show_now(queued)
until_(1000, function()
  return queued.hidden ~= nil
end, "hidden after it was shown")
assert(lasted(queued) >= 190 and lasted(queued) <= 260, "queued toast gets toast_ms once shown: " .. lasted(queued))

-- Dropped unseen (all notifications dismissed): not counted as toasted, so the
-- next check offers it again, once.
local nd = #toasts
local dropped_commit = commit("nvim/lua/r.lua", "return 16")
until_(3000, function()
  return #toasts == nd + 1
end, "toast asked for")
Snacks.notifier.hide(toasts[#toasts].id) -- dismissed before it was shown
until_(1000, function()
  return not hot.state.toasted[dropped_commit]
end, "a dropped toast is no longer counted")
display_ms = 30
vim.api.nvim_exec_autocmds("FocusGained", {})
until_(3000, function()
  return #toasts == nd + 2 and toasts[#toasts].shown_ms
end, "the next check shows it again")
assert(toasts[#toasts].id == "envi.hotreload." .. dropped_commit, "same commit, offered again")
until_(1000, function()
  return toasts[#toasts].hidden ~= nil
end, "re-offered toast expires")
vim.api.nvim_exec_autocmds("FocusGained", {})
sleep(300)
assert(#toasts == nd + 2, "once shown, not again")

-- Two queued toasts, the newer one arriving long after the older (more than
-- toast_ms + 1 s): the older is superseded and dismissed unseen, and isn't
-- offered again. The newer one, once shown, gets toast_ms.
display_ms = false
local no = #toasts
local older_commit = commit("nvim/lua/s.lua", "return 17")
until_(3000, function()
  return #toasts == no + 1
end, "older toast queued")
local older = toasts[#toasts]
sleep(1500)
local newer_commit = commit("nvim/lua/t.lua", "return 18")
until_(3000, function()
  return #toasts == no + 2
end, "newer toast queued")
local newer = toasts[#toasts]
assert(older.hidden and not older.shown, "the superseded older toast is dismissed before it shows")
assert(newer.id == "envi.hotreload." .. newer_commit and not newer.hidden, "the newer toast is the one waiting")
show_now(newer)
until_(1000, function()
  return newer.hidden ~= nil
end, "newer toast expires")
assert(lasted(newer) >= 190 and lasted(newer) <= 260, "newer toast gets toast_ms once shown: " .. lasted(newer))
vim.api.nvim_exec_autocmds("FocusGained", {})
sleep(300)
assert(#toasts == no + 2 and hot.state.toasted[older_commit], "the superseded toast is not offered again")
display_ms = 30

-- A failed `git diff` is no verdict: no toast, `seen` stays, the next check
-- (here FocusGained) classifies the commit properly.
local system, failed, seen_after = vim.system, false, nil
vim.system = function(cmd, opts, cb)
  if cmd[4] == "diff" and not failed then
    failed = true
    vim.schedule(function()
      cb({ code = 128, stdout = "", stderr = "transient" })
      seen_after = hot.state.seen -- right after hot reload handled the failure
    end)
    return {}
  end
  return system(cmd, opts, cb)
end
local n1, seen1, pending1 = #toasts, hot.state.seen, hot.state.pending.to
local docs2 = commit("nvim/doc.md", "more docs")
until_(3000, function()
  return seen_after ~= nil
end, "the diff failed once")
assert(seen_after == seen1, "failed diff: seen stays")
assert(#toasts == n1, "failed diff: no toast")
vim.api.nvim_exec_autocmds("FocusGained", {})
until_(3000, function()
  return hot.state.seen == docs2
end, "the next check classifies the commit")
vim.system = system
sleep(200)
assert(#toasts == n1 and hot.state.pending.to == pending1, "docs-only after the retry: no toast, pending unchanged")
-- A non-ASCII docs file is still docs (paths read with -z, unquoted).
commit("nvim/café.md", "docs")
quiet(500, "non-ASCII *.md")

-- :Reload in a plain nvim: one line saying what to do. (session.lua defines
-- :Reload when sessions are on; here they're stubbed, so hotreload's own runs.)
messages = {}
vim.cmd("Reload")
assert(#messages == 1 and messages[1]:find("close and reopen nvim (or use envi)", 1, true), vim.inspect(messages))

-- Status: watched path, HEAD, pending, reloadability, and the last sync.
vim.fn.mkdir(tmp .. "/state/dotfiles-sync", "p")
vim.fn.writefile(
  { "2026-11-19T10:00:00Z blocked local changes in nvim/lua/plugins/neo-tree.lua" },
  tmp .. "/state/dotfiles-sync/last"
)
local s = hot.status()
for _, want in ipairs({
  "hot reload on",
  "watching " .. hot.state.watching,
  "HEAD " .. sh("git -C " .. repo .. " rev-parse --short=7 HEAD"),
  "pending " .. hot.state.pending.to:sub(1, 7),
  "can't reload itself",
  "sync blocked: local changes in nvim/lua/plugins/neo-tree.lua",
}) do
  assert(s:find(want, 1, true), ("status has %q:\n%s"):format(want, s))
end
vim.fn.writefile({
  "2026-11-19T10:02:00Z wrongbranch the merge advanced other (not main) from aaa to bbb; recover: git -C /r reset --keep aaa (while it is checked out), or git -C /r branch -f other aaa",
}, tmp .. "/state/dotfiles-sync/last")
assert(
  hot.status():find("sync moved the wrong branch: the merge advanced other (not main)", 1, true)
    and hot.status():find("git -C /r branch -f other aaa", 1, true),
  "status names the wrong branch and the recovery"
)
vim.fn.writefile({ "2026-11-19T10:01:00Z synced abc1234..def5678 (1 commit(s))" }, tmp .. "/state/dotfiles-sync/last")
assert(hot.status():find("last sync: synced abc1234..def5678", 1, true), "status shows a synced result")
reloadable = true
assert(hot.status():find("can reload itself", 1, true), "status: launcher nvim")

hot.stop()
os.remove(hot.marker())
vim.fn.delete(tmp, "rf")
print("hot reload tests passed")
