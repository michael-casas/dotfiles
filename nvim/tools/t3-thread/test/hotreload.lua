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
local toasts, display_ms = {}, 30
local function realtime()
  local t = vim.uv.clock_gettime("realtime")
  return t.sec + t.nsec / 1e9
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
      vim.defer_fn(function()
        if not n.hidden then
          n.shown, n.shown_ms = realtime(), vim.uv.now()
        end
      end, display_ms)
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

-- Two commits close together: the newer toast replaces the older and keeps its
-- own full lifetime (the older one's timer can't close it). An unrelated
-- notification keeps its own lifetime too.
Snacks.notifier.notify("unrelated", vim.log.levels.INFO, { id = "unrelated", timeout = 3000 })
local n0 = #toasts
commit("nvim/lua/l.lua", "return 13")
until_(3000, function()
  return #toasts == n0 + 1 and toasts[#toasts].shown_ms
end, "first of two toasts shown")
local first = toasts[#toasts]
sleep(120)
commit("nvim/lua/m.lua", "return 14")
until_(3000, function()
  return #toasts == n0 + 2 and toasts[#toasts].shown_ms
end, "second toast shown")
local second = toasts[#toasts]
assert(first.hidden and first.hidden <= second.at + 5, "the older toast closes when the newer one comes")
assert(second.shown_ms - first.hidden >= 90, "a visible gap between the two: " .. (second.shown_ms - first.hidden))
until_(2000, function()
  return second.hidden ~= nil
end, "second toast hidden")
assert(lasted(second) >= 190 and lasted(second) <= 260, "second toast keeps its own lifetime: " .. lasted(second))
assert(by_id("unrelated").hidden == nil, "an unrelated notification is never hidden by hot reload")

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
vim.fn.writefile({ "2026-11-19T10:01:00Z synced abc1234..def5678 (1 commit(s))" }, tmp .. "/state/dotfiles-sync/last")
assert(hot.status():find("last sync: synced abc1234..def5678", 1, true), "status shows a synced result")
reloadable = true
assert(hot.status():find("can reload itself", 1, true), "status: launcher nvim")

hot.stop()
os.remove(hot.marker())
vim.fn.delete(tmp, "rf")
print("hot reload tests passed")
