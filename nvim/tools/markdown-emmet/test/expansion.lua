local config = vim.fn.getcwd() .. "/nvim"
vim.opt.rtp:prepend(config)
vim.opt.rtp:append(config .. "/after")
vim.cmd.filetype("plugin on")

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
  vim.api.nvim_feedkeys(vim.keycode(input .. "<F5><Esc>"), "mx", false)
end

local function reset(filetype, abbreviation)
  vim.snippet.stop()
  vim.cmd.enew({ bang = true })
  vim.bo.filetype = filetype
  vim.api.nvim_set_current_line(abbreviation or "")
end

local trigger = "<C-g>e"
local function lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local cases = {
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
  { "h$*2", { "# ", "", "## " }, { 1, 2 } },
  { [[h3{Cost \$5 and \{x\}}]], { "### Cost $5 and {x}" }, { 1, 19 } },
  { [[table>tr>td{A|B}]], { [[| A\|B |]], "| --- |" }, { 2, 7 } },
  { "p{100% {braces}}", { "100% {braces}" }, { 1, 13 } },
  { "  ul>li*2", { "  - ", "  - " }, { 1, 4 } },
}
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

reset("markdown", "ul>li*3")
keys("A" .. trigger .. "First<Tab>Second<Tab>Third<S-Tab>")
equal({ "- First", "- Second", "- Third" }, lines(), "list field navigation")
equal({ 2, 2 }, cursor, "reverse field navigation")

reset("markdown", "table2x2")
keys("A" .. trigger .. "Header 1<Tab>Header 2<Tab>Cell 1<Tab>Cell 2")
equal({ "| Header 1 | Header 2 |", "| --- | --- |", "| Cell 1 | Cell 2 |" }, lines(), "table field navigation")

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
  "table>tr>td+tr>td*2",
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
equal(true, vim.fn.maparg(trigger, "i", false, true).buffer == 1, "Markdown-local trigger")
vim.bo.filetype = "text"
equal({}, vim.fn.maparg(trigger, "i", false, true), "trigger removed on filetype change")
reset("text")
keys("iul>li*3")
equal({ "ul>li*3" }, lines(), "non-Markdown typing")

local snippets = vim.json.decode(table.concat(vim.fn.readfile(config .. "/snippets/markdown.json"), "\n"))
local decision = vim.iter(vim.tbl_values(snippets)):find(function(item)
  return item.prefix == "envi-decision"
end)
assert(decision, "repo Markdown snippets contain envi-decision")
reset("markdown")
vim.snippet.expand(table.concat(decision.body, "\n"))
equal({ "## Decision: Title", "", "Rationale" }, lines(), "repo snippet expands")
equal({ 1, 13 }, vim.api.nvim_win_get_cursor(0), "repo snippet starts on the title")
equal(true, vim.snippet.active({ direction = 1 }), "repo snippet has another field")
vim.snippet.jump(1)
equal({ 3, 0 }, vim.api.nvim_win_get_cursor(0), "repo snippet jumps to the rationale")

print("PASS Markdown Emmet expansion, cursor placement and native snippets")
