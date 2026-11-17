-- L2 headless embedded Neovim: real terminal PTY, OSC, input and mouse events.
-- Only the client peer is synthetic; no hc/server/GUI or real thread is used.
local root = vim.fn.getcwd()
local ch = vim.fn.jobstart({ "nvim", "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
assert(ch > 0)
local function lua(code, ...)
  return vim.rpcrequest(ch, "nvim_exec_lua", code, { ... })
end
local function input(keys)
  vim.rpcrequest(ch, "nvim_input", keys)
  vim.wait(150, function()
    return false
  end)
end
local function wait(code, label)
  assert(
    vim.wait(2500, function()
      return lua(code)
    end, 20),
    label
      .. ": "
      .. vim.inspect(
        lua(
          "return {mode=vim.api.nvim_get_mode().mode, win=vim.api.nvim_get_current_win(), main=MAIN, bar=BAR, requests=REQUESTS, lines=vim.api.nvim_buf_get_lines(CLIENT,0,-1,false)}"
        )
      )
  )
end
local ok, err = pcall(function()
  vim.rpcrequest(ch, "nvim_ui_attach", 120, 40, { rgb = true })
  lua(
    [[
    local root = ...
    vim.opt.rtp:prepend(root .. "/nvim")
    vim.system = function(_, _, cb)
      assert(cb, "unexpected blocking hc call")
      vim.schedule(function() cb({code=1, stdout="", stderr="synthetic"}) end)
      return {}
    end
    vim.o.mouse, vim.o.ttimeoutlen = "a", 20
    local facts, bufs = {}, {}
    package.loaded["hcmux.core"] = {
      get = function(id) return facts[id] end,
      list = function() return {} end,
    }
    package.loaded["hcmux.term"] = {
      addr_of = function(buf) return vim.b[buf].hcmux_addr end,
      buf_of = function(addr) return bufs[addr] end,
      detach = function() end,
      attach = function(addr) vim.api.nvim_set_current_buf(bufs[addr]); return bufs[addr] end,
      open = function(_, opts)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buf)
        vim.fn.jobstart({"node", root .. "/nvim/tools/t3-thread/test/support/escape-viewer.mjs"}, {term = true})
        vim.b[buf].hcmux_addr = opts.name
        facts[opts.name] = {address = opts.name, state = "live", labels = opts.labels}
        bufs[opts.name] = buf
        return buf, opts.name
      end,
    }
    SIDE = require("hcmux.t3side")
    SIDE.start = function() end
    LAYOUT = require("hcmux.layout")
    LAYOUT.go("T3")
    BAR = vim.api.nvim_get_current_win()
    SIDE.update({type = "snapshot", projects = {{id = "p", name = "Project"}}, threads = {
      {id = "a", projectId = "p", title = "Alpha", status = "idle", branch = "alpha"},
      {id = "b", projectId = "p", title = "Beta", status = "idle", branch = "beta"},
    }})
    REQUESTS = {}
    vim.api.nvim_create_autocmd("TermRequest", {callback = function(ev) REQUESTS[#REQUESTS+1] = ev.data end})
    LAYOUT.open_thread("b")
    MAIN = vim.api.nvim_get_current_win()
    CLIENT = vim.api.nvim_get_current_buf()
  ]],
    root
  )
  wait("return table.concat(vim.api.nvim_buf_get_lines(CLIENT,0,-1,false)):find('ready',1,true) ~= nil", "peer starts")
  wait("return vim.api.nvim_get_mode().mode == 't'", "open thread lands INSERT")
  input("<Esc>")
  assert(
    lua("return vim.api.nvim_get_current_win() == MAIN and vim.api.nvim_get_mode().mode == 't'"),
    "first Esc dismisses overlay and stays INSERT"
  )
  input("<Esc>")
  wait(
    "return vim.api.nvim_get_current_win() == BAR and vim.api.nvim_get_mode().mode == 'n'",
    "second Esc -> NORMAL bar via actual OSC"
  )
  assert(lua("return vim.api.nvim_get_current_line():find('Beta',1,true) ~= nil"), "bar current title")
  input("k")
  assert(lua("return vim.api.nvim_get_current_line():find('Alpha',1,true) ~= nil"), "immediate k by card")
  input("<CR>")
  wait("return vim.api.nvim_get_current_win() == MAIN and vim.api.nvim_get_mode().mode == 't'", "Enter -> INSERT main")
  input("<C-]>")
  wait("return vim.api.nvim_get_mode().mode == 'nt'", "Ctrl-] -> terminal NORMAL in place")
  input("<C-]>")
  wait("return vim.api.nvim_get_mode().mode == 't'", "Ctrl-] -> INSERT")
  lua("LAYOUT.sidebar_toggle()")
  input("<Esc>") -- newly opened Alpha peer has an overlay
  input("<Esc>")
  wait(
    "return vim.bo.filetype == 'envi-t3-sidebar' and vim.api.nvim_get_mode().mode == 'n'",
    "hidden bar restored by Esc"
  )
  lua("BAR = vim.api.nvim_get_current_win()")
  input("o")
  wait("return vim.api.nvim_get_mode().mode == 't'", "o -> INSERT")
  local function mouse(action, line, col)
    local pos = lua("return vim.fn.win_screenpos(BAR)")
    vim.rpcrequest(ch, "nvim_input_mouse", "left", action, "", 0, pos[1] + line - 2, pos[2] + (col or 2) - 2)
    vim.wait(150, function()
      return false
    end)
  end
  local beta = lua(
    "for i,s in ipairs(vim.api.nvim_buf_get_lines(SIDE.buffer(),0,-1,false)) do if s:find('Beta',1,true) then return i end end"
  )
  mouse("press", beta)
  mouse("release", beta)
  wait(
    "return vim.api.nvim_get_current_win() == MAIN and vim.api.nvim_get_mode().mode == 't'",
    "click from terminal INSERT -> main INSERT"
  )
  assert(lua("return vim.b.hcmux_addr == 't3-b'"), "click opens correct thread")
  mouse("press", beta)
  mouse("drag", beta, 10)
  mouse("release", beta, 10)
  assert(
    lua("return vim.api.nvim_get_current_win() == BAR and vim.api.nvim_get_mode().mode:match('[vV]') ~= nil"),
    "drag keeps native Visual selection, does not open"
  )
  input("<Esc>")
  local rowcount = lua("return vim.api.nvim_buf_line_count(SIDE.buffer())")
  mouse("press", rowcount + 3)
  mouse("release", rowcount + 3)
  assert(
    lua("return vim.api.nvim_get_current_win() == BAR and vim.api.nvim_buf_line_count(SIDE.buffer()) == ...", rowcount),
    "click below buffer never toggles final disclosure"
  )
  print("T3 Esc/input: actual terminal modes, OSC handoff, click, blank space and drag passed")
end)
-- Quit only this owned headless test child; its PTYs are test resources.
pcall(vim.rpcnotify, ch, "nvim_command", "qa!")
assert(ok, err)
