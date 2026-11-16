-- File-first board popover. Direct private stdio, no hc/terminal/T3 dependency.
local M = { active = false }
local api = vim.api
local uv = vim.uv or vim.loop
local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(uv.fs_realpath(source) or source, ":h:h:h")
local main = root .. "/tools/envi-board/main.mjs"
local state, last_path, last_opts
local FRAME, TOTAL = 256 * 1024, 32 * 1024 * 1024
local request = 0

local function valid(win)
  return win and api.nvim_win_is_valid(win)
end

local function geometry()
  local width = math.max(1, math.min(vim.o.columns - 2, math.floor(vim.o.columns * 0.9)))
  local height = math.max(1, math.min(vim.o.lines - 4, math.floor(vim.o.lines * 0.85)))
  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " BOARD ",
    title_pos = "center",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  }
end

local function config(s)
  local cfg = geometry()
  cfg.title = s.snapshot and s.snapshot.stale and " BOARD · STALE " or " BOARD "
  return cfg
end

local function safe(s)
  return tostring(s):gsub("[%z\1-\31\127]", function(c)
    return string.format("<U+%04X>", string.byte(c))
  end)
end

local function set_lines(buf, lines)
  if not api.nvim_buf_is_valid(buf) then
    return
  end
  api.nvim_set_option_value("modifiable", true, { buf = buf })
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_set_option_value("modified", false, { buf = buf })
end

local function theme(s)
  if not s.snapshot then
    return
  end
  local t = s.snapshot.theme and s.snapshot.theme.tokens or {}
  local function color(k)
    return type(t[k]) == "string" and t[k]:match("^#%x%x%x%x%x%x$") and t[k] or nil
  end
  api.nvim_set_hl(0, "EnviBoardNormal", { fg = color("fg"), bg = color("bg") })
  api.nvim_set_hl(0, "EnviBoardBorder", { fg = color("border"), bg = color("bg") })
  api.nvim_set_hl(0, "EnviBoardTitle", { fg = color("title"), bg = color("bg"), bold = true })
  for _, win in ipairs({ s.win, s.child }) do
    if valid(win) then
      api.nvim_set_option_value(
        "winhl",
        "Normal:EnviBoardNormal,NormalFloat:EnviBoardNormal,FloatBorder:EnviBoardBorder,FloatTitle:EnviBoardTitle",
        { win = win }
      )
    end
  end
end

local function send(s, op, fields)
  if state ~= s or not s.job or s.job <= 0 then
    return
  end
  request = request + 1
  local value = vim.tbl_extend("force", { v = 1, id = request, op = op }, fields or {})
  pcall(vim.fn.chansend, s.job, vim.json.encode(value) .. "\n")
  return request
end

local function dismiss(s)
  if valid(s.child) then
    api.nvim_win_close(s.child, true)
  end
  s.child = nil
end

function M.close()
  local s = state
  if not s then
    M.active = false
    return
  end
  state = nil
  M.active = false
  if s.group then
    pcall(api.nvim_del_augroup_by_id, s.group)
  end
  dismiss(s)
  if valid(s.win) then
    pcall(api.nvim_win_close, s.win, true)
  end
  if api.nvim_buf_is_valid(s.buf) then
    pcall(api.nvim_buf_delete, s.buf, { force = true })
  end
  if s.job and s.job > 0 then
    -- EOF lets the exact owned child close watchers/render jobs. A bounded
    -- fallback ends only that job, never enumerates or targets other processes.
    pcall(vim.fn.chanclose, s.job, "stdin")
    local job = s.job
    vim.defer_fn(function()
      if vim.fn.jobwait({ job }, 0)[1] == -1 then
        pcall(vim.fn.jobstop, job)
      end
    end, 500)
  end
  if valid(s.invoker) then
    pcall(api.nvim_set_current_win, s.invoker)
  end
end

local function overlay(s, lines, title)
  dismiss(s)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  set_lines(buf, lines)
  local config = geometry()
  config.width = math.max(1, config.width - 4)
  config.height = math.max(1, config.height - 2)
  config.row = config.row + 1
  config.col = config.col + 2
  config.title = " " .. title .. " "
  s.child = api.nvim_open_win(buf, true, config)
  vim.wo[s.child].wrap = false
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      dismiss(s)
      if valid(s.win) then
        api.nvim_set_current_win(s.win)
      end
    end, { buffer = buf, nowait = true })
  end
  theme(s)
end

local function paint(s, data)
  local cursor = valid(s.win) and api.nvim_win_get_cursor(s.win) or { 1, 0 }
  local old = s.snapshot and s.snapshot.mapping[cursor[1]]
  local intra = 0
  if old and type(old.id) == "string" then
    local first = cursor[1]
    while first > 1 and s.snapshot.mapping[first - 1].id == old.id do
      first = first - 1
    end
    intra = cursor[1] - first
  end
  s.snapshot = data
  local rows = {}
  for _, row in ipairs(data.rows) do
    rows[#rows + 1] = safe(row)
  end
  if #rows == 0 then
    rows = { "Empty board" }
  end
  set_lines(s.buf, rows)
  if valid(s.win) then
    local selected = math.min(cursor[1], #rows)
    if old and type(old.id) == "string" then
      for i, item in ipairs(data.mapping) do
        if item.id == old.id then
          selected = math.min(i + intra, #rows)
          break
        end
      end
    end
    pcall(api.nvim_win_set_cursor, s.win, { selected, 0 })
    api.nvim_win_set_config(s.win, config(s))
    theme(s)
  end
end

local function frame(s, line)
  if #line > FRAME then
    s.pending = nil
    return
  end
  local ok, f = pcall(vim.json.decode, line)
  if not ok or type(f) ~= "table" or f.v ~= 1 then
    s.pending = nil
    return
  end
  if f.type == "begin" then
    if
      type(f.seq) ~= "number"
      or f.seq <= s.seq
      or type(f.count) ~= "number"
      or f.count < 1
      or f.count > 1024
      or type(f.bytes) ~= "number"
      or f.bytes > TOTAL
      or f.bytes < 0
      or type(f.generation) ~= "number"
    then
      return
    end
    s.pending =
      { seq = f.seq, generation = f.generation, count = f.count, bytes = f.bytes, chunks = {}, size = 0, next = 0 }
  elseif f.type == "chunk" then
    local p = s.pending
    if not p or f.seq ~= p.seq or f.index ~= p.next or type(f.data) ~= "string" then
      s.pending = nil
      return
    end
    p.size = p.size + #f.data
    if p.size > TOTAL or p.next >= p.count then
      s.pending = nil
      return
    end
    p.chunks[#p.chunks + 1] = f.data
    p.next = p.next + 1
  elseif f.type == "end" then
    local p = s.pending
    s.pending = nil
    if not p or p.seq ~= f.seq or p.generation ~= f.generation or p.next ~= p.count or p.size ~= p.bytes then
      return
    end
    local good, data = pcall(vim.json.decode, table.concat(p.chunks))
    if
      not good
      or type(data) ~= "table"
      or type(data.rows) ~= "table"
      or type(data.mapping) ~= "table"
      or data.path ~= s.path
      or data.generation ~= p.generation
    then
      return
    end
    for _, row in ipairs(data.rows) do
      if type(row) ~= "string" then
        return
      end
    end
    for _, item in ipairs(data.mapping) do
      if type(item) ~= "table" or (item.id ~= vim.NIL and item.id ~= nil and type(item.id) ~= "string") then
        return
      end
    end
    s.seq = p.seq
    paint(s, data)
  elseif f.type == "source" and f.id == s.source_request and s.snapshot and f.hash == s.snapshot.hash then
    local value = f.value
    if type(value) ~= "table" or type(value.lines) ~= "table" then
      return
    end
    local lines = {
      safe("PINNED " .. (f.block or "") .. " · " .. (value.state or "unavailable")),
      safe(value.notice or value.reason or ""),
      "",
    }
    for _, row in ipairs(value.lines) do
      lines[#lines + 1] = safe(row)
    end
    overlay(s, lines, "IMMUTABLE SOURCE")
  elseif f.type == "error" then
    vim.notify("Board worker rejected a stale, malformed or unavailable request", vim.log.levels.WARN)
  end
end

local function receive(s, data)
  if state ~= s or not data then
    return
  end
  for i, part in ipairs(data) do
    if i > 1 then
      if not s.discard then
        frame(s, s.partial)
      end
      s.partial = ""
      s.discard = false
    end
    if not s.discard then
      s.partial = s.partial .. part
      if #s.partial > FRAME then
        s.partial = ""
        s.discard = true
        s.pending = nil
      end
    end
  end
end

local function jump(s, direction)
  if not s.snapshot then
    return
  end
  local row = api.nvim_win_get_cursor(s.win)[1]
  local choice
  for i, entry in ipairs(s.snapshot.mapping) do
    if entry.kind == "heading" and entry.id and (i == 1 or s.snapshot.mapping[i - 1].id ~= entry.id) then
      if direction > 0 and i > row then
        choice = i
        break
      end
      if direction < 0 and i < row then
        choice = i
      end
    end
  end
  if choice then
    api.nvim_win_set_cursor(s.win, { choice, 0 })
  end
end

function M.open(path, opts)
  opts = opts or {}
  path = path or last_path
  if type(path) ~= "string" or path == "" then
    vim.notify("Board requires a file path", vim.log.levels.WARN)
    return
  end
  path = vim.fn.fnamemodify(path, ":p")
  if state and state.path == path then
    if valid(state.win) then
      api.nvim_set_current_win(state.win)
      return
    end
    M.close()
  elseif state then
    M.close()
  end
  last_path, last_opts = path, opts
  local s = { path = path, opts = opts, invoker = api.nvim_get_current_win(), partial = "", seq = 0 }
  state = s
  s.buf = api.nvim_create_buf(false, true)
  vim.bo[s.buf].bufhidden = "wipe"
  vim.bo[s.buf].swapfile = false
  vim.b[s.buf].envi_board = true
  set_lines(s.buf, { "Loading local board…" })
  s.win = api.nvim_open_win(s.buf, true, geometry())
  vim.wo[s.win].wrap = false
  vim.wo[s.win].conceallevel = 0
  M.active = true
  s.group = api.nvim_create_augroup("EnviBoardOwned", { clear = true })
  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = s.buf, nowait = true, silent = true })
  end
  map("q", M.close)
  map("<Esc>", function() end)
  map("R", function()
    send(s, "refresh")
  end)
  map("[s", function()
    jump(s, -1)
  end)
  map("]s", function()
    jump(s, 1)
  end)
  map("s", function()
    if not s.snapshot then
      return
    end
    local m = s.snapshot.mapping[api.nvim_win_get_cursor(s.win)[1]]
    if m then
      for i, row in ipairs(s.snapshot.rows) do
        if s.snapshot.mapping[i] and s.snapshot.mapping[i].id == m.id and row == "Mermaid source:" then
          api.nvim_win_set_cursor(s.win, { i, 0 })
          break
        end
      end
    end
  end)
  map("<CR>", function()
    if not s.snapshot then
      return
    end
    local m = s.snapshot.mapping[api.nvim_win_get_cursor(s.win)[1]]
    if m and m.kind == "wb-source" then
      s.source_request = send(s, "source", { block = m.id, expectedHash = s.snapshot.hash })
    end
  end)
  map("e", function()
    local m = s.snapshot and s.snapshot.mapping[api.nvim_win_get_cursor(s.win)[1]]
    local file, line, invoker = vim.fs.normalize(s.path), m and m.line or 1, s.invoker
    M.close()
    if valid(invoker) then
      api.nvim_set_current_win(invoker)
    end
    -- bufadd/bufload never interpolate authored text into Ex or replace a
    -- modified buffer. The normal source buffer participates in reload safety.
    local buf = vim.fn.bufadd(file)
    vim.fn.bufload(buf)
    local cur = api.nvim_get_current_buf()
    if cur ~= buf and (vim.bo[cur].modified or vim.bo[cur].buftype ~= "") then
      vim.cmd("split")
    end
    api.nvim_set_current_buf(buf)
    api.nvim_win_set_cursor(0, { math.min(line, api.nvim_buf_line_count(buf)), 0 })
  end)
  map("<Tab>", function()
    if not s.snapshot then
      return
    end
    local rows, targets = {}, {}
    for i, item in ipairs(s.snapshot.mapping) do
      if
        item.kind == "heading"
        and type(item.id) == "string"
        and (i == 1 or s.snapshot.mapping[i - 1].id ~= item.id)
      then
        rows[#rows + 1] = s.snapshot.rows[i]
        targets[#targets + 1] = i
      end
    end
    if #rows == 0 then
      rows = { "No sections" }
    end
    overlay(s, rows, "OUTLINE · Enter to jump")
    local child = api.nvim_win_get_buf(s.child)
    vim.keymap.set("n", "<CR>", function()
      local row = api.nvim_win_get_cursor(s.child)[1]
      dismiss(s)
      if valid(s.win) then
        api.nvim_set_current_win(s.win)
        if targets[row] then
          api.nvim_win_set_cursor(s.win, { targets[row], 0 })
        end
      end
    end, { buffer = child, nowait = true })
  end)
  map("?", function()
    overlay(s, {
      "Read-only file-first review document",
      "Native motions/search/yank; Ctrl-w w leaves the board open",
      "[s / ]s: heading; s: exact Mermaid source",
      "Enter: immutable commit pin (host binding required)",
      "e: edit board file; R: refresh; q: close; Esc: stay",
      "No document links, images, scripts or callbacks execute.",
    }, "BOARD HELP")
  end)
  api.nvim_create_autocmd("WinClosed", {
    group = s.group,
    pattern = tostring(s.win),
    callback = function()
      if state == s then
        M.close()
      end
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = s.group,
    buffer = s.buf,
    callback = function()
      if state == s then
        M.close()
      end
    end,
  })
  api.nvim_create_autocmd("VimLeavePre", { group = s.group, callback = M.close })
  api.nvim_create_autocmd("ColorScheme", {
    group = s.group,
    callback = function()
      theme(s)
    end,
  })
  api.nvim_create_autocmd("VimResized", {
    group = s.group,
    callback = function()
      if valid(s.win) then
        api.nvim_win_set_config(s.win, config(s))
        send(s, "render", { width = geometry().width })
      end
      dismiss(s)
    end,
  })
  s.job = vim.fn.jobstart({ "node", main, "worker" }, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      vim.schedule(function()
        receive(s, data)
      end)
    end,
    on_stderr = function() end, -- Never echo arbitrary child stderr into editor.
    on_exit = function()
      vim.schedule(function()
        if state == s then
          set_lines(s.buf, { "Board worker exited; close/reopen to retry" })
        end
      end)
    end,
  })
  if s.job <= 0 then
    set_lines(s.buf, { "Board worker unavailable: Node 22+ is required" })
  end
  send(s, "open", { path = path, width = geometry().width, bindings = opts.bindings or vim.empty_dict() })
  api.nvim_exec_autocmds("User", { pattern = "EnviBoard", data = { buf = s.buf } })
end

function M.toggle(path, opts)
  if state then
    M.close()
  else
    M.open(path or last_path, opts or last_opts)
  end
end

function M.refresh()
  if state then
    send(state, "refresh")
  end
end

return M
