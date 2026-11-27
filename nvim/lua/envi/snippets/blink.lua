-- Use the pinned Blink converter for prefix ranges and its built-in variables.
local M = {}
local converter
local function registry()
  if not converter then
    converter = require("blink.cmp.sources.snippets.default.registry").new({
      friendly_snippets = false,
      search_paths = {},
    })
  end
  return converter
end

function M.resolve_body(body)
  local ok, instance = pcall(registry)
  if ok then
    return instance:expand_vars(body, vim.uv.hrtime())
  end
  return body
end

function M.new()
  return setmetatable({}, { __index = M })
end

function M:get_completions(context, callback)
  local snippets = require("envi.snippets")
  local items = {}
  for _, record in ipairs(snippets.list(nil, context.bufnr)) do
    items[#items + 1] = registry():snippet_to_completion_item(record, context)
  end
  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

function M:resolve(item, callback)
  require("blink.cmp.sources.snippets.default"):resolve(item, callback)
end

return M
