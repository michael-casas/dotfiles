return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    opts.picker = opts.picker or {}
    opts.picker.sources = opts.picker.sources or {}

    -- ── Connection cache (per nvim session) ────────────────────────────────
    local pg_conn = {}

    local function prompt_conn(callback)
      vim.ui.input({ prompt = "Host (default localhost): ", default = pg_conn.host or "localhost" }, function(host)
        if not host then
          return
        end
        pg_conn.host = host ~= "" and host or "localhost"

        vim.ui.input({ prompt = "Port (default 5432): ", default = pg_conn.port or "5432" }, function(port)
          if not port then
            return
          end
          pg_conn.port = port ~= "" and port or "5432"

          vim.ui.input({ prompt = "User (default postgres): ", default = pg_conn.user or "postgres" }, function(user)
            if not user then
              return
            end
            pg_conn.user = user ~= "" and user or "postgres"

            vim.ui.input({ prompt = "Password: ", default = pg_conn.password or "" }, function(password)
              if not password then
                return
              end
              pg_conn.password = password
              callback(pg_conn)
            end)
          end)
        end)
      end)
    end

    local function list_databases(conn, on_select)
      local cmd = {
        "bash",
        "-c",
        "PGPASSWORD="
          .. vim.fn.shellescape(conn.password)
          .. " psql -h "
          .. vim.fn.shellescape(conn.host)
          .. " -p "
          .. vim.fn.shellescape(conn.port)
          .. " -U "
          .. vim.fn.shellescape(conn.user)
          .. ' -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;"',
      }

      local dbs = {}
      vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data)
          if data then
            for _, line in ipairs(data) do
              if line ~= "" then
                table.insert(dbs, line)
              end
            end
          end
        end,
        on_stderr = function(_, data)
          if data then
            for _, line in ipairs(data) do
              if line ~= "" then
                table.insert(dbs, "ERR: " .. line)
              end
            end
          end
        end,
        on_exit = function(_, code)
          vim.schedule(function()
            if code ~= 0 or #dbs == 0 then
              Snacks.notify("Failed to list databases. Check credentials.", { title = "SQL Runner", level = vim.log.levels.ERROR })
              return
            end

            local items = {}
            for _, db in ipairs(dbs) do
              if not db:match("^ERR:") then
                table.insert(items, { text = db, db = db })
              end
            end

            Snacks.picker({
              prompt = "Database ",
              layout = { preset = "select", layout = { max_width = 50 } },
              show_empty = true,
              focus = "list",
              items = items,
              format = function(item)
                return { { "󰆼 ", "Special" }, { item.db, "Normal" } }
              end,
              confirm = function(picker, item)
                picker:close()
                if item then
                  on_select(item.db)
                end
              end,
            })
          end)
        end,
      })
    end

    local function show_output(title_lines, output_lines)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      vim.bo[buf].swapfile = false
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend(title_lines, output_lines))
      vim.bo[buf].modifiable = false
      vim.bo[buf].filetype = "text"

      local width = math.floor(vim.o.columns * 0.8)
      local height = math.floor(vim.o.lines * 0.8)
      local row = math.floor((vim.o.lines - height) / 2)
      local col = math.floor((vim.o.columns - width) / 2)

      local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " pgcli output ",
        title_pos = "center",
      })

      vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
      end, { buffer = buf, nowait = true, silent = true })
      vim.keymap.set("n", "<Esc>", function()
        vim.api.nvim_win_close(win, true)
      end, { buffer = buf, nowait = true, silent = true })
    end

    -- ── SQL Action Picker ──────────────────────────────────────────────────
    opts.picker.sources.sql_actions = {
      prompt = "Run SQL ",
      layout = { preset = "select", layout = { max_width = 50 } },
      show_empty = true,
      focus = "list",
      main = { current = true },

      items = {
        { text = "Run current file in pgcli", action = "run_file", icon = "▶ " },
        { text = "Launch pgcli shell", action = "launch_shell", icon = " " },
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

        local filepath = vim.api.nvim_buf_get_name(0)
        local is_sql = filepath and filepath ~= "" and filepath:match("%.sql$")

        if item.action == "run_file" and not is_sql then
          Snacks.notify("Not a .sql file — open one first", { title = "SQL Runner", level = vim.log.levels.WARN })
          return
        end

        prompt_conn(function(conn)
          list_databases(conn, function(db)
            if item.action == "run_file" then
              local output_lines = {}
              local run_cmd = {
                "bash",
                "-c",
                "PGPASSWORD="
                  .. vim.fn.shellescape(conn.password)
                  .. " pgcli -w -h "
                  .. vim.fn.shellescape(conn.host)
                  .. " -p "
                  .. vim.fn.shellescape(conn.port)
                  .. " -U "
                  .. vim.fn.shellescape(conn.user)
                  .. " -d "
                  .. vim.fn.shellescape(db)
                  .. " < "
                  .. vim.fn.shellescape(filepath),
              }

              vim.fn.jobstart(run_cmd, {
                stdout_buffered = true,
                stderr_buffered = true,
                on_stdout = function(_, data)
                  if data then
                    for _, line in ipairs(data) do
                      if line ~= "" then
                        table.insert(output_lines, line)
                      end
                    end
                  end
                end,
                on_stderr = function(_, data)
                  if data then
                    for _, line in ipairs(data) do
                      if line ~= "" then
                        table.insert(output_lines, "ERR: " .. line)
                      end
                    end
                  end
                end,
                on_exit = function(_, exit_code)
                  vim.schedule(function()
                    local header = {
                      "pgcli -w -h " .. conn.host .. " -p " .. conn.port .. " -U " .. conn.user .. " -d " .. db,
                      "file: " .. filepath,
                      "exit code: " .. exit_code,
                      string.rep("─", 60),
                    }
                    show_output(header, output_lines)
                  end)
                end,
              })
            elseif item.action == "launch_shell" then
              vim.cmd("enew")
              vim.fn.termopen({ "pgcli", "-w", "-h", conn.host, "-p", conn.port, "-U", conn.user, "-d", db }, {
                env = { PGPASSWORD = conn.password },
                cwd = vim.fn.getcwd(),
              })
              vim.cmd("startinsert")
            end
          end)
        end)
      end,
    }

    return opts
  end,

  keys = {
    {
      "<leader>osql",
      function()
        Snacks.picker.sql_actions()
      end,
      desc = "SQL actions (run file / pgcli shell)",
    },
  },
}
