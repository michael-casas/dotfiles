-- hcmux: nvim as a terminal multiplexer, with herdr-core (`hc`) as the backend.
--
--   * Every terminal buffer is a view (`hc attach`) onto a herdr-core terminal.
--     Programs never run inside nvim, so closing a buffer, a window or nvim
--     itself leaves them running. Reopen nvim in the same folder and they come
--     back as buffers.
--   * nvim windows/tabs are the layout; herdr-core keeps the processes, their
--     scrollback and their agent status (OSC 7501), streamed live.
--   * Inside the Herdr app, the terminals are sub-agents of nvim's tab, so the
--     app shows their status and can peek at them, without adding panes.
--
-- Keys: the prefix (default <C-\>) works in normal AND terminal mode, so you
-- never leave a terminal to drive the layout. <C-\><C-n> stays nvim's own
-- "leave terminal mode", and the prefix keeps ctrl+\ from reaching `hc attach`
-- (where it would detach).
local core = require("hcmux.core")
local term = require("hcmux.term")

local M = {}

M.config = {
  prefix = "<C-\\>", -- normal + terminal mode
  leader = "<leader>m", -- normal mode mirror, with which-key labels
  history = 2000,
  auto_insert = true,
  restore = true,
  keys = true,
  -- nvim sessions kept in herdr-core (hcmux/session.lua): plain `nvim`
  -- attaches to the folder's session, saving is continuous, quitting
  -- detaches. false turns sessions off (and with them the hc:// bridge).
  session = {},
}

local function ai_selector()
  local ok = _G.Snacks and pcall(function()
    Snacks.picker.ai_tools()
  end)
  if not ok then
    vim.notify("hcmux: AI tool selector not available", vim.log.levels.WARN)
  end
end

local function zoom()
  if _G.Snacks and Snacks.zen then
    Snacks.zen.zoom()
  else
    vim.cmd("wincmd |")
    vim.cmd("wincmd _")
  end
end

-- key, description, action (function, or a string of keys for window moves)
M.actions = {
  {
    "c",
    "New shell here",
    function()
      term.open(nil, { where = "current" })
    end,
  },
  {
    "v",
    "New shell in vsplit",
    function()
      term.open(nil, { where = "vsplit" })
    end,
  },
  {
    "s",
    "New shell in split",
    function()
      term.open(nil, { where = "split" })
    end,
  },
  {
    "t",
    "New shell in tab",
    function()
      term.open(nil, { where = "tab" })
    end,
  },
  {
    "w",
    "Pick terminal",
    function()
      require("hcmux.picker").pick()
    end,
  },
  {
    "n",
    "Next terminal",
    function()
      term.cycle(1)
    end,
  },
  {
    "p",
    "Previous terminal",
    function()
      term.cycle(-1)
    end,
  },
  {
    "d",
    "Detach (keeps running)",
    function()
      term.detach()
    end,
  },
  {
    "x",
    "Kill terminal",
    function()
      term.kill(0)
    end,
  },
  {
    "r",
    "Rename terminal",
    function()
      term.rename()
    end,
  },
  { "z", "Zoom window", zoom },
  { "a", "AI tool", ai_selector },
  {
    "R",
    "Restore project terminals",
    function()
      vim.notify(("hcmux: %d terminal(s) restored"):format(term.restore()), vim.log.levels.INFO)
    end,
  },
  { "h", "Window left", "<C-w>h" },
  { "j", "Window down", "<C-w>j" },
  { "k", "Window up", "<C-w>k" },
  { "l", "Window right", "<C-w>l" },
  { "H", "Move window left", "<C-w>H" },
  { "J", "Move window down", "<C-w>J" },
  { "K", "Move window up", "<C-w>K" },
  { "L", "Move window right", "<C-w>L" },
  { "=", "Equalize windows", "<C-w>=" },
  { "o", "Only this window", "<C-w>o" },
  { "q", "Close window", "<C-w>c" },
}

local function set_keys()
  local cfg = M.config
  for _, a in ipairs(M.actions) do
    local key, desc, action = a[1], a[2], a[3]
    local opts = { desc = desc, silent = true }
    if type(action) == "string" then
      vim.keymap.set("n", cfg.prefix .. key, action, opts)
      vim.keymap.set("t", cfg.prefix .. key, "<C-\\><C-n>" .. action, opts)
      if cfg.leader and key:match("^[hjklHJKL]$") == nil then
        vim.keymap.set("n", cfg.leader .. key, action, opts)
      end
    else
      vim.keymap.set("n", cfg.prefix .. key, action, opts)
      -- From terminal mode: leave it first, then act in normal mode.
      vim.keymap.set("t", cfg.prefix .. key, function()
        vim.cmd.stopinsert()
        vim.schedule(action)
      end, opts)
      if cfg.leader then
        vim.keymap.set("n", cfg.leader .. key, action, opts)
      end
    end
  end
  if cfg.leader then
    vim.keymap.set("n", cfg.leader .. ">", function()
      term.send(vim.api.nvim_get_current_line())
    end, { desc = "Send line to terminal" })
    vim.keymap.set("x", cfg.leader .. ">", function()
      local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
      vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
      term.send(table.concat(lines, "\n"))
    end, { desc = "Send selection to terminal" })
  end
  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    wk.add({
      { cfg.leader, group = "mux (herdr-core)", icon = "󰆍 " },
      { cfg.prefix, group = "mux (herdr-core)", icon = "󰆍 ", mode = { "n", "t" } },
    })
  end
end

-- ── :Hc command ──────────────────────────────────────────────────────────

local function argv_of(args)
  args = vim.trim(args or "")
  if args == "" then
    return nil
  end
  -- A line with shell syntax runs through the shell; plain words run directly
  -- (so herdr-core sees `claude`, `pi`, … as the program and tracks it).
  if args:find("[|&;<>$`'\"*?(){}]") then
    return { vim.o.shell, "-c", args }
  end
  return vim.split(args, "%s+", { trimempty = true })
end

M.subcommands = {
  new = function(a)
    term.open(argv_of(a.rest), { where = "current" })
  end,
  split = function(a)
    term.open(argv_of(a.rest), { where = "split" })
  end,
  vsplit = function(a)
    term.open(argv_of(a.rest), { where = "vsplit" })
  end,
  tab = function(a)
    term.open(argv_of(a.rest), { where = "tab" })
  end,
  attach = function(a)
    if a.rest == "" then
      return require("hcmux.picker").pick()
    end
    term.attach(a.rest, "current")
  end,
  list = function()
    require("hcmux.picker").pick()
  end,
  detach = function()
    term.detach()
  end,
  kill = function(a)
    term.kill(a.rest ~= "" and a.rest or 0, not a.bang)
  end,
  rename = function(a)
    term.rename(a.rest ~= "" and a.rest or nil)
  end,
  restore = function(a)
    vim.notify(("hcmux: %d terminal(s) restored"):format(term.restore(a.rest == "all")), vim.log.levels.INFO)
  end,
  send = function(a)
    local text = a.rest
    if a.range > 0 then
      text = table.concat(vim.api.nvim_buf_get_lines(0, a.line1 - 1, a.line2, false), "\n")
    end
    term.send(text)
  end,
}

local function command(opts)
  local sub, rest = opts.args:match("^(%S+)%s*(.*)$")
  if not sub then
    return require("hcmux.picker").pick()
  end
  -- `:Hc! kill t3` and `:Hc kill! t3` mean the same
  local bang = opts.bang
  if sub:sub(-1) == "!" then
    sub, bang = sub:sub(1, -2), true
  end
  local fn = M.subcommands[sub]
  if not fn then
    return vim.notify("hcmux: unknown subcommand " .. sub, vim.log.levels.ERROR)
  end
  fn({ rest = rest or "", bang = bang, range = opts.range, line1 = opts.line1, line2 = opts.line2 })
end

local function complete(lead, line)
  local words = vim.split(line, "%s+")
  if #words <= 2 then
    return vim.tbl_filter(function(s)
      return s:find("^" .. vim.pesc(lead))
    end, vim.tbl_keys(M.subcommands))
  end
  if words[2] == "attach" or words[2] == "kill" then
    return vim.tbl_map(function(t)
      return t.address
    end, core.list())
  end
  return {}
end

-- ── statusline ───────────────────────────────────────────────────────────

local function icon(state)
  local i = require("hcmux.picker").icons[state or "none"]
  return i and i[1] or ""
end

--- In a terminal: its address and status. Elsewhere: how many of nvim's
--- terminals are working / waiting on you / done.
function M.statusline()
  local addr = term.addr_of()
  if addr then
    local t = core.terms[addr]
    local s = core.status(t)
    return ("󰆍 %s%s"):format(addr, s and ("  " .. icon(s) .. s) or "")
  end
  local counts, n = {}, 0
  for _, buf in ipairs(term.bufs()) do
    local s = core.status(core.terms[vim.b[buf].hcmux_addr])
    n = n + 1
    if s then
      counts[s] = (counts[s] or 0) + 1
    end
  end
  if n == 0 then
    return ""
  end
  local parts = { "󰆍 " .. n }
  for _, s in ipairs({ "working", "blocked", "done" }) do
    if counts[s] then
      parts[#parts + 1] = icon(s) .. counts[s]
    end
  end
  return table.concat(parts, " ")
end

-- ── setup ────────────────────────────────────────────────────────────────

function M.setup(cfg)
  M.config = vim.tbl_deep_extend("force", M.config, cfg or {})
  term.setup({
    history = M.config.history,
    auto_insert = M.config.auto_insert,
  })

  if M.config.session ~= false then
    require("hcmux.session-bridge").setup()
    require("hcmux.session").setup(M.config.session)
  end
  -- Hot reload is on in every interactive nvim: envi (started by its launcher)
  -- restarts itself on a new config commit, any other nvim shows a toast.
  if M.config.hot_reload ~= false and require("hcmux.hotreload").interactive() then
    require("hcmux.hotreload").setup(M.config.hot_reload)
  end

  vim.api.nvim_create_user_command("Hc", command, {
    nargs = "*",
    bang = true,
    range = true,
    complete = complete,
    desc = "herdr-core terminals (hcmux)",
  })

  if M.config.keys then
    set_keys()
  end

  if not core.available() then
    return
  end
  core.start_events()

  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("hcmux", { clear = true }),
    pattern = "HcmuxChanged",
    callback = function()
      vim.cmd("redrawstatus!")
      pcall(vim.cmd, "redrawtabline")
    end,
  })

  -- With sessions on, the session lists its own terminals when it attaches.
  if M.config.restore and M.config.session == false then
    local function restore()
      -- Wait briefly for the event snapshot (labels live there).
      vim.wait(1500, function()
        return core.ready
      end, 20)
      term.restore()
    end
    if vim.v.vim_did_enter == 1 then
      vim.schedule(restore)
    else
      vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = vim.schedule_wrap(restore) })
    end
  end
end

-- Convenience for other plugins (the AI session pickers).
M.open = term.open
M.attach = term.attach

--- Live core terminal started from nvim carrying label k=v, if any.
function M.find(k, v)
  for _, t in pairs(core.terms) do
    if t.state == "live" and t.labels and t.labels[k] == v then
      return t
    end
  end
end

return M
