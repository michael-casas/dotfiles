local schema = require("envi.snippets.schema")
local sources = require("envi.snippets.sources")
local M = {}
local opts, shared, projects, cache
local registered = {}
local providers = { ["emmet-md"] = require("envi.snippets.emmet") }
local priority = { friendly = 1, provider = 2, repo = 3, project = 4 }

function M.reload()
  shared, projects, cache = nil, {}, {}
end

function M.setup(options)
  opts = vim.tbl_extend(
    "force",
    { repo_dir = vim.fn.stdpath("config") .. "/snippets", trusted_projects = {} },
    options or {}
  )
  local trusted = {}
  for _, path in ipairs(opts.trusted_projects) do
    local root = vim.uv.fs_realpath(vim.fn.expand(path))
    assert(root and vim.uv.fs_stat(root).type == "directory", "trusted snippet root must be an existing directory")
    trusted[#trusted + 1] = root
  end
  table.sort(trusted, function(a, b)
    return #a > #b
  end)
  opts.trusted_projects = trusted
  M.reload()
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("EnviSnippets", { clear = true }),
    pattern = "*.json",
    callback = function(event)
      if sources.is_pack(event.file, opts) then
        M.reload()
      end
    end,
  })
end

local function report(diagnostics, severity, message, path)
  diagnostics[#diagnostics + 1] = { severity = severity, message = message, path = path }
end

local function recorder(diagnostics, severity)
  return function(message, path)
    report(diagnostics, severity, message, path)
  end
end

local function read_shared()
  if not shared then
    local diagnostics = {}
    local records = sources.owned(opts.repo_dir, "repo", recorder(diagnostics, "error"))
    vim.list_extend(records, sources.friendly(opts.friendly_dir, recorder(diagnostics, "warning")))
    for _, list in pairs(registered) do
      vim.list_extend(records, list)
    end
    shared = { records = records, diagnostics = diagnostics }
  end
  return shared
end

local function project_pack(root)
  if not root then
    return { records = {}, diagnostics = {} }
  end
  if not projects[root] then
    local diagnostics = {}
    local records = sources.owned(root .. "/.envi/snippets", "project", recorder(diagnostics, "error"), root)
    projects[root] = { records = records, diagnostics = diagnostics }
  end
  return projects[root]
end

local function ordered_names(values)
  local names = vim.tbl_keys(values)
  table.sort(names)
  return names
end

local function provider_records(context, diagnostics)
  local entries = {}
  for _, name in ipairs(ordered_names(providers)) do
    local provider = providers[name]
    if provider.list then
      local ok, list = pcall(provider.list, context)
      if not ok or not vim.islist(list) then
        report(diagnostics, "error", "provider " .. name .. " did not return a snippet list")
      else
        for _, entry in ipairs(list) do
          local label = type(entry) == "table" and entry.name
          local records, err = schema.records(label, entry, { context.filetype }, "provider", name)
          if records then
            vim.list_extend(entries, records)
          else
            report(diagnostics, "error", name .. ": " .. err)
          end
        end
      end
    end
  end
  return entries
end

local function resolve(records, filetype, diagnostics)
  local groups = {}
  for _, entry in ipairs(records) do
    if vim.tbl_contains(entry.filetypes, filetype) or vim.tbl_contains(entry.filetypes, "all") then
      groups[entry.prefix] = groups[entry.prefix] or {}
      table.insert(groups[entry.prefix], entry)
    end
  end

  local result, blocked = {}, {}
  for _, prefix in ipairs(ordered_names(groups)) do
    local group = groups[prefix]
    table.sort(group, function(a, b)
      if a.source ~= b.source then
        return priority[a.source] > priority[b.source]
      end
      if a.path ~= b.path then
        return a.path < b.path
      end
      return a.name < b.name
    end)
    local winner, conflicts = group[1], {}
    local seen = {}
    for _, entry in ipairs(group) do
      local previous = seen[entry.source]
      if previous and (entry.source ~= "friendly" or entry.body ~= previous.body) then
        local severity = entry.source == "friendly" and "warning" or "error"
        report(diagnostics, severity, filetype .. ": duplicate prefix " .. prefix .. " in " .. entry.source, entry.path)
        conflicts[entry.source] = severity == "error"
      elseif not previous and entry.source ~= winner.source then
        report(
          diagnostics,
          "warning",
          filetype .. ": prefix " .. prefix .. " from " .. winner.source .. " shadows " .. entry.source,
          entry.path
        )
      end
      seen[entry.source] = previous or entry
    end
    if conflicts[winner.source] then
      blocked[prefix] = true
    else
      result[#result + 1] = winner
    end
  end
  return result, blocked
end

local function context(filetype, bufnr)
  return {
    filetype = filetype or vim.bo[bufnr or 0].filetype,
    project = sources.project(opts.trusted_projects, bufnr),
  }
end

local function for_context(ctx)
  local key = (ctx.project or "") .. "\0" .. ctx.filetype
  if not cache[key] then
    local common, project = read_shared(), project_pack(ctx.project)
    local diagnostics = {}
    local records = vim.list_extend(vim.list_extend({}, common.records), project.records)
    vim.list_extend(records, provider_records(ctx, diagnostics))
    local resolved, blocked = resolve(records, ctx.filetype, diagnostics)
    cache[key] = { records = resolved, blocked = blocked, diagnostics = diagnostics }
  end
  return cache[key]
end

function M.list(filetype, bufnr)
  return vim.deepcopy(for_context(context(filetype, bufnr)).records)
end

function M.validate()
  local ctx = context()
  local common, project = read_shared(), project_pack(ctx.project)
  local results = vim.list_extend(vim.list_extend({}, common.diagnostics), project.diagnostics)
  local filetypes = {}
  if schema.filetype(ctx.filetype) then
    filetypes[ctx.filetype] = true
  end
  for _, pack in ipairs({ common, project }) do
    for _, entry in ipairs(pack.records) do
      for _, ft in ipairs(entry.filetypes) do
        filetypes[ft] = true
      end
    end
  end
  for _, ft in ipairs(ordered_names(filetypes)) do
    vim.list_extend(results, for_context({ filetype = ft, project = ctx.project }).diagnostics)
  end
  return vim.deepcopy(results)
end

function M.register(name, spec)
  if type(name) == "string" and registered[name] then
    return nil, "snippet name is already registered"
  end
  local records, err = schema.records(name, spec, nil, "repo", "Lua:" .. tostring(name))
  if not records then
    return nil, err
  end
  registered[name] = records
  M.reload()
  return true
end

function M.register_provider(name, provider)
  if type(name) ~= "string" or name == "" or providers[name] or type(provider) ~= "table" then
    return nil, "expected a unique provider name and provider table"
  end
  if
    (provider.list ~= nil and type(provider.list) ~= "function")
    or (provider.generate ~= nil and type(provider.generate) ~= "function")
    or not (provider.list or provider.generate)
  then
    return nil, "a provider needs list or generate functions"
  end
  providers[name] = vim.deepcopy(provider)
  M.reload()
  return true
end

function M.get(name, filetype)
  if type(name) ~= "string" or name == "" then
    return nil, "expected a snippet name or prefix"
  end
  local ctx = context(filetype)
  local catalog = for_context(ctx)
  if catalog.blocked[name] then
    return nil, "snippet prefix is ambiguous"
  end
  for _, record in ipairs(catalog.records) do
    if record.prefix == name then
      return vim.deepcopy(record)
    end
  end
  local named
  for _, record in ipairs(catalog.records) do
    if record.name == name then
      if named and (named.path ~= record.path or named.body ~= record.body) then
        return nil, "snippet name is ambiguous; use a prefix"
      end
      named = record
    end
  end
  if named then
    return vim.deepcopy(named)
  end
  local generated
  for _, provider_name in ipairs(ordered_names(providers)) do
    local generate = providers[provider_name].generate
    if generate then
      local ok, result = pcall(generate, name, ctx)
      if not ok then
        return nil, "provider " .. provider_name .. " failed: " .. tostring(result)
      elseif result ~= nil then
        if generated then
          return nil, "multiple providers accepted " .. name
        end
        local entries, err = schema.records(name, result, { ctx.filetype }, provider_name, provider_name)
        if not entries then
          return nil, err
        end
        generated = entries[1]
      end
    end
  end
  if not generated then
    return nil, "unknown snippet " .. name
  end
  return generated
end

function M.expand(value, filetype)
  local body, err
  if type(value) == "table" then
    body, err = schema.body(value.body)
  else
    local entry
    entry, err = M.get(value, filetype)
    body = entry and entry.body
  end
  if not body then
    return nil, err
  end
  if not vim.bo.modifiable then
    return nil, "buffer is not modifiable"
  end
  local ok, blink = pcall(require, "envi.snippets.blink")
  if ok then
    body = blink.resolve_body(body)
  end
  vim.snippet.stop()
  ok, err = pcall(vim.snippet.expand, body)
  if not ok then
    return nil, tostring(err)
  end
  return true
end

function M._repo_dir()
  return opts.repo_dir
end

M.setup()
return M
