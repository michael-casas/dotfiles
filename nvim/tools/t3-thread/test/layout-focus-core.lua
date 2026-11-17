-- H2-r1: real main.mjs + private hc + embedded Neovim. V6's two-view
-- COMMAND-preserving focus sequence; observe actual OSCs and reattachments.
local root = vim.fn.getcwd()
local private = assert(vim.uv.fs_mkdtemp("/tmp/h2-focus-XXXXXX"))
local env = { HC_SESSION = "h2-focus-test", HC_SOCKET = private .. "/core.sock", HC_TERMINAL_ID = "" }
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
  assert(r.code == 0, "private hc: " .. (r.stderr or ""))
  return vim.json.decode(r.stdout)
end
local url
local server = vim.fn.jobstart({ "node", root .. "/nvim/tools/t3-thread/test/support/layout-focus-server.mjs" }, {
  on_stdout = function(_, lines)
    for _, line in ipairs(lines) do
      if line:match("^http://127.0.0.1:") then
        url = line
      end
    end
  end,
})
assert(
  vim.wait(6000, function()
    return url ~= nil
  end, 20),
  "local synthetic server"
)
local status = hc({ "server", "start", "--json" })
local evidence = root .. "/.agent/h2"
vim.fn.mkdir(evidence, "p", 448)
vim.fn.writefile(
  { vim.json.encode({ env = env, pid = status.pid }) },
  evidence .. "/focus-core-" .. status.pid .. ".json"
)
local addr = hc({
  "run",
  "--bg",
  "--no-parent",
  "--no-notify",
  "--label",
  "t3.thread=synthetic-strike",
  "--",
  "env",
  "T3_URL=" .. url,
  "T3_SESSION_TOKEN=synthetic",
  "CI=0",
  "TERM=xterm-256color",
  "node",
  root .. "/nvim/tools/t3-thread/main.mjs",
  "synthetic-strike",
}).address
local ch = vim.fn.jobstart({ "nvim", "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true, env = env })
local function lua(code, ...)
  return vim.rpcrequest(ch, "nvim_exec_lua", code, { ... })
end
local function drain(ms)
  vim.wait(ms, function()
    return false
  end, 10)
end
local ok, err = pcall(function()
  vim.rpcrequest(ch, "nvim_ui_attach", 234, 57, { rgb = true })
  lua(
    [[
    local root, address = ...
    vim.opt.rtp:prepend(root .. "/nvim")
    vim.notify = function() end
    local core = require("hcmux.core")
    core.get = function(id)
      if id == address or id == "t3-synthetic-strike" then return {address=address,state="live",labels={["t3.thread"]="synthetic-strike"}} end
    end
    core.list = function() return {} end
    local term = require("hcmux.term")
    term.setup({restore=false})
    EVENTS = {}
    local start = vim.uv.hrtime()
    function RECORD(kind, extra)
      local w = vim.api.nvim_get_current_win()
      EVENTS[#EVENTS+1] = {kind=kind,extra=extra,t=(vim.uv.hrtime()-start)/1e6,win=w,buf=vim.api.nvim_win_get_buf(w),mode=vim.api.nvim_get_mode().mode,cols=vim.api.nvim_win_get_width(w),rows=vim.api.nvim_win_get_height(w)}
    end
    local reattach = term.reattach
    term.reattach = function(w) RECORD("reattach"); return reattach(w) end
    vim.api.nvim_create_autocmd("TermRequest", {callback=function(ev)
      local seq=type(ev.data)=="table" and ev.data.sequence or ev.data
      if seq and seq:find("7503;",1,true) then RECORD("osc", {buf=ev.buf,seq=seq}) end
    end})
    local side = require("hcmux.t3side"); side.start = function() end
    local layout = require("hcmux.layout"); layout.go("T3")
    side.update({type="snapshot",projects={{id="p",name="Synthetic"}},threads={{id="synthetic-strike",projectId="p",title="Synthetic",status="idle"}}})
    layout.open_thread("synthetic-strike")
    MAIN = vim.api.nvim_get_current_win()
    require("hcmux.t3").setup()
  ]],
    root,
    addr
  )
  drain(1800)
  lua(
    [[require("hcmux.t3").open("synthetic-strike", {mode="command"}); POP=vim.api.nvim_get_current_win(); RECORD("open-pop")]]
  )
  drain(1800)
  for i = 1, 4 do
    lua(
      [[
      vim.api.nvim_set_current_win(... and MAIN or POP)
      vim.cmd.stopinsert()
      -- Follow term's scheduled BufEnter auto-insert, exactly as COMMAND
      -- preservation on open/reattach does; never count an INSERT-only run.
      vim.schedule(function() vim.cmd.stopinsert(); RECORD("focus") end)
    ]],
      i % 2 == 1
    )
    drain(1500)
    assert(lua("return vim.api.nvim_get_mode().mode == 'nt'"), "COMMAND after focus entry " .. i)
  end
  drain(1200)
  local events = lua("return EVENTS")
  vim.fn.writefile({ vim.json.encode(events) }, evidence .. "/focus-events-" .. status.pid .. ".json")
  local per_entry, n, opening = {}, nil, nil
  for _, ev in ipairs(events) do
    print(vim.json.encode(ev))
    if ev.kind == "open-pop" then
      opening = 0
    elseif ev.kind == "focus" then
      assert(ev.mode == "nt", "each entry is COMMAND, not INSERT")
      n = 0
      per_entry[#per_entry + 1] = 0
    elseif ev.kind == "reattach" then
      if n then
        n = n + 1
        per_entry[#per_entry] = n
      elseif opening then
        opening = opening + 1
      end
    end
  end
  for i, count in ipairs(per_entry) do
    assert(count <= 1, "focus entry " .. i .. " reattached " .. count .. " times: " .. vim.inspect(per_entry))
  end
  assert(opening == 1, "opening a shared-buffer popover replays once, not a background-size bounce")
  assert(vim.deep_equal(per_entry, { 1, 1, 1, 1 }), "every differing-width return actually refreshes")
  assert(
    lua([[local text=table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),"\n")
    for i=0,7 do local _,n=text:gsub("HISTORY_"..i," "); if n~=1 then return false end end
    return true]]),
    "whole focused replay retains every history marker exactly once"
  )
  assert(lua("return vim.api.nvim_get_mode().mode == 'nt'"), "COMMAND preserved")
  print("H2-r1 real two-view COMMAND focus: at most one reattach per entry")
end)
pcall(vim.rpcnotify, ch, "nvim_command", "qa!")
hc({ "kill", addr, "--json" })
hc({ "rm", addr, "--json" })
vim.fn.chanclose(server, "stdin") -- owned fake server exits on EOF, private core stays for REP
assert(ok, err)
