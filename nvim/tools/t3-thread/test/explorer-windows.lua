-- Use the installed Snacks windows and real LazyVim mappings in a private editor.
local config = vim.fn.getcwd() .. "/nvim"
local plugins = vim.env.ENVI_TEST_PLUGIN_ROOT or (vim.fn.stdpath("data") .. "/lazy")
for _, name in ipairs({ "snacks.nvim", "LazyVim", "lazy.nvim" }) do
  assert(vim.uv.fs_stat(plugins .. "/" .. name), "install " .. name .. " or set ENVI_TEST_PLUGIN_ROOT")
end

local scratch = assert(vim.uv.fs_mkdtemp(vim.fn.tempname() .. "-XXXXXX"))
vim.fn.writefile({ "original buffer" }, scratch .. "/editor.txt")
vim.fn.writefile({ "another buffer" }, scratch .. "/other.txt")

local function run(test)
  local child = vim.fn.jobstart({ "nvim", "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" }, {
    rpc = true,
    cwd = scratch,
    env = {
      HOME = scratch,
      XDG_CONFIG_HOME = scratch .. "/config",
      XDG_DATA_HOME = scratch .. "/data",
      XDG_STATE_HOME = scratch .. "/state",
      XDG_CACHE_HOME = scratch .. "/cache",
      NVIM_APPNAME = "nvim",
      SHELL = "sh",
    },
  })
  assert(child > 0, "start private Neovim")
  local function lua(code, ...)
    return vim.rpcrequest(child, "nvim_exec_lua", code, { ... })
  end
  local function keys(input)
    vim.rpcrequest(child, "nvim_input", input)
  end
  local function wait(code, message)
    assert(
      vim.wait(1500, function()
        return lua(code)
      end, 10),
      message
    )
  end

  local ok, err = pcall(function()
    lua(
      [[
      local config, plugins = ...
      vim.opt.rtp:prepend(config)
      for _, name in ipairs({ "snacks.nvim", "LazyVim", "lazy.nvim" }) do
        vim.opt.rtp:prepend(plugins .. "/" .. name)
      end

      local opts = require("plugins.neo-tree")[2].opts
      opts.terminal = require("lazyvim.plugins.util")[1].opts.terminal
      Snacks = require("snacks")
      Snacks.setup(opts)
      require("plugins.panel-close")[1].opts(nil, opts)
      LazyVim = require("lazyvim.util")
      require("lazy.core.handler").init()
      require("lazyvim.config.keymaps")
      require("lazyvim.config.autocmds")
      require("config.autocmds")

      vim.cmd.edit("editor.txt")
      editor = vim.api.nvim_get_current_win()
      explorer = Snacks.explorer({
        cwd = vim.fn.getcwd(),
        git_status = false,
        diagnostics = false,
        watch = false,
      })
    ]],
      config,
      plugins
    )
    wait("return explorer and explorer:current_win() == 'list'", "explorer opens on its list")
    test(lua, keys, wait)
  end)
  vim.fn.jobstop(child)
  vim.fn.jobwait({ child }, 1500)
  return ok, err
end

local function history_quit(input)
  return function(lua, keys, wait)
    keys(":q<CR>")
    wait("return explorer.closed and vim.api.nvim_get_current_win() == editor", ":q closes the explorer")
    lua([[
      vim.cmd.split()
      replay_win = vim.api.nvim_get_current_win()
      vim.v.errmsg = ""
    ]])
    keys(input)
    wait("return not vim.api.nvim_win_is_valid(replay_win)", input .. " closes the ordinary split through history")
    assert(lua("return vim.v.errmsg == '' and vim.api.nvim_win_is_valid(editor)"), "history replay raises no error")
  end
end

local function split_quit(view)
  return function(lua, keys, wait)
    lua(
      [[
      local view = ...
      local api = vim.api
      local viewer = api.nvim_create_buf(false, true)
      local fact = { address = "synthetic", state = "live", labels = { ["t3.thread"] = "fixture" } }
      package.loaded["hcmux.core"] = { get = function() return fact end }
      package.loaded["hcmux.term"] = {
        addr_of = function(buf) return buf == viewer and fact.address or nil end,
        buf_of = function() return viewer end,
        attach = function() return viewer end,
      }
      local side = require("hcmux.t3side")
      side.start = function() end
      local layout = require("hcmux.layout")
      layout.go("T3")
      if view == "viewer" then
        layout.open_thread("fixture")
        vim.cmd.stopinsert()
      end
      real_win = api.nvim_get_current_win()
      split = api.nvim_open_win(api.nvim_get_current_buf(), true, { split = "below", win = real_win })
      assert(not vim.w[split].envi_t3_main and api.nvim_win_get_config(split).relative == "")
    ]],
      view
    )
    keys(":q<CR>")
    wait(
      "return not vim.api.nvim_win_is_valid(split) and vim.api.nvim_win_is_valid(real_win)",
      ":q closes the plain " .. view .. " split"
    )
  end
end

local tests = {
  layering = function(lua, keys, wait)
    keys("<M-m>")
    wait("return explorer.layout.opts.fullscreen", "maximize the explorer")
    keys("<C-/>")
    wait("return vim.bo.filetype == 'snacks_terminal' and vim.fn.mode() == 't'", "terminal takes focus")
    assert(
      lua([[
      local api = vim.api
      local term = api.nvim_get_current_win()
      local function rect(win)
        local pos = api.nvim_win_get_position(win)
        local border = api.nvim_win_get_config(win).border
        local pad = type(border) == "table" and 2 or 0
        return { pos[1], pos[2], pos[1] + api.nvim_win_get_height(win) + pad,
          pos[2] + api.nvim_win_get_width(win) + pad }
      end
      local a = rect(term)
      for _, window in pairs(explorer.layout:get_wins()) do
        local win = window.win
        local b = rect(win)
        local overlap = a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
        if overlap and (api.nvim_win_get_config(term).zindex or 0) <= (api.nvim_win_get_config(win).zindex or 0) then
          return false
        end
      end
      return true
    ]]),
      "focused terminal is covered by an explorer window"
    )
    keys("<C-/>")
    wait("return vim.bo.filetype ~= 'snacks_terminal' and not explorer.closed", "toggle hides only the terminal")
  end,
  focus = function(lua, keys, wait)
    keys("<C-l>")
    wait("return vim.api.nvim_get_current_win() == editor", "move to editor")
    lua("vim.cmd.edit('other.txt')")
    wait("return explorer:current().file:match('/other%.txt$') ~= nil", "passively follow the editor file")
    keys("<C-h>")
    wait("return explorer:current_win() == 'list'", "return to the explorer")
    for i = 1, 3 do
      keys("i")
      wait("return explorer:current_win() == 'input' and vim.fn.mode() == 'i'", "enter filter " .. i)
      if i == 1 then
        keys("editor")
        wait("return explorer.input.filter.meta.searching == true", "filter the tree")
      end
      keys("<C-\\><C-n>")
      wait("return vim.fn.mode() == 'n'", "leave Insert in filter " .. i)
      keys("<C-l>")
      wait("return vim.api.nvim_get_current_win() == editor", "move right into editor " .. i)
      keys("<C-h>")
      wait("return explorer:current_win() == 'list' and vim.fn.mode() == 'n'", "move left into list " .. i)
      assert(lua("return explorer.input:get() == 'editor'"), "navigation preserves the filter query")
    end
  end,
  terminal_quit = function(lua, keys, wait)
    -- Make the Snacks terminal the last real split before detaching it.
    keys("<C-/>")
    wait("return vim.bo.filetype == 'snacks_terminal' and vim.fn.mode() == 't'", "terminal takes focus")
    keys("<C-\\><C-n>")
    wait("return vim.fn.mode() == 'n'", "terminal returns to Normal")
    lua([[
      terminal = Snacks.terminal.list()[1]
      buf = terminal.buf
      job = vim.b[buf].terminal_job_id
      local win = vim.api.nvim_get_current_win()
      for _, other in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if other ~= win and vim.api.nvim_win_is_valid(other) and vim.api.nvim_win_get_config(other).relative == "" then
          vim.api.nvim_win_close(other, true)
        end
      end
    ]])
    keys("qa")
    wait("return vim.fn.reg_recording() == 'a'", "q starts a macro in the terminal")
    keys("q:q<CR>")
    wait(
      "return vim.bo.filetype ~= 'snacks_terminal' and not terminal:win_valid()",
      ":q detaches the last terminal split"
    )
    assert(
      lua("return vim.api.nvim_buf_is_valid(buf) and vim.fn.jobwait({ job }, 0)[1] == -1"),
      "terminal job survives"
    )
    keys("<C-/>")
    wait("return terminal:win_valid() and vim.api.nvim_get_current_buf() == buf", "terminal reopens without a new job")
  end,
  panel_quit = function(lua, keys, wait)
    lua([[
      explorer:close()
      local api = vim.api
      local buf = api.nvim_create_buf(false, true)
      api.nvim_win_set_buf(editor, buf)
      vim.bo[buf].filetype = "help"
      panel_buf = buf
      layout_box = api.nvim_open_win(api.nvim_create_buf(false, true), false, { split = "left", win = editor })
      vim.w[layout_box].snacks_layout = true
    ]])
    wait("return vim.fn.maparg('q', 'n') == ''", "LazyVim utility keeps native q")
    keys(":q<CR>")
    wait(
      [[
      return vim.api.nvim_get_current_win() == editor
        and vim.api.nvim_get_current_buf() ~= panel_buf
        and not vim.api.nvim_buf_is_valid(panel_buf)
    ]],
      ":q clears a utility panel from the last editor window"
    )
  end,
  file_quit = function(lua, keys, wait)
    lua([[
      explorer:close()
      vim.o.hidden = false
      vim.cmd.split("other.txt")
      doc_win = vim.api.nvim_get_current_win()
      doc = vim.api.nvim_get_current_buf()
      vim.bo[doc].filetype = "help"
      assert(vim.bo[doc].buftype == "")
      vim.api.nvim_buf_set_lines(doc, 0, -1, false, { "unsaved help edit" })
      vim.v.errmsg = ""
    ]])
    keys(":q<CR>")
    wait(
      [[
      return vim.api.nvim_buf_is_valid(doc)
        and vim.bo[doc].modified
        and vim.api.nvim_buf_get_lines(doc, 0, 1, false)[1] == "unsaved help edit"
        and vim.v.errmsg:find("E37", 1, true) ~= nil
    ]],
      ":q refuses to discard a modified real help file"
    )
    lua("vim.o.hidden = true")
    keys(":q<CR>")
    wait(
      [[
      return not vim.api.nvim_win_is_valid(doc_win)
        and vim.api.nvim_buf_is_valid(doc)
        and vim.bo[doc].modified
        and vim.api.nvim_buf_get_lines(doc, 0, 1, false)[1] == "unsaved help edit"
    ]],
      ":q hides a modified real help file when hidden is enabled"
    )
    lua([[
      vim.cmd.sbuffer({ args = { tostring(doc) } })
      doc_win = vim.api.nvim_get_current_win()
      vim.o.hidden = false
    ]])
    keys(":q!<CR>")
    wait("return not vim.api.nvim_win_is_valid(doc_win) and vim.api.nvim_win_is_valid(editor)", ":q! honors the bang")
    assert(lua("return vim.fn.readfile('other.txt')[1] == 'another buffer'"), "native quit never writes the file")
  end,
  adopted_file_quit = function(lua, keys, wait)
    lua([[
      explorer:close()
      vim.o.hidden = false
      vim.cmd.split("other.txt")
      doc = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(doc, 0, -1, false, { "unsaved adopted edit" })
      vim.keymap.set("n", "q", "<cmd>bd!<CR>", { buffer = doc })
      require("config.panel-close").adopt(doc)
      vim.v.errmsg = ""
    ]])
    keys(":q<CR>")
    wait(
      [[
      return vim.api.nvim_buf_is_valid(doc)
        and vim.bo[doc].modified
        and vim.v.errmsg:find("E37", 1, true) ~= nil
    ]],
      ":q preserves a modified real buffer with an adopted force-delete mapping"
    )
  end,
  history_register = history_quit("@:"),
  history_up = history_quit(":<Up><CR>"),
  t3_viewer_quit = split_quit("viewer"),
  t3_sidebar_quit = split_quit("sidebar"),
  quit_alias = function(lua, keys, wait)
    for _, alias in ipairs({ "quit", "qu", "qui!" }) do
      keys(":" .. alias .. "<CR>")
      wait(
        "return explorer.closed and vim.api.nvim_get_current_win() == editor",
        ":" .. alias .. " closes the explorer"
      )
      local routed = alias:sub(-1) == "!" and "EnviClose!" or "EnviClose"
      assert(lua("return vim.fn.histget(':', -1) == ...", routed), ":" .. alias .. " uses the same close action as :q")
      lua("explorer = Snacks.explorer({ git_status = false, diagnostics = false, watch = false })")
      wait("return explorer and explorer:current_win() == 'list'", "reopen explorer")
    end
  end,
  picker_quit = function(lua, keys, wait)
    lua([[
      explorer:close()
      picker = Snacks.picker.pick({ items = { { text = "one" }, { text = "two" } } })
    ]])
    wait("return picker:current_win() == 'input' and vim.fn.mode() == 'i'", "generic picker input takes focus")
    keys("<Esc>")
    wait("return picker:current_win() == 'input' and vim.fn.mode() == 'n'", "generic input returns to Normal")
    keys("qa")
    wait("return vim.fn.reg_recording() == 'a'", "q starts a macro in picker input")
    keys("q:q<CR>")
    wait("return picker.closed and vim.api.nvim_get_current_win() == editor", ":q closes the generic picker")
  end,
  escape = function(_, keys, wait)
    keys("i")
    wait("return explorer:current_win() == 'input' and vim.fn.mode() == 'i'", "filter receives Insert focus")
    keys("<Esc>")
    wait(
      "return not explorer.closed and explorer:current_win() == 'list' and vim.fn.mode() == 'n'",
      "Escape returns to list"
    )
    keys("<Esc>")
    wait("return not explorer.closed and explorer:current_win() == 'list'", "Escape keeps explorer open in Normal")
    keys("qa")
    wait("return vim.fn.reg_recording() == 'a'", "q starts a macro in the list")
    keys("jq")
    wait("return vim.fn.reg_recording() == '' and vim.fn.getreg('a') == 'j'", "q finishes the macro")
    keys(":q<CR>")
    wait("return explorer.closed and vim.api.nvim_get_current_win() == editor", ":q closes only the explorer")
  end,
}

local failures = {}
for name, test in vim.spairs(tests) do
  local ok, err = run(test)
  if not ok then
    failures[#failures + 1] = name .. ": " .. tostring(err)
  end
end
vim.fn.delete(scratch, "rf")
assert(#failures == 0, table.concat(failures, "\n"))
