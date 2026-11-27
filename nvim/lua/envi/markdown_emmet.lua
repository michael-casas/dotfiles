local M = {}

local max_length = 512
local max_repeat = 50
local max_nodes = 512
local max_table_dimension = 20

local function parse(source)
  local position = 1

  local function take(pattern)
    local first, last = source:find("^" .. pattern, position)
    if first then
      position = last + 1
      return source:sub(first, last)
    end
  end

  local function read_text()
    local start = position
    local depth = 1
    while position <= #source do
      local char = source:sub(position, position)
      position = position + 1
      if char == "\\" then
        position = position + 1
      elseif char == "{" then
        depth = depth + 1
      elseif char == "}" then
        depth = depth - 1
        if depth == 0 then
          return source:sub(start, position - 2)
        end
      end
    end
  end

  local function sequence()
    local root = {}
    local parents = { root }
    while true do
      local node = { children = {} }
      if take("%(") then
        node.group = sequence()
        if not node.group or not take("%)") then
          return
        end
      else
        node.name = take("[a-z][a-z0-9$]*")
        if not node.name then
          return
        end
        if take("{") then
          node.text = read_text()
          if node.text == nil then
            return
          end
        end
      end
      if take("%*") then
        node.count = tonumber(take("%d+") or "")
        if not node.count or node.count < 1 or node.count > max_repeat then
          return
        end
      end
      local siblings = parents[#parents]
      siblings[#siblings + 1] = node

      if take(">") then
        if node.group then
          return
        end
        parents[#parents + 1] = node.children
      elseif take("%+") then
        -- The next node goes into the current container.
      elseif take("%^") then
        repeat
          if #parents == 1 then
            return
          end
          parents[#parents] = nil
        until not take("%^")
      else
        return root
      end
    end
  end

  local nodes = sequence()
  if position == #source + 1 then
    return nodes
  end
end

local function numbered_text(value, index)
  -- Keep abbreviation escapes distinct from the later snippet-string escapes.
  local result = {}
  local pos = 1
  while pos <= #value do
    local start = value:find("[\\$]", pos)
    if not start then
      result[#result + 1] = value:sub(pos)
      break
    end
    result[#result + 1] = value:sub(pos, start - 1)
    if value:sub(start, start) == "$" then
      local _, last = value:find("^%$+", start)
      local digits = tostring(index)
      result[#result + 1] = ("0"):rep(math.max(0, last - start + 1 - #digits)) .. digits
      pos = last + 1
    else
      local next_char = value:sub(start + 1, start + 1)
      if next_char ~= "" and ("{}$\\"):find(next_char, 1, true) then
        result[#result + 1] = next_char
        pos = start + 2
      else
        result[#result + 1] = "\\"
        pos = start + 1
      end
    end
  end
  return table.concat(result)
end

local function render(tree)
  local remaining = max_nodes
  local field = 0

  local function instantiate(nodes, inherited, result)
    for _, node in ipairs(nodes) do
      for repetition = 1, node.count or 1 do
        remaining = remaining - 1
        if remaining < 0 then
          return false
        end
        local index = node.count and repetition or inherited
        if node.group then
          if not instantiate(node.group, index, result) then
            return false
          end
        else
          local children = {}
          if not instantiate(node.children, index, children) then
            return false
          end
          result[#result + 1] = {
            name = numbered_text(node.name, index),
            text = node.text and numbered_text(node.text, index),
            children = children,
          }
        end
      end
    end
    return true
  end

  local function slot(value)
    if value ~= nil then
      return (value:gsub("[\\$}]", "\\%0"))
    end
    field = field + 1
    return "${" .. field .. "}"
  end

  local function row_text(cells)
    local fields = {}
    for i, cell in ipairs(cells) do
      local value = cell.text
      if value then
        value = value:gsub("\\*|", function(pipe)
          return #pipe % 2 == 1 and "\\" .. pipe or pipe
        end)
      end
      fields[i] = slot(value)
    end
    return "| " .. table.concat(fields, " | ") .. " |"
  end

  local function table_lines(node)
    if node.text then
      return
    end

    local rows = {}
    local columns, row_count = node.name:match("^table(%d+)x(%d+)$")
    if columns then
      columns, row_count = tonumber(columns), tonumber(row_count)
      if
        #node.children > 0
        or columns < 1
        or row_count < 1
        or columns > max_table_dimension
        or row_count > max_table_dimension
      then
        return
      end
      remaining = remaining - columns * row_count
      if remaining < 0 then
        return
      end
      local cells = {}
      for col = 1, columns do
        cells[col] = {}
      end
      for row = 1, row_count do
        rows[row] = cells
      end
    elseif node.name == "table" then
      for i, row in ipairs(node.children) do
        local width = #row.children
        if row.name ~= "tr" or row.text or width == 0 or (columns and columns ~= width) then
          return
        end
        for _, cell in ipairs(row.children) do
          if cell.name ~= "td" or #cell.children > 0 then
            return
          end
        end
        columns = width
        rows[i] = row.children
      end
      if not columns or columns > max_table_dimension or #rows > max_table_dimension then
        return
      end
    else
      return
    end

    local lines = { row_text(rows[1]), "|" .. (" --- |"):rep(columns) }
    for i = 2, #rows do
      lines[#lines + 1] = row_text(rows[i])
    end
    return lines
  end

  local function render_list(node, lines, indent)
    if node.text or #node.children == 0 then
      return false
    end
    for i, item in ipairs(node.children) do
      if item.name ~= "li" then
        return false
      end
      local marker = node.name == "ol" and (i .. ". ") or "- "
      lines[#lines + 1] = indent .. marker .. slot(item.text)
      for _, child in ipairs(item.children) do
        if
          (child.name ~= "ul" and child.name ~= "ol") or not render_list(child, lines, indent .. (" "):rep(#marker))
        then
          return false
        end
      end
    end
    return true
  end

  local nodes = {}
  if not instantiate(tree, 1, nodes) then
    return
  end
  local lines = {}
  local previous_was_task = false
  for _, node in ipairs(nodes) do
    local task = node.name == "todo"
    if #lines > 0 and not (task and previous_was_task) then
      lines[#lines + 1] = ""
    end
    local heading = node.name:match("^h([1-6])$")
    if node.name == "ul" or node.name == "ol" then
      if not render_list(node, lines, "") then
        return
      end
    elseif node.name:match("^table") then
      local tabular = table_lines(node)
      if not tabular then
        return
      end
      vim.list_extend(lines, tabular)
    elseif #node.children == 0 and (heading or node.name == "p" or task) then
      local prefix = heading and (("#"):rep(tonumber(heading)) .. " ") or task and "- [ ] " or ""
      lines[#lines + 1] = prefix .. slot(node.text)
    else
      return
    end
    previous_was_task = task
  end
  return table.concat(lines, "\n") .. "$0"
end

local function compile(abbreviation)
  if #abbreviation > max_length then
    return
  end
  local tree = parse(abbreviation)
  if tree then
    return render(tree)
  end
end

local function expand_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local line = vim.api.nvim_get_current_line()
  local first = line:find("%S")
  if not first or first > col or not line:sub(col + 1):match("^[)}]*$") then
    return
  end
  local snippet = compile(line:sub(first))
  if not snippet then
    return
  end

  vim.snippet.stop()
  vim.api.nvim_buf_set_text(0, row, first - 1, row, #line, { "" })
  vim.api.nvim_win_set_cursor(0, { row + 1, first - 1 })
  vim.cmd.undojoin()
  vim.snippet.expand(snippet)
end

function M.expand()
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local function expand()
    if
      vim.api.nvim_get_current_win() == win
      and vim.api.nvim_get_current_buf() == buf
      and vim.fn.mode() == "i"
      and vim.bo.filetype == "markdown"
      and vim.bo.modifiable
    then
      expand_at_cursor()
    end
  end

  -- Cancel instead of hiding: a selected completion may have inserted a preview.
  local blink = package.loaded["blink.cmp"]
  if not (blink and blink.cancel({ callback = expand })) then
    expand()
  end
end

return M
