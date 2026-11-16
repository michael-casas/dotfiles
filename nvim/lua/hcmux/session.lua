-- hcmux.session: nvim sessions kept in herdr-core.
--
-- herdr-core is the single source of truth. A session is one core document
-- (`nvs.<name>`) holding nvim's layout (`:mksession` text: tabs, splits, sizes,
-- buffers, cursors, folds), plus the terminals labelled `herdr.nvs=<name>`.
--
--   * Plain `nvim` (or `nvim <dir>`) attaches to the session of that folder's
--     git root; `nvim-session attach <name>` to a named one. `nvim <file>` is
--     a plain editor and never touches a session ($EDITOR, git commit, …).
--   * Saving is continuous (debounced after layout/buffer changes and on
--     idle), so a crash or a closed tab loses nothing.
--   * Quitting is detaching: the layout is saved and the terminals keep
--     running. `:Detach` (or `:detach`) does it explicitly.
--   * Two nvims on one session: the second is told and does not save until
--     it takes over (`:Session take`); a stale save is refused by the core.
local core = require("hcmux.core")

local M = {}

M.config = {
  debounce = 1500, -- ms after the last change before saving
  -- What the layout keeps. Not "localoptions"/"blank" (noisy and fragile).
  sessionoptions = "buffers,curdir,folds,help,tabpages,winsize,terminal",
}

M.LABEL = "herdr.nvs" -- terminals that belong to a session
M.INDEX = "nvs-index" -- core document listing sessions by name

M.name = nil -- attached session
M.root = nil -- its folder
M.version = 0 -- document version last read or written
M.state = "off" -- off | attached | readonly | conflict

local uv = vim.uv or vim.loop

-- ── names and storage (no UI; also used by the nvim-session CLI) ─────────

--- Session names are core document names minus the `nvs.` prefix:
--- 1-28 of a-z 0-9 - _ .
function M.sanitize(s)
  s = tostring(s or ""):lower():gsub("[^a-z0-9._-]+", "-"):gsub("^[^a-z0-9]+", ""):gsub("%-+$", "")
  s = s:sub(1, 28):gsub("[-._]+$", "")
  return s ~= "" and s or "session"
end

function M.doc_name(name)
  return "nvs." .. name
end

--- The folder a session belongs to: the git root, else the directory.
function M.root_of(dir)
  -- Strip a trailing slash but keep "/" itself ("" would resolve to the cwd).
  dir = vim.fn.fnamemodify(dir or vim.fn.getcwd(), ":p"):gsub("(.)/$", "%1")
  return vim.fs.root(dir, ".git") or dir
end

local function now_ms()
  return os.time() * 1000
end

function M.index()
  local val, ver, err = core.doc_get(M.INDEX)
  if err then
    return nil, nil, err
  end
  local sessions = type(val) == "table" and type(val.sessions) == "table" and val.sessions or {}
  return sessions, ver or 0
end

--- Read-modify-write the index; retried when another nvim wrote first.
function M.index_update(fn)
  for _ = 1, 5 do
    local sessions, ver, err = M.index()
    if not sessions then
      return false, err
    end
    fn(sessions)
    local value = { sessions = next(sessions) and sessions or vim.empty_dict() }
    local nv, serr, kind = core.doc_set(M.INDEX, value, ver)
    if nv then
      return true
    end
    if kind ~= "conflict" then
      return false, serr
    end
  end
  return false, "index kept changing"
end

--- The default name for a folder: its basename, or basename-xxxx when that
--- name already belongs to another folder (e.g. two worktrees).
function M.default_name(dir)
  local root = M.root_of(dir)
  local base = M.sanitize(vim.fs.basename(root))
  local sessions = M.index() or {}
  local entry = sessions[base]
  if entry == nil or entry.root == root then
    return base
  end
  local suffixed = M.sanitize(base:sub(1, 23) .. "-" .. vim.fn.sha256(root):sub(1, 4))
  return suffixed
end

function M.read(name)
  return core.doc_get(M.doc_name(name))
end

function M.holder()
  return { pid = vim.fn.getpid(), host = uv.os_gethostname(), terminal = vim.env.HC_TERMINAL_ID }
end

function M.holder_alive(h)
  if type(h) ~= "table" or not h.pid then
    return false
  end
  if h.host ~= uv.os_gethostname() then
    return true -- can't check another machine; assume it is
  end
  local ok, rc = pcall(uv.kill, h.pid, 0)
  return ok and rc == 0
end

local function is_me(h)
  return type(h) == "table" and h.pid == vim.fn.getpid() and h.host == uv.os_gethostname()
end

--- Live terminals of a session.
function M.terminals(name)
  local res = core.json({ "ls", "--label", M.LABEL .. "=" .. name })
  return res and res.terminals or {}
end

--- End a session: its terminals and its document.
function M.kill(name)
  for _, t in ipairs(M.terminals(name)) do
    core.exec({ "kill", t.address })
    core.exec({ "rm", t.address })
  end
  local _, ver = M.read(name)
  core.doc_set(M.doc_name(name), nil, ver or 0)
  return M.index_update(function(s)
    s[name] = nil
  end)
end

-- ── layout ────────────────────────────────────────────────────────────────

-- Buffers a layout never brings back: plain :terminal buffers (they would
-- start a new shell; hcmux terminals are the durable ones) and side panels.
-- They are renamed in the saved text and dropped on load.
local SKIP = "hcmux-skip://"

local function strip(text)
  text = text:gsub('([ "])term://', "%1" .. SKIP .. "term/")
  text = text:gsub('([ "])(neo%-tree\\? )', "%1" .. SKIP .. "%2")
  text = text:gsub('([ "])NvimTree_', "%1" .. SKIP .. "NvimTree_")
  return text
end

-- Opt-in transient tabs never enter the saved script. Filter mksession's tab
-- blocks rather than closing/reopening live windows (which would lose viewers).
local function exclude_tabs(text, tabs, current)
  local keep, count, selected = {}, 0, 1
  local included_buffers, excluded_names = {}, {}
  for index, tab in ipairs(tabs) do
    keep[index] = not vim.t[tab].hcmux_session_skip
    if keep[index] then
      count = count + 1
      if tab == current then
        selected = count
      end
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        included_buffers[vim.api.nvim_win_get_buf(win)] = true
      end
    end
  end
  if count == #tabs then
    return text
  end
  if count == 0 then
    return nil, "all tab pages excluded from session"
  end
  for index, tab in ipairs(tabs) do
    if not keep[index] then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if not included_buffers[buf] then
          local name = vim.api.nvim_buf_get_name(buf)
          if name ~= "" then
            excluded_names[vim.fn.fnameescape(vim.fn.fnamemodify(name, ":~:."))] = true
            excluded_names[vim.fn.fnameescape(name)] = true
            excluded_names[vim.fn.fnameescape(vim.fn.bufname(buf))] = true
          end
        end
      end
    end
  end
  local result, block, footer = {}, nil, false
  for line in vim.gsplit(text, "\n", { plain = true }) do
    if line == "tabrewind" then
      for _ = 2, count do
        result[#result + 1] = "tabnew +setlocal\\ bufhidden=wipe"
      end
      result[#result + 1] = "tabrewind"
      block = 1
    elseif line == "tabnext" and block and not footer then
      block = block + 1
      if keep[block] and block > 1 then
        local previous = false
        for i = 1, block - 1 do
          previous = previous or keep[i]
        end
        if previous then
          result[#result + 1] = "tabnext"
        end
      end
    elseif line:match("^tabnext %d+$") then
      footer = true
      result[#result + 1] = "tabnext " .. selected
    elseif line:match("^tabnew %+setlocal") and not block then
      -- Rebuilt above with the number of included tab pages.
    elseif not block or footer or keep[block] then
      local name = line:match("^badd %+%d+ (.+)$") or line:match("^balt (.+)$")
      if not (name and excluded_names[name]) then
        result[#result + 1] = line
      end
    end
  end
  return table.concat(result, "\n")
end

--- nvim's layout as `:mksession` text.
function M.serialize()
  local tmp = vim.fn.tempname()
  local saved = vim.o.sessionoptions
  vim.o.sessionoptions = M.config.sessionoptions
  local ok, err = pcall(vim.cmd, "silent mksession! " .. vim.fn.fnameescape(tmp))
  vim.o.sessionoptions = saved
  if not ok then
    os.remove(tmp)
    return nil, err
  end
  local f = io.open(tmp, "r")
  local text = f and f:read("*a")
  if f then
    f:close()
  end
  os.remove(tmp)
  if text then
    local filtered, filter_err = exclude_tabs(text, vim.api.nvim_list_tabpages(), vim.api.nvim_get_current_tabpage())
    return filtered and strip(filtered), filter_err
  end
end

--- Nothing worth keeping: only the dashboard or empty buffers.
local function is_empty()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) ~= "" then
      return false
    end
  end
  return true
end

local function drop_skipped()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):sub(1, #SKIP) == SKIP then
      for _, win in ipairs(vim.fn.win_findbuf(b)) do
        local tab = vim.api.nvim_win_get_tabpage(win)
        if #vim.api.nvim_tabpage_list_wins(tab) > 1 then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  -- `nvim <dir>` leaves a directory buffer behind
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= "" and vim.fn.isdirectory(name) == 1 and #vim.fn.win_findbuf(b) == 0 then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

function M.load_layout(text)
  local tmp = vim.fn.tempname() .. ".vim"
  local f = assert(io.open(tmp, "w"))
  f:write(text)
  f:close()
  M.loading = true
  local ok, err = pcall(vim.cmd, "silent! source " .. vim.fn.fnameescape(tmp))
  M.loading = false
  os.remove(tmp)
  vim.v.this_session = ""
  drop_skipped()
  if not ok then
    vim.notify("hcmux: session layout failed: " .. tostring(err), vim.log.levels.WARN)
  end
end

-- ── saving ────────────────────────────────────────────────────────────────

local warned = {}
local function warn_once(key, msg)
  if not warned[key] then
    warned[key] = true
    vim.notify(msg, vim.log.levels.WARN, { title = "hcmux session" })
  end
end

local function on_saved(version, err, kind, text)
  if version then
    M.version, M.last_text = version, text
    warned.error = nil
    return true
  end
  if kind == "conflict" then
    M.state = "conflict"
    warn_once(
      "conflict",
      ("Session %s was saved by another nvim. This one stopped saving.\n:Session take keeps this layout, :Session reload loads that one."):format(
        M.name
      )
    )
  else
    warn_once("error", "hcmux: session not saved: " .. tostring(err))
  end
  return false
end

--- Save the session now.
---@param o? {sync?:boolean, force?:boolean, release?:boolean}
function M.save(o)
  o = o or {}
  if not M.name or M.loading or vim.g.SessionLoad then
    return
  end
  if M.state ~= "attached" and not o.force then
    return
  end
  local text = M.serialize()
  if not text then
    return
  end
  if is_empty() and M.last_text and not o.force then
    return -- never replace a layout with an empty nvim
  end
  if text == M.last_text and not (o.force or o.release) then
    return
  end
  local value = {
    v = 1,
    name = M.name,
    root = M.root,
    cwd = vim.fn.getcwd(),
    layout = text,
    saved_ms = now_ms(),
    holder = (not o.release) and M.holder() or nil,
  }
  local name = M.doc_name(M.name)
  if o.sync then
    local nv, err, kind = core.doc_set(name, value, M.version)
    return on_saved(nv, err, kind, text)
  end
  if M.saving then
    M.pending = true
    return
  end
  M.saving = true
  core.rpc_async("doc.set", { name = name, value = value, version = M.version }, function(res, err, _, kind)
    M.saving = false
    on_saved(res and res.version, err, kind, text)
    if M.pending then
      M.pending = false
      M.schedule()
    end
  end)
end

local timer
--- Save after things settle.
function M.schedule()
  if M.state ~= "attached" then
    return
  end
  timer = timer or uv.new_timer()
  timer:stop()
  timer:start(
    M.config.debounce,
    0,
    vim.schedule_wrap(function()
      M.save()
    end)
  )
end

-- ── attaching ─────────────────────────────────────────────────────────────

local function term()
  return require("hcmux.term")
end

--- List the session's live terminals that the layout did not show. Older
--- nvim terminals of this folder (from before sessions) are adopted.
function M.list_terminals()
  local t = term()
  local root, name = M.root, M.name
  for _, fact in ipairs(core.list()) do
    local l = fact.labels or {}
    local mine = l[M.LABEL] == name
    local legacy = l[M.LABEL] == nil and core.is_ours(fact) and l[core.LABEL .. ".cwd"] == root
    if (mine or legacy) and not t.buf_of(fact.address) then
      if legacy then
        core.label(fact.address, { [M.LABEL] = name })
      end
      t.placeholder(fact.address)
    end
  end
end

local function wipe_all()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].modified and vim.bo[b].buftype == "" then
      return false, vim.api.nvim_buf_get_name(b)
    end
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[b].hcmux_addr then
      vim.b[b].hcmux_closing = true -- a view ending, not a terminal
    end
  end
  vim.cmd("silent! tabonly | silent! only | enew")
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= vim.api.nvim_get_current_buf() then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  return true
end

--- Attach this nvim to a session (created if it does not exist).
---@param name? string default: this folder's session
---@param o? {switch?:boolean}
function M.attach(name, o)
  o = o or {}
  if not core.available() then
    return vim.notify("hcmux: `hc` (herdr-core) not found", vim.log.levels.ERROR)
  end
  name = name and M.sanitize(name) or M.default_name()
  if o.switch and M.name then
    if name == M.name then
      return
    end
    M.save({ sync = true, force = M.state == "attached", release = true })
    local ok, which = wipe_all()
    if not ok then
      return vim.notify(("Save or discard %s first."):format(which), vim.log.levels.WARN)
    end
  end

  local value, version, err = M.read(name)
  if err then
    return vim.notify("hcmux: session " .. name .. ": " .. tostring(err), vim.log.levels.ERROR)
  end
  M.name, M.version, M.last_text = name, version or 0, nil
  -- A new session belongs to the requested folder (`nvim <dir>`), not the caller's cwd.
  M.root = type(value) == "table" and value.root or o.root or M.root_of()
  vim.g.hcmux_session = name
  warned = {}

  if type(value) == "table" and value.holder and M.holder_alive(value.holder) and not is_me(value.holder) then
    M.state = "readonly"
    warn_once(
      "readonly",
      ("Session %s is attached in another nvim (pid %s). This one won't save.\n:Session take moves the session here."):format(
        name,
        tostring(value.holder.pid)
      )
    )
  else
    M.state = "attached"
  end

  if type(value) == "table" and type(value.layout) == "string" then
    M.load_layout(value.layout)
  elseif M.root and vim.fn.isdirectory(M.root) == 1 then
    vim.cmd.cd(vim.fn.fnameescape(M.root))
  end
  if not value then
    M.index_update(function(s)
      s[name] = { root = M.root, created_ms = now_ms() }
    end)
  end

  -- Show the core's state, then claim the session.
  vim.schedule(function()
    M.list_terminals()
    if M.state == "attached" then
      M.save({ force = true })
    end
    vim.api.nvim_exec_autocmds("User", { pattern = "HcmuxSession", modeline = false })
    vim.cmd("redrawstatus!")
  end)
end

--- Overwrite the session with this nvim's layout and take it over.
function M.take()
  if not M.name then
    return
  end
  local _, version = M.read(M.name)
  M.version, M.state = version or 0, "attached"
  warned = {}
  M.save({ sync = true, force = true })
  vim.notify("Session " .. M.name .. " is now attached here.", vim.log.levels.INFO)
end

--- Load the session's saved layout again (after another nvim changed it).
function M.reload()
  if not M.name then
    return
  end
  local name = M.name
  M.name = nil -- don't save on the way out
  local ok, which = wipe_all()
  M.name = name
  if not ok then
    return vim.notify(("Save or discard %s first."):format(which), vim.log.levels.WARN)
  end
  M.attach(name)
end

--- Save, then quit nvim. Terminals keep running; attach again any time.
function M.detach()
  if M.state == "attached" then
    M.save({ sync = true, force = true, release = true })
    M.released = true
  end
  vim.cmd("confirm qall")
  M.released = false -- still here: the person cancelled
end

-- Set by the `envi` launcher; kept from child processes so a nested nvim
-- can't restart this one.
local reload_file = vim.env.ENVI_RELOAD_FILE
vim.env.ENVI_RELOAD_FILE = nil

--- True when this nvim was started by the `envi` launcher, so `M.restart` can work.
function M.reloadable()
  return reload_file ~= nil and reload_file ~= ""
end

--- Detach, then have the `envi` launcher start nvim again on this session,
--- so config, plugin and launcher changes take effect. Terminals keep running.
function M.restart()
  if not reload_file or reload_file == "" then
    return vim.notify("`:reload` needs nvim started by `envi`. Use `:qd`, then run `envi`.", vim.log.levels.WARN)
  end
  vim.fn.writefile({ M.name or "" }, reload_file)
  M.detach()
  os.remove(reload_file) -- still here: the person cancelled
end

function M.rename(new)
  if not M.name then
    return
  end
  new = M.sanitize(new)
  if new == M.name then
    return
  end
  local existing = M.read(new)
  if existing then
    return vim.notify("A session named " .. new .. " already exists.", vim.log.levels.WARN)
  end
  local old = M.name
  for _, t in ipairs(M.terminals(old)) do
    core.label(t.address, { [M.LABEL] = new })
  end
  M.name, M.version, M.last_text = new, 0, nil
  if not M.save({ sync = true, force = true }) then
    M.name = old
    return
  end
  local _, ver = M.read(old)
  core.doc_set(M.doc_name(old), nil, ver or 0)
  M.index_update(function(s)
    s[new], s[old] = s[old] or { root = M.root }, nil
  end)
  vim.g.hcmux_session = new
  vim.cmd("redrawstatus!")
end

--- Every session, newest first: {name, root, saved_ms, holder, attached}.
function M.list()
  local sessions = M.index() or {}
  local ret = {}
  for name, entry in pairs(sessions) do
    local value = M.read(name)
    if type(value) == "table" or entry then
      value = type(value) == "table" and value or {}
      ret[#ret + 1] = {
        name = name,
        root = value.root or entry.root,
        saved_ms = value.saved_ms or entry.created_ms or 0,
        holder = value.holder,
        attached = M.holder_alive(value.holder),
      }
    end
  end
  table.sort(ret, function(a, b)
    return a.saved_ms > b.saved_ms
  end)
  return ret
end

-- ── pickers, commands ─────────────────────────────────────────────────────

local function age(ms)
  local s = os.time() - math.floor((ms or 0) / 1000)
  if ms == 0 then
    return "never"
  elseif s < 60 then
    return "now"
  elseif s < 3600 then
    return math.floor(s / 60) .. "m"
  elseif s < 86400 then
    return math.floor(s / 3600) .. "h"
  end
  return math.floor(s / 86400) .. "d"
end

function M.pick()
  if not (_G.Snacks and Snacks.picker) then
    return
  end
  local home = vim.env.HOME or ""
  Snacks.picker.pick({
    title = "nvim sessions (herdr-core)",
    finder = function()
      return vim.tbl_map(function(s)
        s.text = s.name .. " " .. (s.root or "")
        return s
      end, M.list())
    end,
    format = function(item)
      local here = item.name == M.name
      return {
        { here and "● " or (item.attached and "◐ " or "  "), here and "DiagnosticOk" or "DiagnosticInfo" },
        { ("%-24s "):format(item.name), here and "Special" or "Normal" },
        { ("%-5s "):format(age(item.saved_ms)), "Comment" },
        { (item.root or ""):gsub("^" .. vim.pesc(home), "~"), "Comment" },
      }
    end,
    layout = { preset = "select" },
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          M.attach(item.name, { switch = true })
        end)
      end
    end,
    actions = {
      session_kill = function(picker, item)
        if not item then
          return
        end
        if vim.fn.confirm(("End session %s and its terminals?"):format(item.name), "&Yes\n&No", 2) ~= 1 then
          return
        end
        if item.name == M.name then
          M.state, M.name, vim.g.hcmux_session = "off", nil, nil
        end
        M.kill(item.name)
        picker:find({ refresh = true })
      end,
    },
    win = { input = { keys = { ["<c-x>"] = { "session_kill", mode = { "n", "i" } } } } },
  })
end

M.commands = {
  attach = function(arg)
    M.attach(arg ~= "" and arg or nil, { switch = true })
  end,
  list = M.pick,
  save = function()
    M.save({ sync = true, force = true })
  end,
  take = M.take,
  reload = M.reload,
  detach = M.detach,
  rename = function(arg)
    if arg ~= "" then
      return M.rename(arg)
    end
    vim.ui.input({ prompt = "Rename session: ", default = M.name }, function(v)
      if v and v ~= "" then
        M.rename(v)
      end
    end)
  end,
  kill = function(arg)
    local name = arg ~= "" and M.sanitize(arg) or M.name
    if name and vim.fn.confirm(("End session %s and its terminals?"):format(name), "&Yes\n&No", 2) == 1 then
      if name == M.name then
        M.state, M.name, vim.g.hcmux_session = "off", nil, nil
      end
      M.kill(name)
    end
  end,
}

--- `name`, plus why it isn't saving when it isn't.
function M.statusline()
  if not M.name then
    return ""
  end
  local flag = ({ readonly = " (read-only)", conflict = " (not saving)" })[M.state] or ""
  return "󰆓 " .. M.name .. flag
end

-- ── setup ─────────────────────────────────────────────────────────────────

local group = vim.api.nvim_create_augroup("hcmux.session", { clear = true })
local stdin = false

--- Plain `nvim` and `nvim <dir>` attach; `nvim <file>` is a plain editor.
-- Folders that never get an automatic session (as the old auto-session config did).
local function suppressed(dir)
  local home = vim.fn.expand("~")
  local root = M.root_of(dir)
  for _, d in ipairs({ home, "/", "/tmp", "/private/tmp", home .. "/Downloads" }) do
    if root == d then
      return true
    end
  end
  return false
end

function M.autostart()
  -- Implicit, so silent: without herdr-core (a fresh clone, a remote box) nvim is a plain editor.
  if vim.env.HCMUX_NO_SESSION == "1" or stdin or not core.available() then
    return
  end
  local name = vim.env.HCMUX_SESSION
  if name == nil or name == "" then
    if #vim.api.nvim_list_uis() == 0 then
      return -- headless, embedded
    end
    local args = vim.fn.argv()
    if #args > 1 or (#args == 1 and vim.fn.isdirectory(args[1]) == 0) then
      return
    end
    if suppressed(args[1]) then
      return
    end
    name = M.default_name(args[1])
    return M.attach(name, { root = M.root_of(args[1]) })
  end
  M.attach(name)
end

function M.setup(cfg)
  M.config = vim.tbl_deep_extend("force", M.config, cfg or {})

  -- New terminals belong to the attached session.
  local t = term()
  t.config.labels = function()
    return M.name and { [M.LABEL] = M.name } or {}
  end
  -- The session lists its own terminals; hcmux's folder restore stands down.
  t.config.scope = function(fact)
    return M.name ~= nil and (fact.labels or {})[M.LABEL] == M.name
  end

  vim.api.nvim_create_autocmd("StdinReadPre", {
    group = group,
    callback = function()
      stdin = true
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      vim.schedule(M.autostart)
    end,
  })

  vim.api.nvim_create_autocmd({
    "BufAdd",
    "BufDelete",
    "BufWinEnter",
    "BufWritePost",
    "WinNew",
    "WinClosed",
    "WinResized",
    "TabNew",
    "TabClosed",
    "DirChanged",
    "CursorHold",
    "FocusLost",
  }, {
    group = group,
    callback = function()
      M.schedule()
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "HcmuxChanged",
    callback = function()
      M.schedule() -- a terminal renamed or gone
    end,
  })

  -- Quitting is detaching.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if M.state == "attached" and not M.released then
        M.save({ sync = true, force = true, release = true })
      end
    end,
  })

  vim.api.nvim_create_user_command("Session", function(opts)
    local sub, rest = opts.args:match("^(%S+)%s*(.*)$")
    local fn = M.commands[sub or "list"]
    if not fn then
      return vim.notify("Session: unknown subcommand " .. tostring(sub), vim.log.levels.ERROR)
    end
    fn(rest or "")
  end, {
    nargs = "*",
    complete = function(lead, line)
      local words = vim.split(line, "%s+")
      if #words <= 2 then
        return vim.tbl_filter(function(s)
          return s:find("^" .. vim.pesc(lead))
        end, vim.tbl_keys(M.commands))
      end
      if words[2] == "attach" or words[2] == "kill" then
        return vim.tbl_map(function(s)
          return s.name
        end, M.list())
      end
      return {}
    end,
    desc = "nvim sessions in herdr-core",
  })
  vim.api.nvim_create_user_command("Detach", M.detach, { desc = "Save the session and quit; terminals keep running" })
  vim.api.nvim_create_user_command(
    "Reload",
    M.restart,
    { desc = "Detach and start envi again on this session (picks up config changes)" }
  )
  -- `:detach`, `:qd` and `:reload` too (user commands must start uppercase).
  -- Only the whole command line expands, so :q, :qa, :wq … keep their meaning.
  for word, cmd in pairs({ detach = "Detach", qd = "Detach", reload = "Reload" }) do
    vim.cmd(
      ("cnoreabbrev <expr> %s (getcmdtype() ==# ':' && getcmdline() ==# '%s') ? '%s' : '%s'"):format(
        word,
        word,
        cmd,
        word
      )
    )
  end
end

return M
