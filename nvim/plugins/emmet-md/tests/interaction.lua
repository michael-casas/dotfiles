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
    vim.opt.rtp:append(vim.env.EMMET_MD_ENVI_CONFIG .. "/after")
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

  local function chord(before, after, gap)
    if gap == 0 then
      keys(before .. "<C-g>" .. after)
    else
      input(before .. "<C-g>")
      vim.uv.sleep(gap)
      keys(after)
    end
  end

  for _, gap in ipairs({ 0, 400, 2500 }) do
    fresh({ "ul>li*3" })
    chord("A", "e<Esc>", gap)
    equal({ "- ", "- ", "- " }, lines(), ("Markdown chord after %d ms"):format(gap))
    equal({}, lua("return _G.emmet_test_notices"), ("no refusal on valid expansion after %d ms"):format(gap))

    fresh({ "" })
    chord("ione", "utwo<Esc>u", gap)
    equal({ "one" }, lines(), ("built-in Ctrl+g u after %d ms"):format(gap))

    for _, direction in ipairs({ "j", "k" }) do
      fresh({ "abc", "abc", "abc" })
      lua("vim.api.nvim_win_set_cursor(0, { 2, 0 })")
      chord("A", direction .. "X<Esc>", gap)
      local expected = { "abc", "abc", "abc" }
      expected[direction == "j" and 3 or 1] = "abcX"
      equal(expected, lines(), ("built-in Ctrl+g %s after %d ms"):format(direction, gap))
    end
  end

  local function snapshot()
    local mode = vim.rpcrequest(channel, "nvim_get_mode")
    if mode.blocking then
      return { mode = mode.mode, blocking = true }
    end
    return lua([[
      return {
        lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        cursor = vim.api.nvim_win_get_cursor(0),
        mode = vim.api.nvim_get_mode().mode,
        error = vim.v.errmsg,
      }
    ]])
  end

  local function pass_through(filetype, key, gap, before, after)
    fresh({ "abcdef", "abcdef", "abcdef" }, filetype)
    lua("vim.api.nvim_win_set_cursor(0, {2, 2})")
    if gap == 0 then
      input(before .. "<C-g>" .. key .. after)
    else
      input(before .. "<C-g>")
      vim.uv.sleep(gap)
      input(key .. after)
    end
    vim.uv.sleep(75)
    local state = snapshot()
    input("<Esc><Esc>")
    settle()
    return state
  end

  for _, gap in ipairs({ 0, 600 }) do
    for _, key in ipairs({
      "u",
      "U",
      "j",
      "k",
      "<Up>",
      "<Down>",
      "<Left>",
      "<Esc>",
      "<C-c>",
    }) do
      local after = key == "<C-c>" and "" or "X<Esc>"
      local native = pass_through("text", key, gap, "iZZ", after)
      equal(native, pass_through("markdown", key, gap, "iZZ", after), ("native %s after %d ms"):format(key, gap))
    end
  end

  for _, case in ipairs({
    { "count insert", "3iZZ", "u", "X<Esc>" },
    { "dot repeat", "iZZ", "j", "X<Esc>." },
    { "Replace mode", "RZZ", "j", "X<Esc>" },
    { "macro replay", "qqiZZ", "j", "X<Esc>q@q" },
  }) do
    local label, before, key, after = unpack(case)
    equal(pass_through("text", key, 400, before, after), pass_through("markdown", key, 400, before, after), label)
  end

  for _, gap in ipairs({ 0, 400, 2500, 6000 }) do
    fresh({ "ul>li*2" })
    lua(
      [[
      _G.emmet_async = nil
      vim.defer_fn(function()
        local edited = pcall(vim.api.nvim_buf_set_lines, 0, -1, -1, false, { "scheduled" })
        local floated = pcall(function()
          local buffer = vim.api.nvim_create_buf(false, true)
          local win = vim.api.nvim_open_win(buffer, false, { relative = "editor", row = 1, col = 1, width = 5, height = 1 })
          vim.api.nvim_win_close(win, true)
          vim.api.nvim_buf_delete(buffer, { force = true })
        end)
        _G.emmet_async = { edited, floated }
      end, ...)
    ]],
      gap == 0 and 0 or 200
    )
    chord("A", "e<Esc>", gap)
    assert(
      vim.wait(1000, function()
        return lua("return _G.emmet_async ~= nil")
      end, 15),
      "scheduled edits did not run"
    )
    equal({ true, true }, lua("return _G.emmet_async"), ("scheduled edits after %d ms"):format(gap))
    equal({ "- ", "- ", "scheduled" }, lines(), ("expansion with scheduled edits after %d ms"):format(gap))
  end

  fresh({ "intro" })
  keys("otext before<CR>ul>li*3<C-g>eone<Tab>two<Esc>")
  local expanded = { "intro", "text before", "- one", "- two", "- " }
  equal(expanded, lines(), "expansion and fields before undo")
  keys("u")
  equal({ "intro", "text before", "ul>li*3" }, lines(), "one undo restores only the abbreviation")
  keys("<C-r>")
  equal(expanded, lines(), "one redo restores the filled expansion")

  fresh({ "h7{x}" })
  keys("A<C-g>e<Esc>")
  equal({ "h7{x}" }, lines(), "refusal keeps the original text")
  local notices = lua("return _G.emmet_test_notices")
  equal(1, #notices, "refusal reports one notice")
  if #notices == 1 then
    equal(vim.log.levels.WARN, notices[1][2], "refusal is a warning")
    equal(true, notices[1][1]:match("%S") ~= nil and not notices[1][1]:find("\n", 1, true), "warning is one line")
  end

  assert(#failures == 0, table.concat(failures, "\n"))
end, debug.traceback)

-- The server belongs to this test, including on assertion failure.
server:kill(15)
server:wait()
assert(ok, err)
print("PASS Markdown chord timing, native Ctrl+g commands, undo and refusal feedback")
