local config = vim.fn.getcwd()

local plugin = vim.fn.stdpath("state") .. "/standalone-emmet-md [x] $ % #"
vim.fn.mkdir(plugin .. "/plugin", "p")
vim.fn.mkdir(plugin .. "/doc", "p")
local plugin_file = plugin .. "/plugin/emmet-md.lua"
local standalone_doc = plugin .. "/doc"
local standalone_tags = standalone_doc .. "/tags"
local emmet_help = standalone_doc .. "/emmet-md.txt"
assert(vim.uv.fs_copyfile(config .. "/plugin/emmet-md.lua", plugin_file))
vim.fn.writefile({ "*test-emmet-tag*  Standalone help" }, emmet_help)
vim.opt.rtp:prepend(config)
local function source_emmet()
  vim.g.loaded_emmet_md = nil
  if vim.fn.exists(":EmmetMd") == 2 then
    vim.api.nvim_del_user_command("EmmetMd")
  end
  dofile(plugin_file)
end
source_emmet()
assert(vim.fn.readfile(standalone_tags)[1]:find("test-emmet-tag", 1, true))

local api_cmd = vim.api.nvim_cmd
local attempts = 0
local unwritable = false
vim.api.nvim_cmd = function(command, opts)
  if command.cmd == "helptags" then
    attempts = attempts + 1
    if unwritable then
      error("simulated unwritable tags directory")
    end
  end
  return api_cmd(command, opts)
end

assert(vim.uv.fs_utime(emmet_help, 100.1, 100.1))
assert(vim.uv.fs_utime(standalone_doc, 100.1, 100.1))
assert(vim.uv.fs_utime(standalone_tags, 100.5, 100.5))
source_emmet()
assert(attempts == 0, "fresh tags must not be rewritten")

vim.fn.writefile({ "*updated-emmet-tag*  Updated help" }, emmet_help)
assert(vim.uv.fs_utime(emmet_help, 100.9, 100.9))
source_emmet()
assert(attempts == 1 and vim.fn.readfile(standalone_tags)[1]:find("updated-emmet-tag", 1, true))

assert(vim.uv.fs_utime(emmet_help, 100, 100))
assert(vim.uv.fs_utime(standalone_tags, 101, 101))
assert(vim.uv.fs_utime(standalone_doc, 102, 102))
source_emmet()
assert(attempts == 2, "directory changes must refresh tags")

unwritable = true
assert(vim.uv.fs_unlink(standalone_tags))
source_emmet()
assert(attempts == 3 and vim.fn.exists(":EmmetMd") == 2)
print("PASS startup help tags are generated and refreshed")
