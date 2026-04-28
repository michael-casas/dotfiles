return {
  "rmagatti/auto-session",
  lazy = false,
  keys = {
    { "<leader>qs", "<cmd>AutoSession search<CR>", desc = "Search sessions" },
    { "<leader>qS", "<cmd>AutoSession save<CR>", desc = "Save session" },
    { "<leader>qd", "<cmd>AutoSession delete<CR>", desc = "Delete session" },
  },
  opts = {
    auto_save = true,
    auto_restore = true,
    auto_create = true,
    suppressed_dirs = { "~/", "~/Downloads", "/", "/tmp" },
    bypass_save_filetypes = { "snacks_dashboard", "alpha", "dashboard" },
    close_filetypes_on_save = { "checkhealth" },
    session_lens = {
      picker = "snacks",
      mappings = {
        delete_session = { "i", "<C-d>" },
        alternate_session = { "i", "<C-s>" },
        copy_session = { "i", "<C-y>" },
      },
    },
    pre_save_cmds = {
      function()
        -- Close any terminal buffers before saving to avoid weird state
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.bo[buf].buftype == "terminal" then
            vim.api.nvim_buf_call(buf, function()
              vim.cmd("stopinsert")
            end)
          end
        end
      end,
    },
  },
}
