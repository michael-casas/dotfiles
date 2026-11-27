vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local snippets = require("envi.snippets")
local root = vim.fn.stdpath("state") .. "/upstream"
for _, dir in ipairs({ "repo", "friendly" }) do
  vim.fn.mkdir(root .. "/" .. dir, "p")
end
local function write(path, value)
  vim.fn.writefile({ vim.json.encode(value) }, root .. "/" .. path)
end
local repairable = "try ${1:raise $2} then $0"
local repaired = "try ${1:condition} then $0"
local conflicting = "${1:first} ${1:second}$0"
package.loaded["lazyvim.util.cmp"] = {
  snippet_fix = function(body)
    if body == "${1:missing" then
      return "${2:still missing"
    end
    if body == conflicting then
      return "${1:first} ${1:first}$0"
    end
    return body == repairable and repaired or body
  end,
}
write("friendly/package.json", { contributes = { snippets = { { language = "lua", path = "./lua.json" } } } })
write("friendly/lua.json", {
  Recipe = { prefix = "recipe", body = repairable },
  ["Recipe duplicate"] = { prefix = "recipe", body = repairable },
  Broken = { prefix = "broken", body = "${1:missing" },
  Conflicting = { prefix = "conflicting", body = conflicting },
  Shadowed = { prefix = "owned", body = "friendly" },
})
write("repo/lua.json", {
  Owned = { prefix = "owned", body = "repo" },
  Strict = { prefix = "strict", body = repairable },
})
snippets.setup({ repo_dir = root .. "/repo", friendly_dir = root .. "/friendly" })
vim.bo.filetype = "lua"
local entry = snippets.get("recipe")
assert(entry and entry.body == repairable, "serve the original upstream body")
assert(entry.description == "Recipe", "fall back to the snippet name")
assert(snippets.get("conflicting").body == conflicting)
assert(not snippets.get("broken") and not snippets.get("strict"))
assert(snippets.expand("recipe"))
assert(vim.api.nvim_get_current_line() == "try condition then ")
vim.snippet.stop()

local info, errors = {}, {}
vim.health.start = function() end
vim.health.info = function(message)
  info[#info + 1] = message
end
vim.health.error = function(message)
  errors[#errors + 1] = message
end
vim.health.ok = function() end
require("envi.snippets.health").check()
local report = table.concat(info, "\n")
assert(report:find("1 upstream invalid", 1, true), report)
assert(report:find("1 identical upstream aliases", 1, true), report)
assert(report:find("1 owned shadowing diagnostics", 1, true), report)
assert(vim.iter(errors):any(function(message)
  return message:find("1 snippet errors", 1, true)
end))
print("PASS upstream repair, strict owned bodies, fallback documentation and health totals")
