local M = {}

function M.check()
  vim.health.start("envi snippets")
  local ok, err = require("envi.snippets.blink").probe()
  if ok then
    vim.health.ok("The pinned Blink snippet converter is available")
  else
    vim.health.error(err)
  end

  local errors = 0
  local counts = { upstream_invalid = 0, upstream_alias = 0, owned_shadowing = 0 }
  for _, diagnostic in ipairs(require("envi.snippets").validate()) do
    if diagnostic.severity == "error" then
      errors = errors + 1
    elseif diagnostic.kind then
      counts[diagnostic.kind] = counts[diagnostic.kind] + 1
    end
  end
  if errors == 0 then
    vim.health.ok("Owned snippets validate")
  else
    vim.health.error(("%d snippet errors; run :Snippets validate for details"):format(errors))
  end
  vim.health.info(("%d upstream invalid"):format(counts.upstream_invalid))
  vim.health.info(("%d identical upstream aliases"):format(counts.upstream_alias))
  vim.health.info(("%d owned shadowing diagnostics; use :Snippets validate for details"):format(counts.owned_shadowing))
end

return M
