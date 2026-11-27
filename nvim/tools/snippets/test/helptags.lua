local config = vim.fn.getcwd() .. "/nvim"
vim.opt.rtp:prepend(config)
local doc = vim.fn.stdpath("config") .. "/doc"
vim.fn.mkdir(doc, "p")
local function source()
  vim.g.loaded_envi_snippets = nil
  vim.cmd("runtime plugin/envi-snippets.lua")
end
local function has_tag(tag)
  return vim.iter(vim.fn.readfile(doc .. "/tags")):any(function(line)
    return vim.startswith(line, tag .. "\t")
  end)
end
vim.fn.writefile({ "*initial-envi-tag*  Initial help" }, doc .. "/envi-snippets.txt")
source()
assert(has_tag("initial-envi-tag"), "startup must create missing help tags")
assert(vim.fn.exists(":Snippets") == 2 and not package.loaded["emmet-md.helptags"])
vim.uv.sleep(25)
vim.fn.writefile({ "*replacement-envi-tag*  Updated help" }, doc .. "/envi-snippets.txt")
source()
assert(has_tag("replacement-envi-tag") and not has_tag("initial-envi-tag"), "startup must refresh stale help tags")

local plugin = vim.fn.stdpath("state") .. "/standalone-emmet-md"
vim.fn.mkdir(plugin .. "/plugin", "p")
vim.fn.mkdir(plugin .. "/doc", "p")
local plugin_file = plugin .. "/plugin/emmet-md.lua"
assert(vim.uv.fs_copyfile(config .. "/plugins/emmet-md/plugin/emmet-md.lua", plugin_file))
vim.fn.writefile({ "*test-emmet-tag*  Standalone help" }, plugin .. "/doc/emmet-md.txt")
vim.opt.rtp:prepend(config .. "/plugins/emmet-md")
dofile(plugin_file)
assert(vim.fn.readfile(plugin .. "/doc/tags")[1]:find("test-emmet-tag", 1, true))

local api_cmd = vim.api.nvim_cmd
local attempts = 0
vim.api.nvim_cmd = function(command, opts)
  if command.cmd == "helptags" then
    attempts = attempts + 1
    error("simulated unwritable tags directory")
  end
  return api_cmd(command, opts)
end
assert(vim.uv.fs_unlink(plugin .. "/doc/tags"))
vim.g.loaded_emmet_md = nil
vim.api.nvim_del_user_command("EmmetMd")
dofile(plugin_file)
assert(attempts == 1 and vim.fn.exists(":EmmetMd") == 2)
print("PASS startup help tags are generated and refreshed")
