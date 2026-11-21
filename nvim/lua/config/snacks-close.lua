local M = {}

function M.setup()
  if M.installed then
    return
  end
  local close = require("config.panel-close")
  local win = require("snacks").win
  M.installed = true
  local map = win.map
  -- Snacks builds the final buffer-local action in win:map(). Use that same
  -- action for :q on every mount, including hidden terminals and new layouts.
  function win:map()
    map(self)
    for _, key in ipairs(self.keys) do
      local modes = type(key.mode) == "table" and key.mode or { key.mode or "n" }
      if key[1] == "q" and vim.tbl_contains(modes, "n") then
        close.adopt(self.buf, function()
          close.keep_editor(self.win)
        end)
        return
      end
    end
  end
  vim.api.nvim_create_autocmd("User", {
    pattern = "SnacksDashboardOpened",
    callback = function()
      if vim.bo.filetype == "snacks_dashboard" then
        close.adopt(vim.api.nvim_get_current_buf())
      end
    end,
  })
end

return M
