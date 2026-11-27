vim.opt.rtp:prepend(vim.fn.getcwd())

local function equal(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end

local emmet = require("emmet-md")
local before = vim.api.nvim_get_current_line()
local lines, stops = emmet.expand("ul>li*2")
equal({ "- ", "- " }, lines)
equal({
  { index = 1, row = 1, col = 2 },
  { index = 2, row = 2, col = 2 },
  { index = 0, row = 2, col = 2 },
}, stops)
equal(before, vim.api.nvim_get_current_line())
equal({ "## Price $5" }, emmet.expand([[h2{Price \$5}]]))
equal("ul", emmet.parse("ul>li")[1].name)
local refused, reason = emmet.expand("table2x0")
equal(nil, refused)
assert(type(reason) == "string" and #reason > 0)
equal(nil, emmet.expand("ul>li*2", { max_repeat = 1 }))
assert(emmet.expand("ul>li*2"))

local function mappings()
  local result = {}
  for _, mode in ipairs({ "n", "x", "s", "o", "i", "c", "t", "l" }) do
    result[mode] = vim
      .iter(vim.api.nvim_get_keymap(mode))
      :filter(function(map)
        return mode ~= "i" or map.lhs ~= "<Plug>(emmet-md-expand)"
      end)
      :totable()
  end
  return result
end

local original_maps = mappings()
vim.cmd("runtime plugin/emmet-md.lua")
equal(original_maps, mappings())
assert(vim.fn.maparg("<Plug>(emmet-md-expand)", "i") ~= "")
assert(
  vim.iter(vim.fn.readfile("doc/tags")):any(function(line)
    return vim.startswith(line, "emmet-md\t")
  end),
  "the exact emmet-md help tag must exist"
)
vim.cmd.help("emmet-md")
assert(vim.fs.basename(vim.api.nvim_buf_get_name(0)) == "emmet-md.txt")
assert(vim.api.nvim_get_current_line():find("*emmet-md*", 1, true))
vim.cmd.helpclose()

emmet.setup({ filetypes = { "text" }, max_repeat = 2 })
equal(nil, emmet.expand("ul>li*3"))
vim.bo.filetype = "text"
vim.cmd("EmmetMd h2{A Title}")
equal("## A Title", vim.api.nvim_get_current_line())
vim.cmd.enew({ bang = true })
vim.bo.filetype = "text"
vim.api.nvim_set_current_line("todo{Pack}")
vim.cmd.EmmetMd()
equal("- [ ] Pack", vim.api.nvim_get_current_line())
print("PASS standalone emmet-md API and entry points")
