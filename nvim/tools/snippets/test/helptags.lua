local config = vim.fn.getcwd() .. "/nvim"
vim.opt.rtp:prepend(config)
vim.opt.rtp:prepend(config .. "/plugins/emmet-md")
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
vim.uv.sleep(25)
vim.fn.writefile({ "*replacement-envi-tag*  Updated help" }, doc .. "/envi-snippets.txt")
source()
assert(has_tag("replacement-envi-tag") and not has_tag("initial-envi-tag"), "startup must refresh stale help tags")
print("PASS startup help tags are generated and refreshed")
