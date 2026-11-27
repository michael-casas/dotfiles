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

local function render(tree, max_nodes, max_table_dimension)
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
  -- Even an empty paragraph needs a valid snippet body for Neovim.
  return table.concat(lines, "\n") .. "$0"
end

return render
