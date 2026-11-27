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
  local candidate = vim.tbl_extend(
    "force",
    { repo_dir = vim.fn.stdpath("config") .. "/snippets", trusted_projects = {}, filetypes = {} },
    options or {}
  )
  assert(vim.islist(candidate.trusted_projects), "trusted_projects must be a list of directory paths")
  assert(type(candidate.repo_dir) == "string", "repo_dir must be a directory path")
  assert(vim.islist(candidate.filetypes), "filetypes must be a list of filetype names")
  for _, ft in ipairs(candidate.filetypes) do
    assert(schema.filetype(ft), "filetypes must contain valid filetype names")
  end
  candidate.filetypes = vim.deepcopy(candidate.filetypes)
  assert(
    candidate.friendly_dir == nil or candidate.friendly_dir == false or type(candidate.friendly_dir) == "string",
    "friendly_dir must be a directory path or false"
  )
  local trusted = {}
  for _, path in ipairs(candidate.trusted_projects) do
    assert(type(path) == "string" and path ~= "", "trusted_projects must contain nonempty directory paths")
    local root = vim.uv.fs_realpath(vim.fs.normalize(path, { expand_env = false }))
    local stat = root and vim.uv.fs_stat(root)
    if stat and stat.type == "directory" then
      trusted[#trusted + 1] = root
    else
      vim.notify("Skipping unavailable trusted snippet root: " .. path, vim.log.levels.WARN)
    end
  end
  table.sort(trusted, function(a, b)
    return #a > #b
  end)
  candidate.trusted_projects = trusted
  opts = candidate
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

local function report(diagnostics, severity, message, path, kind)
  diagnostics[#diagnostics + 1] = { severity = severity, message = message, path = path, kind = kind }
end

local function recorder(diagnostics, severity, kind)
  return function(message, path)
    report(diagnostics, severity, message, path, kind)
  end
end

local function read_shared()
  if not shared then
    local diagnostics = {}
    local known_filetype = sources.filetypes(opts.filetypes)
    local records = sources.owned(opts.repo_dir, "repo", recorder(diagnostics, "error"), known_filetype)
    vim.list_extend(records, sources.friendly(opts.friendly_dir, recorder(diagnostics, "warning", "upstream_invalid")))
    for _, list in pairs(registered) do
      vim.list_extend(records, list)
    end
    shared = { records = records, diagnostics = diagnostics, known_filetype = known_filetype }
  end
  return shared
end

local function project_pack(root)
  if not root then
    return { records = {}, diagnostics = {} }
  end
  if not projects[root] then
    local diagnostics = {}
    local records = sources.owned(
      root .. "/.envi/snippets",
      "project",
      recorder(diagnostics, "error"),
      read_shared().known_filetype,
      root
    )
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
    local seen, upstream, upstream_bodies = {}, {}, {}
    for _, entry in ipairs(group) do
      local previous = seen[entry.source]
      if previous and entry.source ~= "friendly" then
        local severity = "error"
        report(diagnostics, severity, filetype .. ": duplicate prefix " .. prefix .. " in " .. entry.source, entry.path)
        conflicts[entry.source] = severity == "error"
      elseif not previous and entry.source ~= winner.source then
        report(
          diagnostics,
          "warning",
          filetype .. ": prefix " .. prefix .. " from " .. winner.source .. " shadows " .. entry.source,
          entry.path,
          "owned_shadowing"
        )
      end
      if entry.source == "friendly" then
        local repeated_scope = filetype ~= "all"
          and vim.tbl_contains(entry.filetypes, "all")
          and vim.tbl_contains(entry.filetypes, filetype)
        if repeated_scope or upstream_bodies[entry.body] then
          report(
            diagnostics,
            "warning",
            filetype .. ": identical upstream alias " .. prefix,
            entry.path,
            "upstream_alias"
          )
        end
        if not upstream_bodies[entry.body] then
          upstream_bodies[entry.body] = true
          upstream[#upstream + 1] = entry
        end
      end
      seen[entry.source] = previous or entry
    end
    if conflicts[winner.source] then
      blocked[prefix] = true
    elseif winner.source == "friendly" then
      vim.list_extend(result, upstream)
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
  local by_prefix
  for _, record in ipairs(catalog.records) do
    if record.prefix == name then
      if by_prefix then
        return nil, "upstream prefix has multiple bodies; select a completion or use a unique name"
      end
      by_prefix = record
    end
  end
  if by_prefix then
    return vim.deepcopy(by_prefix)
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
  local generated, failure
  for _, provider_name in ipairs(ordered_names(providers)) do
    local generate = providers[provider_name].generate
    if generate then
      local ok, result = pcall(generate, name, ctx)
      if not ok then
        failure = failure or ("provider " .. provider_name .. " failed: " .. tostring(result))
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
    return nil, failure or ("unknown snippet " .. name)
  end
  return generated
end

local function expand_body(body, repaired_body)
  local err
  if not vim.bo.modifiable then
    return nil, "buffer is not modifiable"
  end
  if package.loaded["blink.cmp"] or #vim.api.nvim_get_runtime_file("lua/blink/cmp/init.lua", false) > 0 then
    body, err = require("envi.snippets.blink").resolve_body(body)
    if not body then
      return nil, err
    end
  end
  vim.snippet.stop()
  local ok
  ok, err = pcall(vim.snippet.expand, repaired_body or body)
  if not ok then
    return nil, tostring(err)
  end
  return true
end

function M._expand_record(entry)
  return expand_body(entry.body, entry.repaired_body)
end

function M.expand(value, filetype)
  if type(value) == "table" then
    local body, err = schema.body(value.body)
    if not body then
      return nil, err
    end
    return expand_body(body)
  end
  local entry, err = M.get(value, filetype)
  if not entry then
    return nil, err
  end
  return M._expand_record(entry)
end

function M._repo_dir()
  return opts.repo_dir
end

M.setup()
return M
