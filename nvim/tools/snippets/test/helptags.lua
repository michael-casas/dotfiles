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

-- The platform helper must contain a command failure, even when emmet-md
-- is absent, and return control to the startup script.
local real_cmd = vim.api.nvim_cmd
local calls = 0
local fail_write = false
vim.api.nvim_cmd = function(command, opts)
  if command.cmd == "helptags" then
    calls = calls + 1
    if fail_write then
      error("simulated platform help write failure")
    end
  end
  return real_cmd(command, opts)
end
local help = doc .. "/envi-snippets.txt"
assert(vim.uv.fs_utime(help, 100, 100))
assert(vim.uv.fs_utime(doc, 100, 100))
assert(vim.uv.fs_utime(doc .. "/tags", 101, 101))
source()
assert(calls == 0, "fresh platform tags must remain untouched")
assert(vim.uv.fs_utime(doc, 102, 102))
source()
assert(calls == 1, "platform tags must refresh after a directory change")
fail_write = true
assert(vim.uv.fs_unlink(doc .. "/tags"))
local cwd = vim.uv.cwd()
source()
assert(calls == 2 and vim.fn.exists(":Snippets") == 2)
assert(vim.uv.cwd() == cwd, "failed tag generation must preserve the working directory")
vim.api.nvim_cmd = real_cmd

local plugin = vim.fn.stdpath("state") .. "/standalone-emmet-md"
vim.fn.mkdir(plugin .. "/plugin", "p")
vim.fn.mkdir(plugin .. "/doc", "p")
local plugin_file = plugin .. "/plugin/emmet-md.lua"
local standalone_doc = plugin .. "/doc"
local standalone_tags = standalone_doc .. "/tags"
local emmet_help = standalone_doc .. "/emmet-md.txt"
assert(vim.uv.fs_copyfile(config .. "/plugins/emmet-md/plugin/emmet-md.lua", plugin_file))
vim.fn.writefile({ "*test-emmet-tag*  Standalone help" }, emmet_help)
vim.opt.rtp:prepend(config .. "/plugins/emmet-md")
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
