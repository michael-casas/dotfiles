-- Real embedded Neovim terminal/jobresize + OSC7503; fake peer/core facts only.
local root = vim.fn.getcwd()
local ch = vim.fn.jobstart({ "nvim", "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
assert(ch > 0)
local function lua(code, ...)
  return vim.rpcrequest(ch, "nvim_exec_lua", code, { ... })
end
local function wait(code, label)
  assert(
    vim.wait(3000, function()
      return lua(code)
    end, 20),
    label
  )
end
local ok, err = pcall(function()
  vim.rpcrequest(ch, "nvim_ui_attach", 120, 40, { rgb = true })
  lua(
    [[
    local root = ...
    vim.opt.rtp:prepend(root .. "/nvim")
    local base = vim.fn.stdpath("state") .. "/layout-pty-test"
    vim.fn.mkdir(base, "p")
    NOTICES, REQUESTS, READS, REPAIRS = {}, {}, 0, 0
    vim.notify = function(s) NOTICES[#NOTICES+1] = s end
    vim.system = function(argv, opts, cb)
      assert(argv[1] == "hc" and argv[2] == "get" and cb)
      READS = READS + 1
      -- Deliberately stale core: same-size jobresize does not necessarily signal.
      vim.schedule(function() cb({code=0, stdout=vim.json.encode({cols=80,rows=24})}) end)
      return {wait=function() error("blocking") end}
    end
    local resize = vim.fn.jobresize
    vim.fn.jobresize = function(...)
      REPAIRS = REPAIRS + 1
      return resize(...)
    end
    package.loaded["hcmux.core"] = { get=function() end, list=function() return {} end }
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    local job = vim.fn.jobstart({"python3", root .. "/nvim/tools/t3-thread/test/support/layout-viewer.py"}, {term=true})
    assert(job > 0)
    vim.b[buf].hcmux_addr, vim.b[buf].hcmux_float = "synthetic", "t3"
    BUF, JOB = buf, job
    vim.api.nvim_create_autocmd("TermRequest", {callback=function(ev) REQUESTS[#REQUESTS+1] = ev.data.sequence end})
    require("hcmux.t3").setup()
  ]],
    root
  )
  wait(
    "return table.concat(vim.api.nvim_buf_get_lines(BUF,0,-1,false)):find('LAYOUT_READY',1,true) ~= nil",
    "real peer ready"
  )
  lua('vim.cmd("T3Recenter")')
  wait("return #NOTICES == 1", "one real OSC manual result")
  assert(lua("return NOTICES[1]:find('client checked',1,true) ~= nil"), "OSC7503 accepted from real terminal")
  assert(lua("return READS == 4 and REPAIRS == 2"), "two repairs plus one final ownership-handoff read, no loop")
  assert(lua([[return #REQUESTS == 1 and not REQUESTS[1]:find('\27\\',1,true)]]), "Neovim stripped OSC terminator")
  print("T3 layout real PTY: resize delivery and OSC7503 passed")
end)
pcall(vim.rpcnotify, ch, "nvim_command", "qa!")
assert(ok, err)
