-- Dadbod UI: a database drawer, query buffers and result buffers inside envi.
-- See nvim/docs/dadbod.md for connections, secrets and switching.
--
-- Hand-written in place of LazyVim's `lang.sql` extra: the extra also adds a
-- global <leader>D mapping, sqlfluff through Mason with lint and format hooks,
-- and an edgy layout. Envi adds no global keys here; use :DBUIToggle.
--
-- Connections come from three places, all outside git:
--   1. g:dbs, read from a local Lua file ($ENVI_DBS_FILE, default
--      $XDG_CONFIG_HOME/envi-local/dbs.lua). Envi's config is a link into a
--      checkout, so the file deliberately does not live there.
--   2. :DBUIAddConnection, saved under g:db_ui_save_location (envi's data dir).
--   3. DBUI_URL (and optionally DBUI_NAME) in the environment envi starts in.

local sql_ft = { "sql", "mysql", "plsql" }

--- The local connections file. Returns its path.
local function dbs_file()
  if vim.env.ENVI_DBS_FILE and vim.env.ENVI_DBS_FILE ~= "" then
    return vim.env.ENVI_DBS_FILE
  end
  local config_home = vim.env.XDG_CONFIG_HOME
  if not config_home or config_home == "" then
    config_home = vim.fn.expand("~/.config")
  end
  return config_home .. "/envi-local/dbs.lua"
end

--- Load g:dbs from the local file, if there is one. The file returns either
--- { name = "url", ... } or { { name = "...", url = "..." }, ... }.
local function load_dbs()
  local path = dbs_file()
  if not vim.uv.fs_stat(path) then
    return
  end
  local ok, dbs = pcall(dofile, path)
  if not ok then
    vim.notify("Dadbod: could not load " .. path .. ": " .. tostring(dbs), vim.log.levels.ERROR)
    return
  end
  if type(dbs) ~= "table" then
    vim.notify("Dadbod: " .. path .. " must return a table of connections", vim.log.levels.ERROR)
    return
  end
  vim.g.dbs = dbs
end

return {
  {
    "tpope/vim-dadbod",
    cmd = "DB",
    init = function()
      -- Dadbod runs psql as `psql -X`, so ~/.psqlrc stays out of its results;
      -- plain psql still reads it. vim-dadbod's g:db_adapter_<scheme> override
      -- points both Postgres schemes at autoload/envi/dadbod_postgresql.vim.
      vim.g.db_adapter_postgresql = "envi#dadbod_postgresql#"
      vim.g.db_adapter_postgres = "envi#dadbod_postgresql#"
    end,
  },

  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = "tpope/vim-dadbod",
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    init = function()
      local data = vim.fn.stdpath("data") .. "/dadbod_ui"
      vim.g.db_ui_save_location = data
      vim.g.db_ui_tmp_query_location = data .. "/tmp"
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_use_nvim_notify = 1
      -- Choosing a table helper such as "List" runs it straight away.
      vim.g.db_ui_auto_execute_table_helpers = 1
    end,
    config = load_dbs,
  },

  {
    "kristijanhusak/vim-dadbod-completion",
    dependencies = "tpope/vim-dadbod",
    ft = sql_ft,
    init = function()
      -- Neovim's SQL ftplugin maps <C-c> prefixes in Insert mode; keep <C-c> free.
      vim.g.omni_sql_no_default_maps = 1
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("EnviDadbodCompletion", { clear = true }),
        pattern = sql_ft,
        callback = function(ev)
          -- <C-x><C-o> works without blink.cmp too.
          vim.bo[ev.buf].omnifunc = "vim_dadbod_completion#omni"
        end,
      })
    end,
  },

  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" }
      opts.sources.per_filetype = opts.sources.per_filetype or {}
      for _, ft in ipairs(sql_ft) do
        opts.sources.per_filetype[ft] = { "dadbod", inherit_defaults = true }
      end
    end,
  },
}
