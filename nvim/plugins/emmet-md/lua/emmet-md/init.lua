local M = {}

local defaults = {
  max_length = 512,
  max_repeat = 50,
  max_nodes = 512,
  max_table_dimension = 20,
  filetypes = { "markdown" },
  notify_level = vim.log.levels.WARN,
}
local config = vim.deepcopy(defaults)
local parser = require("emmet-md.parser")
local render = require("emmet-md.renderer")

local function options(base, overrides)
  local opts = vim.tbl_extend("force", base, overrides or {})
  for _, name in ipairs({ "max_length", "max_repeat", "max_nodes", "max_table_dimension" }) do
    local value = opts[name]
    assert(
      type(value) == "number" and value >= 1 and value < math.huge and value % 1 == 0,
      name .. " must be a positive integer"
    )
  end
  assert(vim.islist(opts.filetypes), "filetypes must be a list")
  for _, filetype in ipairs(opts.filetypes) do
    assert(type(filetype) == "string" and filetype ~= "", "filetypes must contain nonempty strings")
  end
  assert(type(opts.notify_level) == "number", "notify_level must be a vim.log.levels value")
  return opts
end

function M.setup(opts)
  config = options(defaults, vim.deepcopy(opts))
end

local function parse(abbreviation, opts)
  if type(abbreviation) ~= "string" or #abbreviation > opts.max_length or abbreviation:find("[\r\n]") then
    return nil, "Expected an abbreviation on one line within the length limit"
  end
  local tree = parser(abbreviation, opts.max_repeat)
  if not tree then
    return nil, "Invalid abbreviation syntax"
  end
  return tree
end

function M.parse(abbreviation)
  return parse(abbreviation, config)
end

local function compile(abbreviation, opts)
  local tree, err = parse(abbreviation, opts)
  if not tree then
    return nil, err
  end
  local body = render(tree, opts.max_nodes, opts.max_table_dimension)
  if not body then
    return nil, "Unsupported Markdown structure or expansion limit exceeded"
  end
  return body
end

function M.expand(abbreviation, opts)
  local body, err = compile(abbreviation, opts and options(config, opts) or config)
  if not body then
    return nil, err
  end

  -- The renderer emits only text and empty stops. Use Neovim's own decoder
  -- so the pure result and the inserted snippet agree on literal escapes.
  local grammar = vim.lsp._snippet_grammar
  local lines, stops = { "" }, {}
  for _, node in ipairs(grammar.parse(body).data.children) do
    if node.type == grammar.NodeType.Tabstop then
      stops[#stops + 1] = { index = node.data.tabstop, row = #lines, col = #lines[#lines] }
    else
      local pieces = vim.split(node.data.text, "\n", { plain = true })
      lines[#lines] = lines[#lines] .. pieces[1]
      vim.list_extend(lines, pieces, 2)
    end
  end
  return lines, stops
end

local function configured_body(abbreviation)
  return compile(abbreviation, config)
end

function M.expand_at_cursor()
  require("emmet-md.editor").at_cursor(configured_body, config)
end

function M._command(abbreviation)
  require("emmet-md.editor").command(configured_body, config, abbreviation)
end

return M
