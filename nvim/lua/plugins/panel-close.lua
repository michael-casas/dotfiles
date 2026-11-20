return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      local preset = opts.dashboard and opts.dashboard.preset
      if preset and type(preset.keys) == "table" then
        for _, item in ipairs(preset.keys) do
          if item.key == "q" then
            item.key = nil
          end
        end
      end
      require("config.snacks-close").setup()
    end,
  },
}
