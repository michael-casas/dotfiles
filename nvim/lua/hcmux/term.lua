-- hcmux.term: nvim buffers that are views onto herdr-core terminals.
--
-- Each buffer runs `hc attach <addr>`. Deleting the buffer, closing the
-- window or quitting nvim only ends that viewer; the program keeps running in
-- the core and can be attached again from any nvim, the Herdr app or `hc`.
local core = require("hcmux.core")

local M = {}

M.config = {
  history = 2000, -- scrollback lines replayed on attach
  auto_insert = true, -- entering a terminal window enters terminal mode
  restore = true, -- on start, list this project's live terminals as buffers
  labels = nil, -- fun(): table  extra labels for new terminals (session)
  scope = nil, -- fun(fact): boolean  which terminals `restore` lists
}

local group = vim.api.nvim_create_augroup("hcmux.term", { clear = true })

-- ── buffer bookkeeping ───────────────────────────────────────────────────

function M.addr_of(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  return vim.b[buf].hcmux_addr
end

function M.buf_of(addr)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].hcmux_addr == addr then
      return buf
    end
  end
end

--- hcmux buffers in buffer-list order.
function M.bufs()
  local ret = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].hcmux_addr and vim.bo[buf].buflisted then
      ret[#ret + 1] = buf
    end
  end
  return ret
end

local function project()
  return vim.fn.getcwd()
end

local function set_name(buf, addr)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local title = core.title(core.terms[addr]):gsub("/", "∕")
  local old = vim.api.nvim_buf_get_name(buf)
  local name = ("hc://%s/%s"):format(addr, title)
  if not pcall(vim.api.nvim_buf_set_name, buf, name) then
    pcall(vim.api.nvim_buf_set_name, buf, name .. " [viewer " .. buf .. "]")
  end
  -- Renaming leaves the old name behind as an unlisted alternate buffer.
  local stale = old ~= "" and vim.fn.bufnr(old) or -1
  if stale > 0 and stale ~= buf and not vim.bo[stale].buflisted and not vim.api.nvim_buf_is_loaded(stale) then
    pcall(vim.api.nvim_buf_delete, stale, { force = true })
  end
end

--- A centered floating window covering `size` of the editor (each way).
---@param o {size?:number, title?:string}
local function open_float(o)
  local size = o.size or 0.65
  local lines = vim.o.lines - vim.o.cmdheight
  local width = math.max(20, math.floor(vim.o.columns * size))
  local height = math.max(5, math.floor(lines * size))
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].bufhidden = "wipe"
  return vim.api.nvim_open_win(scratch, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = o.title and (" " .. o.title .. " ") or nil,
    title_pos = o.title and "center" or nil,
  })
end

---@param where? "current"|"split"|"vsplit"|"tab"|"float"
local function in_window(where, o)
  if where == "float" then
    return open_float(o or {})
  elseif where == "split" then
    vim.cmd("split")
  elseif where == "vsplit" then
    vim.cmd("vsplit")
  elseif where == "tab" then
    vim.cmd("tabnew")
    -- tabnew's empty buffer goes away once the terminal replaces it
    vim.bo.bufhidden = "wipe"
  end
end

--- Close a buffer the way a multiplexer closes a pane: a split window goes
--- away, the last window in a tab keeps its place and shows another buffer.
local function close_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local tab = vim.api.nvim_win_get_tabpage(win)
    local wins = vim.tbl_filter(function(w)
      return vim.api.nvim_win_get_config(w).relative == ""
    end, vim.api.nvim_tabpage_list_wins(tab))
    if vim.api.nvim_win_get_config(win).relative ~= "" or #wins > 1 then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  if vim.api.nvim_buf_is_valid(buf) then
    if _G.Snacks and Snacks.bufdelete then
      Snacks.bufdelete({ buf = buf, force = true, wipe = true })
    else
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

-- `hc attach` opens with ESC[?1049l, which also restores the saved cursor.
-- Neovim's terminal restores a never-saved cursor with an explicit black pen,
-- so every cell erased after it (blank rows, the rest of each line) stays
-- black whatever the window's Normal. Save a clean cursor (ESC 7) first, then
-- exec hc: the job keeps hc's pid and exit status, and the address and other
-- arguments reach hc only as "$@", never as shell text.
local VIEWER = { "/bin/sh", "-c", "printf '\\033%s' 7; exec \"$@\"", "hcmux-viewer" }

-- Start the viewer in the current (empty) buffer.
local function start_viewer(buf, addr)
  vim.b[buf].hcmux_closing = nil
  local cmd = vim.list_extend(vim.list_slice(VIEWER), { "hc", "attach", "--history", tostring(M.config.history), addr })
  local opts = {
    on_exit = function(_, code)
      vim.schedule(function()
        M._viewer_exited(buf, addr, code)
      end)
    end,
  }
  local ok, job
  if vim.fn.has("nvim-0.11") == 1 then
    opts.term = true
    ok, job = pcall(vim.fn.jobstart, cmd, opts)
  else
    ok, job = pcall(vim.fn.termopen, cmd, opts)
  end
  if not ok or job <= 0 then
    vim.notify("hcmux: could not attach " .. addr .. ": " .. tostring(job), vim.log.levels.ERROR)
    return false
  end
  vim.b[buf].hcmux_addr = addr
  require("config.panel-close").bind(buf, function()
    M.detach(buf)
  end, "Detach terminal")
  vim.b[buf].hcmux_lazy = nil
  vim.bo[buf].buflisted = true
  set_name(buf, addr)
  return true
end

function M._viewer_exited(buf, addr, code)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].hcmux_closing then
    return
  end
  local t = core.get(addr)
  if t and t.state == "live" then
    -- Detached (ctrl+\ or a lost connection): the program is still running.
    vim.notify(("%s detached; still running in herdr-core"):format(addr), vim.log.levels.INFO, { title = "hcmux" })
    return close_buf(buf)
  end
  if t and t.state == "finished" then
    local ec = t.exit_code
    if ec == 0 or (ec == nil and t.reason == "killed") then
      core.exec_async({ "rm", addr })
      return close_buf(buf)
    end
    -- Failed: keep the last screen visible so the error can be read.
    vim.notify(
      ("%s exited (%s)"):format(core.title(t), ec or t.reason or "?"),
      vim.log.levels.WARN,
      { title = "hcmux" }
    )
    return
  end
  if code ~= 0 then
    vim.notify(("hcmux: viewer for %s ended (%d)"):format(addr, code), vim.log.levels.WARN)
  end
end

-- ── public API ───────────────────────────────────────────────────────────

--- Show terminal `addr` in a window. Reuses its buffer if one exists.
---@param where? "current"|"split"|"vsplit"|"tab"
---@param o? {size?:number, title?:string, separate?:boolean} float options; separate creates a viewer when already shown
function M.attach(addr, where, o)
  local buf = M.buf_of(addr)
  -- Differently sized T3 windows need independent PTYs. A shared job is
  -- resized by Neovim when either window replaces its buffer during replay.
  if buf and o and o.separate and #vim.fn.win_findbuf(buf) > 0 then
    buf = nil
  end
  if buf then
    local win = vim.fn.win_findbuf(buf)[1]
    if win and (where == nil or where == "current") then
      vim.api.nvim_set_current_win(win)
    else
      in_window(where, o)
      vim.api.nvim_set_current_buf(buf)
    end
    if vim.b[buf].hcmux_lazy then
      M._wake(buf)
    end
    return buf
  end
  in_window(where, o)
  buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  if not start_viewer(buf, addr) then
    return
  end
  if M.config.auto_insert then
    vim.cmd.startinsert()
  end
  return buf
end

--- Fresh replay for one focused stale viewer, never a new core program.
--- Other windows retain their old buffer until they elect to refresh too.
function M.reattach(win)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_get_current_win() ~= win then
    return
  end
  local old = vim.api.nvim_win_get_buf(win)
  local addr = M.addr_of(old)
  if not addr then
    return
  end
  local buf = vim.api.nvim_create_buf(vim.bo[old].buflisted, false)
  vim.b[buf].hcmux_display = vim.b[old].hcmux_display
  vim.api.nvim_win_set_buf(win, buf)
  if not start_viewer(buf, addr) then
    vim.api.nvim_win_set_buf(win, old)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return
  end
  -- Reusing an address is intentional: distinguish viewer buffer names while
  -- another window still carries the previous replay.
  if #vim.fn.win_findbuf(old) == 0 then
    vim.b[old].hcmux_closing = true
    pcall(vim.api.nvim_buf_delete, old, { force = true })
    set_name(buf, addr)
  end
  return buf
end

--- Start a program in herdr-core and show it.
---@param argv? string[] nil = a shell
---@param o? {where?:string, cwd?:string, title?:string, name?:string, labels?:table<string,string>, session?:boolean, listed?:boolean, size?:number, display?:{fg?:string, bg?:string, cursor?:string}}
--- display: colors (#rrggbb) for this terminal instead of nvim's Normal/Cursor,
--- e.g. a themed float's own background. The program gets them from its first
--- byte (terminal.run) and as this buffer's OSC 10/11/12 answers. Default: none.
function M.open(argv, o)
  o = o or {}
  if not core.available() then
    vim.notify("hcmux: `hc` (herdr-core) not found on PATH", vim.log.levels.ERROR)
    return
  end
  -- o.session == false: not part of the attached session (not restored)
  local extra = (o.session ~= false and M.config.labels) and M.config.labels() or {}
  local labels = vim.tbl_extend("force", {
    [core.LABEL .. ".cwd"] = project(),
  }, extra, o.labels or {})
  if o.title then
    labels[core.LABEL .. ".title"] = o.title
  end
  -- Open the window first: the program starts at that window's size.
  local prev_win = vim.api.nvim_get_current_win()
  in_window(o.where, { size = o.size, title = o.title })
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, false)
  local prev_buf = vim.api.nvim_win_get_buf(win)
  vim.api.nvim_win_set_buf(win, buf)
  local size =
    { cols = math.max(vim.api.nvim_win_get_width(win), 1), rows = math.max(vim.api.nvim_win_get_height(win), 1) }
  vim.b[buf].hcmux_display = o.display

  local addr, err =
    core.run(argv, { cwd = o.cwd or vim.fn.getcwd(), name = o.name, labels = labels, size = size, display = o.display })
  if not addr then
    -- Undo the window we opened for it.
    if win ~= prev_win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    else
      pcall(vim.api.nvim_win_set_buf, win, prev_buf)
    end
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    vim.notify("hcmux: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  if not start_viewer(buf, addr) then
    return
  end
  if o.listed == false then
    vim.bo[buf].buflisted = false
  end
  if M.config.auto_insert then
    vim.cmd.startinsert()
  end
  return buf, addr
end

--- Stop viewing; the program keeps running.
function M.detach(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not M.addr_of(buf) then
    return vim.notify("hcmux: not a herdr-core terminal", vim.log.levels.WARN)
  end
  vim.b[buf].hcmux_closing = true
  close_buf(buf)
end

--- End the program and close its buffer.
function M.kill(addr_or_buf, confirm)
  local addr = type(addr_or_buf) == "string" and addr_or_buf or M.addr_of(addr_or_buf)
  if not addr then
    return vim.notify("hcmux: not a herdr-core terminal", vim.log.levels.WARN)
  end
  local title = core.title(core.terms[addr])
  if confirm ~= false and vim.fn.confirm(("Kill %s (%s)?"):format(title, addr), "&Yes\n&No", 2) ~= 1 then
    return
  end
  local buf = M.buf_of(addr)
  if buf then
    vim.b[buf].hcmux_closing = true
  end
  core.kill(addr, function()
    if buf then
      close_buf(buf)
    end
  end)
end

function M.rename(title, buf)
  local addr = M.addr_of(buf)
  if not addr then
    return vim.notify("hcmux: not a herdr-core terminal", vim.log.levels.WARN)
  end
  local function apply(t)
    if not t or t == "" then
      return
    end
    local ok, err = core.label(addr, { [core.LABEL .. ".title"] = t })
    if not ok then
      return vim.notify("hcmux: " .. tostring(err), vim.log.levels.ERROR)
    end
    set_name(M.buf_of(addr), addr)
    vim.cmd.redrawstatus()
  end
  if title then
    return apply(title)
  end
  vim.ui.input({ prompt = "Rename terminal: ", default = core.title(core.terms[addr]) }, apply)
end

--- Next/previous hcmux buffer in the current window (like tmux n/p).
function M.cycle(dir)
  local bufs = M.bufs()
  if #bufs == 0 then
    return
  end
  local cur = vim.api.nvim_get_current_buf()
  local idx = 0
  for i, b in ipairs(bufs) do
    if b == cur then
      idx = i
    end
  end
  local nxt = bufs[((idx - 1 + dir) % #bufs) + 1]
  if idx == 0 then
    nxt = dir > 0 and bufs[1] or bufs[#bufs]
  end
  vim.api.nvim_set_current_buf(nxt)
end

--- Paste text into a terminal and press enter (default: the last one used).
function M.send(text, addr)
  addr = addr or M.addr_of() or M.last
  if not addr or not core.terms[addr] then
    return require("hcmux.picker").pick({
      prompt = "Send to ",
      on_pick = function(a)
        M.send(text, a)
      end,
    })
  end
  M.last = addr
  core.send(addr, text, function(_, err)
    if err then
      vim.notify("hcmux: " .. err, vim.log.levels.ERROR)
    end
  end)
end

-- ── restore: list live terminals as buffers that attach when shown ───────

--- Put a buffer in the list for `addr` without attaching yet.
---@param buf? integer adopt this buffer (e.g. one a session created) instead of a new one
function M.placeholder(addr, buf)
  local existing = M.buf_of(addr)
  if existing and existing ~= buf then
    return existing
  end
  buf = buf or vim.api.nvim_create_buf(true, false)
  vim.bo[buf].buflisted = true
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.b[buf].hcmux_addr = addr
  vim.b[buf].hcmux_lazy = true
  set_name(buf, addr)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "",
    ("  herdr-core terminal %s: %s"):format(addr, core.title(core.terms[addr])),
    "  attaching…",
  })
  vim.bo[buf].modified = false
  vim.bo[buf].modifiable = false
  return buf
end

--- The terminal behind a placeholder is gone. Keep the windows (a restored
--- layout should not collapse); show a note in them instead.
local function gone(buf, addr)
  vim.notify(("hcmux: %s has ended"):format(addr), vim.log.levels.WARN, { title = "hcmux" })
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then
    return close_buf(buf)
  end
  local note = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(note, 0, -1, false, {
    "",
    ("  herdr-core terminal %s has ended."):format(addr),
    "  <C-\\>c starts a new shell here, <C-\\>w picks another terminal.",
  })
  vim.bo[note].modifiable = false
  vim.bo[note].bufhidden = "wipe"
  for _, win in ipairs(wins) do
    vim.api.nvim_win_set_buf(win, note)
  end
  vim.b[buf].hcmux_closing = true
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

--- Turn a placeholder into a live viewer in the current window.
function M._wake(buf)
  if not (vim.api.nvim_buf_is_valid(buf) and vim.b[buf].hcmux_lazy) then
    return
  end
  -- The viewer takes its size from a window, so wake only once one shows it
  -- (focused or not: a layout can show several restored terminals at once).
  local win = vim.fn.win_findbuf(buf)[1]
  if not win then
    return
  end
  local addr = vim.b[buf].hcmux_addr
  local t = core.terms[addr] or core.get(addr)
  if not t or t.state ~= "live" then
    return gone(buf, addr)
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.bo[buf].buftype = ""
  vim.bo[buf].modified = false
  local ok = vim.api.nvim_win_call(win, function()
    return start_viewer(buf, addr)
  end)
  if ok and M.config.auto_insert and vim.api.nvim_get_current_buf() == buf then
    vim.cmd.startinsert()
  end
end

--- Re-derive every hcmux buffer's name from its terminal's current title.
function M.refresh_names()
  for _, buf in ipairs(M.bufs()) do
    set_name(buf, vim.b[buf].hcmux_addr)
  end
end

--- List this project's live nvim terminals as buffers (attached when shown).
---@param all? boolean every project, not just the current directory
function M.restore(all)
  local cwd = project()
  local found = core.list(function(t)
    if not core.is_ours(t) then
      return false
    end
    if M.config.scope and not all then
      return M.config.scope(t)
    end
    return all or t.labels[core.LABEL .. ".cwd"] == cwd
  end)
  local n = 0
  for i = #found, 1, -1 do -- oldest first, so buffer order matches creation
    if not M.buf_of(found[i].address) then
      M.placeholder(found[i].address)
      n = n + 1
    end
  end
  return n
end

-- ── autocmds ─────────────────────────────────────────────────────────────

function M.setup(cfg)
  M.config = vim.tbl_deep_extend("force", M.config, cfg or {})

  -- `hc attach` asks its terminal (this buffer) for its colors with OSC
  -- 10/11/12 and reports them to herdr-core, which answers the program's own
  -- color queries with them. nvim leaves the queries unanswered, so programs
  -- fall back to black backgrounds; answer with the colorscheme's colors, or
  -- the buffer's own display colors (vim.b.hcmux_display: M.open's display,
  -- kept in step by its owner, e.g. hcmux.t3), never depending on
  -- which window happens to have focus.
  vim.api.nvim_create_autocmd("TermRequest", {
    group = group,
    callback = function(ev)
      if not vim.b[ev.buf].hcmux_addr then
        return
      end
      local seq = type(ev.data) == "table" and ev.data.sequence or ev.data
      local code = type(seq) == "string" and seq:match("^\27%](1[012]);%?")
      if not code then
        return
      end
      local display = core.display(vim.b[ev.buf].hcmux_display)
      local hex = ({ ["10"] = display.fg, ["11"] = display.bg, ["12"] = display.cursor })[code]
      local color = type(hex) == "string" and tonumber(hex:match("^#(%x%x%x%x%x%x)$") or "", 16)
      local chan = vim.bo[ev.buf].channel
      if not color or not chan or chan <= 0 then
        return
      end
      local r, g, b = bit.rshift(color, 16), bit.band(bit.rshift(color, 8), 0xff), bit.band(color, 0xff)
      local rgb = ("rgb:%02x%02x/%02x%02x/%02x%02x"):format(r, r, g, g, b, b)
      pcall(vim.api.nvim_chan_send, chan, ("\27]%s;%s\27\\"):format(code, rgb))
    end,
  })

  -- A restored placeholder attaches as soon as any window shows it.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      if vim.b[ev.buf].hcmux_lazy then
        vim.schedule(function()
          M._wake(ev.buf)
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      if not vim.b[ev.buf].hcmux_addr then
        return
      end
      M.last = vim.b[ev.buf].hcmux_addr
      vim.schedule(function()
        if vim.api.nvim_get_current_buf() ~= ev.buf then
          return
        end
        if vim.b[ev.buf].hcmux_lazy then
          M._wake(ev.buf)
        elseif M.config.auto_insert and vim.bo[ev.buf].buftype == "terminal" and vim.fn.mode() ~= "t" then
          vim.cmd.startinsert()
        end
      end)
    end,
  })

  -- Keep buffer names in step with renames done elsewhere (hc label, app).
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "HcmuxChanged",
    callback = function()
      for _, buf in ipairs(M.bufs()) do
        local addr = vim.b[buf].hcmux_addr
        local want = ("hc://%s/%s"):format(addr, (core.title(core.terms[addr]):gsub("/", "∕")))
        if vim.api.nvim_buf_get_name(buf) ~= want then
          set_name(buf, addr)
        end
      end
    end,
  })
end

return M
