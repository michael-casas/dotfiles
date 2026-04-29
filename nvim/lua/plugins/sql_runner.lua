return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    opts.picker = opts.picker or {}
    opts.picker.sources = opts.picker.sources or {}

    -- ── SQL Action Picker ──────────────────────────────────────────────────
    opts.picker.sources.sql_actions = {
      prompt = "Run SQL ",
      layout = { preset = "select", layout = { max_width = 50 } },
      show_empty = true,
      focus = "list",
      main = { current = true },

      items = {
        { text = "Run current file in psql", action = "run_file", icon = "▶ " },
        { text = "Launch psql shell", action = "launch_shell", icon = " " },
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
        if not filepath or filepath == "" or not filepath:match("%.sql$") then
          Snacks.notify("Not a .sql file", vim.log.levels.WARN, { title = "SQL Runner" })
          return
        end

        vim.schedule(function()
          if item.action == "run_file" then
            -- Async job: psql -f <file>
            local output_lines = {}
            local job_id = vim.fn.jobstart({ "psql", "-f", filepath }, {
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
                  -- Create scratch buffer
                  local buf = vim.api.nvim_create_buf(false, true)
                  vim.bo[buf].buftype = "nofile"
                  vim.bo[buf].bufhidden = "wipe"
                  vim.bo[buf].swapfile = false
                  vim.bo[buf].modifiable = true

                  local header = {
                    "psql -f " .. filepath,
                    "exit code: " .. exit_code,
                    string.rep("─", 60),
                  }
                  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend(header, output_lines))
                  vim.bo[buf].modifiable = false
                  vim.bo[buf].filetype = "text"

                  -- Floating window dimensions
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
                    title = " psql output ",
                    title_pos = "center",
                  })

                  -- Normal mode, q to close
                  vim.keymap.set("n", "q", function()
                    vim.api.nvim_win_close(win, true)
                  end, { buffer = buf, nowait = true, silent = true })
                  vim.keymap.set("n", "<Esc>", function()
                    vim.api.nvim_win_close(win, true)
                  end, { buffer = buf, nowait = true, silent = true })
                end)
              end,
            })

            if job_id <= 0 then
              Snacks.notify("Failed to start psql job", vim.log.levels.ERROR, { title = "SQL Runner" })
            end

          elseif item.action == "launch_shell" then
            vim.cmd("enew")
            vim.fn.termopen({ "psql" }, { cwd = vim.fn.getcwd() })
            vim.cmd("startinsert")
          end
        end)
      end,
    }

    return opts
  end,

  keys = {
    {
      "<leader>osql",
      function()
        local filepath = vim.api.nvim_buf_get_name(0)
        if filepath and filepath:match("%.sql$") then
          Snacks.picker.sql_actions()
        else
          Snacks.notify("Open a .sql file first", vim.log.levels.WARN, { title = "SQL Runner" })
        end
      end,
      desc = "SQL actions (run file / psql shell)",
    },
  },
}
