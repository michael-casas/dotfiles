-- hcmux.hotreload: when a commit lands on the branch envi's config is checked
-- out from, every running envi reloads itself (`:reload`), once it is safe.
--
-- Each nvim watches its own config repo (the git dir's logs/HEAD, plus a check
-- on FocusGained), so it works for commits by anyone: REP, workers, the user.
-- * Only commits that change files under the config dir count; docs (*.md)
--   alone don't reload.
-- * "Safe" = normal mode, no unsaved buffers, no key pressed for `idle_ms`. In
--   INSERT/TERMINAL (e.g. typing in a T3 popover) it waits. Unsaved buffers make
--   it wait too, with one notice.
-- * Needs nvim started by `envi` (the launcher restarts it); otherwise it only
--   says that a new commit is there.
-- :EnviHotReload [on|off|status]. ENVI_HOT_RELOAD_ROOT overrides the watched dir.
local M = {}

M.config = { enabled = true, idle_ms = 3000, debounce_ms = 400, poll_ms = 500 }
M.state = { head = nil, pending = nil, watching = nil }

local uv = vim.uv
local root, gitdir
local watcher, debounce, poll
local last_key = uv.now()
local warned = {}

local function git(args, cb)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      cb(res.code == 0 and vim.trim(res.stdout or "") or nil)
    end)
  end)
end

local function notify(msg, level, once)
  if once then
    if warned[once] then
      return
    end
    warned[once] = true
  end
  vim.notify("envi: " .. msg, level or vim.log.levels.INFO, { title = "hot reload" })
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
  if not M.state.pending or not M.config.enabled then
    return stop_poll()
  end
  local ok, why = M.safe()
  if not ok then
    if why == "unsaved" then
      notify("save your buffers to apply the new config (or :reload)", vim.log.levels.WARN, "unsaved")
    end
    return
  end
  stop_poll()
  local pending = M.state.pending
  M.state.pending = nil
  -- The restarted nvim says why it restarted (see M.setup).
  pcall(vim.fn.writefile, { pending.to:sub(1, 7), tostring(#pending.files) }, M.marker())
  require("hcmux.session").restart()
end

local function schedule_reload()
  if poll then
    return
  end
  poll = uv.new_timer()
  poll:start(0, M.config.poll_ms, vim.schedule_wrap(try_reload))
end

--- Compare HEAD with the one this nvim started on; queue a reload if config changed.
function M.check()
  if not root or not M.config.enabled then
    return
  end
  git({ "rev-parse", "HEAD" }, function(head)
    if not head or head == M.state.head or (M.state.pending and M.state.pending.to == head) then
      return
    end
    local from = M.state.head
    -- `.` is the config dir: git -C runs there, so pathspecs are relative to it.
    git({ "diff", "--name-only", from, head, "--", "." }, function(names)
      local files = {}
      for name in (names or "?"):gmatch("[^\n]+") do
        if not name:match("%.md$") then
          files[#files + 1] = name
        end
      end
      if #files == 0 then
        M.state.head = head -- docs only: nothing to reload
        return
      end
      M.state.pending = { from = from, to = head, files = files }
      if not require("hcmux.session").reloadable() then
        return notify(
          ("new config commit %s; :qd then envi to apply"):format(head:sub(1, 7)),
          vim.log.levels.WARN,
          head
        )
      end
      notify(("commit %s changed %d config file(s); reloading when idle"):format(head:sub(1, 7), #files))
      warned.unsaved = nil
      schedule_reload()
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

local function watch()
  if watcher then
    watcher:stop()
    watcher:close()
  end
  local target = gitdir .. "/logs/HEAD"
  if not uv.fs_stat(target) then
    target = gitdir -- no reflog: watch the git dir itself
  end
  watcher = uv.new_fs_event()
  watcher:start(target, {}, function(err)
    if err then
      -- The file was replaced or the watch broke: start over on the new inode.
      return vim.schedule(watch)
    end
    vim.schedule(on_change)
  end)
  M.state.watching = target
end

function M.stop()
  for _, h in ipairs({ watcher, debounce }) do
    if h and not h:is_closing() then
      h:stop()
      h:close()
    end
  end
  watcher, debounce = nil, nil
  stop_poll()
  M.state.watching = nil
end

function M.status()
  local s = M.state
  return ("hot reload %s · watching %s · HEAD %s%s"):format(
    M.config.enabled and "on" or "off",
    s.watching or "nothing",
    s.head and s.head:sub(1, 7) or "?",
    s.pending and (" · pending %s"):format(s.pending.to:sub(1, 7)) or ""
  )
end

--- Per-session file left by a hot reload for the next nvim to report.
function M.marker()
  -- HCMUX_SESSION is what the launcher starts nvim on, known before the session attaches.
  local name = (vim.env.HCMUX_SESSION or require("hcmux.session").name or "none"):gsub("[^%w._-]", "_")
  return vim.fn.stdpath("state") .. "/envi-hotreload." .. name
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
      M.check()
    end
    vim.notify(M.status())
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "status" }
    end,
    desc = "envi: reload on new config commits",
  })
  local group = vim.api.nvim_create_augroup("envi.hotreload", { clear = true })
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = M.check })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop })
  git({ "rev-parse", "--absolute-git-dir" }, function(dir)
    if not dir then
      return -- the config isn't in a git checkout: nothing to watch
    end
    gitdir = dir
    git({ "rev-parse", "HEAD" }, function(head)
      M.state.head = head
      watch()
    end)
  end)
end

return M
