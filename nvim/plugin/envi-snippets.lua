if vim.g.loaded_envi_snippets then
  return
end
vim.g.loaded_envi_snippets = true
require("envi.snippets.commands").register()
