return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    opts.picker = opts.picker or {}
    opts.picker.sources = opts.picker.sources or {}

    -- Ensure files and explorer pickers respect gitignore and global fd ignore
    -- (prevents node_modules/, dist/, build/ from appearing in search)
    opts.picker.sources.files = opts.picker.sources.files or {}
    opts.picker.sources.files.ignored = false
    opts.picker.sources.files.hidden = true

    opts.picker.sources.explorer = opts.picker.sources.explorer or {}
    opts.picker.sources.explorer.ignored = false
    opts.picker.sources.explorer.hidden = true
  end,
}
