local function newer(left, right)
  return left.sec > right.sec or (left.sec == right.sec and left.nsec > right.nsec)
end

return function(directory)
  if directory:match("^~[^/\\]") then
    directory = "./" .. directory
  end
  directory = vim.fs.normalize(vim.fs.abspath(directory), { expand_env = false })
  local dir = vim.uv.fs_stat(directory)
  if not dir or dir.type ~= "directory" then
    return
  end
  local tags = vim.uv.fs_stat(directory .. "/tags")
  if tags and not newer(dir.mtime, tags.mtime) then
    local outdated = false
    for name in vim.fs.dir(directory) do
      if name:match("%.txt$") then
        local doc = vim.uv.fs_stat(directory .. "/" .. name)
        if doc and newer(doc.mtime, tags.mtime) then
          outdated = true
          break
        end
      end
    end
    if not outdated then
      return
    end
  end
  -- :helptags globs its argument internally. Enter the directory through
  -- libuv so only the fixed pattern "." reaches the command.
  local cwd = vim.uv.cwd()
  if cwd and vim.uv.chdir(directory) then
    pcall(vim.api.nvim_cmd, { cmd = "helptags", args = { "." } }, {})
    assert(vim.uv.chdir(cwd))
  end
end
