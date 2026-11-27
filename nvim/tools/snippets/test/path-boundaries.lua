vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local root = vim.fs.normalize(vim.fn.stdpath("state") .. "/literal-paths", { expand_env = false })
local repo = root .. "/`literal` % # [x]"
local home = root .. "/home"
local source = vim.fn.writefile
vim.fn.mkdir(repo, "p")
vim.fn.mkdir(home .. "/pack", "p")
local pack = '{"Test":{"prefix":"example","body":"literal"}}'
source({ pack }, repo .. "/markdown.json")
source({ pack }, home .. "/pack/markdown.json")
vim.env.HOME = home
local snippets = require("envi.snippets")

local warnings = {}
vim.notify = function(message, level)
  warnings[#warnings + 1] = { message, level }
end
if vim.env.ENVI_PATH_CASE == "home" then
  snippets.setup({ repo_dir = "~/pack", friendly_dir = false })
  assert(snippets.get("example", "markdown"), "the catalogue must read the home-relative pack")
  snippets.setup({ repo_dir = "~/missing", friendly_dir = false })
  snippets.list("markdown")
  assert(
    vim.iter(warnings):any(function(record)
      return record[2] == vim.log.levels.WARN and record[1]:find(home .. "/missing", 1, true)
    end),
    "warn about an unavailable repository"
  )
  local non_directory = home .. "/pack/markdown.json"
  snippets.setup({ repo_dir = non_directory, friendly_dir = false })
  snippets.list("markdown")
  assert(
    vim.iter(warnings):any(function(record)
      return record[2] == vim.log.levels.WARN and record[1]:find(non_directory, 1, true)
    end),
    "warn about an unusable repository"
  )
else
  local nvim_cmd = vim.api.nvim_cmd
  vim.api.nvim_cmd = function(command, opts)
    for _, arg in ipairs(command.args or {}) do
      assert(not arg:find(repo, 1, true), "an owner path reached Ex expansion")
    end
    return nvim_cmd(command, opts)
  end
  snippets.setup({ repo_dir = repo, friendly_dir = false })
  vim.bo.filetype = "markdown"
  vim.cmd("runtime plugin/envi-snippets.lua")
  vim.cmd("Snippets edit")
  assert(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(repo .. "/markdown.json"))
  assert(vim.api.nvim_get_current_line() == pack)
  local doc = repo .. "/doc"
  vim.fn.mkdir(doc, "p")
  source({ "*literal-envi-help*  Help" }, doc .. "/literal.txt")
  local cwd = vim.uv.cwd()
  require("envi.snippets.helptags")(doc)
  assert(vim.uv.cwd() == cwd, "help must preserve the working directory")
  assert(vim.fn.readfile(doc .. "/tags")[1]:find("literal-envi-help", 1, true))
end
print("PASS literal repo paths, help and unavailable directory warnings")
