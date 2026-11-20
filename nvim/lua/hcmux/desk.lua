-- hcmux.desk: agents with a fixed place in envi (<leader>h).
--
--   <leader>ha  the agent picker (plugins/opencode.lua): pick a tool, and it
--               starts in nvim's cwd in a herdr-core pane of this session.
--   <leader>hi  the "REP | dotfiles" Claude in a centered popover. Toggles:
--               shows it (attaching, resuming it by name, or creating it with
--               opus, medium effort, when it has never existed) or hides it.
--               :q / <Esc> (normal) and <C-\>i (terminal) hide it too. It runs
--               in herdr-core like every hcmux terminal, so hiding it, or
--               quitting nvim, leaves it running.
--   <leader>h?  keybinder: a T3 thread for config changes and questions
--               (plugins/hcmux.lua). Toggles the popover like <leader>hi.
--   <leader>hn  the help desk: pi on j5/gpt-6-luna in a centered float, told
--               where this config lives and handed the live keymaps. Fresh
--               each time it is started.
local core = require("hcmux.core")
local term = require("hcmux.term")

local panel_close = require("config.panel-close")
local M = {}

M.config = {
  rep = {
    title = "REP | dotfiles",
    role = "rep-dotfiles", -- label herdr.nvim.role, how it is found again
    name = "rep-dotfiles", -- hc name (unique among live terminals)
    cwd = "~/.dotfiles",
    size = 0.85, -- popover, of the editor's width and height, centered
    resume = { "claude", "--dangerously-skip-permissions", "--resume", "REP | dotfiles" },
    create = {
      "claude",
      "--dangerously-skip-permissions",
      "--model",
      "opus",
      "--effort",
      "medium",
      "--name",
      "REP | dotfiles",
    },
  },
  helpdesk = {
    title = "help desk · luna",
    role = "helpdesk",
    size = 0.65, -- of the editor's width and height, centered
    -- fresh context, read-only: no saved session, no edit/write tools
    argv = { "pi", "--model", "j5/gpt-6-luna", "--no-session", "--no-skills", "--exclude-tools", "edit,write" },
  },
}

local ROLE = core.LABEL .. ".role"

--- A live terminal carrying role `role` (or hc name `name`).
local function find(role, name)
  local res = core.json({ "ls", "--label", ROLE .. "=" .. role })
  local t = res and res.terminals and res.terminals[1]
  if t then
    return t.address
  end
  if name then
    local fact = core.get(name)
    if fact and fact.state == "live" then
      return fact.address
    end
  end
end

local function focus(addr)
  local buf = term.buf_of(addr)
  local win = buf and vim.fn.win_findbuf(buf)[1]
  if not win then
    return false
  end
  vim.api.nvim_set_current_win(win)
  if vim.bo[buf].buftype == "terminal" then
    vim.cmd.startinsert()
  end
  return true
end

-- ── REP | dotfiles ───────────────────────────────────────────────────────

--- Claude stores sessions per folder, the path with every non-alphanumeric
--- character as "-"; a name set with --name / /rename is in custom-title.json.
--- Returns the session id named `title` in `cwd`, if any.
function M.claude_session(title, cwd)
  local home = vim.env.CLAUDE_CONFIG_DIR or vim.fn.expand("~/.claude")
  local dir = home .. "/projects/" .. cwd:gsub("/$", ""):gsub("[^%w]", "-")
  for _, file in ipairs(vim.fn.glob(dir .. "/*/custom-title.json", true, true)) do
    local f = io.open(file, "r")
    if f then
      local ok, data = pcall(vim.json.decode, f:read("*a"))
      f:close()
      if ok and type(data) == "table" and data.customTitle == title then
        return vim.fs.basename(vim.fs.dirname(file))
      end
    end
  end
end

local REP = "rep"

--- The popover window showing the REP buffer, if open.
local function rep_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative ~= "" and vim.b[buf].hcmux_float == REP then
      return win
    end
  end
end

local function rep_hide()
  local win = rep_win()
  if win then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function rep_mark(buf)
  if not buf or vim.b[buf].hcmux_float == REP then
    return
  end
  vim.b[buf].hcmux_float = REP
  local opts = { buffer = buf, silent = true, desc = "Hide REP | dotfiles" }
  panel_close.bind(buf, rep_hide, opts.desc)
  vim.keymap.set("n", "<Esc>", rep_hide, opts)
  vim.keymap.set("t", "<C-\\>i", rep_hide, opts)
  -- Leaving the popover hides it (it keeps running; <leader>hi brings it back).
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_get_config(0).relative ~= "" then
        vim.schedule(rep_hide)
      end
    end,
  })
end

--- Toggle the REP popover.
function M.rep()
  local c = M.config.rep
  if rep_win() then
    return rep_hide()
  end
  local float = { size = c.size, title = c.title }
  local addr = find(c.role, c.name)
  if addr then
    -- Older layouts showed it in a split: move it into the popover.
    local buf = term.buf_of(addr)
    if buf then
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if #vim.api.nvim_tabpage_list_wins(0) > 1 then
          pcall(vim.api.nvim_win_close, win, false)
        end
      end
    end
    buf = term.attach(addr, "float", float)
    rep_mark(buf)
    if buf and vim.bo[buf].buftype == "terminal" then
      vim.cmd.startinsert()
    end
    return
  end
  local cwd = vim.fn.expand(c.cwd)
  local sid = M.claude_session(c.title, cwd)
  local buf = term.open(sid and c.resume or c.create, {
    where = "float",
    size = c.size,
    cwd = cwd,
    title = c.title,
    name = c.name,
    labels = { [ROLE] = c.role, [core.LABEL .. ".tool"] = "claude", [core.LABEL .. ".session"] = sid },
  })
  rep_mark(buf)
end

-- ── help desk ────────────────────────────────────────────────────────────

local function desk_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.b[vim.api.nvim_win_get_buf(win)].hcmux_desk then
      return win
    end
  end
end

local function hide()
  local win = desk_win()
  if win then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function config_dir()
  return vim.uv.fs_realpath(vim.fn.stdpath("config")) or vim.fn.stdpath("config")
end

--- The live keymaps worth asking about, one per line.
local function keymap_dump()
  local lines = {}
  local leader = vim.g.mapleader or "\\"
  for _, mode in ipairs({ "n", "x", "t" }) do
    local maps = vim.api.nvim_get_keymap(mode)
    table.sort(maps, function(a, b)
      return a.lhs < b.lhs
    end)
    for _, m in ipairs(maps) do
      if m.desc and m.desc ~= "" and not m.lhs:find("<Plug>", 1, true) then
        local lhs = m.lhs
        if leader ~= "" and lhs:sub(1, #leader) == leader then
          lhs = "<leader>" .. lhs:sub(#leader + 1)
        end
        lines[#lines + 1] = ("%s  %-22s %s"):format(mode, lhs, m.desc)
      end
    end
  end
  return lines
end

--- The help desk's instructions, regenerated for each fresh desk.
local function write_prompt()
  local cfg = config_dir()
  local lines = {
    "# You are the envi help desk",
    "",
    'Answer quick questions about this Neovim setup ("envi", experimental nvim): its keybinds,',
    "plugins, commands and how its herdr-core integration behaves. Be brief and concrete:",
    "give the exact keys or command, then one or two lines of why/how. Cite file:line when",
    "you looked something up. If you are not sure, read the files below before answering.",
    "",
    "You are read-only. Never edit or write files, never run commands that change state",
    "(no git commit/checkout, no hc kill/run, no installs). Reading files, `rg`, `grep`,",
    "`hc ls`, `hc get` are fine.",
    "",
    "## The <leader>h agents",
    "",
    "- <leader>ha: the agent picker. Pick a tool and it starts in the nvim cwd, in a pane of this session.",
    '- <leader>hi: the person\'s main working agent, a Claude Code session named "REP | dotfiles"',
    "  in a centered popover (<leader>hi toggles; :q, <Esc>, <C-\\>i hide it). It builds and changes this config. Runs in herdr-core, so it survives nvim.",
    "- <leader>h?: keybinder, the config agent on a T3 thread. Not you.",
    "- <leader>hn: you, the help desk (pi on gpt-6-luna) in a float. Hide with :q or <Esc>.",
    "",
    "## Where things are",
    "",
    ("- Config (a LazyVim setup): %s"):format(cfg),
    "  - It is the production config: the ~/.dotfiles checkout of main. Changes are made in worktrees",
    "    (run with envi-dev) and arrive here when they merge.",
    ("- envi workflow and roadmap: %s/ENVI.md"):format(cfg),
    ("- hcmux (nvim as a terminal multiplexer on herdr-core, sessions): %s/lua/hcmux/README.md"):format(cfg),
    ("- Agents on <leader>h (this desk, the REP Claude): %s/lua/hcmux/desk.lua"):format(cfg),
    ("- AI session manager (<leader>ha, <leader>o…, :AI, :Claude …): %s/lua/plugins/opencode.lua"):format(cfg),
    ("- Own keymaps: %s/lua/config/keymaps.lua; plugin specs: %s/lua/plugins/"):format(cfg, cfg),
    "- LazyVim defaults: ~/.local/share/nvim/lazy/LazyVim/lua/lazyvim/config/keymaps.lua",
    "",
    "## Live keymaps right now (mode, keys, description)",
    "",
    "```",
  }
  vim.list_extend(lines, keymap_dump())
  lines[#lines + 1] = "```"
  local path = vim.fn.stdpath("state") .. "/hcmux-helpdesk.md"
  vim.fn.writefile(lines, path)
  return path
end

local function mark(buf)
  if not buf then
    return
  end
  vim.b[buf].hcmux_desk = true
  vim.bo[buf].buflisted = false
  local opts = { buffer = buf, silent = true, desc = "Hide help desk" }
  panel_close.bind(buf, hide, opts.desc)
  vim.keymap.set("n", "<Esc>", hide, opts)
  vim.keymap.set("t", "<C-\\>?", hide, opts)
  -- Leaving the float hides it (it keeps running; <leader>hn starts a fresh one).
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    callback = function()
      vim.schedule(hide)
    end,
  })
end

--- Toggle the help desk. o.fresh: replace it with a new one.
function M.helpdesk(o)
  o = o or {}
  local c = M.config.helpdesk
  if desk_win() then
    hide()
    if not o.fresh then
      return
    end
  end
  local live = M.desk_addr and core.terms[M.desk_addr] and core.terms[M.desk_addr].state == "live"
  if live and not o.fresh then
    mark(term.attach(M.desk_addr, "float", { size = c.size, title = c.title }))
    return
  end
  M.close_desk()
  local argv = vim.list_extend(vim.deepcopy(c.argv), { "--append-system-prompt", write_prompt() })
  local buf, addr = term.open(argv, {
    where = "float",
    size = c.size,
    title = c.title,
    cwd = config_dir(),
    session = false, -- never part of a saved session: fresh each run
    listed = false,
    labels = { [ROLE] = c.role, [core.LABEL .. ".tool"] = "pi" },
  })
  M.desk_addr = addr
  mark(buf)
end

--- End the help desk's terminal.
function M.close_desk()
  local addr = M.desk_addr
  M.desk_addr = nil
  if not addr then
    return
  end
  local buf = term.buf_of(addr)
  if buf then
    vim.b[buf].hcmux_closing = true
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  core.exec({ "kill", addr })
  core.exec({ "rm", addr })
end

function M.setup(cfg)
  M.config = vim.tbl_deep_extend("force", M.config, cfg or {})
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("hcmux.desk", { clear = true }),
    callback = M.close_desk, -- the desk is per run; the REP agent stays
  })
end

return M
