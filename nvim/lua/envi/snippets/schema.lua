local grammar = vim.lsp._snippet_grammar
local M = {}

function M.filetype(name)
  return type(name) == "string" and name:match("^[%w_][%w_.-]*$") ~= nil
end

function M.body(body)
  if vim.islist(body) then
    for _, line in ipairs(body) do
      if type(line) ~= "string" then
        return nil, "body lines must be strings"
      end
    end
    body = table.concat(body, "\n")
  end
  if type(body) ~= "string" or body == "" then
    return nil, "body must be a nonempty string or list of lines"
  end

  local ok, tree = pcall(grammar.parse, body)
  if not ok then
    return nil, "invalid native LSP snippet body"
  end
  local defaults, final_stops = {}, 0
  for _, node in ipairs(tree.data.children) do
    local data = node.data
    if data.tabstop == 0 then
      final_stops = final_stops + 1
    end
    if node.type == grammar.NodeType.Placeholder then
      local value = tostring(data.value)
      if defaults[data.tabstop] and defaults[data.tabstop] ~= value then
        return nil, "conflicting defaults for stop " .. data.tabstop
      end
      defaults[data.tabstop] = value
    end
  end
  if final_stops > 1 then
    return nil, "multiple final $0 stops"
  end
  return body
end

function M.records(name, spec, scope, source, path)
  if type(name) ~= "string" or name == "" or type(spec) ~= "table" or vim.islist(spec) then
    return nil, "expected a named snippet object"
  end
  local prefixes = type(spec.prefix) == "string" and { spec.prefix } or spec.prefix
  if not vim.islist(prefixes) or #prefixes == 0 then
    return nil, "prefix must be a string or nonempty list of strings"
  end
  local filetypes = scope or spec.filetypes
  if not vim.islist(filetypes) or #filetypes == 0 then
    return nil, "filetypes must be a nonempty list"
  end
  for _, ft in ipairs(filetypes) do
    if not M.filetype(ft) then
      return nil, "invalid filetype " .. tostring(ft)
    end
  end
  local body, err = M.body(spec.body)
  if not body then
    return nil, err
  end
  local description = spec.description
  if source == "friendly" and vim.islist(description) then
    for _, line in ipairs(description) do
      if type(line) ~= "string" then
        return nil, "description lines must be strings"
      end
    end
    description = table.concat(description, " ")
  end
  if description ~= nil and type(description) ~= "string" then
    return nil, "description must be a string"
  end

  local entries, seen = {}, {}
  for _, prefix in ipairs(prefixes) do
    if type(prefix) ~= "string" or not prefix:match("%S") or prefix:find("[\r\n]") then
      return nil, "prefixes must be nonempty strings on one line"
    end
    if seen[prefix] then
      return nil, "duplicate prefix " .. prefix
    end
    seen[prefix] = true
    entries[#entries + 1] = {
      name = name,
      prefix = prefix,
      body = body,
      description = description,
      filetypes = vim.deepcopy(filetypes),
      source = source,
      path = path,
    }
  end
  return entries
end

return M
