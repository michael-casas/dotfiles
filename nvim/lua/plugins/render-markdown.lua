-- render-markdown.nvim: inline markdown preview with conceal and virtual text
-- Renders headers, code blocks, bullets, checkboxes, and quotes inline
-- so markdown files look like a preview without leaving the editor.
return {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  ft = { "markdown", "mdx", "norg", "rmd", "org" },
  opts = {
    enabled = true,
    max_file_size = 5 * 1024 * 1024,
    anti_conceal = {
      enabled = true,
      above = 0,
      below = 0,
    },
    heading = {
      enabled = true,
      sign = true,
      style = "full",
      icons = { "󰉫 ", "󰉬 ", "󰉭 ", "󰉮 ", "󰉯 ", "󰉰 " },
    },
    code = {
      enabled = true,
      sign = true,
      style = "full",
      position = "left",
      language_pad = 2,
      language_name = true,
      disable_background = false,
      width = "full",
      left_pad = 2,
      right_pad = 2,
      min_width = 0,
      border = "thin",
      above = "▄",
      below = "▀",
    },
    bullet = {
      enabled = true,
      icons = { "●", "○", "◆", "◇" },
      left_pad = 0,
      right_pad = 0,
    },
    checkbox = {
      enabled = true,
      unchecked = { icon = "󰄱 " },
      checked = { icon = "󰱒 " },
      custom = {
        todo = { raw = "[-]", rendered = "󰥔 ", highlight = "RenderMarkdownTodo" },
        important = { raw = "[!]", rendered = "󰀦 ", highlight = "RenderMarkdownImportant" },
      },
    },
    quote = {
      enabled = true,
      icon = "▋",
      repeat_linebreak = false,
    },
    pipe_table = {
      enabled = true,
      preset = "heavy",
      style = "full",
      cell = "padded",
      alignment_indicator = "━",
      border = {
        "┌", "┬", "┐",
        "├", "┼", "┤",
        "└", "┴", "┘",
        "│", "─",
      },
    },
    -- NOTE: callout does NOT have an `enabled` key at the top level.
    -- It is a flat table of callout definitions. Each entry must have
    -- `raw`, `rendered`, and `highlight` fields.
    callout = {
      note = { raw = "[!NOTE]", rendered = "󰋽 Note", highlight = "RenderMarkdownInfo" },
      tip = { raw = "[!TIP]", rendered = "󰌶 Tip", highlight = "RenderMarkdownSuccess" },
      important = { raw = "[!IMPORTANT]", rendered = "󰅾 Important", highlight = "RenderMarkdownHint" },
      warning = { raw = "[!WARNING]", rendered = "󰀪 Warning", highlight = "RenderMarkdownWarn" },
      caution = { raw = "[!CAUTION]", rendered = "󰳦 Caution", highlight = "RenderMarkdownError" },
    },
    link = {
      enabled = true,
      image = "󰥶 ",
      hyperlink = "󰌷 ",
      wiki = { icon = "󱗖 " },
      custom = {
        web = { pattern = "^http[s]?://", icon = "󰖟 " },
        github = { pattern = "^http[s]?://github%.com/", icon = "󰊤 " },
      },
    },
    sign = { enabled = true },
    indent = { enabled = false, per_level = 2 },
    latex = { enabled = false },
    win_options = {
      conceallevel = {
        default = vim.o.conceallevel,
        rendered = 3,
      },
      concealcursor = {
        default = vim.o.concealcursor,
        rendered = "nc",
      },
    },
  },
}
