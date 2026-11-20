-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local close = require("config.panel-close")
local api = vim.api

-- Keep LazyVim's unlisted utility buffers and cleanup behavior, with a
-- buffer-local command that also keeps the last editor window open.
local ok, defaults = pcall(api.nvim_get_autocmds, { group = "lazyvim_close_with_q", event = "FileType" })
if ok and #defaults > 0 then
  api.nvim_clear_autocmds({ group = "lazyvim_close_with_q", event = "FileType" })
  api.nvim_create_autocmd("FileType", {
    group = "lazyvim_close_with_q",
    pattern = vim.tbl_map(function(autocmd)
      return autocmd.pattern
    end, defaults),
    callback = function(ev)
      vim.bo[ev.buf].buflisted = false
      close.bind(ev.buf, function()
        close.close_window()
        if api.nvim_buf_is_valid(ev.buf) then
          api.nvim_buf_delete(ev.buf, { force = true })
        end
      end)
    end,
  })
end

-- These plugins install their close mappings while creating the view.
local function adopt_close(buf)
  close.adopt(buf, function()
    close.keep_editor(api.nvim_get_current_win())
  end)
end

local group = api.nvim_create_augroup("envi_plugin_panel_close", { clear = true })
api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "trouble", "noice", "grug-far-help", "DiffviewFileHistory", "lazy", "mason", "man" },
  callback = function(ev)
    vim.schedule(function()
      adopt_close(ev.buf)
    end)
  end,
})
api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(ev)
    if ev.match:match("^diffview:///panels/") then
      vim.schedule(function()
        adopt_close(ev.buf)
      end)
    elseif vim.bo[ev.buf].buftype == "nofile" then
      -- Some plugin floats use generic scratch buffers. Inspect the bound
      -- window after construction and accept only a recognized close action.
      vim.schedule(function()
        if
          not api.nvim_buf_is_valid(ev.buf)
          or not vim.iter(vim.fn.win_findbuf(ev.buf)):any(function(win)
            return api.nvim_win_get_config(win).relative ~= ""
          end)
        then
          return
        end
        for _, map in ipairs(api.nvim_buf_get_keymap(ev.buf, "n")) do
          local rhs = (map.rhs or ""):lower()
          if map.lhs == "q" and (map.desc == "Close" or rhs == "<cmd>close<cr>" or rhs == "<cmd>quit!<cr>") then
            adopt_close(ev.buf)
            return
          end
        end
      end)
    end
  end,
})
