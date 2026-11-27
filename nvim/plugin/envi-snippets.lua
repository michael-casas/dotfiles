if vim.g.loaded_envi_snippets then
  return
end
vim.g.loaded_envi_snippets = true
require("emmet-md.helptags")(vim.fn.stdpath("config") .. "/doc")
require("envi.snippets.commands").register()
