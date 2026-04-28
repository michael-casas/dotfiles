local split_cmd = "enew"

return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    opts.picker = opts.picker or {}
    opts.picker.sources = opts.picker.sources or {}

    -- ── Higher-order factory for AI CLI session pickers ────────────────────
    local function normalize_time(v)
      if type(v) == "number" then
        return v
      end
      if type(v) == "string" then
        local ok, ts = pcall(vim.fn.strptime, "%Y-%m-%dT%H:%M:%S", v:gsub("%.%d+Z$", "Z"):gsub("Z$", ""))
        if ok and ts and ts > 0 then
          return ts
        end
        local n = tonumber(v)
        if n then
          return n
        end
      end
      return 0
    end

    local function ai_session_picker(config)
      return {
        prompt = config.label .. " ",
        layout = { preset = "vscode" },
        show_empty = true,

        finder = function(_, ctx)
          local items = {}
          local bin = config.bin
          if vim.fn.executable(bin) ~= 1 then
            return items
          end

          -- Map existing buffers by session id for this tool
          local buf_map = {}
          local var_name = config.buf_var or (config.name .. "_session_id")
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local ok, sid = pcall(vim.api.nvim_buf_get_var, buf, var_name)
            if ok and sid then
              buf_map[sid] = buf
            end
          end

          -- Fetch sessions via tool-specific logic
          local sessions = config.list_sessions(bin)
          if not sessions or type(sessions) ~= "table" then
            return items
          end

          for _, s in ipairs(sessions) do
            local sid = s.id or ""
            local title = s.title or "Untitled"
            local directory = s.directory or ""
            local buf = buf_map[sid]

            table.insert(items, {
              text = title .. " " .. directory .. " " .. sid,
              session_id = sid,
              title = title,
              directory = directory,
              updated = s.updated,
              buf = buf,
              file = directory,
            })
          end

          -- Sort by updated descending (most recent first)
          table.sort(items, function(a, b)
            return normalize_time(a.updated) > normalize_time(b.updated)
          end)

          return ctx.filter:filter(items)
        end,

        format = function(item)
          local dir = (item.directory or ""):gsub(vim.env.HOME, "~")
          local tag = item.buf and vim.api.nvim_buf_is_valid(item.buf) and "[BUF]" or "[SES]"
          local hl = tag == "[BUF]" and "DiffAdd" or "DiffChange"
          return {
            { tag .. " ", hl },
            { item.title .. " ", "Normal" },
            { dir, "Comment" },
          }
        end,

        confirm = function(picker, item)
          picker:close()
          if not item then
            return
          end

          vim.schedule(function()
            -- Jump to existing buffer if open
            if item.buf and vim.api.nvim_buf_is_valid(item.buf) then
              for _, win in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_get_buf(win) == item.buf then
                  vim.api.nvim_set_current_win(win)
                  return
                end
              end
              vim.api.nvim_set_current_buf(item.buf)
              return
            end

            -- Open new terminal buffer for session
            local bin = config.bin
            local cmd = config.attach_cmd(bin, item.session_id, item.directory)

            vim.cmd(split_cmd)
            vim.fn.termopen(cmd, { cwd = item.directory })
            vim.cmd("startinsert")

            local buf = vim.api.nvim_get_current_buf()
            local var_name = config.buf_var or (config.name .. "_session_id")
            vim.api.nvim_buf_set_var(buf, var_name, item.session_id)
            vim.api.nvim_buf_set_var(buf, var_name .. "_title", item.title)
          end)
        end,

        win = {
          input = {
            keys = config.delete_key ~= false and {
              ["<c-d>"] = { config.name .. "_session_delete", mode = { "n", "i" } },
            } or {},
          },
        },

        actions = vim.tbl_deep_extend("force", {
          [config.name .. "_session_delete"] = function(picker)
            local it = picker:current()
            if not it or not it.session_id then
              return
            end
            if config.delete_session then
              local ok, msg = config.delete_session(config.bin, it.session_id)
              if ok then
                Snacks.notify("Deleted session: " .. it.title, { title = config.label })
              else
                Snacks.notify(msg or "Failed to delete session", vim.log.levels.ERROR, { title = config.label })
              end
            else
              Snacks.notify("Delete not supported for " .. config.label, vim.log.levels.WARN, { title = config.label })
            end
            picker:find({ refresh = true })
          end,
        }, config.extra_actions or {}),
      }
    end

    -- ── Higher-order factory for AI tool mode pickers (New / Resume) ───────
    local function ai_tool_mode_picker(config)
      return {
        prompt = config.label .. " ",
        layout = { preset = "select", layout = { max_width = 50 } },
        show_empty = true,
        focus = "list",
        main = { current = true },

        items = {
          { text = "Create New Session", action = "new", icon = "󰐕 " },
          { text = "Resume Session", action = "resume", icon = "󰁯 " },
        },

        format = function(item)
          return {
            { item.icon, "Special" },
            { item.text, "Normal" },
          }
        end,

        confirm = function(picker, item)
          picker:close()
          if not item then
            return
          end

          vim.schedule(function()
            if item.action == "new" then
              local bin = config.bin
              local cmd = config.new_cmd and config.new_cmd(bin) or { bin }
              vim.cmd(split_cmd)
              vim.fn.termopen(cmd, { cwd = vim.fn.getcwd() })
              vim.cmd("startinsert")
            elseif item.action == "resume" then
              Snacks.picker[config.name .. "_sessions"]()
            end
          end)
        end,
      }
    end

    -- ── Tool configs ───────────────────────────────────────────────────────

    -- 1. OpenCode
    local opencode_bin = vim.fn.expand("~/.opencode/bin/opencode")
    if vim.fn.executable(opencode_bin) ~= 1 then
      opencode_bin = "opencode"
    end

    opts.picker.sources.opencode_sessions = ai_session_picker({
      name = "opencode",
      label = "OpenCode",
      bin = opencode_bin,
      buf_var = "opencode_session_id",
      list_sessions = function(bin)
        local output = vim.fn.system({ bin, "session", "list", "--format", "json" })
        if vim.v.shell_error ~= 0 then
          return {}
        end
        local ok, sessions = pcall(vim.json.decode, output)
        if not ok or type(sessions) ~= "table" then
          return {}
        end
        local ret = {}
        for _, s in ipairs(sessions) do
          table.insert(ret, {
            id = s.id,
            title = s.title or "Untitled",
            directory = s.directory or "",
            updated = s.updated,
          })
        end
        return ret
      end,
      attach_cmd = function(bin, sid, cwd)
        return { bin, "-s", sid }
      end,
      delete_session = function(bin, sid)
        vim.fn.system({ bin, "session", "delete", sid })
        return vim.v.shell_error == 0
      end,
    })

    -- 2. Codex
    local codex_bin = "codex"
    opts.picker.sources.codex_sessions = ai_session_picker({
      name = "codex",
      label = "Codex",
      bin = codex_bin,
      buf_var = "codex_session_id",
      list_sessions = function(_)
        local path = vim.fn.expand("~/.codex/session_index.jsonl")
        local file = io.open(path, "r")
        if not file then
          return {}
        end
        local ret = {}
        for line in file:lines() do
          local ok, s = pcall(vim.json.decode, line)
          if ok and s and s.id then
            table.insert(ret, {
              id = s.id,
              title = s.thread_name or "Untitled",
              directory = "", -- codex stores cwd per-session internally
              updated = s.updated_at,
            })
          end
        end
        file:close()
        return ret
      end,
      attach_cmd = function(bin, sid, _)
        return { bin, "resume", sid }
      end,
      delete_session = nil, -- codex CLI has no delete command
    })

    -- 3. Claude
    local claude_bin = "claude"
    opts.picker.sources.claude_sessions = ai_session_picker({
      name = "claude",
      label = "Claude",
      bin = claude_bin,
      buf_var = "claude_session_id",
      list_sessions = function(_)
        local session_dir = vim.fn.expand("~/.claude/sessions")
        local ret = {}
        local handle = vim.uv.fs_scandir(session_dir)
        if not handle then
          return ret
        end
        while true do
          local name, t = vim.uv.fs_scandir_next(handle)
          if not name then
            break
          end
          if t == "file" and name:match("%.json$") then
            local path = session_dir .. "/" .. name
            local fd = io.open(path, "r")
            if fd then
              local content = fd:read("*a")
              fd:close()
              local ok, s = pcall(vim.json.decode, content)
              if ok and s and s.sessionId then
                table.insert(ret, {
                  id = s.sessionId,
                  title = "Session " .. s.sessionId:sub(1, 8),
                  directory = s.cwd or "",
                  updated = s.startedAt or nil,
                })
              end
            end
          end
        end
        return ret
      end,
      attach_cmd = function(bin, sid, _)
        return { bin, "-r", sid }
      end,
      delete_session = nil, -- claude CLI has no delete command
    })

    -- 4. Opus (isolated claude-code)
    local opus_bin = "claude-opus"
    opts.picker.sources.opus_sessions = ai_session_picker({
      name = "opus",
      label = "Opus",
      bin = opus_bin,
      buf_var = "opus_session_id",
      list_sessions = function(_)
        local session_dir = vim.fn.expand("~/.claude-opus/sessions")
        local ret = {}
        local handle = vim.uv.fs_scandir(session_dir)
        if not handle then
          return ret
        end
        while true do
          local name, t = vim.uv.fs_scandir_next(handle)
          if not name then
            break
          end
          if t == "file" and name:match("%.json$") then
            local path = session_dir .. "/" .. name
            local fd = io.open(path, "r")
            if fd then
              local content = fd:read("*a")
              fd:close()
              local ok, s = pcall(vim.json.decode, content)
              if ok and s and s.sessionId then
                table.insert(ret, {
                  id = s.sessionId,
                  title = "Session " .. s.sessionId:sub(1, 8),
                  directory = s.cwd or "",
                  updated = s.startedAt or nil,
                })
              end
            end
          end
        end
        return ret
      end,
      attach_cmd = function(bin, sid, _)
        return { bin, "-r", sid }
      end,
      delete_session = nil, -- claude-opus CLI has no delete command
    })

    -- 5. Kiro
    local kiro_bin = "kiro-cli"
    opts.picker.sources.kiro_sessions = ai_session_picker({
      name = "kiro",
      label = "Kiro",
      bin = kiro_bin,
      buf_var = "kiro_session_id",
      list_sessions = function(bin)
        local output = vim.fn.system({ bin, "chat", "--list-sessions", "-f", "json" })
        if vim.v.shell_error ~= 0 then
          return {}
        end
        -- kiro may print ANSI codes even with -f json; strip them
        output = output:gsub("\27%[[%d;]*m", "")
        local ok, sessions = pcall(vim.json.decode, output)
        if not ok or type(sessions) ~= "table" then
          return {}
        end
        local ret = {}
        for _, s in ipairs(sessions) do
          table.insert(ret, {
            id = s.id or s.session_id,
            title = s.title or s.name or "Untitled",
            directory = s.directory or s.cwd or "",
            updated = s.updated,
          })
        end
        return ret
      end,
      attach_cmd = function(bin, sid, cwd)
        return { bin, "chat", "--resume-id", sid }
      end,
      delete_session = function(bin, sid)
        vim.fn.system({ bin, "chat", "--delete-session", sid })
        return vim.v.shell_error == 0
      end,
    })

    -- Mode pickers (New / Resume gateway)
    opts.picker.sources.opencode_mode = ai_tool_mode_picker({
      name = "opencode",
      label = "OpenCode",
      bin = opencode_bin,
    })

    opts.picker.sources.codex_mode = ai_tool_mode_picker({
      name = "codex",
      label = "Codex",
      bin = codex_bin,
    })

    opts.picker.sources.claude_mode = ai_tool_mode_picker({
      name = "claude",
      label = "Claude",
      bin = claude_bin,
    })

    opts.picker.sources.opus_mode = ai_tool_mode_picker({
      name = "opus",
      label = "Opus",
      bin = opus_bin,
    })

    opts.picker.sources.kiro_mode = ai_tool_mode_picker({
      name = "kiro",
      label = "Kiro",
      bin = kiro_bin,
      new_cmd = function(bin)
        return { bin, "chat" }
      end,
    })

    -- 6. Docker AI (Ask Gordon) — no session persistence, opens directly
    opts.picker.sources.docker_mode = {
      prompt = "Docker AI ",
      layout = { preset = "select", layout = { max_width = 50 } },
      show_empty = true,
      focus = "list",
      main = { current = true },
      items = {
        { text = "Open Docker AI", action = "open", icon = "󰡨 " },
      },
      format = function(item)
        return {
          { item.icon, "Special" },
          { item.text, "Normal" },
        }
      end,
      confirm = function(picker, item)
        picker:close()
        if not item then
          return
        end
        vim.schedule(function()
          vim.cmd(split_cmd)
          vim.fn.termopen({ "docker", "ai" }, { cwd = vim.fn.getcwd() })
          vim.cmd("startinsert")
        end)
      end,
    }

    -- ── AI Tool selector (top-level) ──────────────────────────────────────
    opts.picker.sources.ai_tools = {
      prompt = "AI Tool ",
      layout = { preset = "select", layout = { max_width = 50 } },
      show_empty = true,
      focus = "list",
      main = { current = true },

      items = {
        { text = "OpenCode", tool = "opencode", icon = "󰆍 " },
        { text = "Codex", tool = "codex", icon = "󰊕 " },
        { text = "Claude", tool = "claude", icon = "󰋦 " },
        { text = "Opus", tool = "opus", icon = "󰌆 " },
        { text = "Kiro", tool = "kiro", icon = "󰧑 " },
        { text = "Docker", tool = "docker", icon = "󰡨 " },
      },

      format = function(item)
        return {
          { item.icon, "Special" },
          { item.text, "Normal" },
        }
      end,

      confirm = function(picker, item)
        picker:close()
        if not item then
          return
        end
        vim.schedule(function()
          Snacks.picker[item.tool .. "_mode"]()
        end)
      end,
    }

    return opts
  end,

  keys = {
    {
      "<leader>oask",
      function()
        vim.cmd("AskAI")
      end,
      desc = "Ask Support agent",
    },
    {
      "<leader>oc",
      function()
        split_cmd = "enew"
        Snacks.picker.opencode_mode()
      end,
      desc = "OpenCode",
    },
    {
      "<leader>od",
      function()
        split_cmd = "enew"
        Snacks.picker.codex_mode()
      end,
      desc = "Codex",
    },
    {
      "<leader>ol",
      function()
        split_cmd = "enew"
        Snacks.picker.claude_mode()
      end,
      desc = "Claude",
    },
    {
      "<leader>oo",
      function()
        split_cmd = "enew"
        Snacks.picker.opus_mode()
      end,
      desc = "Opus",
    },
    {
      "<leader>ok",
      function()
        split_cmd = "enew"
        Snacks.picker.kiro_mode()
      end,
      desc = "Kiro",
    },
    {
      "<leader>og",
      function()
        split_cmd = "enew"
        Snacks.picker.docker_mode()
      end,
      desc = "Docker AI",
    },
    {
      "<leader>oai",
      function()
        split_cmd = "enew"
        Snacks.picker.ai_tools()
      end,
      desc = "AI Tool Selector",
    },
    {
      "<leader>oaiv",
      function()
        split_cmd = "vsplit"
        Snacks.picker.ai_tools()
      end,
      desc = "AI Tool Selector (vsplit)",
    },
    {
      "<leader>oaih",
      function()
        split_cmd = "split"
        Snacks.picker.ai_tools()
      end,
      desc = "AI Tool Selector (hsplit)",
    },
    {
      "<leader>oaic",
      function()
        split_cmd = "enew"
        Snacks.picker.ai_tools()
      end,
      desc = "AI Tool Selector (current)",
    },
  },

  init = function()
    -- ── Support agent ask functionality ────────────────────────────────────
    local support_server_url = "http://localhost:4096"

    local function ensure_support_server()
      local ok = vim.fn.system("curl -s " .. support_server_url .. "/global/health > /dev/null 2>&1 && echo ok || echo fail"):gsub("%s+", "")
      if ok ~= "ok" then
        Snacks.notify("Support server not running on " .. support_server_url .. "\nStart it with: support-serve", { title = "AskAI", level = vim.log.levels.ERROR })
        return false
      end
      return true
    end

    local function get_support_session_id()
      local output = vim.fn.system("opencode session list --format json 2>/dev/null")
      local ok, sessions = pcall(vim.json.decode, output)
      if not ok or type(sessions) ~= "table" then
        return nil
      end
      table.sort(sessions, function(a, b)
        return (a.updated or 0) > (b.updated or 0)
      end)
      for _, s in ipairs(sessions) do
        if s.title == "Support" then
          return s.id
        end
      end
      return nil
    end

    local function ask_support(prompt)
      if not ensure_support_server() then
        return
      end
      local session_id = get_support_session_id()
      local cmd
      if session_id then
        cmd = { "opencode", "run", "--attach", support_server_url, "--agent", "Support", "--session", session_id, prompt }
      else
        cmd = { "opencode", "run", "--attach", support_server_url, "--agent", "Support", "--title", "Support", prompt }
      end
      vim.cmd(split_cmd)
      vim.fn.termopen(cmd, { cwd = vim.fn.getcwd() })
      vim.cmd("startinsert")
    end

    vim.api.nvim_create_user_command("AskAI", function()
      vim.ui.input({ prompt = "How can I help you? " }, function(input)
        if not input or input == "" then
          return
        end
        ask_support(input)
      end)
    end, { desc = "Ask Support agent" })

    vim.api.nvim_create_user_command("AI", function()
      split_cmd = "enew"
      Snacks.picker.ai_tools()
    end, { desc = "AI tool selector" })

    vim.api.nvim_create_user_command("AIV", function()
      split_cmd = "vsplit"
      Snacks.picker.ai_tools()
    end, { desc = "AI tool selector (vsplit)" })

    vim.api.nvim_create_user_command("AIH", function()
      split_cmd = "split"
      Snacks.picker.ai_tools()
    end, { desc = "AI tool selector (hsplit)" })

    vim.api.nvim_create_user_command("OpenCode", function()
      split_cmd = "enew"
      Snacks.picker.opencode_mode()
    end, { desc = "OpenCode session manager" })

    vim.api.nvim_create_user_command("Codex", function()
      split_cmd = "enew"
      Snacks.picker.codex_mode()
    end, { desc = "Codex session manager" })

    vim.api.nvim_create_user_command("Claude", function()
      split_cmd = "enew"
      Snacks.picker.claude_mode()
    end, { desc = "Claude session manager" })

    vim.api.nvim_create_user_command("Opus", function()
      split_cmd = "enew"
      Snacks.picker.opus_mode()
    end, { desc = "Opus session manager" })

    vim.api.nvim_create_user_command("Kiro", function()
      split_cmd = "enew"
      Snacks.picker.kiro_mode()
    end, { desc = "Kiro session manager" })

    vim.api.nvim_create_user_command("Docker", function()
      split_cmd = "enew"
      Snacks.picker.docker_mode()
    end, { desc = "Docker AI session manager" })
  end,
}
