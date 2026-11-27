vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local root = vim.fn.stdpath("state") .. "/pack-paths"
local project = root .. "/trusted"
local directory = project .. "/.envi/snippets"
local sentinel = root .. "/expansion-attempt"
vim.fn.mkdir(directory, "p")

local write = vim.fn.writefile
local bracketed = string.char(96) .. "literal-name" .. string.char(96)
local hostile = { bracketed .. ".json", "{.json", "$(literal-name).json", "*.json", "..json" }
for _, file in ipairs(hostile) do
  write({ "the loader must not read this" }, directory .. "/" .. file)
end
write({ '{"Owned":{"prefix":"owned","body":"body"}}' }, directory .. "/markdown.json")
write({ '{"Custom":{"prefix":"custom","body":"body"}}' }, directory .. "/localtype.json")
for _, ft in ipairs({ "mdx", "norg", "templ", "typescript.tsx", "project.notes" }) do
  write({ '{"Example":{"prefix":"example","body":"body"}}' }, directory .. "/" .. ft .. ".json")
end
write({ "{}" }, root .. "/outside-pack.json")
assert(vim.uv.fs_symlink(root .. "/outside-pack.json", directory .. "/markdwon.json"))

-- Stop at Vim's expansion boundary. The sentinel records attempts without
-- allowing any filename or root to reach the real expanding function.
local glob = vim.fn.glob
vim.fn.glob = function(value, ...)
  if value:find("`", 1, true) or value:find("*", 1, true) or value:find("$", 1, true) then
    write({ "unsafe glob argument" }, sentinel)
    error("unsafe glob argument")
  end
  return glob(value, ...)
end
local getcompletion = vim.fn.getcompletion
vim.fn.getcompletion = function(value, kind, ...)
  if (kind == "filetype" or kind == "file") and value ~= "" then
    write({ "unsafe completion argument" }, sentinel)
    error("unsafe completion argument")
  end
  return getcompletion(value, kind, ...)
end
local expand = vim.fn.expand
vim.fn.expand = function(value, ...)
  if value:find(bracketed, 1, true) or value == root .. "/trust*" then
    write({ "unsafe root expansion" }, sentinel)
    error("unsafe root expansion")
  end
  return expand(value, ...)
end
local readfile = vim.fn.readfile
vim.fn.readfile = function(path, ...)
  for _, name in ipairs(hostile) do
    if path == directory .. "/" .. name then
      error("invalid pack was read")
    end
  end
  return readfile(path, ...)
end
local match = vim.filetype.match
vim.filetype.match = function(args)
  if args.filename and args.filename:find("[^%w_.-]") then
    write({ "unsafe filetype detection argument" }, sentinel)
    error("unsafe filetype detection argument")
  end
  return match(args)
end

local snippets = require("envi.snippets")
vim.filetype.add({ extension = { localtype = "localtype" } })
local errors = {}
for _, operation in ipairs({
  snippets.list,
  function()
    return snippets.get("owned")
  end,
  snippets.validate,
}) do
  snippets.setup({ repo_dir = root .. "/repo", friendly_dir = false, trusted_projects = { project } })
  vim.api.nvim_buf_set_name(0, project .. "/notes.md")
  vim.bo.filetype = "markdown"
  local ok, value = pcall(operation)
  if not ok then
    errors[#errors + 1] = value
  end
end
assert(not vim.uv.fs_stat(sentinel), "a pack name reached the unsafe completion API")
assert(#errors == 0, vim.inspect(errors))

local warnings = {}
vim.notify = function(message, level)
  assert(level == vim.log.levels.WARN)
  warnings[#warnings + 1] = message
end
local setup_ok = pcall(snippets.setup, {
  repo_dir = root .. "/repo",
  friendly_dir = false,
  trusted_projects = { project, bracketed, root .. "/trust*", root .. "/outside-pack.json" },
  filetypes = { "project.notes" },
})
assert(not vim.uv.fs_stat(sentinel), "a trust root reached the unsafe expansion API")
assert(setup_ok and #warnings == 3, "literal missing paths and nondirectories must be skipped")
local valid, setup_error = pcall(snippets.setup, { repo_dir = true })
assert(not valid and setup_error:find("repo_dir must be a directory path", 1, true))
assert(snippets.get("owned").body == "body")
assert(snippets.get("custom", "localtype"))
for _, ft in ipairs({ "mdx", "norg", "templ", "typescript.tsx", "project.notes" }) do
  assert(snippets.get("example", ft), ft)
end

local diagnostics = snippets.validate()
for _, name in ipairs(hostile) do
  assert(
    vim.iter(diagnostics):any(function(item)
      return item.severity == "error"
        and vim.fs.basename(item.path or "") == name
        and item.message:find("invalid pack name", 1, true)
    end),
    name
  )
end
assert(
  vim.iter(diagnostics):any(function(item)
    return vim.fs.basename(item.path or "") == "markdwon.json"
      and item.message:find("file escapes its snippet directory", 1, true)
  end),
  "check the symlink boundary before checking the filetype"
)
print("PASS pack names and trusted roots just use literal paths")
