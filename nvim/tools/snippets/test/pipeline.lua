local config = vim.fn.getcwd() .. "/nvim"
vim.opt.rtp:prepend(config)
vim.opt.rtp:prepend(config .. "/plugins/emmet-md")
local snippets = require("envi.snippets")

local function equal(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end

local function contains(diagnostics, severity, term)
  return vim.iter(diagnostics):any(function(item)
    return item.severity == severity
      and (item.message:find(term, 1, true) or (item.path or ""):find(term, 1, true)) ~= nil
  end)
end

local function write(path, value)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ vim.json.encode(value) }, path)
end

local root = vim.fn.stdpath("state") .. "/test"
vim.fn.mkdir(root, "p")
root = assert(vim.uv.fs_realpath(root))
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
  contributes = {
    snippets = {
      { language = { "markdown", "all" }, path = "./pack.json" },
      { language = "markdown", path = "./variants.json" },
    },
  },
})
write(friendly .. "/pack.json", {
  Upstream = spec("same", "friendly"),
  Other = spec("upstream", "upstream"),
  Provider = spec("provided", "from friendly"),
})
write(friendly .. "/variants.json", {
  Variant = spec("upstream", "variant"),
  Alias = spec("upstream", "upstream"),
  Shadowed = spec("same", "another upstream body"),
})
vim.api.nvim_buf_set_name(0, project .. "/notes.md")
vim.bo.filetype = "markdown"
snippets.setup({ repo_dir = repo, friendly_dir = friendly })
equal("repo $1$0", snippets.get("same").body)
equal("one\ntwo", snippets.get("also").body)
equal("shared", snippets.get("global", "lua").body)
equal(nil, snippets.get("yes", "lua"))
local function with_prefix(prefix, ft)
  return vim.tbl_filter(function(entry)
    return entry.prefix == prefix
  end, snippets.list(ft))
end
equal(2, #with_prefix("upstream", "markdown"))
equal(1, #with_prefix("same", "markdown"))
equal(nil, snippets.get("upstream", "markdown"))
equal("variant", snippets.get("Variant", "markdown").body)
assert(vim.iter(snippets.validate()):any(function(item)
  return item.kind == "upstream_alias" and item.message == "markdown: identical upstream alias provided"
end))
equal(1, #with_prefix("provided", "markdown"))
assert(vim.iter(snippets.validate()):any(function(item)
  return item.severity == "warning" and item.kind == "owned_shadowing" and item.message:find("prefix same", 1, true)
end))

snippets.setup({ repo_dir = repo, friendly_dir = friendly, trusted_projects = { project } })
equal("project $1$0", snippets.get("same").body)
vim.cmd.enew({ bang = true })
vim.fn.mkdir(project .. "-neighbor", "p")
vim.api.nvim_buf_set_name(0, project .. "-neighbor/notes.md")
vim.bo.filetype = "markdown"
equal("repo $1$0", snippets.get("same").body)
vim.cmd.enew({ bang = true })
vim.api.nvim_buf_set_name(0, project .. "/other.md")
vim.bo.filetype = "markdown"

local escaping_pack = project .. "/.envi/snippets/lua.json"
assert(vim.uv.fs_symlink(friendly .. "/pack.json", escaping_pack))
snippets.reload()
equal("friendly", snippets.get("upstream", "lua").source)
assert(contains(snippets.validate(), "error", "file escapes its snippet directory"))

local function open_buffer(path)
  vim.cmd.enew({ bang = true })
  vim.api.nvim_buf_set_name(0, path)
  vim.bo.filetype = "markdown"
end

local outside, nested = root .. "/outside", project .. "/nested"
write(outside .. "/notes.md", {})
assert(vim.uv.fs_symlink(outside .. "/notes.md", project .. "/linked.md"))
open_buffer(project .. "/linked.md")
equal("repo $1$0", snippets.get("same").body)

write(nested .. "/.envi/snippets/markdown.json", { Nested = spec("same", "nested") })
snippets.setup({ repo_dir = repo, friendly_dir = friendly, trusted_projects = { project, nested } })
open_buffer(nested .. "/notes.md")
equal("nested", snippets.get("same").body)

local project_alias = root .. "/project-alias"
assert(vim.uv.fs_symlink(project, project_alias))
snippets.setup({ repo_dir = repo, friendly_dir = friendly, trusted_projects = { project_alias } })
open_buffer(project .. "/alias.md")
equal("project $1$0", snippets.get("same").body)
write(project_pack, { Project = spec("same", "updated project") })
vim.api.nvim_exec_autocmds("BufWritePost", { pattern = project_pack })
equal("updated project", snippets.get("same").body)

local original_notify, warnings = vim.notify, {}
vim.notify = function(message, level)
  if level == vim.log.levels.WARN then
    warnings[#warnings + 1] = message
  end
end
local missing = root .. "/missing-project"
snippets.setup({ repo_dir = repo, friendly_dir = friendly, trusted_projects = { project, missing } })
local setup_ok, setup_error = pcall(snippets.setup, { trusted_projects = project })
vim.notify = original_notify
equal(1, #warnings)
assert(warnings[1]:find(missing, 1, true))
assert(not setup_ok and setup_error:find("trusted_projects must be a list", 1, true))
equal("updated project", snippets.get("same").body)

local escape_root = root .. "/escape-root"
vim.fn.mkdir(escape_root .. "/.envi", "p")
assert(vim.uv.fs_symlink(project .. "/.envi/snippets", escape_root .. "/.envi/snippets"))
snippets.setup({ repo_dir = repo, friendly_dir = friendly, trusted_projects = { escape_root } })
open_buffer(escape_root .. "/notes.md")
equal("repo $1$0", snippets.get("same").body)
assert(contains(snippets.validate(), "error", "snippet directory escapes"))
snippets.setup({ repo_dir = repo, friendly_dir = friendly })

assert(snippets.register("Registered", { prefix = "from-lua", body = "$1$0", filetypes = { "markdown" } }))
assert(not snippets.register("Registered", { prefix = "overwritten", body = "text", filetypes = { "markdown" } }))
assert(not snippets.register("Invalid", { prefix = "bad-ft", body = "text", filetypes = { "bad ft" } }))
assert(not snippets.register_provider("empty", {}))
assert(snippets.register_provider("static", {
  list = function(context)
    if context.filetype == "markdown" then
      return { { name = "Provided", prefix = "provided", body = "data" } }
    end
    return {}
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
assert(not vim.iter(snippets.list("markdown")):any(function(item)
  return item.prefix == "ul>li*2"
end))
assert(snippets.register_provider("broken", {
  generate = function()
    error("provider error")
  end,
}))
equal("emmet-md", snippets.get("ul>li*2").source)
assert(snippets.register_provider("overlapping", {
  generate = function(name)
    if name == "dynamic-example" then
      return { prefix = name, body = "conflict" }
    end
  end,
}))
local ambiguous, ambiguity = snippets.get("dynamic-example")
assert(not ambiguous and ambiguity:find("multiple providers", 1, true))
equal(nil, snippets.get("ul>li*2", "lua"))
local escaped = assert(snippets.get([[p{Cost \$5}]]))
equal([[Cost \$5${0}]], escaped.body)
assert(snippets.expand("ul>li*2"))
equal({ "- ", "- " }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
assert(vim.snippet.active({ direction = 1 }))
vim.snippet.jump(1)
equal(2, vim.api.nvim_win_get_cursor(0)[1])
vim.bo.modifiable = false
local changed, err = snippets.expand({ body = "new $1" })
vim.bo.modifiable = true
equal(nil, changed)
equal("buffer is not modifiable", err)
assert(vim.snippet.active({ direction = 1 }))
vim.snippet.stop()

write(repo .. "/markdown.json", { Fresh = spec("fresh", "after reload") })
assert(not snippets.get("fresh"))
vim.api.nvim_exec_autocmds("BufWritePost", { pattern = repo .. "/markdown.json" })
equal("after reload", snippets.get("fresh").body)
write(repo .. "/markdown.json", { New = spec("new", "after explicit reload") })
snippets.reload()
equal("after explicit reload", snippets.get("new").body)

write(repo .. "/invalid ft.json", { Bad = spec("invalid", "text") })
write(repo .. "/markdwon.json", { Typo = spec("typo", "text") })
write(repo .. "/lua.json", { spec("not-object", "ignored") })
write(repo .. "/markdown.json", {
  BadShape = { prefix = false, body = "text" },
  BadSyntax = spec("syntax", "${1:missing"),
  BadStops = spec("stops", "${1:A} ${1:B} $0"),
  DoubleFinal = spec("double-final", "$0 $0"),
  DuplicateAliases = spec({ "duplicate", "duplicate" }, "bad"),
  Blank = spec(" ", "bad"),
  Multiline = spec("line\nbreak", "bad"),
  Twice = spec("ambiguous", "one"),
  Again = spec("ambiguous", "two"),
})
snippets.reload()
local diagnostics = snippets.validate()
for _, term in ipairs({
  "invalid ft",
  "markdwon",
  "expected a JSON object",
  "BadShape",
  "BadSyntax",
  "BadStops",
  "DoubleFinal",
  "DuplicateAliases",
  "Blank",
  "Multiline",
  "ambiguous",
}) do
  assert(contains(diagnostics, "error", term), term .. " missing from diagnostics")
end
equal(nil, snippets.get("ambiguous"))

vim.cmd("runtime plugin/envi-snippets.lua")
assert(vim.fn.exists(":Snippets") == 2)
local tool_repo = root .. "/tool-repo"
snippets.setup({ repo_dir = tool_repo, friendly_dir = false })
local before_command = vim.api.nvim_get_current_buf()
vim.cmd("Snippets new two words")
equal(before_command, vim.api.nvim_get_current_buf())
vim.cmd("Snippets new drafted")
equal(tool_repo .. "/markdown.json", vim.api.nvim_buf_get_name(0))
local scaffold = vim.json.decode(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
equal("drafted", scaffold.drafted.prefix)
vim.cmd.write()
equal("${1:Text}\n$0", snippets.get("drafted", "markdown").body)
scaffold.drafted.body = "authored body"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { vim.json.encode(scaffold) })
vim.cmd.write()
vim.cmd.enew({ bang = true })
vim.bo.filetype = "markdown"
vim.cmd("Snippets new drafted")
equal("authored body", vim.json.decode(vim.api.nvim_get_current_line()).drafted.body)
vim.cmd.enew({ bang = true })
vim.bo.filetype = "markdown"
vim.cmd("Snippets edit")
equal(tool_repo .. "/markdown.json", vim.api.nvim_buf_get_name(0))
vim.cmd("Snippets validate")
equal({}, vim.fn.getqflist())
vim.cmd("Snippets reload")
vim.cmd.enew({ bang = true })

snippets.setup({ repo_dir = config .. "/snippets", friendly_dir = false })
for _, diagnostic in ipairs(snippets.validate()) do
  assert(diagnostic.severity ~= "error", (diagnostic.path or "snippet catalogue") .. ": " .. diagnostic.message)
end
local grammar = vim.lsp._snippet_grammar
local inspected = {}
for filename in vim.fs.dir(config .. "/snippets") do
  local filetype = filename:match("^(.*)%.json$")
  if filetype then
    vim.bo.filetype = filetype
    for _, entry in ipairs(snippets.list(filetype)) do
      if vim.startswith(entry.path, config .. "/snippets/") and not inspected[entry.path .. ":" .. entry.name] then
        inspected[entry.path .. ":" .. entry.name] = true
        local expected = {}
        for _, node in ipairs(grammar.parse(entry.body).data.children) do
          if node.data.tabstop and node.data.tabstop > 0 then
            expected[node.data.tabstop] = true
          end
        end
        vim.snippet.stop()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        assert(snippets.expand(entry.prefix, filetype))
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
        equal(expected, visited)
        equal(0, vim.snippet._session.current_tabstop.index)
      end
    end
  end
end
assert(vim.tbl_count(inspected) >= 2)
print("PASS envi snippets sources, trust, precedence, providers, tooling, reload, and shipped stops")
