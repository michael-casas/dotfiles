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
