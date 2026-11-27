local function newer(left, right)
  return left.sec > right.sec or (left.sec == right.sec and left.nsec > right.nsec)
end

return function(directory)
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
  pcall(vim.api.nvim_cmd, { cmd = "helptags", args = { directory } }, {})
end
