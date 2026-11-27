local socket = vim.fn.tempname()
local server = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "--listen", socket })

local ok, err = xpcall(function()
  assert(
    vim.wait(3000, function()
      return vim.uv.fs_stat(socket) ~= nil
    end, 20),
    "test Neovim did not start"
  )
  local channel = vim.fn.sockconnect("pipe", socket, { rpc = true })

  local function lua(source, ...)
    return vim.rpcrequest(channel, "nvim_exec_lua", source, { ... })
  end

  lua([[
    vim.opt.rtp:prepend(vim.fn.getcwd())
    vim.cmd("runtime plugin/emmet-md.lua")
    vim.keymap.set("i", "<F6>", "<Plug>(emmet-md-expand)")
    vim.cmd.filetype("plugin on")
    vim.o.timeoutlen = 300
    vim.notify = function(message, level)
      table.insert(_G.emmet_test_notices, { message, level })
    end
  ]])

  local failures = {}
  local function equal(expected, actual, label)
    if not vim.deep_equal(expected, actual) then
      failures[#failures + 1] = ("%s: expected %s, got %s"):format(label, vim.inspect(expected), vim.inspect(actual))
    end
  end

  local function lines()
    return lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  end

  local function fresh(content, filetype)
    lua(
      [[
      vim.snippet.stop()
      vim.cmd.enew({ bang = true })
      local lines, filetype = ...
      vim.bo.filetype = filetype
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.bo.undolevels = vim.bo.undolevels
      _G.emmet_test_notices = {}
      vim.v.errmsg = ""
    ]],
      content,
      filetype or "markdown"
    )
  end

  local function input(keys)
    assert(vim.rpcrequest(channel, "nvim_input", keys) > 0)
  end

  local function settle()
    vim.uv.sleep(25)
    assert(
      vim.wait(1000, function()
        local mode = vim.rpcrequest(channel, "nvim_get_mode")
        return mode.mode == "n" and not mode.blocking
      end, 15),
      "test did not return to Normal mode"
    )
  end

  local function keys(sequence)
    input(sequence)
    settle()
  end

  fresh({ "intro" })
  keys("otext before<CR>ul>li*3<F6>one<Tab>two<Esc>")
  local expanded = { "intro", "text before", "- one", "- two", "- " }
  equal(expanded, lines(), "expansion and fields before undo")
  equal({}, lua("return _G.emmet_test_notices"), "successful expansion stays quiet")
  keys("u")
  equal({ "intro", "text before", "ul>li*3" }, lines(), "one undo restores only the abbreviation")
  keys("<C-r>")
  equal(expanded, lines(), "one redo restores the filled expansion")

  fresh({ "h7{x}" })
  keys("A<F6><Esc>")
  equal({ "h7{x}" }, lines(), "refusal keeps the original text")
  local notices = lua("return _G.emmet_test_notices")
  equal(1, #notices, "refusal reports one notice")
  if #notices == 1 then
    equal(vim.log.levels.WARN, notices[1][2], "refusal is a warning")
    equal(true, notices[1][1]:match("%S") ~= nil and not notices[1][1]:find("\n", 1, true), "warning is one line")
  end

  fresh({ "h2{Custom}" }, "text")
  lua("require('emmet-md').setup({ filetypes = { 'text' }, max_repeat = 1 })")
  keys("A<F6><Esc>")
  equal({ "## Custom" }, lines(), "Insert expansion honours configured filetypes")
  lua("require('emmet-md').setup({})")
  assert(lua("return require('emmet-md').expand('ul>li*2') ~= nil"), "setup resets the repeat limit")

  local function refusal(content, filetype, options, writable, command, level, label)
    fresh({ content }, filetype)
    local result = lua(
      [[
      local options, writable, args = ...
      require("emmet-md").setup(options)
      vim.bo.modifiable = writable
      local ok, err = pcall(vim.api.nvim_cmd, { cmd = "EmmetMd", args = args }, {})
      vim.bo.modifiable = true
      return { ok, not ok and tostring(err) or "" }
    ]],
      options,
      writable,
      command
    )
    assert(result[1], result[2])
    equal({ content }, lines(), label .. " leaves text intact")
    local warnings = lua("return _G.emmet_test_notices")
    equal(1, #warnings, label .. " reports one notice")
    equal(level, warnings[1] and warnings[1][2], label .. " reports the configured level")
  end
  refusal("", "text", {}, true, { "h2{A}" }, vim.log.levels.WARN, "wrong filetype")
  refusal("", "markdown", {}, false, { "h2{A}" }, vim.log.levels.WARN, "unmodifiable buffer")
  refusal("", "markdown", {}, true, { "h7{x}" }, vim.log.levels.WARN, "invalid argument")
  refusal(
    "plain prose",
    "markdown",
    { notify_level = vim.log.levels.ERROR },
    true,
    {},
    vim.log.levels.ERROR,
    "invalid line"
  )

  assert(#failures == 0, table.concat(failures, "\n"))
end, debug.traceback)

-- The server belongs to this test, including on assertion failure.
server:kill(15)
server:wait()
assert(ok, err)
print("PASS standalone undo, refusal feedback, command guards and setup")
