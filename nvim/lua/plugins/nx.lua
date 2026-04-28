return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    opts.picker = opts.picker or {}
    opts.picker.sources = opts.picker.sources or {}

    local function nx_bin()
      if vim.fn.filereadable("package.json") == 1 then
        local f = io.open("package.json", "r")
        if f then
          local content = f:read("*a")
          f:close()
          if content:find("nx") then
            return "npx nx"
          end
        end
      end
      return nil
    end

    -- ── Nx Task Runner ─────────────────────────────────────────────────────
    opts.picker.sources.nx_tasks = {
      prompt = "Nx Task ",
      layout = { preset = "vscode" },
      show_empty = true,

      finder = function(_, ctx)
        local items = {}
        local bin = nx_bin()
        if not bin then
          return items
        end

        local output = vim.fn.system(bin .. " show projects --json")
        if vim.v.shell_error ~= 0 then
          return items
        end

        local ok, projects = pcall(vim.json.decode, output)
        if not ok or type(projects) ~= "table" then
          return items
        end

        for _, project in ipairs(projects) do
          local proj_output = vim.fn.system(bin .. " show project " .. project .. " --json")
          if vim.v.shell_error == 0 then
            local pok, proj_info = pcall(vim.json.decode, proj_output)
            if pok and proj_info and proj_info.targets then
              for target, _ in pairs(proj_info.targets) do
                table.insert(items, {
                  text = project .. ":" .. target,
                  project = project,
                  target = target,
                })
              end
            end
          end
        end

        return ctx.filter:filter(items)
      end,

      format = function(item)
        return {
          { item.project .. ":", "Keyword" },
          { item.target, "Function" },
        }
      end,

      confirm = function(picker, item)
        picker:close()
        if not item then
          return
        end
        vim.schedule(function()
          vim.cmd("enew")
          vim.fn.termopen({ "npx", "nx", "run", item.project .. ":" .. item.target })
          vim.cmd("startinsert")
        end)
      end,
    }

    -- ── Nx Generators ──────────────────────────────────────────────────────
    opts.picker.sources.nx_generators = {
      prompt = "Nx Generator ",
      layout = { preset = "vscode" },
      show_empty = true,

      finder = function(_, ctx)
        local items = {}
        local bin = nx_bin()
        if not bin then
          return items
        end

        local output = vim.fn.system(bin .. " list")
        if vim.v.shell_error ~= 0 then
          return items
        end

        for line in output:gmatch("[^\r\n]+") do
          local plugin, gen = line:match("^%s+([%w%-%_]+):([%w%-%_]+)")
          if plugin and gen then
            table.insert(items, {
              text = plugin .. ":" .. gen,
              plugin = plugin,
              generator = gen,
            })
          end
        end

        return ctx.filter:filter(items)
      end,

      format = function(item)
        return {
          { item.plugin .. ":", "Keyword" },
          { item.generator, "Function" },
        }
      end,

      confirm = function(picker, item)
        picker:close()
        if not item then
          return
        end
        vim.schedule(function()
          vim.cmd("enew")
          vim.fn.termopen({ "npx", "nx", "generate", item.plugin .. ":" .. item.generator })
          vim.cmd("startinsert")
        end)
      end,
    }

    return opts
  end,

  keys = {
    {
      "<leader>nxg",
      function()
        Snacks.picker.nx_generators()
      end,
      desc = "Nx Generators",
    },
    {
      "<leader>nxr",
      function()
        Snacks.picker.nx_tasks()
      end,
      desc = "Nx Task Runner",
    },
  },
}
