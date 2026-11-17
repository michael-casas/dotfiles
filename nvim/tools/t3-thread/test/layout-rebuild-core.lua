-- Scenario 6a + 7: real embedded Neovim, private hc, synthetic peer.
-- Every core path is isolated before the first hc call; no default-core access.
local root = vim.fn.getcwd()
local private = assert(vim.uv.fs_mkdtemp("/tmp/h2-rebuild-XXXXXX"))
local env = { HC_SESSION = "h2-rebuild-test", HC_SOCKET = private .. "/core.sock", HC_TERMINAL_ID = "" }
for key, name in pairs({
  XDG_STATE_HOME = "state",
  XDG_CONFIG_HOME = "config",
  XDG_DATA_HOME = "data",
  XDG_CACHE_HOME = "cache",
  XDG_RUNTIME_DIR = "run",
}) do
  env[key] = private .. "/" .. name
  vim.fn.mkdir(env[key], "p", 448)
end
vim.fn.mkdir(env.XDG_CONFIG_HOME .. "/herdr-core", "p", 448)
vim.fn.writefile({ "notes = false" }, env.XDG_CONFIG_HOME .. "/herdr-core/config.toml")
local function hc(args)
  local argv = { "hc" }
  vim.list_extend(argv, args)
  local r = vim.system(argv, { env = env, text = true }):wait(10000)
  assert(r.code == 0, "private hc failed: " .. (r.stderr or ""))
  return vim.json.decode(r.stdout)
end
local status = hc({ "server", "start", "--json" })
-- Private cores are intentionally left running; REP owns later cleanup.
local evidence = root .. "/.agent/h2"
vim.fn.mkdir(evidence, "p", 448)
vim.fn.writefile(
  { vim.json.encode({ env = env, pid = status.pid }) },
  evidence .. "/rebuild-core-" .. status.pid .. ".json"
)
local ch = vim.fn.jobstart({ "nvim", "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true, env = env })
assert(ch > 0)
local function lua(code, ...)
  return vim.rpcrequest(ch, "nvim_exec_lua", code, { ... })
end
local function wait(code, label)
  assert(
    vim.wait(6000, function()
      return lua(code)
    end, 20),
    label
  )
end
local addr = hc({
  "run",
  "--bg",
  "--no-parent",
  "--no-notify",
  "--label",
  "t3.thread=history",
  "--",
  "python3",
  root .. "/nvim/tools/t3-thread/test/support/layout-core-peer.py",
}).address
local ok, err = pcall(function()
  vim.rpcrequest(ch, "nvim_ui_attach", 120, 40, { rgb = true })
  lua(
    [[
    local root, address = ...
    vim.opt.rtp:prepend(root .. "/nvim")
    vim.notify = function() end
    local core = require("hcmux.core")
    core.get = function(id)
      if id == address or id == "t3-history" then return {address=address,state="live",labels={["t3.thread"]="history"}} end
    end
    core.list = function() return {} end
    require("hcmux.term").setup({restore=false})
    local side = require("hcmux.t3side")
    side.start = function() end
    LAYOUT = require("hcmux.layout")
    LAYOUT.go("T3")
    BAR = vim.api.nvim_get_current_win()
    side.update({type="snapshot", projects={{id="p",name="Synthetic"}}, threads={
      {id="history",projectId="p",title="Synthetic history",status="idle"}}})
    LAYOUT.open_thread("history")
    MAIN = vim.api.nvim_get_current_win()
    OLD = vim.api.nvim_get_current_buf()
    ADDRESS = address
    require("hcmux.t3").setup()
  ]],
    root,
    addr
  )
  wait(
    "return table.concat(vim.api.nvim_buf_get_lines(OLD,0,-1,false)):find('OLD_HISTORY_',1,true) ~= nil",
    "old scrollback really present"
  )
  local function rebuild(insert)
    lua(
      [[
      if ... then vim.cmd.startinsert() else vim.cmd.stopinsert() end
      OLD = vim.api.nvim_get_current_buf()
      vim.fn.chansend(vim.b.terminal_job_id, "REBUILD")
    ]],
      insert
    )
    wait("return vim.api.nvim_get_current_buf() ~= OLD and vim.b.hcmux_addr == ADDRESS", "fresh same-address viewer")
    wait(
      "return table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false)):find('NEW_HISTORY_',1,true) ~= nil",
      "rebuilt replay arrives"
    )
    local evidence = lua([[
      local text=table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),"\n")
      local _,old=text:gsub("OLD_HISTORY_","")
      local _,new=text:gsub("NEW_HISTORY_","")
      return {old=old,new=new,win=vim.api.nvim_get_current_win(),main=MAIN,mode=vim.api.nvim_get_mode().mode,
        maps=#vim.api.nvim_buf_get_keymap(0,"t"),role=vim.w.envi_t3_main,title=vim.wo.winbar,
        bottom=vim.api.nvim_win_get_cursor(0)[1],lines=vim.api.nvim_buf_line_count(0)}
    ]])
    assert(evidence.old == 0 and evidence.new >= 1, "whole-buffer no stale history: " .. vim.inspect(evidence))
    assert(
      evidence.win == evidence.main
        and evidence.role
        and evidence.maps > 0
        and evidence.title:find("Synthetic history", 1, true),
      "window/maps/chrome intact"
    )
    wait(
      insert and "return vim.api.nvim_get_mode().mode == 't'" or "return vim.api.nvim_get_mode().mode == 'nt'",
      "mode preserved"
    )
    if not insert then
      assert(evidence.bottom >= evidence.lines - 1, "COMMAND lands at bottom")
    end
    print("private core replay: old=" .. evidence.old .. " new=" .. evidence.new .. " mode=" .. evidence.mode)
  end
  rebuild(false)
  rebuild(true)
  vim.rpcrequest(ch, "nvim_input", "<Esc>")
  wait(
    "return vim.api.nvim_get_current_win() == BAR and vim.api.nvim_get_mode().mode == 'n'",
    "action7 on reattached buffer focuses bar"
  )
  assert(lua("return vim.api.nvim_get_current_line():find('Synthetic history',1,true) ~= nil"), "same bar selection")
  vim.rpcrequest(ch, "nvim_input", "<CR>")
  wait(
    "return vim.api.nvim_get_current_win() == MAIN and vim.api.nvim_get_mode().mode == 't'",
    "bar Enter reuses fresh viewer"
  )
  vim.rpcrequest(ch, "nvim_input", "<C-]>")
  wait("return vim.api.nvim_get_mode().mode == 'nt'", "Ctrl-] after replay")
  print("T3 private core + Neovim: whole-buffer replay, COMMAND/INSERT, Esc-to-bar and Ctrl-] passed")
end)
pcall(vim.rpcnotify, ch, "nvim_command", "qa!")
-- End only the explicitly created synthetic peer; leave its private core alive.
hc({ "kill", addr, "--json" })
hc({ "rm", addr, "--json" })
assert(ok, err)
