local schema = require("envi.snippets.schema")
local uv = vim.uv
local M = {}

local function inside(root, path)
  return path == root or vim.startswith(path, root .. "/")
end

function M.project(trusted, bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr or 0)
  if path == "" then
    return
  end
  local real = uv.fs_realpath(path) or uv.fs_realpath(vim.fs.dirname(path))
  if not real then
    return
  end
  for _, root in ipairs(trusted) do
    if inside(root, real) then
      return root
    end
  end
end

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "could not read JSON"
  end
  local decoded, value = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded or type(value) ~= "table" or vim.islist(value) then
    return nil, "expected a JSON object"
  end
  return value
end

local function append_pack(result, path, root, filetypes, tier, diagnostic)
  local real = uv.fs_realpath(path)
  if not real or not inside(root, real) then
    diagnostic("file escapes its snippet directory or cannot be resolved", path)
    return
  end
  local pack, err = read_json(real)
  if not pack then
    diagnostic(err, path)
    return
  end
  for _, name in ipairs(vim.fn.sort(vim.tbl_keys(pack))) do
    local spec = pack[name]
    if tier == "friendly" and type(spec) == "table" and spec.prefix == nil then
      spec.prefix = name
    end
    local records, problem = schema.records(name, spec, filetypes, tier, path)
    if records then
      vim.list_extend(result, records)
    else
      diagnostic(name .. ": " .. problem, path)
    end
  end
end

function M.owned(directory, tier, diagnostic, trusted_root)
  local result = {}
  local root = directory and uv.fs_realpath(directory)
  if not root then
    return result
  end
  if trusted_root and not inside(trusted_root, root) then
    diagnostic("snippet directory escapes the trusted project", directory)
    return result
  end
  local scanner = uv.fs_scandir(root)
  if not scanner then
    return result
  end
  local filenames = {}
  while true do
    local name, kind = uv.fs_scandir_next(scanner)
    if not name then
      break
    end
    if kind ~= "directory" and name:match("%.json$") then
      filenames[#filenames + 1] = name
    end
  end
  table.sort(filenames)
  for _, name in ipairs(filenames) do
    local ft = name:sub(1, -6)
    append_pack(result, root .. "/" .. name, root, { ft }, tier, diagnostic)
  end
  return result
end

function M.friendly(directory, diagnostic)
  local result = {}
  if directory == nil then
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      if vim.fs.basename(path) == "friendly-snippets" then
        directory = path
        break
      end
    end
    if directory == nil then
      local lazy = package.loaded["lazy.core.config"]
      local plugin = lazy and lazy.plugins["friendly-snippets"]
      directory = plugin and plugin.dir
    end
  end
  local root = directory and uv.fs_realpath(directory)
  if not root then
    return result
  end
  local manifest_path = root .. "/package.json"
  local manifest, err = read_json(manifest_path)
  local contributions = manifest and vim.tbl_get(manifest, "contributes", "snippets")
  if not vim.islist(contributions) then
    diagnostic(err or "missing VS Code snippet contributions", manifest_path)
    return result
  end
  local paths = {}
  for _, record in ipairs(contributions) do
    if type(record) == "table" and type(record.path) == "string" then
      local languages = type(record.language) == "string" and { record.language } or record.language
      if vim.islist(languages) then
        local path = vim.fs.normalize(root .. "/" .. record.path)
        paths[path] = vim.list_extend(paths[path] or {}, languages)
      end
    end
  end
  for _, path in ipairs(vim.fn.sort(vim.tbl_keys(paths))) do
    append_pack(result, path, root, vim.fn.uniq(vim.fn.sort(paths[path])), "friendly", diagnostic)
  end
  return result
end

function M.is_pack(path, opts)
  if not path:match("%.json$") then
    return false
  end
  local directory = uv.fs_realpath(vim.fs.dirname(path))
  if not directory then
    return false
  end
  if directory == uv.fs_realpath(opts.repo_dir) then
    return true
  end
  for _, root in ipairs(opts.trusted_projects) do
    if directory == uv.fs_realpath(root .. "/.envi/snippets") and inside(root, directory) then
      return true
    end
  end
  return false
end

return M
