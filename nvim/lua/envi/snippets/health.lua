local M = {}

function M.check()
  vim.health.start("envi snippets")
  local ok, registry = pcall(require, "blink.cmp.sources.snippets.default.registry")
  if ok and type(registry.snippet_to_completion_item) == "function" then
    vim.health.ok("The pinned Blink snippet converter is available")
  else
    vim.health.error("The pinned Blink snippet converter is unavailable")
  end

  local errors, warnings = 0, 0
  for _, diagnostic in ipairs(require("envi.snippets").validate()) do
    if diagnostic.severity == "error" then
      errors = errors + 1
    else
      warnings = warnings + 1
    end
  end
  if errors == 0 then
    vim.health.ok("Owned snippets validate")
  else
    vim.health.error(("%d snippet errors; run :Snippets validate for details"):format(errors))
  end
  vim.health.info(("%d upstream or precedence diagnostics; use :Snippets validate for details"):format(warnings))
end

return M
