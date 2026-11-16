-- hcmux: nvim as a multiplexer with herdr-core (`hc`) as the backend.
-- Terminal buffers are views onto herdr-core terminals, so programs and agents
-- survive closing buffers, windows and nvim. Sessions live in herdr-core too:
-- plain `nvim` attaches to the folder's session and quitting detaches.
-- Code: lua/hcmux/, docs: README.md there.

-- Whiteboard (lua/hcmux/board.lua, *.wb.md). No bindings are passed: source-pin
-- trust (bindings.repo) is never inferred from cwd for arbitrary files.
local last_board -- last board this entry point opened (board.lua keeps its own private)
local function open_board(path)
  path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  if not path:match("%.wb%.md$") then
    return vim.notify("EnviBoard: not a *.wb.md file: " .. path, vim.log.levels.WARN)
  end
  if vim.fn.filereadable(path) == 0 then
    return vim.notify("EnviBoard: no such file: " .. path, vim.log.levels.WARN)
  end
  last_board = path
  require("hcmux.board").open(path)
end
local function board_prompt()
  vim.ui.input({ prompt = "Board file (*.wb.md): ", completion = "file" }, function(input)
    if input and input ~= "" then
      open_board(input)
    else
      vim.notify("EnviBoard: open a *.wb.md and press <leader>hw, or :EnviBoard <file>")
    end
  end)
end
--- <leader>hw / :EnviBoard [file]: an argument or the current *.wb.md opens (or focuses) that board;
--- otherwise close the shown board, reopen the last one, or prompt for a file.
local function board_entry(arg)
  if arg and arg ~= "" then
    return open_board(arg)
  end
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == "" and name:match("%.wb%.md$") then
    return open_board(name)
  end
  local board = require("hcmux.board")
  if board.active then
    return board.close()
  end
  if last_board then
    return open_board(last_board)
  end
  board_prompt()
end

return {
  {
    "hcmux",
    virtual = true,
    lazy = false,
    dependencies = { "folke/snacks.nvim" },
    opts = {
      prefix = "<C-\\>", -- normal + terminal mode: <C-\>c new, w pick, d detach, …
      leader = "<leader>m",
      session = {}, -- herdr-core sessions (lua/hcmux/session.lua); false = off
    },
    keys = {
      { "<leader>qs", "<cmd>Session list<cr>", desc = "Sessions (herdr-core)" },
      { "<leader>qd", "<cmd>Detach<cr>", desc = "Detach (save, quit, keep terminals)" },
      { "<leader>qr", "<cmd>Session rename<cr>", desc = "Rename session" },
      { "<leader>qt", "<cmd>Session take<cr>", desc = "Take over session" },
      {
        "<leader>a",
        function()
          require("hcmux.agent").toggle()
        end,
        desc = "AGENT: board 1-9 · i new · / search",
        -- AGENT owns <leader>a: 1-9, i, / are buffer-local keys in its popover. nowait keeps a
        -- future <leader>a* global map (e.g. a LazyVim AI extra) from turning this into a prefix.
        nowait = true,
      },
      {
        "<leader>gp",
        function()
          require("hcmux.prs").toggle()
        end,
        desc = "PR viewer (open PRs · review in hunk)",
        -- Replaces LazyVim's Snacks gh_pr picker on this key (disabled in the snacks spec below);
        -- <leader>gP stays Snacks' all-states picker.
        nowait = true,
      },
      -- <leader>h: agents with a fixed place (lua/hcmux/desk.lua)
      {
        "<leader>hi",
        function()
          -- The stable "REP | dotfiles" T3 thread (Opus 5.5, high effort).
          require("hcmux.t3").toggle("mcp:launch:7cfff520205ef311a8754eb825618f8153bb634effec0b5d0045afe861ee937b")
        end,
        desc = "REP | dotfiles (T3 thread)",
      },
      {
        "<leader>h?",
        function()
          -- keybinder: config changes and questions for envi (T3 thread).
          require("hcmux.t3").toggle("mcp:launch:7c6fdaafe87206a071ce2b73108234605a56145ec0ffa7f35f2a387169d44b14")
        end,
        desc = "keybinder (T3 thread)",
      },
      {
        "<leader>hv",
        function()
          require("hcmux.layout").pick()
        end,
        desc = "Layout switcher (nvim | T3)",
      },
      {
        "<leader>hw",
        function()
          board_entry()
        end,
        desc = "Whiteboard (*.wb.md): open this / toggle last",
      },
      {
        "<leader>hn",
        function()
          require("hcmux.desk").helpdesk({ fresh = true })
        end,
        desc = "Help desk, fresh",
      },
    },
    config = function(_, opts)
      require("hcmux").setup(opts)
      require("hcmux.desk").setup(opts.desk)
      require("hcmux.t3").setup(opts.t3) -- spike: :T3Thread
      vim.api.nvim_create_user_command("EnviBoard", function(a)
        board_entry(a.args)
      end, { nargs = "?", complete = "file", desc = "Open a *.wb.md whiteboard (default: this buffer)" })
      -- <leader>b toggles the T3 sidebar in the T3 tab and is the LazyVim buffer group elsewhere.
      -- which-key treats <leader>b as a group and never fires a global bare map, so the toggle is
      -- a buffer-local nowait map: permanent on the sidebar, and on the focused non-float window's
      -- buffer only while focus is in the T3 tab (that buffer may also be the popover's).
      local sync -- defined below
      local function toggle()
        require("hcmux.layout").sidebar_toggle()
        -- layout.lua moves focus with noautocmd when the focused sidebar closes; re-sync here.
        vim.schedule(sync)
      end
      local group = vim.api.nvim_create_augroup("hcmux.keys.t3b", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        pattern = "EnviT3Sidebar",
        group = group,
        callback = function(ev)
          vim.keymap.set("n", "<leader>b", toggle, { buffer = ev.data.buf, nowait = true, desc = "Toggle T3 sidebar" })
        end,
      })
      local mapped, saved -- buffer holding the tab-scoped map, and the buffer map it replaced
      -- which-key caches each buffer's key tree and doesn't watch keymap changes; drop the cache.
      -- It only rebuilds the current buffer on BufEnter, which layout.lua's noautocmd focus move
      -- skips, so rebuild the current buffer here (this also re-attaches its <Space> trigger).
      local function wk_refresh(buf)
        local ok, wk = pcall(require, "which-key.buf")
        if ok then
          wk.clear({ buf = buf })
          if buf == vim.api.nvim_get_current_buf() then
            wk.get({ buf = buf })
          end
        end
      end
      function sync()
        if mapped and vim.api.nvim_buf_is_valid(mapped) then
          pcall(vim.keymap.del, "n", "<leader>b", { buffer = mapped })
          if saved then
            vim.api.nvim_buf_call(mapped, function()
              vim.fn.mapset("n", false, saved)
            end)
          end
          wk_refresh(mapped)
        end
        mapped, saved = nil, nil
        local buf = vim.api.nvim_get_current_buf()
        if
          vim.t.envi_layout ~= "T3"
          or vim.api.nvim_win_get_config(0).relative ~= ""
          or vim.bo[buf].filetype == "envi-t3-sidebar"
        then
          return
        end
        local old = vim.fn.maparg("<leader>b", "n", false, true)
        saved = old.buffer == 1 and old or nil
        vim.keymap.set("n", "<leader>b", toggle, { buffer = buf, nowait = true, desc = "Toggle T3 sidebar (T3 tab)" })
        mapped = buf
        wk_refresh(buf)
      end
      vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "TabEnter" }, {
        group = group,
        callback = function()
          vim.schedule(sync) -- after layout.lua has finished setting up the tab or window
        end,
      })
    end,
  },

  {
    "folke/which-key.nvim",
    optional = true,
    opts = { spec = { { "<leader>h", group = "herdr agents", icon = "󰚩 " } } },
  },

  -- <leader>gp is the hcmux PR viewer (lua/hcmux/prs.lua), not Snacks' gh_pr picker.
  { "folke/snacks.nvim", optional = true, keys = { { "<leader>gp", false } } },

  -- herdr-core is the single source of session truth.
  { "folke/persistence.nvim", enabled = false },

  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      opts.sections = opts.sections or {}
      -- PR (lua/hcmux/prs.lua), AGENT (lua/hcmux/agent.lua), then BOARD (lua/hcmux/board.lua) relabel the mode.
      for i, c in ipairs(opts.sections.lualine_a or {}) do
        if c == "mode" or (type(c) == "table" and c[1] == "mode") then
          c = type(c) == "table" and c or { "mode" }
          local fmt = c.fmt
          c.fmt = function(label, ...)
            if package.loaded["hcmux.prs"] and require("hcmux.prs").active then
              return "PR"
            end
            if package.loaded["hcmux.agent"] and require("hcmux.agent").active then
              return "AGENT"
            end
            if package.loaded["hcmux.board"] and require("hcmux.board").active then
              return "BOARD"
            end
            return fmt and fmt(label, ...) or label
          end
          opts.sections.lualine_a[i] = c
        end
      end
      opts.sections.lualine_x = opts.sections.lualine_x or {}
      table.insert(opts.sections.lualine_x, 1, {
        function()
          return require("hcmux").statusline()
        end,
        cond = function()
          return package.loaded["hcmux"] ~= nil
        end,
      })
      opts.sections.lualine_c = opts.sections.lualine_c or {}
      table.insert(opts.sections.lualine_c, 1, {
        function()
          return require("hcmux.session").statusline()
        end,
        cond = function()
          return package.loaded["hcmux.session"] ~= nil and vim.g.hcmux_session ~= nil
        end,
        color = "Special",
      })
    end,
  },
}
