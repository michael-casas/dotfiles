-- hcmux.core: the herdr-core (`hc`) backend.
--
-- Programs run in herdr-core terminals, never inside nvim. nvim only shows
-- them (see hcmux.term). This module wraps the `hc` CLI and keeps a live cache
-- of every terminal's facts, fed by one `hc events --json` stream.
local M = {}

M.LABEL = "herdr.nvim" -- marks terminals started from nvim
M.terms = {} ---@type table<string, table> address -> fact (as `hc get --json`)
M.ready = false -- the event stream has delivered its snapshot

-- hc prints null for unset fields; keep them nil (vim.NIL is truthy).
local JSON_OPTS = { luanil = { object = true, array = true } }

local events_job ---@type integer?
local events_restarts = 0
local notify_pending = false

function M.available()
  return vim.fn.executable("hc") == 1
end

--- Run `hc <args>` synchronously. Returns stdout, or nil and an error message.
---@param args string[]
---@param timeout? integer ms
function M.exec(args, timeout)
  local cmd = { "hc" }
  vim.list_extend(cmd, args)
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait(timeout or 10000)
  end)
  if not ok then
    return nil, tostring(res)
  end
  if res.code ~= 0 then
    local err = vim.trim((res.stderr ~= "" and res.stderr) or res.stdout or "")
    -- `hc --json` errors are {"error":{"message":…,"hint":…}}
    local okj, j = pcall(vim.json.decode, err, JSON_OPTS)
    if okj and type(j) == "table" and type(j.error) == "table" and j.error.message then
      err = j.error.message .. (j.error.hint and (" (" .. j.error.hint .. ")") or "")
    end
    return nil, err ~= "" and err or ("hc exited " .. res.code)
  end
  return res.stdout
end

--- Run `hc <args> --json` and decode the result.
---@param args string[]
function M.json(args, timeout)
  local a = vim.list_extend({}, args)
  table.insert(a, 2, "--json")
  local out, err = M.exec(a, timeout)
  if not out then
    return nil, err
  end
  local ok, data = pcall(vim.json.decode, out, JSON_OPTS)
  if not ok then
    return nil, "bad JSON from hc " .. args[1]
  end
  return data
end

--- Async `hc <args>`; cb(stdout|nil, err) runs on the main loop.
function M.exec_async(args, cb)
  local cmd = { "hc" }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      if not cb then
        return
      end
      if res.code ~= 0 then
        cb(nil, vim.trim(res.stderr or ""))
      else
        cb(res.stdout)
      end
    end)
  end)
end

-- A highlight group's global definition, following links. Not
-- nvim_get_hl(link = false): once drawn, that resolves through the current
-- window's 'winhighlight', so the answer would depend on which window has focus.
local function global_hl(name)
  local hl = vim.api.nvim_get_hl(0, { name = name })
  for _ = 1, 20 do
    if not hl.link then
      break
    end
    hl = vim.api.nvim_get_hl(0, { name = hl.link })
  end
  return hl
end

--- The colors of nvim's own `Normal`/`Cursor`, as herdr-core's Display.
--- `override` ({fg?, bg?, cursor?} as "#rrggbb") replaces single colors, e.g.
--- a popover's own background for the terminal it shows.
function M.display(override)
  local function hex(n)
    return n and ("#%06x"):format(n) or nil
  end
  local normal, cursor = global_hl("Normal"), global_hl("Cursor")
  local display = { fg = hex(normal.fg), bg = hex(normal.bg), cursor = hex(cursor.bg or normal.fg) }
  return vim.tbl_extend("force", display, override or {})
end

-- Parse `hc connect` output for request id 1.
-- Returns result, or nil, message, refused (the core answered no), kind.
local function rpc_reply(res)
  if res.code ~= 0 then
    return nil, vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or ("hc connect exited " .. res.code)
  end
  for line in vim.gsplit(res.stdout or "", "\n", { trimempty = true }) do
    local okj, msg = pcall(vim.json.decode, line, JSON_OPTS)
    if okj and type(msg) == "table" and msg.id == 1 then
      if msg.error then
        local e = msg.error
        local hint = e.data and e.data.hint and (" (" .. e.data.hint .. ")") or ""
        return nil, (e.message or vim.inspect(e)) .. hint, true, e.data and e.data.kind
      end
      return msg.result
    end
  end
  return nil, "no reply from hc connect"
end

local function rpc_request(method, params)
  return vim.json.encode({ jsonrpc = "2.0", id = 1, method = method, params = params or vim.empty_dict() }) .. "\n"
end

--- One JSON-RPC call through `hc connect` (blocking).
--- Returns result, or nil, message, refused, kind.
function M.rpc(method, params, timeout)
  local ok, res = pcall(function()
    return vim.system({ "hc", "connect" }, { text = true, stdin = rpc_request(method, params) }):wait(timeout or 30000)
  end)
  if not ok then
    return nil, tostring(res)
  end
  return rpc_reply(res)
end

--- Same, without blocking; cb(result, err, refused, kind) runs on the main loop.
function M.rpc_async(method, params, cb)
  local ok, err = pcall(
    vim.system,
    { "hc", "connect" },
    { text = true, stdin = rpc_request(method, params) },
    function(res)
      local r = { rpc_reply(res) }
      vim.schedule(function()
        if cb then
          cb(unpack(r, 1, 4))
        end
      end)
    end
  )
  if not ok and cb then
    vim.schedule(function()
      cb(nil, tostring(err))
    end)
  end
end
local rpc = M.rpc

--- Core documents: versioned JSON in herdr-core (names: 1-32 of a-z 0-9 - _ .).
--- Returns value (nil if unset), version.
function M.doc_get(name)
  local res, err = rpc("doc.get", { name = name }, 10000)
  if not res then
    return nil, nil, err
  end
  return res.value, res.version or 0
end

--- Write if still at `version`. value = nil deletes. Returns new version,
--- or nil, err, kind ("conflict" when someone else wrote first).
function M.doc_set(name, value, version)
  local res, err, _, kind =
    rpc("doc.set", { name = name, value = value == nil and vim.NIL or value, version = version or 0 }, 10000)
  if not res then
    return nil, err, kind
  end
  return res.version
end

--- Start a program in a new core terminal. Returns its address.
---@param argv string[]|nil program and args; nil/empty = the machine's shell
---@param o? {cwd?:string, name?:string, labels?:table<string,string>, size?:{cols:integer, rows:integer}, display?:{fg?:string, bg?:string, cursor?:string}}
function M.run(argv, o)
  o = o or {}
  local labels = vim.tbl_extend("force", { [M.LABEL] = "1" }, o.labels or {})
  local cwd = vim.fn.fnamemodify((o.cwd and o.cwd ~= "") and o.cwd or vim.fn.getcwd(), ":p")
  -- Inside a herdr terminal, parent the new terminal to it: the Herdr app
  -- then lists it as a sub-agent of nvim's tab (status, peek) without adding
  -- a pane. outlive_parent keeps it alive when nvim's own terminal ends.
  local parent = vim.env.HC_TERMINAL_ID
  if parent == "" then
    parent = nil
  end

  -- The API (not the CLI) can hand over our colors and window size, so the
  -- program sees the right background and width from its first byte instead
  -- of the core's black 200x120 default until the viewer attaches.
  local res, err, refused = rpc("terminal.run", {
    argv = argv or {},
    cwd = cwd,
    name = (o.name and o.name ~= "") and o.name or nil,
    labels = labels,
    parent = parent,
    caller = parent,
    outlive_parent = parent ~= nil,
    no_parent = parent == nil,
    no_notify = true,
    display = M.display(o.display),
    size = o.size,
  })

  if refused then
    return nil, err -- the core answered: no point retrying through the CLI
  end
  if not (res and res.address) then
    -- Fallback: the CLI (no display or size), if `hc connect` itself failed.
    local args = { "run", "--bg", "--no-notify", "--cwd", cwd }
    if parent then
      vim.list_extend(args, { "--parent", parent, "--outlive-parent" })
    else
      table.insert(args, "--no-parent")
    end
    if o.name and o.name ~= "" then
      vim.list_extend(args, { "--name", o.name })
    end
    for k, v in pairs(labels) do
      vim.list_extend(args, { "--label", k .. "=" .. v })
    end
    if argv and #argv > 0 then
      table.insert(args, "--")
      vim.list_extend(args, argv)
    end
    local cli_err
    res, cli_err = M.json(args, 30000)
    if not (res and res.address) then
      return nil, cli_err or err or "hc run returned no address"
    end
  end
  -- Prime the cache so the buffer has a title before the event arrives.
  M.terms[res.address] = vim.tbl_extend("keep", M.terms[res.address] or {}, res, { labels = labels })
  return res.address
end

function M.get(addr)
  local fact = M.json({ "get", addr })
  if fact and fact.address then
    M.terms[fact.address] = fact
  end
  return fact
end

--- All terminals from the cache (or `hc ls` before the stream is up).
---@param filter? fun(t:table):boolean
function M.list(filter)
  if not M.ready then
    local res = M.json({ "ls" })
    for _, t in ipairs(res and res.terminals or {}) do
      M.terms[t.address] = vim.tbl_extend("keep", M.terms[t.address] or {}, t)
    end
  end
  local ret = {}
  for _, t in pairs(M.terms) do
    if t.state ~= "finished" and (not filter or filter(t)) then
      ret[#ret + 1] = t
    end
  end
  table.sort(ret, function(a, b)
    return (a.created_ms or 0) > (b.created_ms or 0)
  end)
  return ret
end

function M.is_ours(t)
  return t and t.labels and t.labels[M.LABEL] ~= nil
end

function M.label(addr, kv)
  local args = { "label", addr }
  for k, v in pairs(kv) do
    args[#args + 1] = k .. "=" .. (v or "")
  end
  local out, err = M.exec(args)
  if out and M.terms[addr] then
    M.terms[addr].labels = M.terms[addr].labels or {}
    for k, v in pairs(kv) do
      M.terms[addr].labels[k] = (v ~= "" and v) or nil
    end
  end
  return out ~= nil, err
end

--- End a terminal's program and remove its record.
function M.kill(addr, cb)
  M.exec_async({ "kill", addr }, function()
    M.exec_async({ "rm", addr }, function()
      M.terms[addr] = nil
      M.changed(addr)
      if cb then
        cb()
      end
    end)
  end)
end

--- Paste text into a terminal and press enter.
function M.send(addr, text, cb)
  M.exec_async({ "send", addr, text }, cb)
end

--- Display title: our label, else hc name, else foreground program, else address.
function M.title(t)
  if not t then
    return "?"
  end
  local l = t.labels or {}
  local program = (t.status and t.status.app)
    or (t.foreground and t.foreground.name)
    or t.agent
    or (t.argv and t.argv[1] and vim.fs.basename(t.argv[1]))
  -- The app stamps `where` (space / tab) on its panes and on nvim's
  -- sub-agents alike; it names app panes well but says nothing about ours.
  local tab = not M.is_ours(t) and l.where and l.where:match("/ (.+)$")
  return l[M.LABEL .. ".title"] or t.name or tab or program or t.address
end

-- Status of a terminal's program, from OSC 7501 (`working`, `blocked`,
-- `idle`, `done`) or nil.
function M.status(t)
  return t and t.status and t.status.state or nil
end

-- ── live event stream ────────────────────────────────────────────────────

--- Tell listeners something changed (coalesced to one autocmd per tick).
function M.changed(addr)
  M.last_changed = addr
  if notify_pending then
    return
  end
  notify_pending = true
  vim.schedule(function()
    notify_pending = false
    vim.api.nvim_exec_autocmds("User", { pattern = "HcmuxChanged", modeline = false })
  end)
end

local function apply(msg)
  if msg.terminals then -- snapshot (first line, or after a reconnect)
    M.terms = {}
    for _, t in ipairs(msg.terminals) do
      M.terms[t.address] = t
    end
    M.ready = true
    M.changed()
    return
  end
  local p = msg.params
  if not (p and p.terminal and p.type) then
    return
  end
  local addr, data = p.terminal, p.data or {}
  if p.type == "created" then
    M.terms[addr] = data
  elseif p.type == "removed" then
    M.terms[addr] = nil
  else
    local t = M.terms[addr]
    if not t then
      t = { address = addr }
      M.terms[addr] = t
    end
    -- Each event carries only its own slice of the fact. Nulls decode to nil,
    -- so assign fields explicitly instead of merging (a merge can't clear).
    if p.type == "turn" then
      -- data.state here is the turn's outcome, not the terminal's state
      t.turn = data.turn
    elseif p.type == "status" then
      t.status, t.reported = data.status, data.reported
    elseif p.type == "foreground" then
      t.foreground = data -- the process object, not terminal fields
    elseif p.type == "labels" then
      t.labels = data.labels or {}
    elseif p.type == "finished" then
      for k, v in pairs(data) do
        t[k] = v
      end
      t.state, t.status, t.foreground = "finished", nil, nil
    else
      -- Unknown event: re-read the whole fact rather than guess its shape.
      M.exec_async({ "get", "--json", addr }, function(out)
        local ok, fact = pcall(vim.json.decode, out or "", JSON_OPTS)
        if ok and type(fact) == "table" and fact.address then
          M.terms[fact.address] = fact
          M.changed(fact.address)
        end
      end)
    end
  end
  M.changed(addr)
end

function M.start_events()
  if events_job or not M.available() then
    return
  end
  local partial = ""
  events_job = vim.fn.jobstart({ "hc", "events", "--json" }, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      -- jobstart splits on newlines; the first chunk continues the last one
      data[1] = partial .. data[1]
      partial = table.remove(data)
      for _, line in ipairs(data) do
        if line ~= "" then
          local ok, msg = pcall(vim.json.decode, line, JSON_OPTS)
          if ok and type(msg) == "table" then
            apply(msg)
          end
        end
      end
    end,
    on_exit = function()
      events_job = nil
      M.ready = false
      if vim.v.exiting ~= vim.NIL then
        return
      end
      -- The core restarts on update; follow it with a short backoff.
      events_restarts = events_restarts + 1
      local delay = math.min(30000, 500 * 2 ^ math.min(events_restarts, 6))
      vim.defer_fn(M.start_events, delay)
    end,
  })
  if events_job <= 0 then
    events_job = nil
  else
    vim.defer_fn(function()
      events_restarts = 0
    end, 60000)
  end
end

return M
