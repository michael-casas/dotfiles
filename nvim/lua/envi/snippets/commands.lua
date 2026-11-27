local M = {}
local snippets = require("envi.snippets")
local schema = require("envi.snippets.schema")
local subcommands = { "list", "new", "edit", "validate", "reload", "expand" }

local function warn(message)
  vim.notify(message, vim.log.levels.WARN, { title = "envi snippets" })
end

local function pack_path()
  local filetype = vim.bo.filetype
  if not schema.filetype(filetype) then
    return nil, "set a valid filetype before editing its snippets"
  end
  local repo = snippets._repo_dir()
  if repo == "" then
    return nil, "configure a snippet repository before editing packs"
  end
  return repo .. "/" .. filetype .. ".json"
end

local function open_pack(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local buffer = vim.fn.bufadd(path)
  vim.bo[buffer].buflisted = true
  vim.api.nvim_set_current_buf(buffer)
end

local function edit()
  local path, err = pack_path()
  if path then
    open_pack(path)
  else
    warn(err)
  end
end

local function new(prefix)
  local path, err = pack_path()
  if not path then
    warn(err)
    return
  end
  local function scaffold(value)
    if not value then
      return
    end
    if value == "" or value:find("%s") then
      warn("enter a nonempty prefix without whitespace")
      return
    end
    open_pack(path)
    local buffer = vim.api.nvim_get_current_buf()
    local text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
    local valid, pack = pcall(vim.json.decode, text:match("%S") and text or "{}")
    if not valid or type(pack) ~= "table" or vim.islist(pack) then
      warn("fix the JSON object before adding a snippet")
      return
    end
    for name, entry in pairs(pack) do
      local existing = type(entry) == "table" and entry.prefix
      if name == value or existing == value or (vim.islist(existing) and vim.tbl_contains(existing, value)) then
        warn("this pack already contains " .. value)
        return
      end
    end
    pack[value] = { prefix = value, body = { "${1:Text}", "$0" } }
    local names, lines = vim.tbl_keys(pack), { "{" }
    table.sort(names)
    for i, name in ipairs(names) do
      lines[#lines + 1] = "  "
        .. vim.json.encode(name)
        .. ": "
        .. vim.json.encode(pack[name])
        .. (i < #names and "," or "")
    end
    lines[#lines + 1] = "}"
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  end
  if prefix ~= "" then
    scaffold(prefix)
  else
    vim.ui.input({ prompt = "Snippet prefix: " }, scaffold)
  end
end

local function expand(value)
  local ok, err = snippets.expand(value)
  if not ok then
    warn(err)
  end
end

local function list()
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local items = {}
  for _, record in ipairs(snippets.list()) do
    items[#items + 1] = { text = record.prefix .. "  " .. (record.description or record.name), record = record }
  end
  if #items == 0 then
    warn("no snippets for this buffer")
    return
  end
  local snacks = _G.Snacks
  if not snacks or not snacks.picker then
    for _, item in ipairs(items) do
      vim.api.nvim_echo({ { item.text .. "\n" } }, true, {})
    end
    return
  end
  snacks.picker.pick({
    title = "Snippets",
    items = items,
    format = function(item)
      return { { item.text } }
    end,
    confirm = function(picker, item)
      picker:close()
      vim.schedule(function()
        if item and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
          vim.api.nvim_win_call(win, function()
            local ok, err = snippets._expand_record(item.record)
            if not ok then
              warn(err)
            end
          end)
        end
      end)
    end,
  })
end

local function validate()
  local items, errors = {}, 0
  for _, diagnostic in ipairs(snippets.validate()) do
    local failed = diagnostic.severity == "error"
    errors = errors + (failed and 1 or 0)
    items[#items + 1] = {
      type = failed and "E" or "W",
      filename = diagnostic.path and vim.startswith(diagnostic.path, "/") and diagnostic.path or nil,
      lnum = 1,
      text = diagnostic.message,
    }
  end
  vim.fn.setqflist({}, " ", { title = "Snippet validation", items = items })
  vim.notify(
    ("Snippet validation: %d errors, %d warnings"):format(errors, #items - errors),
    errors > 0 and vim.log.levels.ERROR or vim.log.levels.INFO
  )
end

function M.register()
  vim.api.nvim_create_user_command("Snippets", function(command)
    local action, value = command.args:match("^%s*(%S*)%s*(.-)%s*$")
    if action == "" or action == "list" then
      list()
    elseif action == "expand" then
      expand(value)
    elseif action == "edit" then
      edit()
    elseif action == "new" then
      new(value)
    elseif action == "validate" then
      validate()
    elseif action == "reload" then
      snippets.reload()
      vim.notify("Snippets reloaded")
    else
      warn("unknown Snippets action " .. action)
    end
  end, {
    desc = "Browse, edit, expand or validate snippets",
    nargs = "*",
    complete = function(lead)
      return vim.tbl_filter(function(action)
        return vim.startswith(action, lead)
      end, subcommands)
    end,
  })
end

return M
