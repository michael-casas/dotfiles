-- Bounded, event-driven geometry reconciliation for the focused T3 viewer.
-- No polling or fabricated widths. Last focus wins; leaving cancels all work.
local M = {}
local group = vim.api.nvim_create_augroup("hcmux.t3.layout", { clear = true })
local serial = math.floor(vim.uv.hrtime() / 1000) % 900000000
local active, timer
local focused = true -- FocusLost keeps another editor's most-recent focus authoritative.
local stale, refresh_timer, refreshing = {}, nil, false
local refresh_viewer -- registered by t3.lua so every fresh buffer gets mark()'s maps

local function refresh_current()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if not focused or not stale[buf] or refreshing or not refresh_viewer then
    return
  end
  if refresh_timer then
    refresh_timer:stop()
    if not refresh_timer:is_closing() then
      refresh_timer:close()
    end
  end
  refresh_timer = vim.defer_fn(function()
    refresh_timer = nil
    if focused and vim.api.nvim_get_current_win() == win and vim.api.nvim_win_get_buf(win) == buf and stale[buf] then
      refreshing = true
      refresh_viewer(win)
      refreshing = false
    end
  end, 100)
end

local function rebuilt(buf)
  if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].hcmux_float == "t3" then
    stale[buf] = true
    vim.schedule(refresh_current)
  end
end

function M.on_refresh(callback)
  refresh_viewer = callback
end

local function size(win)
  local info = vim.fn.getwininfo(win)[1]
  return math.max(1, vim.api.nvim_win_get_width(win) - (info and info.textoff or 0)),
    math.max(1, vim.api.nvim_win_get_height(win))
end

local function viewer(win)
  if not focused or not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_get_current_win() ~= win then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local job = vim.b[buf].terminal_job_id
  if vim.b[buf].hcmux_float == "t3" and vim.b[buf].hcmux_addr and type(job) == "number" and job > 0 then
    return buf, job, vim.b[buf].hcmux_addr
  end
end

local function cancel()
  active = nil
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    timer = nil
  end
end

local function here(r)
  if active ~= r then
    return false
  end
  local buf, job, addr = viewer(r.win)
  if buf ~= r.buf or job ~= r.job or addr ~= r.addr then
    return false
  end
  local cols, rows = size(r.win)
  return cols == r.cols and rows == r.rows
end

-- Only dimensions and local request IDs, never terminal content or hc errors.
local function log(r, message)
  local dir = vim.fn.stdpath("state") .. "/hcmux"
  pcall(function()
    vim.fn.mkdir(dir, "p", 448)
    vim.fn.writefile(
      { ("%s request=%d %s"):format(os.date("!%Y-%m-%dT%H:%M:%SZ"), r.id, message) },
      dir .. "/t3-layout.log",
      "a"
    )
  end)
end

local function finish(r, client)
  if not here(r) then
    return
  end
  active = nil
  if not r.manual then
    return
  end
  local dimensions = ("%d×%d"):format(r.cols, r.rows)
  local result
  if r.pty_error then
    result = dimensions .. " PTY size unavailable"
  elseif r.mismatch then
    result = dimensions .. " PTY mismatch after re-apply"
  elseif r.was then
    result = ("re-applied %s (was %d×%d)"):format(dimensions, r.was.cols, r.was.rows)
  else
    result = dimensions .. " ok"
  end
  vim.notify("T3: " .. result .. "; " .. client, vim.log.levels.INFO)
end

-- hc selects the controlling viewer when it sends input. Action 9 is also
-- that ownership handoff: even an old client need not understand it for hc
-- to restore this viewer's cached size. Confirm once more only if repairs
-- had not converged before the handoff; this read never triggers a resize.
local function client_done(r, client)
  if not here(r) then
    return
  end
  if not r.mismatch or r.final_read then
    return finish(r, client)
  end
  r.final_read = true
  local ok = pcall(vim.system, { "hc", "get", r.addr, "--json" }, { text = true, timeout = 1000 }, function(res)
    vim.schedule(function()
      if not here(r) then
        return
      end
      local decoded, fact = pcall(vim.json.decode, res.stdout or "")
      if
        res.code == 0
        and decoded
        and type(fact) == "table"
        and type(fact.cols) == "number"
        and type(fact.rows) == "number"
      then
        r.mismatch = fact.cols ~= r.cols or fact.rows ~= r.rows
      end
      finish(r, client)
    end)
  end)
  if not ok then
    finish(r, client)
  end
end

local function ask_client(r)
  if not here(r) then
    return
  end
  r.waiting = true
  local ok, sent = pcall(vim.fn.chansend, r.job, ("\27[>777;9;%du"):format(r.id))
  if not ok or sent == 0 then
    return client_done(r, "client unavailable")
  end
  vim.defer_fn(function()
    if not r.final_read then
      client_done(r, "client did not answer (older client)")
    end
  end, 1000)
end

local function read_pty(r)
  if not here(r) then
    return
  end
  local ok = pcall(vim.system, { "hc", "get", r.addr, "--json" }, { text = true, timeout = 1000 }, function(res)
    vim.schedule(function()
      if not here(r) then
        return
      end
      local decoded, fact = pcall(vim.json.decode, res.stdout or "")
      if
        res.code ~= 0
        or not decoded
        or type(fact) ~= "table"
        or type(fact.cols) ~= "number"
        or type(fact.rows) ~= "number"
      then
        r.pty_error = true
        log(r, "PTY size unavailable")
        return ask_client(r)
      end
      r.mismatch = fact.cols ~= r.cols or fact.rows ~= r.rows
      if not r.mismatch then
        return ask_client(r)
      end
      r.was = r.was or { cols = fact.cols, rows = fact.rows }
      if r.attempts >= 2 then
        log(r, ("PTY mismatch cols=%d rows=%d wanted=%d×%d"):format(fact.cols, fact.rows, r.cols, r.rows))
        return ask_client(r)
      end
      r.attempts = r.attempts + 1
      -- term.start_viewer execs hc attach on this terminal job's PTY. jobresize
      -- changes that PTY and signals hc, whose normal resize-capable attach
      -- forwards cols/rows to the core. Never send size escapes to the client.
      local resized, result = pcall(vim.fn.jobresize, r.job, r.cols, r.rows)
      if not resized or result == 0 then
        r.pty_error = true
        log(r, "viewer resize unavailable")
        return ask_client(r)
      end
      -- Let hc consume SIGWINCH before the single confirmation per attempt.
      vim.defer_fn(function()
        read_pty(r)
      end, 50)
    end)
  end)
  if not ok and here(r) then
    r.pty_error = true
    log(r, "PTY query unavailable")
    ask_client(r)
  end
end

function M.check(win, manual)
  win = win or vim.api.nvim_get_current_win()
  cancel()
  local buf, job, addr = viewer(win)
  if not buf then
    if manual then
      vim.notify("T3: current window is not a T3 viewer", vim.log.levels.INFO)
    end
    return
  end
  local cols, rows = size(win)
  serial = serial % 999999999 + 1
  local r = {
    id = serial,
    win = win,
    buf = buf,
    job = job,
    addr = addr,
    cols = cols,
    rows = rows,
    attempts = 0,
    manual = manual,
  }
  active = r
  read_pty(r)
end

function M.settle(win)
  win = win or vim.api.nvim_get_current_win()
  -- Background callers must not cancel a newer focused viewer's work.
  if not viewer(win) then
    return
  end
  cancel()
  timer = vim.defer_fn(function()
    timer = nil
    if viewer(win) then
      M.check(win)
    end
  end, 150)
end

vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave", "VimLeavePre" }, { group = group, callback = cancel })
vim.api.nvim_create_autocmd("FocusLost", {
  group = group,
  callback = function()
    focused = false
    cancel()
  end,
})
vim.api.nvim_create_autocmd("FocusGained", {
  group = group,
  callback = function()
    focused = true
    refresh_current()
    M.settle()
  end,
})
vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "VimResized" }, {
  group = group,
  callback = function()
    refresh_current()
    M.settle()
  end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(ev)
    stale[ev.buf] = nil
  end,
})
vim.api.nvim_create_autocmd("WinResized", {
  group = group,
  callback = function()
    local windows = vim.v.event.windows
    if not windows or #windows == 0 or vim.tbl_contains(windows, vim.api.nvim_get_current_win()) then
      M.settle()
    end
  end,
})
vim.api.nvim_create_autocmd("TermRequest", {
  group = group,
  callback = function(ev)
    local r = active
    local seq = type(ev.data) == "table" and ev.data.sequence or ev.data
    if type(seq) ~= "string" then
      return
    end
    -- Neovim removes ST; also accept ST/BEL in synthetic or older events.
    seq = seq:gsub("\27\\$", ""):gsub("\7$", "")
    local id, cols, rows, frozen, reflowed =
      seq:match("^\27%]7503;envi%-t3%-layout=(%d+);cols=(%d+);rows=(%d+);frozen=(%d+);reflowed=([01])$")
    if not id or tonumber(cols) < 1 or tonumber(rows) < 1 or tonumber(frozen) < 1 then
      return
    end
    if id == "0" then
      if reflowed == "1" then
        rebuilt(ev.buf)
      end
      return
    end
    if not r or not r.waiting or ev.buf ~= r.buf or tonumber(id) ~= r.id or not here(r) then
      return
    end
    r.waiting = false
    if reflowed == "1" then
      rebuilt(ev.buf)
    end
    -- TermRequest can run in a restricted context, like the action-7 handler.
    vim.schedule(function()
      if not here(r) then
        return
      end
      local mismatch = tonumber(cols) ~= r.cols
      if mismatch then
        log(r, ("client cols=%s rows=%s frozen=%s wanted=%d×%d"):format(cols, rows, frozen, r.cols, r.rows))
      end
      client_done(
        r,
        (mismatch and "client width mismatch" or "client checked") .. (reflowed == "1" and "; client reflowed" or "")
      )
    end)
  end,
})
vim.api.nvim_create_user_command("T3Recenter", function()
  M.check(nil, true)
end, { desc = "Check and re-apply the current T3 viewer's real geometry" })

return M
