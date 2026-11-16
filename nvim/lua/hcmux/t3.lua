-- hcmux.t3 (spike): T3 Code threads in a popover.
--
-- The pane runs tools/t3-thread (an Ink client of the T3 websocket stream) in a
-- herdr-core terminal, so it survives hiding the popover, closing nvim, etc.
--   INSERT <Esc>/<C-]> -> COMMAND (sends "dismiss", never a raw Esc); COMMAND
--   i/a/I/A/<C-]> -> INSERT.
--   q in COMMAND hides; <leader>hi / <leader>h? open, focus, or switch the shown
--   popover to their thread in place (never hide).
--   :T3Thread            open or focus the popover (first time: thread picker)
--   :T3Thread <id>       open that thread in the popover
--   :T3Thread new        new thread; your first prompt starts it
--   :T3Restart           restart only this client on the same thread
local term = require("hcmux.term")
local core = require("hcmux.core")

local M = {}

M.config = { size = 0.85 }

local MARK = "t3"
local source = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)) or debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fn.fnamemodify(source, ":h:h:h")
local main = nvim_root .. "/tools/t3-thread/main.mjs"
-- main.mjs is tracked; what a fresh clone lacks is node and the npm dependencies.
local function ready()
  return vim.fn.executable("node") == 1 and vim.uv.fs_stat(nvim_root .. "/tools/t3-thread/node_modules/ink") ~= nil
end
local hub_file = vim.fn.fnamemodify(nvim_root, ":h") .. "/theme/theme.json"
local last -- address shown last

local function name_for(id)
  if not id then
    return "t3-pick"
  end
  return ("t3-" .. id:lower():gsub("^mcp:", ""):gsub("[^a-z0-9_-]", "")):sub(1, 32)
end

local function pop_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" and vim.b[vim.api.nvim_win_get_buf(win)].hcmux_float == MARK then
      return win
    end
  end
end

-- Read on every open (and ColorScheme), so reopening follows hub selection.
-- Invalid/missing hubs leave the float's existing appearance alone.
local function theme_highlights()
  local ok, colors = pcall(function()
    local file = vim.env.ENVI_THEME_FILE or hub_file
    local hub = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
    local theme = hub.themes[vim.env.ENVI_THEME or hub.active]
    local function resolve(value)
      assert(type(value) == "string")
      local color = value:sub(1, 1) == "#" and value or theme.palette[value]
      assert(type(color) == "string" and color:match("^#%x%x%x%x%x%x$"))
      return color
    end
    -- Like the TUI, reject partially broken themes rather than mixing colours.
    for _, tokens in pairs(theme.tokens) do
      for _, value in pairs(tokens) do
        resolve(value)
      end
    end
    local ui = theme.tokens.ui
    return {
      fg = resolve(ui.fg),
      bg = resolve(ui.popover),
      border = resolve(ui.border),
      title = resolve(ui.title),
    }
  end)
  if not ok then
    return false
  end
  vim.api.nvim_set_hl(0, "EnviT3Normal", { fg = colors.fg, bg = colors.bg })
  vim.api.nvim_set_hl(0, "EnviT3Border", { fg = colors.border, bg = colors.bg })
  vim.api.nvim_set_hl(0, "EnviT3Title", { fg = colors.title, bg = colors.bg, bold = true })
  vim.api.nvim_set_hl(0, "EnviT3Mode", { fg = colors.bg, bg = colors.title, bold = true })
  return true
end

-- Only the T3 float: COMMAND is terminal-normal mode, INSERT sends keys to Ink.
local function mode_title(buf)
  local label = vim.api.nvim_get_current_buf() == buf and vim.fn.mode():sub(1, 1) == "t" and "INSERT" or "COMMAND"
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      vim.api.nvim_win_set_config(win, {
        title = { { " T3 ", "EnviT3Title" }, { " " .. label .. " ", "EnviT3Mode" } },
        title_pos = "right",
      })
    end
  end
end

local function theme_float()
  local win = pop_win()
  if win and theme_highlights() then
    vim.wo[win].winhl = "NormalFloat:EnviT3Normal,Normal:EnviT3Normal,FloatBorder:EnviT3Border,FloatTitle:EnviT3Title"
  end
  if win then
    -- A new float copies the window options of the window it opened from, e.g.
    -- the T3 layout's main pane winbar ("T3 · <title>"). The popover has its own title.
    vim.api.nvim_set_option_value("winbar", "", { scope = "local", win = win })
    mode_title(vim.api.nvim_win_get_buf(win))
  end
end

local function hide(win)
  win = win or pop_win()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function mark(buf)
  if not buf or vim.b[buf].hcmux_float == MARK then
    return
  end
  vim.b[buf].hcmux_float = MARK
  local o = { buffer = buf, silent = true, desc = "Hide T3 popover" }
  vim.keymap.set("n", "q", function()
    -- A buffer can be shared by the tiled main pane and the popover. Decide
    -- at keypress time, not by replacing its buffer-local mapping on attach.
    if not vim.w.envi_t3_main then
      hide()
    end
  end, o)
  -- Private CSI reports go through the viewer job (hc attach) unmodified.
  -- Keep these codes aligned with tools/t3-thread/control.mjs.
  local function send(action)
    local job = vim.b[buf].terminal_job_id
    if not job then
      return false
    end
    return pcall(vim.fn.chansend, job, "\27[>777;" .. action .. "u")
  end
  -- INSERT -> COMMAND. A raw Esc never reaches the client (older TUIs interrupted
  -- on it); the private "dismiss" action (6) closes a dialog, the model picker or
  -- a menu and never interrupts. <C-]> toggles INSERT/COMMAND.
  for _, lhs in ipairs({ "<Esc>", "<C-]>" }) do
    vim.keymap.set("t", lhs, function()
      send(6)
      return "<C-\\><C-N>"
    end, { buffer = buf, silent = true, expr = true, desc = "T3: COMMAND mode" })
  end
  vim.keymap.set("n", "<Esc>", "<Nop>", { buffer = buf, silent = true, desc = "T3: stay in COMMAND" })
  for _, lhs in ipairs({ "i", "a", "I", "A", "<C-]>" }) do
    vim.keymap.set("n", lhs, function()
      vim.cmd.startinsert()
    end, { buffer = buf, silent = true, desc = "T3: INSERT mode" })
  end
  for lhs, motion in pairs({ j = "<C-e>", k = "<C-y>" }) do
    vim.keymap.set("n", lhs, function()
      -- Vim applies the original count to an expr-map result; adding it again
      -- would turn 5k into 55<C-y>.
      return motion
    end, { buffer = buf, silent = true, expr = true, desc = "T3: scroll chat one line" })
  end
  vim.keymap.set("n", "m", function()
    if send(1) then
      vim.cmd.startinsert()
    end
  end, { buffer = buf, silent = true, desc = "T3: model picker" })
  local function confirm(action)
    if not send(action) then
      return
    end
    -- Channel output is processed during getcharstr, but terminal-normal mode
    -- does not repaint it until the mapping returns. Redraw just while waiting
    -- for this dialog, following the live region without entering INSERT.
    local win = vim.api.nvim_get_current_win()
    local function reveal()
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
        vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
        vim.api.nvim_win_call(win, function()
          vim.cmd("normal! zb")
        end)
        vim.cmd.redraw()
      end
    end
    reveal()
    local timer = vim.fn.timer_start(50, reveal, { ["repeat"] = -1 })
    local ok, answer = pcall(vim.fn.getcharstr)
    vim.fn.timer_stop(timer)
    send(ok and answer == "y" and 3 or 4)
  end
  vim.keymap.set("n", "c", function()
    confirm(2)
  end, { buffer = buf, silent = true, desc = "T3: confirm compact" })
  vim.keymap.set("n", "<C-c>", function()
    confirm(5)
  end, { buffer = buf, silent = true, desc = "T3: confirm interrupt" })
  vim.api.nvim_create_autocmd({ "ModeChanged", "BufWinEnter", "BufLeave" }, {
    buffer = buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            mode_title(buf)
          end
        end)
      end
    end,
  })
end

local function live(addr)
  local fact = addr and core.get(addr)
  return fact and fact.state == "live" and fact.address or nil
end

-- where: "float" opens the popover; "current" swaps the shown popover's buffer.
local function command_mode(buf, opts)
  if not buf or not opts or opts.mode ~= "command" then
    return
  end
  local function apply()
    if vim.api.nvim_get_current_buf() == buf then
      vim.cmd.stopinsert()
      mode_title(buf)
    end
  end
  apply()
  -- term's BufEnter schedules auto-insert; run after that existing hook.
  vim.schedule(apply)
end

local function show(addr, where, opts)
  local buf = term.attach(addr, where or "float", { size = M.config.size, title = " T3 " })
  mark(buf)
  theme_float()
  last = addr
  if buf and vim.bo[buf].buftype == "terminal" then
    vim.cmd.startinsert()
  end
  command_mode(buf, opts)
end

--- Open or focus the popover. An explicit different thread switches the shown
--- popover in place: the window stays open and swaps which client it views.
function M.open(id, opts)
  opts = opts or {}
  local win = pop_win()
  if win then
    local addr = term.addr_of(vim.api.nvim_win_get_buf(win))
    local fact = id and addr and core.get(addr)
    if vim.api.nvim_get_current_win() ~= win then
      vim.api.nvim_set_current_win(win)
    end
    if not id or (id ~= "new" and fact and fact.labels and fact.labels["t3.thread"] == id) then
      theme_float()
      command_mode(vim.api.nvim_win_get_buf(win), opts)
      return
    end
  end
  -- From here on, `where` == "current" means: reuse the focused popover window.
  local where = win and "current" or "float"
  if not id then
    local addr = live(last)
    if addr then
      return show(addr, where, opts)
    end
  end
  local argv = { "node", main }
  if id then
    argv[#argv + 1] = id
  end
  local name = id ~= "new" and name_for(id) or ("t3-new-" .. os.time())
  local addr = id ~= "new" and live(name)
  if addr then
    return show(addr, where, opts)
  end
  if not ready() then
    return vim.notify("t3: run `npm install` in tools/t3-thread (and install node)", vim.log.levels.ERROR)
  end
  local buf, new = term.open(argv, {
    where = where == "float" and "float" or nil, -- nil: the focused popover window
    size = M.config.size,
    title = " T3 ",
    name = name,
    labels = { ["t3.thread"] = id or "" },
    cwd = opts.cwd,
  })
  mark(buf)
  theme_float()
  last = new
  command_mode(buf, opts)
end

--- Attach a thread client in exactly this window, never focus another viewer.
--- Switching drops only the previous viewer, not the core client program.
function M.attach_in(win, id)
  assert(vim.api.nvim_win_is_valid(win), "T3: invalid main window")
  assert(type(id) == "string" and id ~= "" and id ~= "new", "T3: expected a thread id")
  local old = vim.api.nvim_win_get_buf(win)
  local old_addr = term.addr_of(old)
  local addr = live(name_for(id))
  local fact = addr and core.get(addr)
  if fact and (not fact.labels or fact.labels["t3.thread"] ~= id) then
    addr = nil -- shortened deterministic names can collide
  end
  if not addr then
    local matches = core.list(function(t)
      return t.state == "live" and t.labels and t.labels["t3.thread"] == id
    end)
    addr = matches[1] and matches[1].address
  end
  vim.api.nvim_set_current_win(win)
  vim.w[win].envi_t3_main = true
  local buf, new
  if addr then
    -- term.attach("current") may jump to a different window that shows this
    -- buffer. Place it first so the requested window always remains the main.
    buf = term.buf_of(addr)
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_win_set_buf(win, buf)
    end
    buf = term.attach(addr, "current")
    if buf then
      vim.api.nvim_win_set_buf(win, buf)
      vim.api.nvim_set_current_win(win)
    end
  else
    if not ready() then
      return vim.notify("t3: run `npm install` in tools/t3-thread (and install node)", vim.log.levels.ERROR)
    end
    buf, new = term.open({ "node", main, id }, {
      name = name_for(id),
      title = " T3 ",
      labels = { ["t3.thread"] = id },
    })
    addr = new
  end
  if not buf then
    return
  end
  mark(buf)
  if old_addr and old ~= buf and vim.api.nvim_buf_is_valid(old) and #vim.fn.win_findbuf(old) == 0 then
    -- Move off it before detach: term.detach otherwise closes the main split.
    term.detach(old)
  end
  last = addr
  return buf, addr
end

--- Name kept for the <leader>h maps: open, focus, or switch threads in place.
--- It never hides; only `q` in COMMAND mode does.
function M.toggle(id)
  M.open(id)
end

-- Only restart a verified T3 client, never a run, viewer, or arbitrary terminal.
function M.restart()
  local win = pop_win()
  local buf = win and vim.api.nvim_win_get_buf(win) or nil
  local addr = (buf and term.addr_of(buf)) or last
  local fact = addr and core.get(addr)
  local id = fact and fact.labels and fact.labels["t3.thread"]
  if
    not fact
    or not id
    or id == ""
    or id == "new"
    or not fact.argv
    or fact.argv[1] ~= "node"
    or fact.argv[2] ~= main
    or fact.argv[3] ~= id
  then
    return vim.notify("t3: cannot restart an unverified T3 thread client", vim.log.levels.ERROR)
  end
  if M.restarting then
    return
  end
  M.restarting = true
  -- core.kill ignores errors; use checked core.exec so a failed kill never
  -- launches a second client or falls back to a terminal found by name.
  local killed, err = core.exec({ "kill", fact.address })
  if not killed then
    M.restarting = nil
    return vim.notify("t3: restart failed: " .. (err or "kill failed"), vim.log.levels.ERROR)
  end
  if win then
    hide(win)
  end
  local old = term.buf_of(fact.address)
  if old and vim.api.nvim_buf_is_valid(old) then
    vim.b[old].hcmux_closing = true
    pcall(vim.api.nvim_buf_delete, old, { force = true })
  end
  local removed, remove_err = core.exec({ "rm", fact.address })
  if not removed then
    M.restarting = nil
    return vim.notify(
      "t3: stopped client but could not remove it: " .. (remove_err or "rm failed"),
      vim.log.levels.ERROR
    )
  end
  core.terms[fact.address] = nil
  last = nil
  local ok, fresh, new = pcall(term.open, { "node", main, id }, {
    where = "float",
    cwd = fact.cwd,
    size = M.config.size,
    title = " T3 ",
    name = fact.name,
    labels = { ["t3.thread"] = id },
  })
  M.restarting = nil -- never leave :T3Restart locked after a failed open
  if not ok then
    return vim.notify("t3: restart could not open a new client: " .. tostring(fresh), vim.log.levels.ERROR)
  end
  mark(fresh)
  theme_float()
  last = new
end

function M.setup(cfg)
  M.config = vim.tbl_deep_extend("force", M.config, cfg or {})
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("hcmux.t3.theme", { clear = true }),
    callback = function()
      theme_float()
    end,
  })
  vim.api.nvim_create_user_command("T3Restart", M.restart, { desc = "Restart this T3 thread client" })
  vim.api.nvim_create_user_command("T3Thread", function(a)
    M.open(a.args ~= "" and a.args or nil)
  end, { nargs = "?", desc = "T3 thread popover (spike)" })
end

return M
