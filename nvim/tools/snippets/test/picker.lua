vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local root = vim.fn.tempname()
local repo, friendly = root .. "/repo", root .. "/friendly"
vim.fn.mkdir(repo, "p")
vim.fn.mkdir(friendly, "p")
local function write(path, value)
  vim.fn.writefile({ vim.json.encode(value) }, friendly .. "/" .. path)
end
local raw = "${1:raise $2}$0"
package.loaded["lazyvim.util.cmp"] = {
  snippet_fix = function(body)
    return body == raw and "${1:raise prepared}$0" or body
  end,
}
write("package.json", { contributes = { snippets = { { language = "python", path = "./python.json" } } } })
write("python.json", { Repaired = { prefix = "try", body = raw } })
local snippets = require("envi.snippets")
snippets.setup({ repo_dir = repo, friendly_dir = friendly })
vim.bo.filetype = "python"
vim.cmd("runtime plugin/envi-snippets.lua")
local edited = vim.api.nvim_get_current_buf()
if vim.env.ENVI_SNIPPETS_SNACKS then
  vim.opt.rtp:append(vim.env.ENVI_SNIPPETS_SNACKS)
  require("snacks").setup({ picker = { enabled = true } })
  vim.cmd("Snippets list")
  local picker
  assert(
    vim.wait(1000, function()
      picker = Snacks.picker.get({})[1]
      return picker and picker:current()
    end),
    "Snacks picker did not show the repaired snippet"
  )
  assert(picker:current().record.prefix == "try")
  picker:action("confirm")
else
  -- Exercise the same picker contract on checkouts without installed plugins.
  _G.Snacks = {
    picker = {
      pick = function(opts)
        assert(opts.title == "Snippets" and #opts.items == 1)
        opts.confirm({ close = function() end }, opts.items[1])
      end,
    },
  }
  vim.cmd("Snippets list")
end
assert(
  vim.wait(1000, function()
    return vim.api.nvim_buf_get_lines(edited, 0, 1, false)[1] == "raise prepared"
  end),
  "the picker must insert the repaired upstream body"
)
assert(vim.snippet.active())
print("PASS snippets picker inserts a repaired upstream body")
