-- This is the private API contract exercised against the pinned Blink commit.
local M = { pinned_revision = "78336bc89ee5365633bcf754d93df01678b5c08f" }
local converter, cached_constructor
local warned = false
local record_failure

local function constructor()
  return require("blink.cmp.sources.snippets.default.registry").new
end

local function new_registry(new)
  local instance = new({ friendly_snippets = false, search_paths = {} })
  assert(type(instance.expand_vars) == "function", "missing expand_vars")
  assert(type(instance.snippet_to_completion_item) == "function", "missing snippet_to_completion_item")
  return instance
end

local function registry()
  local new = constructor()
  if not converter or new ~= cached_constructor then
    converter, cached_constructor = new_registry(new), new
  end
  return converter
end

local function failure(err)
  return "envi snippets: Blink private API (pin " .. M.pinned_revision .. ") failed: " .. tostring(err)
end

local function warn(err)
  if not warned then
    warned = true
    vim.schedule(function()
      vim.notify(failure(err), vim.log.levels.WARN)
    end)
  end
end

local function convert(instance, record, context)
  local item = instance:snippet_to_completion_item(record, context)
  assert(
    type(item) == "table" and type(item.label) == "string" and type(item.insertText) == "string",
    "invalid completion item"
  )
  return item
end

local function expand_vars(instance, body)
  local expanded = instance:expand_vars(body, vim.uv.hrtime())
  assert(type(expanded) == "string", "invalid expanded snippet body")
  return expanded
end

local function resolve_item(item)
  local result
  require("blink.cmp.sources.snippets.default"):resolve(item, function(value)
    result = value
  end)
  assert(type(result) == "table", "invalid resolved completion item")
  return result
end

function M.resolve_body(body)
  local ok, result = pcall(function()
    return expand_vars(registry(), body)
  end)
  if not ok then
    warn(result)
    return nil, failure(result)
  end
  return result
end

function M.probe()
  local ok, err = pcall(function()
    local instance = new_registry(constructor())
    local body = "health ${1:sample}$0"
    assert(expand_vars(instance, body) == body, "sample snippet body was altered")
    local item = convert(instance, { prefix = "envi-health", body = body }, {
      bufnr = vim.api.nvim_get_current_buf(),
      id = vim.uv.hrtime(),
      cursor = { 1, 0 },
      bounds = { start_col = 1 },
      get_line = function()
        return ""
      end,
    })
    assert(item.label == "envi-health" and item.insertText == body, "sample completion was altered")
    local resolved = resolve_item(item)
    assert(resolved.label == item.label and resolved.insertText == body, "sample resolution was altered")
  end)
  if ok and record_failure then
    return false, failure(record_failure)
  end
  return ok, not ok and failure(err) or nil
end

function M.new()
  return setmetatable({}, { __index = M })
end

function M:get_completions(context, callback)
  local ok, result = pcall(function()
    local snippets = require("envi.snippets")
    local instance = registry()
    local items = {}
    local pass_failure
    for _, record in ipairs(snippets.list(nil, context.bufnr)) do
      local converted, item = pcall(convert, instance, record, context)
      if converted then
        items[#items + 1] = item
      else
        pass_failure = pass_failure or ("snippet " .. record.prefix .. ": " .. tostring(item))
        warn(pass_failure)
      end
    end
    record_failure = pass_failure
    return items
  end)
  if not ok then
    warn(result)
  end
  callback({ items = ok and result or {}, is_incomplete_forward = false, is_incomplete_backward = false })
end

function M:resolve(item, callback)
  local ok, resolved = pcall(resolve_item, item)
  if not ok then
    warn(resolved)
  end
  callback(ok and resolved or item)
end

return M
