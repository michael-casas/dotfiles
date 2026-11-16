-- Synthetic-only sidebar contract. No hc/T3 jobs, clients, or user configuration.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns = 100
local fixture =
  vim.json.decode(table.concat(vim.fn.readfile("nvim/tools/t3-thread/test/fixtures/sidebar-cards.json"), "\n"))
local side, buf, bar, main, opened, picker_options, data
local passed, failed = 0, {}
local function lines()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
local function find(text)
  for index, line in ipairs(lines()) do
    if line:find(text, 1, true) then
      return index
    end
  end
  error("missing rendered text: " .. text)
end
local function at(text)
  vim.api.nvim_win_set_cursor(bar, { find(text), 0 })
end
local function on(text)
  assert(vim.api.nvim_win_get_cursor(bar)[1] == find(text), "expected title/header: " .. text)
end
local function key(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end
local function map(lhs)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if mapping.lhs == lhs then
      return mapping
    end
  end
end
local function setup()
  vim.cmd("only!")
  vim.cmd("enew!")
  main = vim.api.nvim_get_current_win()
  local main_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, { "Synthetic main client", "Draft unchanged" })
  vim.api.nvim_win_set_cursor(main, { 2, 3 })
  package.loaded["hcmux.t3side"] = nil
  side = require("hcmux.t3side")
  side.start = function()
    error("must not start a feed")
  end
  opened, picker_options = {}, nil
  package.loaded["hcmux.layout"] = {
    open_thread = function(id)
      opened[#opened + 1] = id
      -- Like real layout.open_thread, select/render after main-window work.
      vim.api.nvim_set_current_win(main)
      side.select(id)
    end,
  }
  package.loaded["hcmux.t3"] = {
    open = function()
      error("must not open a popover")
    end,
  }
  _G.Snacks = {
    picker = {
      pick = function(options)
        picker_options = options
        return options
      end,
    },
  }
  data = vim.deepcopy(fixture)
  side.update(data)
  buf = side.buffer()
  vim.cmd("vsplit")
  bar = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(bar, buf)
  vim.api.nvim_win_set_width(bar, 36)
  side.render()
end
local function test(name, fn)
  setup()
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("ok sidebar-cards: " .. name)
  else
    failed[#failed + 1] = name .. ": " .. tostring(err)
    print("FAIL sidebar-cards: " .. failed[#failed])
  end
end
local function search()
  assert(map("/"), "missing buffer-local thread search")
  key("/")
  assert(picker_options, "slash must open thread picker")
  return picker_options
end
local function choose(options, item)
  local closed = false
  options.confirm({
    close = function()
      closed = true
    end,
  }, item)
  vim.wait(100, function()
    return #opened > 0
  end)
  assert(closed, "confirm closes picker")
end

test("j/k step distinct title cards, including secondary-line origins", function()
  at("First card")
  key("j")
  on("Second card")
  key("k")
  on("First card")
  at("first-metadata")
  key("j")
  on("Second card")
  at("second-metadata")
  key("k")
  on("First card")
end)

test("skip pinned metadata, project headers, blanks and branch rows", function()
  at("Pinned card")
  key("j")
  on("First card")
  at("First card")
  key("k")
  on("Pinned card")
  at("Third card")
  key("j")
  on("Last card")
  key("k")
  on("Third card")
end)

test("counts move cards in both directions", function()
  at("Pinned card")
  key("3j")
  on("Third card")
  at("Last card")
  key("3k")
  on("First card")
end)

test("clamp at first/last card with no wrap", function()
  at("Pinned card")
  key("999k")
  on("Pinned card")
  at("Last card")
  key("999j")
  on("Last card")
end)

test("headers remain native gg/G reachable and directional stepping works", function()
  assert(not map("gg") and not map("G"), "do not remap native gg/G")
  key("gg")
  on("PINNED")
  key("j")
  on("Pinned card")
  at("AP Alpha project")
  key("j")
  on("First card")
  at("AP Alpha project")
  key("k")
  on("Pinned card")
  key("G")
  on(" Settled  ")
  key("k")
  on("Last card")
end)

test("only visible cards in collapsed groups and settled disclosure", function()
  at("AP Alpha project")
  key("<CR>")
  at("Pinned card")
  key("j")
  on("Last card")
  key("j")
  on("Last card")
  at(" Settled  ")
  key("<CR>")
  at("Last card")
  key("j")
  on("Settled searchable")
  at(" Settled  ")
  key("<CR>")
  at("Last card")
  key("999j")
  on("Last card")
  -- Existing collapse exceptions remain visible and participate in navigation.
  data.threads[3].status = "working"
  side.select("third")
  side.update(data)
  at("Pinned card")
  key("j")
  on("Second card")
  key("j")
  on("Third card")
end)

test("movement never attaches; CR/o retain explicit open", function()
  at("First card")
  local before = vim.api.nvim_win_get_cursor(main)
  key("3j2k")
  assert(#opened == 0 and vim.deep_equal(before, vim.api.nvim_win_get_cursor(main)), "movement is inert")
  on("Second card")
  key("<CR>")
  assert(opened[1] == "second")
  vim.api.nvim_set_current_win(bar)
  at("first-metadata")
  key("o")
  assert(opened[2] == "first")
end)

test("same card title and exact secondary key survive reordered feed render", function()
  at("First card")
  key("j")
  on("Second card")
  data.threads[3].status = "working"
  side.update(data)
  on("Second card")
  at("second-metadata")
  data.threads[3].pinned = true
  side.update(data)
  on("second-metadata")
end)

test("empty visible catalogue has safe no-op movement", function()
  side.update({ type = "snapshot", projects = {}, threads = {} })
  local before = vim.api.nvim_win_get_cursor(bar)
  key("99j99k")
  assert(vim.deep_equal(before, vim.api.nvim_win_get_cursor(bar)) and #opened == 0)
end)

test("search candidates use full snapshot, listed eligibility, settled and full titles", function()
  local long = "Full title " .. string.rep("synthetic ", 12) .. "UniqueSuffix"
  data.threads[2].title = long
  side.update(data)
  at("AP Alpha project")
  key("<CR>")
  assert(type(side.search_items) == "function", "expose UI-independent candidates")
  local items = side.search_items()
  local by_id = {}
  for _, item in ipairs(items) do
    by_id[item.id] = item
  end
  assert(#items == 6, "exclude archived and listed=false, include absent listed and settled")
  assert(not by_id.archived and not by_id.unlisted and not by_id["unlisted-settled"])
  assert(by_id.settled and by_id.first, "collapsed and settled cards are searchable")
  assert(by_id.first.text == long, "search full title, not rendered/truncated text or context")
  by_id.first.text = "mutated candidate"
  assert(side.title("first") == long, "candidates cannot mutate snapshot")
end)

test("picker uses case-insensitive title fuzzy matching with project and age context", function()
  data.threads[2].title = "Duplicate title"
  data.threads[5].title = "Duplicate title"
  side.update(data)
  local options = search()
  assert(options.matcher.fuzzy and options.matcher.ignorecase and options.matcher.smartcase == false)
  assert(options.preview == false, "no preview attaches or mutates main")
  local by_id = {}
  for _, item in ipairs(options.items) do
    by_id[item.id] = item
  end
  assert(by_id.first.text == "Duplicate title" and by_id.last.text == "Duplicate title")
  local first = vim.inspect(options.format(by_id.first))
  local last = vim.inspect(options.format(by_id.last))
  assert(first:find("Alpha project", 1, true) and last:find("Beta project", 1, true), "duplicate project context")
  assert(first:find(side.presentation.age(data.threads[2].updatedAt), 1, true), "presentation age context")
end)

test("picker cancellation returns to the sidebar, not Snacks' preferred file window", function()
  local options = search()
  assert(options.main and options.main.current == true, "pin picker return focus to sidebar scratch window")
end)

test("Enter opens layout not popover and moves sidebar cursor even after focus changes", function()
  at("First card")
  local options = search()
  local hit
  for _, item in ipairs(options.items) do
    if item.id == "last" then
      hit = item
    end
  end
  assert(hit)
  choose(options, hit)
  assert(#opened == 1 and opened[1] == "last", "use layout.open_thread")
  on("Last card")
end)

test("Enter can open collapsed/settled hits and target visible post-open card", function()
  at("Beta project")
  key("<CR>")
  local options = search()
  local hit
  for _, item in ipairs(options.items) do
    if item.id == "settled" then
      hit = item
    end
  end
  assert(hit)
  choose(options, hit)
  assert(#opened == 1 and opened[1] == "settled")
  -- Real side.select retains a selected card, even in its collapsed group.
  on("Settled searchable")
end)

test("Esc cancels in INSERT and NORMAL, preserving bar and main client", function()
  at("second-metadata")
  local bar_cursor, main_cursor = vim.api.nvim_win_get_cursor(bar), vim.api.nvim_win_get_cursor(main)
  local main_buf = vim.api.nvim_win_get_buf(main)
  local main_lines = vim.api.nvim_buf_get_lines(main_buf, 0, -1, false)
  local before_snapshot = side.snapshot()
  local options = search()
  local escape = options.win.input.keys["<Esc>"]
  assert(escape[1] == "close" and vim.tbl_contains(escape.mode, "i") and vim.tbl_contains(escape.mode, "n"))
  assert(options.win.list.keys["<Esc>"] == "close")
  choose(options, nil) -- UI-independent cancellation/no item path.
  assert(#opened == 0, "cancel never opens/attaches")
  assert(vim.deep_equal(bar_cursor, vim.api.nvim_win_get_cursor(bar)), "bar cursor unchanged")
  assert(vim.api.nvim_win_get_buf(main) == main_buf and vim.deep_equal(main_cursor, vim.api.nvim_win_get_cursor(main)))
  assert(vim.deep_equal(main_lines, vim.api.nvim_buf_get_lines(main_buf, 0, -1, false)), "draft/content unchanged")
  assert(vim.deep_equal(before_snapshot, side.snapshot()), "snapshot/selection not mutated")
end)

print(("sidebar-cards: %d passed, %d failed"):format(passed, #failed))
assert(#failed == 0, table.concat(failed, "\n"))
