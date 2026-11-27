if not vim.env.ENVI_REGULAR_PACKS_CHILD then
  local result = vim
    .system({
      vim.v.progpath,
      "--headless",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "-l",
      "nvim/tools/snippets/test/regular-packs.lua",
    }, { env = { ENVI_REGULAR_PACKS_CHILD = "1" }, text = true })
    :wait(4000)
  assert(result.code == 0, result.code == 124 and "regular-pack check exceeded its timeout" or result.stderr)
  print("PASS non-regular packs are diagnosed before reading (real FIFO and socket)")
  return
end

vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
local fifo = repo .. "/markdown.json"
local socket = repo .. "/lua.json"
assert(vim.system({ "mkfifo", fifo }):wait(1000).code == 0)
local server = vim.uv.new_pipe(false)
assert(server:bind(socket))
assert(vim.uv.fs_stat(fifo).type == "fifo" and vim.uv.fs_stat(socket).type == "socket")
local original = vim.fn.readfile
local opened = {}
vim.fn.readfile = function(path, ...)
  local name = vim.fs.basename(path)
  if name == "markdown.json" or name == "lua.json" then
    opened[#opened + 1] = name
    error("attempted to open a special file")
  end
  return original(path, ...)
end
local snippets = require("envi.snippets")
snippets.setup({ repo_dir = repo, friendly_dir = false })
local diagnostics = snippets.validate()
server:close()
assert(#opened == 0, vim.inspect(opened))
for _, file in ipairs({ "markdown.json", "lua.json" }) do
  assert(
    vim.iter(diagnostics):any(function(item)
      return item.severity == "error"
        and vim.fs.basename(item.path) == file
        and item.message:find("regular file", 1, true)
    end),
    file
  )
end
