local M = {}

function M.check()
  vim.health.start("emmet-md")
  if type(vim.snippet.expand) ~= "function" then
    vim.health.error("Neovim native snippets are required")
    return
  end
  local ok, lines, stops =
    pcall(require("emmet-md").expand, "ul>li*2", { max_repeat = 2, max_length = 8, max_nodes = 3 })
  if ok and vim.deep_equal(lines, { "- ", "- " }) and #stops == 3 then
    vim.health.ok("Native snippet API and Markdown expansion are available")
  else
    vim.health.error("Markdown expansion self-check failed")
  end
end

return M
