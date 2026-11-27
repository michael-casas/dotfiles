local function parse(source, max_repeat)
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

return parse
