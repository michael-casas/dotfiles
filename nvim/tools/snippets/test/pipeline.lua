local config = vim.fn.getcwd() .. "/nvim"
vim.opt.rtp:prepend(config)
vim.opt.rtp:prepend(config .. "/plugins/emmet-md")
local snippets = require("envi.snippets")

local function equal(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end

local function contains(diagnostics, severity, term)
  return vim.iter(diagnostics):any(function(item)
    return item.severity == severity and item.message:find(term, 1, true) ~= nil
  end)
end

local function write(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ vim.json.encode(value) }, path)
end

local root = vim.fn.stdpath("state") .. "/test"
local repo, project, friendly = root .. "/repo", root .. "/project", root .. "/friendly"
local project_pack = project .. "/.envi/snippets/markdown.json"
local function spec(prefix, body)
  return { prefix = prefix, body = body }
end

write(repo .. "/markdown.json", {
  Local = spec("same", "repo $1$0"),
  Scoped = spec({ "yes", "also" }, { "one", "two" }),
})
write(repo .. "/all.json", { Shared = spec("global", "shared") })
write(project_pack, { Project = spec("same", "project $1$0") })
write(friendly .. "/package.json", {
  contributes = { snippets = { { language = { "markdown", "all" }, path = "./pack.json" } } },
})
write(friendly .. "/pack.json", {
  Upstream = spec("same", "friendly"),
  Other = spec("upstream", "upstream"),
})
vim.api.nvim_buf_set_name(0, project .. "/notes.md")
vim.bo.filetype = "markdown"
snippets.setup({ repo_dir = repo, friendly_dir = friendly })
equal("repo $1$0", snippets.get("same").body)
equal("one\ntwo", snippets.get("also").body)
equal("shared", snippets.get("global", "lua").body)
equal(nil, snippets.get("yes", "lua"))
equal("upstream", snippets.get("upstream").body)
assert(contains(snippets.validate(), "warning", "same"))

snippets.setup({ repo_dir = repo, friendly_dir = friendly, trusted_projects = { project } })
equal("project $1$0", snippets.get("same").body)
vim.cmd.enew({ bang = true })
vim.api.nvim_buf_set_name(0, project .. "-neighbor/notes.md")
vim.bo.filetype = "markdown"
equal("repo $1$0", snippets.get("same").body)
vim.cmd.enew({ bang = true })
vim.api.nvim_buf_set_name(0, project .. "/other.md")
vim.bo.filetype = "markdown"

local escaping_pack = project .. "/.envi/snippets/escape.json"
assert(vim.uv.fs_symlink(friendly .. "/pack.json", escaping_pack))
assert(not snippets.get("upstream", "escape"))
assert(contains(snippets.validate(), "error", "escape.json"))

assert(snippets.register("Registered", { prefix = "from-lua", body = "$1$0", filetypes = { "markdown" } }))
assert(snippets.register_provider("static", {
  list = function(context)
    equal("markdown", context.filetype)
    return { { name = "Provided", prefix = "provided", body = "data" } }
  end,
}))
equal("Registered", snippets.get("from-lua").name)
equal("data", snippets.get("provided").body)
assert(snippets.register_provider("dynamic", {
  generate = function(name)
    if name == "dynamic-example" then
      return { prefix = name, body = "generated $1$0" }
    end
  end,
}))
assert(not vim.iter(snippets.list("markdown")):any(function(item)
  return item.prefix == "dynamic-example"
end))
equal("generated $1$0", snippets.get("dynamic-example").body)
equal("emmet-md", snippets.get("ul>li*2").source)
assert(snippets.expand("ul>li*2"))
equal({ "- ", "- " }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
vim.snippet.stop()

write(repo .. "/markdown.json", { Fresh = spec("fresh", "after reload") })
assert(not snippets.get("fresh"))
vim.api.nvim_exec_autocmds("BufWritePost", { pattern = repo .. "/markdown.json" })
equal("after reload", snippets.get("fresh").body)
write(repo .. "/markdown.json", { New = spec("new", "after explicit reload") })
snippets.reload()
equal("after explicit reload", snippets.get("new").body)

write(repo .. "/invalid ft.json", { Bad = spec("invalid", "text") })
write(repo .. "/markdown.json", {
  BadShape = { prefix = false, body = "text" },
  BadSyntax = spec("syntax", "${1:missing"),
  BadStops = spec("stops", "${1:A} ${1:B} $0"),
  Twice = spec("ambiguous", "one"),
  Again = spec("ambiguous", "two"),
})
snippets.reload()
local diagnostics = snippets.validate()
for _, term in ipairs({ "invalid ft", "BadShape", "BadSyntax", "BadStops", "ambiguous" }) do
  assert(contains(diagnostics, "error", term), term .. " missing from diagnostics")
end
equal(nil, snippets.get("ambiguous"))

snippets.setup({ repo_dir = config .. "/snippets", friendly_dir = false })
vim.cmd("runtime plugin/envi-snippets.lua")
assert(vim.fn.exists(":Snippets") == 2)
local shipped = snippets.list("markdown")
equal(2, #shipped)
for _, entry in ipairs(shipped) do
  vim.snippet.stop()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  assert(snippets.expand(entry.prefix, "markdown"))
  local visited = {}
  while vim.snippet.active({ direction = 1 }) do
    local index = vim.snippet._session.current_tabstop.index
    if index == 0 then
      break
    end
    assert(not visited[index], "tab stops must progress")
    visited[index] = true
    vim.snippet.jump(1)
  end
  equal({ [1] = true, [2] = true }, visited)
  equal(0, vim.snippet._session.current_tabstop.index)
end
assert(not vim.iter(snippets.validate()):any(function(item)
  return item.severity == "error"
end))
print("PASS envi snippets sources, trust, precedence, providers, reload, and shipped stops")
