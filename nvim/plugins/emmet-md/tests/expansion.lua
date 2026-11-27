local envi = vim.env.EMMET_MD_ENVI_CONFIG
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/emmet-md.lua")
if envi then
  vim.opt.rtp:append(envi .. "/after")
end
vim.cmd.filetype("plugin on")
vim.notify = function() end

local function equal(expected, actual, label)
  assert(
    vim.deep_equal(expected, actual),
    ("%s\nExpected: %s\nActual: %s"):format(label, vim.inspect(expected), vim.inspect(actual))
  )
end

local cursor
vim.keymap.set({ "i", "s" }, "<F5>", function()
  cursor = vim.api.nvim_win_get_cursor(0)
end)

local function keys(input)
  cursor = nil
  vim.cmd("messages clear")
  vim.api.nvim_feedkeys(vim.keycode(input .. "<F5><Esc>"), "mx", false)
  equal("", vim.api.nvim_exec2("messages", { output = true }).output, "no Neovim error for " .. input)
end

local function reset(filetype, abbreviation)
  vim.snippet.stop()
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = filetype
  vim.api.nvim_set_current_line(abbreviation or "")
end

local trigger = envi and "<C-g>e" or "<Plug>(emmet-md-expand)"
local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local cases = {
  { "p{}", { "" }, { 1, 0 } },
  { "p{}+p{}", { "", "", "" }, { 3, 0 } },
  { "ul>li{}", { "- " }, { 1, 2 } },
  { "h2{}", { "## " }, { 1, 3 } },
  { "ul>li*3", { "- ", "- ", "- " }, { 1, 2 } },
  { "ol>li*3", { "1. ", "2. ", "3. " }, { 1, 3 } },
  { "h2{Title}", { "## Title" }, { 1, 8 } },
  { "todo*3", { "- [ ] ", "- [ ] ", "- [ ] " }, { 1, 6 } },
  { "p{First}+p{Second}", { "First", "", "Second" }, { 3, 6 } },
  { "ul>li*2^h2{Done}", { "- ", "- ", "", "## Done" }, { 1, 2 } },
  {
    "ul>(li{Parent}>ol>li*2)+li{Tail}",
    { "- Parent", "  1. ", "  2. ", "- Tail" },
    { 2, 5 },
  },
  { "ul>li{Item $$}*3", { "- Item 01", "- Item 02", "- Item 03" }, { 3, 9 } },
  { "ul>(li{A $}+li{B $})*2", { "- A 1", "- B 1", "- A 2", "- B 2" }, { 4, 5 } },
  { "ul>li{a}>ul>li{b}^^^h2{Next}", { "- a", "  - b", "", "## Next" }, { 4, 7 } },
  { "ol>li{a}>ul>li{b}", { "1. a", "   - b" }, { 2, 6 } },
  { "h$*2", { "# ", "", "## " }, { 1, 2 } },
  { [[h3{Cost \$5 and \{x\}}]], { "### Cost $5 and {x}" }, { 1, 19 } },
  { [[table>tr>td{A|B}]], { [[| A\|B |]], "| --- |" }, { 2, 7 } },
  { "p{100% {braces}}", { "100% {braces}" }, { 1, 13 } },
  { "  ul>li*2", { "  - ", "  - " }, { 1, 4 } },
}
local max_abbreviation_text = ("a"):rep(509)
table.insert(cases, { "p{" .. max_abbreviation_text .. "}", { max_abbreviation_text }, { 1, 509 } })

local table_lines = { "|  |  |  |", "| --- | --- | --- |", "|  |  |  |" }
table.insert(cases, { "table3x2", table_lines, { 1, 2 } })
table.insert(cases, { "table>tr*2>td*3", table_lines, { 1, 2 } })

for _, case in ipairs(cases) do
  local abbreviation, expected_lines, first_cursor = unpack(case)
  reset("markdown", abbreviation)
  keys("A" .. trigger)
  equal(expected_lines, lines(), abbreviation)
  equal(first_cursor, cursor, "first field or final cursor for " .. abbreviation)
end

reset("markdown", "(ul>li*50)*9+ul>li*43")
keys("A" .. trigger)
local expected_at_node_limit = {}
for block = 1, 10 do
  if block > 1 then
    table.insert(expected_at_node_limit, "")
  end
  for _ = 1, block == 10 and 43 or 50 do
    table.insert(expected_at_node_limit, "- ")
  end
end
equal(expected_at_node_limit, lines(), "512 generated elements are allowed")

reset("markdown", "ul>li*3")
keys("A" .. trigger .. "First<Tab>Second<Tab>Third<S-Tab>")
equal({ "- First", "- Second", "- Third" }, lines(), "list field navigation")
equal({ 2, 2 }, cursor, "reverse field navigation")

reset("markdown", "table2x2")
keys("A" .. trigger .. "Header 1<Tab>Header 2<Tab>Cell 1<Tab>Cell 2")
equal({ "| Header 1 | Header 2 |", "| --- | --- |", "| Cell 1 | Cell 2 |" }, lines(), "table field navigation")

reset("markdown", "h2")
local cancel_mode
package.loaded["blink.cmp"] = {
  cancel = function(opts)
    -- Blink can call back while Neovim is still in an Insert completion submode.
    vim.fn.complete(1, { "h2" })
    cancel_mode = vim.api.nvim_get_mode().mode
    opts.callback()
    return true
  end,
}
keys("A" .. trigger)
package.loaded["blink.cmp"] = nil
equal("ic", cancel_mode, "native completion reproduces Blink's cancel callback mode")
equal({ "## " }, lines(), "expand after completion cancellation")
equal({ 1, 3 }, cursor, "cursor after completion cancellation")

reset("markdown", "h2{Title}")
keys("A<Left>" .. trigger)
equal({ "## Title" }, lines(), "expand before a mini.pairs closing brace")

reset("markdown", "(h2{Title})")
keys("A<Left><Left>" .. trigger)
equal({ "## Title" }, lines(), "expand before stacked mini.pairs closers")

reset("markdown", "h2{Title}")
keys("A")
equal({ "h2{Title}" }, lines(), "normal typing leaves abbreviations alone")

for _, abbreviation in ipairs({
  "table0x2",
  "table2x0",
  "table>tr>td^tr>td*2",
  "table21x1",
  "table1x21",
  "table>tr*21>td",
  "table>tr>td*21",
  "table20x20+table20x20",
  "table>td",
  "table>tr",
  "table>tr>p",
  "table>tr>td>p",
  "h7{x}",
  "h2{x}*0",
  "h2{x}>p{lost}",
  "ul>li^^h2",
  "(ul>li)>p{x}",
  "ul>li*51",
  "(ul>li*50)*9+ul>li*44",
  "p{" .. max_abbreviation_text .. "a}",
  "ul>h2",
  "ul>li*0",
  "ul>li*999999999999999999",
  "(ul>(li*50))*50",
  "ul++li",
  "(h2",
  "h2{Title",
  "prefix h2{Title}",
}) do
  reset("markdown", abbreviation)
  keys("A" .. trigger)
  equal({ abbreviation }, lines(), "invalid abbreviation " .. abbreviation)
end

reset("markdown", "h2{Title}")
keys("0a" .. trigger)
equal({ "h2{Title}" }, lines(), "non-closer text after the cursor prevents expansion")

local function defer_expansion()
  local callback
  package.loaded["blink.cmp"] = {
    cancel = function(opts)
      callback = opts.callback
      return true
    end,
  }
  return function()
    assert(callback, "blink received the expansion callback")
    package.loaded["blink.cmp"] = nil
    callback()
  end
end

reset("markdown", "h2{Title}")
local deferred = defer_expansion()
keys("A" .. trigger)
deferred()
equal({ "h2{Title}" }, lines(), "deferred callback leaves normal mode alone")

for _, case in ipairs({
  {
    "filetype changed",
    function()
      vim.bo.filetype = "text"
    end,
    function() end,
  },
  {
    "buffer is unmodifiable",
    function()
      vim.bo.modifiable = false
    end,
    function()
      vim.bo.modifiable = true
    end,
  },
  {
    "window changed",
    function()
      vim.cmd.split()
    end,
    function()
      vim.cmd.close()
    end,
  },
}) do
  local label, change, restore = unpack(case)
  reset("markdown", "h2")
  deferred = defer_expansion()
  vim.keymap.set("i", "<F6>", function()
    change()
    assert(vim.fn.mode() == "i", "callback still runs in Insert mode")
    deferred()
  end)
  keys("A" .. trigger .. "<F6>")
  equal({ "h2" }, lines(), "deferred callback when " .. label)
  restore()
end
vim.keymap.del("i", "<F6>")

local snippet_ns = assert(vim.api.nvim_get_namespaces()["nvim.snippet"])
local function snippet_marks()
  return #vim.api.nvim_buf_get_extmarks(0, snippet_ns, 0, -1, {})
end

reset("markdown", "h2")
keys("A" .. trigger)
local clean_marks = snippet_marks()
assert(clean_marks > 0, "the snippet created marks")

reset("markdown")
vim.keymap.set("i", "<F6>", function()
  vim.snippet.expand("${1}$0")
end)
keys("i<F6>h2" .. trigger)
vim.keymap.del("i", "<F6>")
equal({ "## " }, lines(), "expand from an existing snippet")
equal(clean_marks, snippet_marks(), "old snippet marks are removed")

if envi then
  reset("markdown", "h2{Title}")
  local mapping = vim.fn.maparg("<C-g>", "i", false, true)
  local lhs = next(mapping) and "<C-g>" or trigger
  equal(true, vim.fn.maparg(lhs, "i", false, true).buffer == 1, "Markdown-local trigger")
  vim.bo.filetype = "text"
  equal({}, vim.fn.maparg(lhs, "i", false, true), "trigger removed on filetype change")
  reset("rmd")
  vim.cmd("runtime! ftplugin/markdown.lua")
  equal({}, vim.fn.maparg(lhs, "i", false, true), "no trigger on inherited Markdown ftplugins")
end
reset("text")
keys("iul>li*3")
equal({ "ul>li*3" }, lines(), "non-Markdown typing")

reset("markdown")
vim.snippet.expand("## Decision: ${1:Title}\n\n${2:Rationale}$0")
equal({ "## Decision: Title", "", "Rationale" }, lines(), "repo snippet expands")
equal({ 1, 13 }, vim.api.nvim_win_get_cursor(0), "repo snippet starts on the title")
equal(true, vim.snippet.active({ direction = 1 }), "repo snippet has another field")
vim.snippet.jump(1)
equal({ 3, 0 }, vim.api.nvim_win_get_cursor(0), "repo snippet jumps to the rationale")

print("PASS Markdown Emmet expansion, cursor placement and native snippets")
