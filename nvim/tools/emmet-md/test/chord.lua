local socket = vim.fn.tempname()
local server = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "--listen", socket })

local ok, err = xpcall(function()
  local channel
  assert(
    vim.wait(3000, function()
      if vim.uv.fs_stat(socket) then
        local connected, id = pcall(vim.fn.sockconnect, "pipe", socket, { rpc = true })
        if connected and id > 0 then
          channel = id
          return true
        end
      end
    end, 20),
    "test Neovim did not start"
  )

  local function lua(source, ...)
    return vim.rpcrequest(channel, "nvim_exec_lua", source, { ... })
  end

  lua([[
    vim.opt.rtp:prepend(vim.fn.getcwd() .. "/plugins/emmet-md")
    vim.cmd("runtime plugin/emmet-md.lua")
    vim.opt.rtp:append(vim.fn.getcwd() .. "/after")
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
      vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
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

  fresh({ "h2{Title}" })
  equal(1, lua("return vim.fn.maparg('<C-g>', 'i', false, true).buffer"), "Markdown-local trigger")
  lua("vim.bo.filetype = 'text'")
  equal("", lua("return vim.fn.maparg('<C-g>', 'i')"), "trigger removed on filetype change")
  fresh({ "h2{Title}" }, "rmd")
  lua("vim.cmd('runtime! ftplugin/markdown.lua')")
  equal("", lua("return vim.fn.maparg('<C-g>', 'i')"), "no trigger on inherited Markdown ftplugins")

  for _, gap in ipairs({ 0, 600 }) do
    for _, key in ipairs({ "—", "“", "…", "À", "。", "😀" }) do
      equal(
        pass_through("text", key, gap, "iZZ", "XY<Esc>"),
        pass_through("markdown", key, gap, "iZZ", "XY<Esc>"),
        ("native multibyte %s after %d ms"):format(key, gap)
      )
    end
  end

  local function during_wait(filetype, start, callback, finish)
    fresh({ "" }, filetype)
    lua("vim.defer_fn(" .. callback .. ", 150)")
    input(start .. "<C-g>")
    vim.uv.sleep(400)
    keys(finish)
    return { lines(), lua("return vim.v.errmsg") }
  end

  local error_message = "deferred Emmet test error"
  local error_callback = ("function() vim.api.nvim_err_writeln(%q) end"):format(error_message)
  local native = during_wait("text", "ione", error_callback, "utwo<Esc>")
  equal({ { "onetwo" }, error_message }, native, "native deferred error stays visible")
  equal(native, during_wait("markdown", "ione", error_callback, "utwo<Esc>"), "deferred error on native u")
  equal(
    { { "- Buy milk", "- " }, error_message },
    during_wait("markdown", "iul>li*2", error_callback, "eBuy milk<Esc>"),
    "deferred error preserves expansion and Insert mode"
  )

  for _, case in ipairs({
    { "stopinsert", "function() vim.cmd.stopinsert() end", "utwo<Esc>" },
    { "scheduled input", "function() vim.api.nvim_feedkeys('jX', 'n', false) end", "uXY<Esc>" },
  }) do
    local label, callback, finish = unpack(case)
    equal(
      during_wait("text", "ione", callback, finish),
      during_wait("markdown", "ione", callback, finish),
      label .. " matches native input"
    )
  end

  assert(#failures == 0, table.concat(failures, "\n"))

  for _, key in ipairs({ "u", "E", "e" }) do
    fresh({ "h2" })
    local count = lua("return vim.on_key()")
    keys("A<C-g>" .. key .. "<Esc>")
    equal({ key == "e" and "## " or "h2" }, lines(), "only lowercase e expands")
    equal({}, lua("return _G.emmet_test_notices"), "no notice after a valid or native chord")
    equal(count, lua("return vim.on_key()"), "a finished chord removes its listener")
    lua("vim.api.nvim_set_current_line('h2{Titl}')")
    keys("A<Left>e<Esc>")
    equal({ "h2{Title}" }, lines(), "a later plain e is text")
  end

  local function complete(abbreviation, second_key, after, filetype)
    fresh({ abbreviation, "" }, filetype)
    lua("vim.o.completeopt = 'menu,menuone'; vim.api.nvim_win_set_cursor(0, {2, 0})")
    input("iul<C-x><C-l>")
    assert(
      vim.wait(1000, function()
        return lua("return vim.fn.pumvisible()") == 1
      end),
      "native line completion did not open"
    )
    keys("<C-g>" .. second_key .. after .. "<Esc>")
    return lines()
  end
  equal({ "ul>li*2", "- X", "- " }, complete("ul>li*2", "e", "X"), "first chord in native completion")
  complete("ul gibberish", "e", "")
  local notices = lua("return _G.emmet_test_notices")
  equal(1, #notices, "one refusal from native completion")
  equal(vim.log.levels.WARN, notices[1] and notices[1][2], "refusal from native completion is a warning")
  for _, key in ipairs({ "u", "j" }) do
    equal(
      complete("ul>li*2", key, "X", "text"),
      complete("ul>li*2", key, "X"),
      "native completion preserves Ctrl+g " .. key
    )
  end
  assert(#failures == 0, table.concat(failures, "\n"))

  fresh({ "h2" })
  equal(
    true,
    lua([[
    local map = vim.fn.maparg("<C-g>", "i", false, true)
    local on_key, get_buf, get_win, mode, feed = vim.on_key, vim.api.nvim_get_current_buf,
      vim.api.nvim_get_current_win, vim.fn.mode, vim.api.nvim_feedkeys
    local slots = {}
    local ns = assert(vim.api.nvim_get_namespaces()["envi-emmet-md-chord"])
    local feeds = 0
    local current_mode = "i"
    vim.on_key = function(callback, namespace)
      assert(namespace == ns, "the same namespace must register and clear the listener")
      slots[namespace] = callback
    end
    vim.fn.mode = function()
      return current_mode
    end
    vim.api.nvim_feedkeys = function()
      feeds = feeds + 1
    end
    local ok, result = pcall(function()
      for _, changed in ipairs({ "buffer", "window" }) do
        map.callback()
        local pending = assert(slots[ns], "the chord should watch the native second key")
        pending(vim.keycode("<C-g>"))
        if changed == "buffer" then
          vim.api.nvim_get_current_buf = function() return -1 end
        else
          vim.api.nvim_get_current_win = function() return -1 end
        end
        pending("e")
        assert(slots[ns] == nil, "the listener must remove itself")
        vim.api.nvim_get_current_buf, vim.api.nvim_get_current_win = get_buf, get_win
      end
      assert(feeds == 0, "a second key in another buffer or window cannot expand")
      map.callback()
      local mode_pending = assert(slots[ns])
      mode_pending(vim.keycode("<C-g>"))
      current_mode = "n"
      mode_pending("e")
      assert(feeds == 0 and slots[ns] == nil, "a second key outside Insert mode cannot expand")
      current_mode = "i"
      map.callback()
      local completion_pending = assert(slots[ns])
      completion_pending(vim.keycode("<C-g>"))
      vim.api.nvim_exec_autocmds("ModeChanged", { buffer = 0 })
      assert(slots[ns] == completion_pending, "leaving native completion must retain the chord")
      completion_pending(vim.keycode("<MouseMove>"))
      assert(slots[ns] == completion_pending, "mouse motion must not consume the second key")
      for _, event in ipairs({ "ModeChanged", "BufLeave", "WinLeave" }) do
        map.callback()
        assert(slots[ns] ~= nil)
        current_mode = "n"
        vim.api.nvim_exec_autocmds(event, { buffer = 0 })
        assert(slots[ns] == nil, event .. " must clear the listener")
        current_mode = "i"
      end
      map.callback()
      local pending = assert(slots[ns])
      pending(vim.keycode("<C-g>"))
      vim.api.nvim_get_current_win = function()
        error("test failure while processing the second key")
      end
      local completed = pcall(pending, "e")
      assert(not completed and slots[ns] == nil, "the listener must clear before handling a key")
      return feeds == 0
    end)
    vim.on_key, vim.api.nvim_get_current_buf, vim.api.nvim_get_current_win = on_key, get_buf, get_win
    vim.fn.mode, vim.api.nvim_feedkeys = mode, feed
    assert(ok, result)
    return result
  ]]),
    "changing the buffer or window before the second key cannot expand"
  )

  fresh({ "h2" })
  equal(
    true,
    lua([[
    local group = "EnviEmmetMdChord" .. vim.api.nvim_get_current_buf()
    assert(#vim.api.nvim_get_autocmds({ group = group }) == 3)
    vim.cmd("runtime! ftplugin/markdown.lua")
    assert(#vim.api.nvim_get_autocmds({ group = group }) == 3, "reload must clear prior cleanup hooks")
    vim.bo.filetype = "text"
    return not pcall(vim.api.nvim_get_autocmds, { group = group })
  ]]),
    "undo_ftplugin removes cleanup hooks"
  )

  lua("vim.keymap.del('i', '<Plug>(emmet-md-expand)')")
  fresh({ "abc" })
  keys("A<C-g>e<Esc>")
  equal({ "abc" }, lines(), "absent plugin leaves the buffer intact")
  equal(
    pass_through("text", "u", 0, "ione", "two<Esc>u"),
    pass_through("markdown", "u", 0, "ione", "two<Esc>u"),
    "absent plugin preserves native Ctrl+g u"
  )

  assert(#failures == 0, table.concat(failures, "\n"))
end, debug.traceback)

server:kill(15)
server:wait()
assert(ok, err)
print("PASS envi Markdown chord, native typing and deferred work")
