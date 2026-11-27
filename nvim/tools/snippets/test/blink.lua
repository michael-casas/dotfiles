local config = vim.fn.getcwd() .. "/nvim"
vim.opt.rtp:prepend(config)
local snippets = require("envi.snippets")
local registry_name = "blink.cmp.sources.snippets.default.registry"
local source_name = "blink.cmp.sources.snippets.default"
package.loaded["blink.cmp"] = {}
package.loaded[source_name] = {
  resolve = function(_, item, callback)
    callback(item)
  end,
}
vim.bo.filetype = "markdown"
assert(snippets.register("Sample", { prefix = "sample", body = "text $1", filetypes = { "markdown" } }))
snippets.setup({ repo_dir = vim.fn.tempname(), friendly_dir = false })

local diagnostics, warnings = {}, 0
vim.health.start = function() end
vim.health.info = function() end
vim.health.ok = function() end
vim.health.error = function(message)
  diagnostics[#diagnostics + 1] = message
end
vim.notify = function()
  warnings = warnings + 1
end

local function module()
  local instance = {
    expand_vars = function(_, body)
      return body
    end,
  }
  instance.snippet_to_completion_item = function(self, entry)
    return { label = entry.prefix, insertText = self:expand_vars(entry.body) }
  end
  return {
    new = function()
      return instance
    end,
    snippet_to_completion_item = instance.snippet_to_completion_item,
  },
    instance
end

local context = {
  bufnr = 0,
  id = 1,
  cursor = { 1, 0 },
  bounds = { start_col = 1 },
  get_line = function()
    return ""
  end,
}
local function run(label, breakage)
  local registry, instance = module()
  package.loaded[registry_name] = registry
  package.preload[registry_name] = nil
  package.loaded["envi.snippets.blink"] = nil
  diagnostics, warnings = {}, 0
  if breakage then
    breakage(registry, instance)
  end
  local source = require("envi.snippets.blink").new()
  for _ = 1, 2 do
    local result
    source:get_completions(context, function(response)
      result = response.items
    end)
    assert(result and #result == (breakage and 0 or 1), label)
    if not breakage then
      assert(result[1].label == "sample" and result[1].insertText == "text $1", label)
    end
  end
  require("envi.snippets.health").check()
  if breakage then
    assert(#diagnostics > 0 and diagnostics[1]:find("78336bc", 1, true), label .. " health diagnostic")
    assert(vim.wait(100, function()
      return warnings > 0
    end) and warnings == 1, label .. " should warn once")
    assert(pcall(snippets.expand, "sample"), label .. " explicit expand must not throw")
  else
    assert(#diagnostics == 0)
  end
end

run("pinned converter")
run("missing registry", function()
  package.loaded[registry_name] = nil
  package.preload[registry_name] = function()
    error("missing registry")
  end
end)
run("renamed converter", function(registry, instance)
  registry.snippet_to_completion_item = nil
  instance.snippet_to_completion_item = nil
end)
run("changed converter signature", function(registry, instance)
  instance.snippet_to_completion_item = function(_, _, _, extra)
    return extra.required
  end
  registry.snippet_to_completion_item = instance.snippet_to_completion_item
end)
run("missing expand_vars", function(_, instance)
  instance.expand_vars = nil
end)
run("changed constructor signature", function(registry)
  registry.new = function()
    error("incompatible constructor")
  end
end)

local registry = module()
package.loaded[registry_name] = registry
package.loaded["envi.snippets.blink"] = nil
local source = require("envi.snippets.blink").new()
package.loaded[source_name].resolve = function()
  error("incompatible resolver")
end
local original = { label = "sample", insertText = "text $1" }
local resolved
source:resolve(original, function(item)
  resolved = item
end)
assert(resolved == original)
diagnostics = {}
require("envi.snippets.health").check()
assert(#diagnostics == 1 and diagnostics[1]:find("incompatible resolver", 1, true))

package.loaded[source_name].resolve = function(_, item, callback)
  callback(item)
end
assert(snippets.register("Conflict", { prefix = "sample", body = "different", filetypes = { "markdown" } }))
diagnostics = {}
require("envi.snippets.health").check()
assert(#diagnostics > 0 and diagnostics[1]:find("snippet errors", 1, true))
print("PASS Blink adapter, five private API failures, resolver fallback and health")
