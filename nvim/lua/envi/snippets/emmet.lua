local function escape(text)
  return (text:gsub("[\\$}]", "\\%0"))
end

return {
  generate = function(abbreviation, context)
    if context.filetype ~= "markdown" then
      return
    end
    local lines, stops = require("emmet-md").expand(abbreviation)
    if not lines then
      return
    end
    local next_stop = 1
    for row, line in ipairs(lines) do
      local pieces, offset = {}, 0
      while stops[next_stop] and stops[next_stop].row == row do
        local stop = stops[next_stop]
        pieces[#pieces + 1] = escape(line:sub(offset + 1, stop.col))
        pieces[#pieces + 1] = "${" .. stop.index .. "}"
        offset = stop.col
        next_stop = next_stop + 1
      end
      pieces[#pieces + 1] = escape(line:sub(offset + 1))
      lines[row] = table.concat(pieces)
    end
    return { prefix = abbreviation, body = table.concat(lines, "\n"), description = "Expand Markdown Emmet" }
  end,
}
