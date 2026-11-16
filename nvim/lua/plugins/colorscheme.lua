-- Default theme: nord (nordic.nvim), aligned with the main nvim, herdr-app, Claude Code and pi.
-- gruvbox stays installed so it can still be picked (<leader>uC).
return {
  {
    "AlexvZyl/nordic.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      bold_keywords = false,
      italic_comments = true,
      transparent = {
        bg = false,
        float = false,
      },
      bright_border = false,
      reduced_blue = true,
      swap_backgrounds = false,
    },
    config = function(_, opts)
      require("nordic").setup(opts)
      -- nordic.nvim defines terminal colors but its loader does not apply them.
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "nordic",
        callback = function()
          for name, color in pairs(require("nordic.groups.terminal").get_groups()) do
            vim.g[name] = color
          end
        end,
      })
    end,
  },
  {
    "ellisonleao/gruvbox.nvim",
    lazy = true,
    opts = {
      terminal_colors = true,
      undercurl = true,
      underline = true,
      bold = true,
      italic = {
        strings = true,
        emphasis = true,
        comments = true,
        operators = false,
        folds = true,
      },
      strikethrough = true,
      invert_selection = false,
      invert_signs = false,
      invert_tabline = false,
      invert_intend_guides = false,
      inverse = true,
      contrast = "hard",
      palette_overrides = {},
      overrides = {},
      dim_inactive = false,
      transparent_mode = false,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "nordic",
    },
  },
}
