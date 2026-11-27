if vim.g.loaded_emmet_md then
  return
end
vim.g.loaded_emmet_md = true
local plugin = debug.getinfo(1, "S").source:sub(2)
require("emmet-md.helptags")(vim.fs.dirname(vim.fs.dirname(plugin)) .. "/doc")

vim.keymap.set("i", "<Plug>(emmet-md-expand)", function()
  require("emmet-md").expand_at_cursor()
end, { desc = "Expand Markdown Emmet abbreviation" })

vim.api.nvim_create_user_command("EmmetMd", function(command)
  require("emmet-md")._command(command.args)
end, { nargs = "*", desc = "Expand Markdown Emmet at the cursor" })
