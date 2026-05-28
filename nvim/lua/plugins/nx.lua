return {
  "yardnsm/nx-console.nvim",
  submodules = false,
  dependencies = {
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim",
  },

  opts = function()
    return {
      picker = "snacks",
      command_runner = require("nx-console.runners").snacks(),
    }
  end,

  keys = {
    {
      "<leader>nxr",
      function()
        require("nx-console").pickers.targets()
      end,
      desc = "Nx Task Runner",
    },
    {
      "<leader>nxg",
      function()
        require("nx-console").pickers.generators()
      end,
      desc = "Nx Generators",
    },
  },
}
