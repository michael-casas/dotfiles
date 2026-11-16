-- Real swaps/processes, private state, fake core. The RPC UI is in-memory only:
-- bare --headless Neovim skips the interactive SwapExists path being tested.
local repo, uv = vim.fn.getcwd(), vim.uv or vim.loop
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local processes, channels, failures, cases = {}, {}, {}, 0
local function write(path, text)
  vim.fn.writefile(vim.split(text, "\n"), path)
end
local function wait_file(path)
  assert(
    vim.wait(5000, function()
      return vim.fn.filereadable(path) == 1
    end, 10),
    "missing child marker: " .. path
  )
end
local function private(name)
  local dir = root .. "/" .. name
  for _, sub in ipairs({ "state/envi/swap", "data", "config", "cache", "home/.dotfiles", "tmp", "bin" }) do
    vim.fn.mkdir(dir .. "/" .. sub, "p")
  end
  write(dir .. "/document", "saved")
  return dir,
    {
      NVIM_APPNAME = "envi",
      SWAP_TEST_DIR = dir,
      SWAP_TEST_REPO = repo,
      SWAP_TEST_NVIM = vim.v.progpath,
      XDG_STATE_HOME = dir .. "/state",
      XDG_DATA_HOME = dir .. "/data",
      XDG_CONFIG_HOME = dir .. "/config",
      XDG_CACHE_HOME = dir .. "/cache",
      TMPDIR = dir .. "/tmp",
      HOME = dir .. "/home",
      ENVI_RELOAD_SESSION = "",
      ENVI_SESSION = "",
      HCMUX_SESSION = "",
    }
end
local bootstrap = [[
local dir = assert(vim.env.SWAP_TEST_DIR)
vim.opt.rtp:prepend(assert(vim.env.SWAP_TEST_REPO) .. '/nvim')
vim.opt.directory = dir .. '/state/envi/swap//'
package.loaded['hcmux.core'] = {available = function() return false end}
package.loaded['hcmux.term'] = {config = {}}
local s = require('hcmux.session')
s.setup({debounce = 60000})
]]
local function probe(dir, env, recovery, deferred, directory)
  local ch = vim.fn.jobstart({ vim.v.progpath, "--embed", "-u", "NONE", "-i", "NONE" }, { rpc = true, env = env })
  assert(ch > 0)
  channels[#channels + 1] = ch
  vim.rpcrequest(ch, "nvim_ui_attach", 80, 24, { rgb = true })
  local result = vim.rpcrequest(ch, "nvim_exec_lua", bootstrap .. [[
local recovery, deferred, directory = ...
if directory and directory ~= vim.NIL then vim.opt.directory = directory end
local events, notices = {}, {}
vim.notify = function(text, level) notices[#notices + 1] = {text = text, level = level} end
vim.api.nvim_create_autocmd('SwapExists', {callback = function()
  events[#events + 1] = {choice = vim.v.swapchoice, info = vim.fn.swapinfo(vim.v.swapname)}
  -- Test-only observer: preserve the product's decision; otherwise choose
  -- recovery/readonly so an intentionally protected prompt cannot hang CI.
  if vim.v.swapchoice == '' then vim.v.swapchoice = recovery end
end})
s.load_layout((deferred and 'badd ' or 'edit ') .. vim.fn.fnameescape(dir .. '/document') .. '\n')
local before_enter = #events
if deferred then vim.cmd.edit(dir .. '/document') end
return {events = events, before_enter = before_enter,
  lines = vim.api.nvim_buf_get_lines(0, 0, -1, false), readonly = vim.bo.readonly, notices = notices}
]], { recovery or "o", deferred or false, directory or vim.NIL })
  vim.rpcnotify(ch, "nvim_command", "qa!")
  assert(vim.fn.jobwait({ ch }, 5000)[1] == 0)
  return result
end
local function old(dir, env, dirty)
  write(dir .. "/old.lua", bootstrap .. [[
if vim.env.SWAP_TEST_LOCAL == '1' then vim.opt.directory = '.' end
vim.cmd.edit(dir .. '/document')
if vim.env.SWAP_TEST_DIRTY == '1' then vim.api.nvim_buf_set_lines(0,0,-1,false,{'unsaved recovery text'}) end
vim.cmd('preserve')
vim.fn.writefile({vim.fn.swapname('%')}, dir .. '/ready')
]])
  env.SWAP_TEST_DIRTY = dirty and "1" or "0"
  local p = vim.system(
    { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-c", "luafile " .. dir .. "/old.lua" },
    { env = env }
  )
  processes[#processes + 1] = p
  wait_file(dir .. "/ready")
  return p, vim.fn.readfile(dir .. "/ready")[1]
end
local function test(name, fn)
  cases = cases + 1
  local ok, err = pcall(fn)
  if ok then
    print("PASS " .. name)
  else
    failures[#failures + 1] = name .. ": " .. tostring(err)
    print("FAIL " .. failures[#failures])
  end
end

-- Equivalent early-return frontend: a real old server enters VimLeavePre with
-- its swap held, but the frontend returns before it finishes. This deliberately
-- injects that boundary; it is NOT evidence the stock TUI normally exits early.
local function launcher(mode, timeout)
  local dir, env = private(mode .. (timeout and "-timeout" or ""))
  env.PATH = dir .. "/bin:" .. vim.env.PATH
  env.ENVI_EXIT_TIMEOUT = timeout and "1" or "15"
  write(dir .. "/old.lua", bootstrap .. [[
vim.cmd.edit(dir .. '/document')
vim.cmd('preserve')
vim.fn.writefile({tostring(vim.fn.getpid()),vim.fn.swapname('%')},dir .. '/ready')
vim.api.nvim_create_autocmd('VimLeavePre',{callback=function()
  vim.fn.writefile({'exiting'},dir .. '/leaving')
  vim.wait(]] .. (timeout and "3000" or "1200") .. [[,function() return false end)
  vim.fn.writefile({'finished'},dir .. '/left')
end})
s.name = 'swap-test'
vim.defer_fn(function() s.]] .. (mode == "reload" and "restart" or "detach") .. [[() end,50)
]])
  -- New server checks through an embedded UI, exactly like probe() above.
  write(dir .. "/new.lua", [[
local dir = vim.env.SWAP_TEST_DIR
local ch = vim.fn.jobstart({vim.env.SWAP_TEST_NVIM,'--embed','-u','NONE','-i','NONE'},{rpc=true})
vim.rpcrequest(ch,'nvim_ui_attach',80,24,{rgb=true})
local r = vim.rpcrequest(ch,'nvim_exec_lua', ]] .. string.format("%q", bootstrap .. [[
local events = 0
vim.api.nvim_create_autocmd('SwapExists',{callback=function() events=events+1;vim.v.swapchoice='o' end})
s.load_layout('edit ' .. vim.fn.fnameescape(dir .. '/document') .. '\n')
return {events=events,lines=vim.api.nvim_buf_get_lines(0,0,-1,false),old_finished=vim.fn.filereadable(dir .. '/left')==1}
]]) .. [[, {})
vim.rpcnotify(ch,'nvim_command','qa!')
assert(vim.fn.jobwait({ch},5000)[1]==0)
vim.fn.writefile({vim.json.encode(r)},dir .. '/result')
]])
  write(
    dir .. "/bin/nvim",
    [[#!/usr/bin/env bash
set -eu
if [ ! -f "$SWAP_TEST_DIR/started" ]; then
  touch "$SWAP_TEST_DIR/started"
  "$SWAP_TEST_NVIM" --headless -u NONE -i NONE "$@" -c "luafile $SWAP_TEST_DIR/old.lua" >"$SWAP_TEST_DIR/old.log" 2>&1 </dev/null &
  for ((i=0;i<500;i++)); do
    [ ! -f "$SWAP_TEST_DIR/leaving" ] || exit 0
    sleep .01
  done
  exit 2
fi
# The driver hosts an embedded editor; don't let the driver itself open the
# document too. Forward only the launcher's pre-config PID capture command.
startup=()
if [ "${1:-}" = --cmd ]; then startup=("$1" "$2"); fi
exec "$SWAP_TEST_NVIM" --headless -u NONE -i NONE "${startup[@]}" -c "luafile $SWAP_TEST_DIR/new.lua" -c 'qa!'
]]
  )
  uv.fs_chmod(dir .. "/bin/nvim", 493)
  local args = { repo .. "/nvim/bin/envi", dir .. "/document" }
  local p = vim.system(args, { env = env, text = true })
  processes[#processes + 1] = p
  local r = p:wait(10000)
  local stderr = r.stderr
  if mode == "detach" and not timeout then
    p = vim.system(args, { env = env, text = true })
    processes[#processes + 1] = p
    r = p:wait(10000)
    stderr = stderr .. r.stderr
  end
  wait_file(dir .. "/left")
  local pid = tonumber(vim.fn.readfile(dir .. "/ready")[1])
  assert(
    vim.wait(5000, function()
      return uv.kill(pid, 0) ~= 0
    end, 10),
    "old server leaked"
  )
  if timeout then
    assert(
      r.code ~= 0 and vim.fn.filereadable(dir .. "/result") == 0,
      "timeout must refuse to launch a competing editor"
    )
    assert(r.stderr:find("not starting", 1, true), "timeout must explain the refusal")
  else
    local result = vim.json.decode(table.concat(vim.fn.readfile(dir .. "/result"), "\n"))
    print(mode .. " observation: " .. vim.json.encode(result))
    assert(r.code == 0, r.stderr)
    assert(result.events == 0, "new instance encountered its old server's swap")
    assert(result.old_finished, "launcher returned/restarted before server finished")
    assert(vim.deep_equal(result.lines, { "saved" }), "buffer contents must survive")
    assert(stderr:find("waiting", 1, true), "bounded wait must be visible")
  end
  assert(#vim.fn.glob(dir .. "/tmp/envi.*", false, true) == 0, "private launcher metadata must be cleaned")
end

test("native TUI graceful quit waits through delayed VimLeavePre", function()
  local dir, env = private("native-tui")
  write(dir .. "/tui.lua", bootstrap .. [[
vim.cmd.edit(dir .. '/document')
vim.cmd('preserve')
vim.fn.writefile({tostring(vim.fn.getpid()),vim.fn.swapname('%')},dir .. '/ready')
vim.api.nvim_create_autocmd('VimLeavePre',{callback=function()
  vim.fn.writefile({'exiting'},dir .. '/leaving')
  vim.wait(500,function() return false end)
  vim.fn.writefile({'finished'},dir .. '/left')
end})
vim.defer_fn(function() vim.cmd('qa!') end,50)
]])
  local observation
  local ch = vim.fn.jobstart({ vim.v.progpath, "-u", "NONE", "-i", "NONE", "-c", "luafile " .. dir .. "/tui.lua" }, {
    pty = true,
    env = env,
    on_exit = function()
      local ready = vim.fn.readfile(dir .. "/ready")
      observation = {
        finished = vim.fn.filereadable(dir .. "/left") == 1,
        swap = vim.fn.filereadable(ready[2]) == 1,
        alive = uv.kill(tonumber(ready[1]), 0) == 0,
      }
    end,
  })
  assert(ch > 0)
  channels[#channels + 1] = ch
  assert(vim.fn.jobwait({ ch }, 5000)[1] == 0, "native TUI did not quit normally")
  assert(
    observation and observation.finished and not observation.swap and not observation.alive,
    "native exit overlap observed: " .. vim.inspect(observation)
  )
  print("native TUI observation: " .. vim.json.encode(observation))
end)

test("reload waits for the old server holding its swap", function()
  launcher("reload")
end)
test("detach waits before a subsequent envi opens the buffers", function()
  launcher("detach")
end)
test("timeout refuses re-exec while the old server still owns its swap", function()
  launcher("reload", true)
end)
test("dead-owner clean swap is removed without a prompt", function()
  local dir, env = private("dead-clean")
  local p, swap = old(dir, env, false)
  assert(vim.fn.swapinfo(swap).dirty == 0)
  p:kill(9)
  p:wait(5000) -- only this test-owned child: leave a genuine crash swap
  local result = probe(dir, env)
  assert(#result.events == 0, "clean crash swap should not prompt")
  assert(vim.deep_equal(result.lines, { "saved" }))
  assert(vim.fn.filereadable(swap) == 0, "clean stale swap must be removed")
end)
test("dead-owner dirty swap retains recovery and unsaved text", function()
  local dir, env = private("dead-dirty")
  local p, swap = old(dir, env, true)
  assert(vim.fn.swapinfo(swap).dirty == 1)
  p:kill(9)
  p:wait(5000)
  local result = probe(dir, env, "r")
  assert(#result.events == 1 and result.events[1].choice == "", "dirty recovery decision must remain Neovim's")
  assert(vim.deep_equal(result.lines, { "unsaved recovery text" }), "dirty swap must recover unsaved text")
  assert(vim.fn.filereadable(swap) == 1, "original recovery swap must not be deleted")
end)
test("live owner keeps upstream Edit and W325 during silent layout source", function()
  local dir, env = private("foreign-live")
  local p, swap = old(dir, env, false)
  local result = probe(dir, env)
  assert(#result.events == 1 and result.events[1].choice == "e", "live owner must retain upstream Edit choice")
  assert(result.events[1].info.pid == p.pid and not result.readonly, "upstream live-owner behavior must be unchanged")
  assert(#result.notices == 1 and result.notices[1].text:find("W325", 1, true), "upstream W325 must remain visible")
  assert(vim.fn.filereadable(swap) == 1 and uv.kill(p.pid, 0) == 0, "foreign owner and swap must be untouched")
end)
test("deferred BufEnter after silent badd keeps upstream live-owner behavior", function()
  local dir, env = private("foreign-deferred")
  local p = old(dir, env, false)
  local result = probe(dir, env, "o", true)
  assert(result.before_enter == 0 and #result.events == 1, "badd defers the conflict to actual buffer entry")
  assert(result.events[1].choice == "e" and not result.readonly and uv.kill(p.pid, 0) == 0)
  assert(#result.notices == 1 and result.notices[1].text:find("W325", 1, true))
end)

-- block 0 has fixed-width byte fields: PID at 24 (4 bytes, little endian),
-- b0_hname at 68 (40 bytes). Patch only a closed test child's real swap, then
-- verify through Neovim's parser before using it as reproduction evidence.
local function drift_swap(swap, pid)
  local before = vim.fn.swapinfo(swap)
  assert(not before.error)
  local f = assert(io.open(swap, "r+b"))
  assert(f:seek("set", 68))
  local host = "previous-host.example"
  f:write(host .. string.rep("\0", 40 - #host))
  if pid then
    assert(f:seek("set", 24))
    for _ = 1, 4 do
      f:write(string.char(pid % 256))
      pid = math.floor(pid / 256)
    end
  end
  f:close()
  local after = vim.fn.swapinfo(swap)
  assert(
    not after.error and after.host == host and after.dirty == before.dirty and after.fname == before.fname,
    "header fixture must preserve the real swap's contents: " .. vim.inspect(after)
  )
  return after
end
local function crashed(dir, env, dirty, pid)
  local p, swap = old(dir, env, dirty)
  p:kill(9)
  p:wait(5000)
  local info = drift_swap(swap, pid)
  return swap, info
end
local function removed_notice(result)
  assert(
    #result.notices == 1
      and result.notices[1].text:find("removed stale swap for ", 1, true)
      and result.notices[1].text:find("(no unsaved changes)", 1, true),
    "exactly one quiet cleanup notice expected"
  )
  assert(result.notices[1].level <= vim.log.levels.INFO, "cleanup must not warn")
end
for _, pid in ipairs({ 0, 2147483647 }) do
  test("hostname-drift clean swap with dead pid " .. pid .. " is deleted without a prompt", function()
    local dir, env = private("drift-clean-" .. pid)
    local swap, info = crashed(dir, env, false, pid)
    assert(info.pid == pid or info.pid == 0, "swapinfo may normalize an absent owner to zero")
    if pid ~= 0 then
      local rc, _, code = uv.kill(pid, 0)
      assert(rc == nil and code == "ESRCH", "fixture pid must be provably dead")
    end
    local result = probe(dir, env)
    assert(
      #result.events == 1 and result.events[1].choice == "d",
      "clean local-state drift swap must choose deletion, not prompt/Edit"
    )
    assert(vim.fn.filereadable(swap) == 0, "clean drift swap must be deleted")
    assert(vim.deep_equal(result.lines, { "saved" }), "saved file contents must be intact")
    removed_notice(result)
  end)
end
test("hostname-drift dirty swap retains the recovery prompt and unsaved text", function()
  local dir, env = private("drift-dirty")
  local swap = crashed(dir, env, true, 0)
  local result = probe(dir, env, "r")
  assert(#result.events == 1 and result.events[1].choice == "", "dirty drift swap must keep recovery decision")
  assert(vim.deep_equal(result.lines, { "unsaved recovery text" }), "dirty drift swap must recover exact text")
  assert(vim.fn.filereadable(swap) == 1 and #result.notices == 0, "dirty swap must remain without a cleanup notice")
end)
test("hostname-drift swap beside the document is left to upstream", function()
  local dir, env = private("drift-outside")
  env.SWAP_TEST_LOCAL = "1"
  local swap = crashed(dir, env, false, 0)
  assert(uv.fs_realpath(vim.fs.dirname(swap)) == uv.fs_realpath(dir), "fixture swap must be outside profile state")
  local result = probe(dir, env, "o", false, ".")
  assert(
    #result.events == 1 and result.events[1].choice == "" and result.readonly,
    "outside swap must keep upstream prompt"
  )
  assert(vim.fn.filereadable(swap) == 1 and #result.notices == 0, "outside swap must not be deleted or called stale")
end)

-- Cleanup even if an assertion fails; never enumerate or signal user processes.
for _, ch in ipairs(channels) do
  pcall(vim.rpcnotify, ch, "nvim_command", "qa!")
  pcall(vim.fn.jobwait, { ch }, 1000)
end
for _, p in ipairs(processes) do
  if not p:is_closing() then
    p:kill(9)
  end
  pcall(function()
    p:wait(1000)
  end)
end
vim.fn.delete(root, "rf")
assert(#failures == 0, table.concat(failures, "\n"))
print(("session-swap: %d cases passed"):format(cases))
