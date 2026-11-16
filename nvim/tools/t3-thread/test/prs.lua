vim.env.ENVI_PR_NO_BROWSER = "1"
vim.env.ENVI_PR_DRY_RUN = "1"
-- Public PR API + real Neovim windows; fake executable boundaries, no real reviews/terminals.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 160, 45
vim.env.ENVI_PR_DRY_RUN = "1"
local temp, original_path = vim.fn.tempname(), vim.env.PATH
vim.env.XDG_CACHE_HOME = temp .. "/cache"
vim.fn.mkdir(temp, "p")
vim.env.PRS_LOG, vim.env.PRS_APPLIED = temp .. "/calls", temp .. "/applied"
local fake = vim.fn.getcwd() .. "/nvim/tools/t3-thread/test/fixtures/prs-tools.py"
for _, name in ipairs({ "gh", "git", "hunk", "hc" }) do
  vim.fn.writefile(
    { "#!/bin/sh", "exec python3 " .. vim.fn.shellescape(fake) .. " " .. name .. ' "$@"' },
    temp .. "/" .. name
  )
  vim.fn.setfperm(temp .. "/" .. name, "rwx------")
end
vim.env.PATH = temp .. ":" .. original_path
local notes = {
  { noteId = "one", source = "user", filePath = "a.lua", body = "Fix this", newRange = { 1, 1 } },
  { noteId = "two", source = "user", filePath = "a.lua", body = "Old lines", oldRange = { 2, 4 } },
}
vim.env.PRS_NOTES = vim.json.encode(notes)
package.loaded["hcmux.session"] = { root = temp }
package.loaded["hcmux.t3side"] = {
  snapshot = function()
    return { projects = {} }
  end,
  presentation = {
    age = function()
      return "2h"
    end,
    clean = function(s)
      return tostring(s or ""):gsub("[%c]", " ")
    end,
    truncate = function(s, w)
      return vim.fn.strcharpart(s, 0, math.max(0, w))
    end,
    highlights = function() end,
  },
}
local opens, kills, notifications, clipboard = {}, {}, {}, nil
vim.notify = function(msg)
  notifications[#notifications + 1] = msg
end
vim.fn.setreg = function(_, value)
  clipboard = value
end
package.loaded["hcmux.term"] = {
  open = function(argv, opts)
    opens[#opens + 1] = { argv = argv, opts = opts }
    for _, arg in ipairs(argv) do
      local marker = arg:match("^TERM_SESSION_ID=(.+)$")
      if marker then
        vim.env.PRS_MARKER = marker
      end
    end
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_open_win(
      b,
      true,
      { relative = "editor", row = 1, col = 1, width = 80, height = 20, style = "minimal" }
    )
    vim.b[b].hcmux_addr = "our-terminal-" .. #opens
    return b, vim.b[b].hcmux_addr
  end,
  kill = function(addr)
    kills[#kills + 1] = addr
  end,
}
-- Never reach a real browser: record what would open instead.
local opened = {}
vim.ui.open = function(url)
  opened[#opened + 1] = url
end
local prs = require("hcmux.prs")
local function wait(fn)
  local ok = vim.wait(6000, fn, 10)
  if not ok then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      print(vim.bo[b].filetype, table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "|"))
    end
    print(vim.inspect(notifications))
    print(calltext and calltext() or "")
  end
  assert(ok, "condition reached")
end
local function key(lhs, mode)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, mode or "n")) do
    if m.lhs == lhs then
      m.callback()
      return
    end
  end
  error("missing mapping " .. lhs .. " in " .. vim.bo.filetype)
end
local function text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end
local function calltext()
  return table.concat(vim.fn.readfile(vim.env.PRS_LOG), "\n")
end
local baseline = #vim.api.nvim_list_wins()
prs.open({ repo = "acme/repo" })
local board = vim.api.nvim_get_current_win()
wait(function()
  return text():find("Fix build 2", 1, true)
end)
assert(prs.active and #vim.api.nvim_list_wins() == baseline + 3, "wide detail pane")
assert(text():find("✓ 1", 1, true) and text():find("✗ 1", 1, true) and text():find("DRAFT"))
key("y")
assert(clipboard == "https://github.com/acme/repo/pull/2")
key("o")
assert(not calltext():find("%-%-web"), "NO_BROWSER prevents even fake gh --web dispatch")
assert(table.concat(notifications, " "):find("Browser suppressed", 1, true), "guard notifies")
key("?")
assert(text():find("Discard") and text():find("<C%-q>"))
key("q")
assert(vim.api.nvim_get_current_win() == board)
key("c")
assert(text():find("unit"))
key("<CR>")
assert(#opened == 0, "NO_BROWSER suppresses checks before vim.ui.open (also stubbed)")
assert(table.concat(notifications, " "):find("actions/runs/1", 1, true), "suppressed check URL notified")
key("q")
key("<Tab>")
wait(function()
  return text():find("Review %[3%]")
end)
key("<S-Tab>")
key("/")
assert(vim.b.completion == false and vim.b.minipairs_disable)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Zbr" })
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = 0 })
key("<Esc>", "i")
assert(text():find("Zebra") and not text():find("Fix build 2", 1, true), "fuzzy filter")
key("<CR>") -- launch top hit
wait(function()
  return #opens == 1
end)
assert(opens[1].opts.where == "float" and opens[1].opts.session == false and opens[1].opts.listed == false)
assert(
  table.concat(opens[1].argv, " "):find("hunk patch", 1, true)
    and table.concat(opens[1].argv, " "):find("%-%-theme nord")
)
local hunk_buf = vim.api.nvim_get_current_buf()
assert(
  vim.api.nvim_win_get_config(0).zindex > vim.api.nvim_win_get_config(board).zindex,
  "a new hunk float is drawn above the board"
)
wait(function()
  return vim.fn.filereadable(vim.fn.stdpath("cache") .. "/envi-pr/acme-repo-3.comments.json") == 1
end)
key("<C-Q>", "t")
assert(vim.api.nvim_get_current_win() == board and text():find("◉ hunk", 1, true) and text():find("✎ 2", 1, true))
key("<CR>")
assert(#opens == 1 and vim.api.nvim_get_current_buf() == hunk_buf, "same hunk re-shown")
key("<C-Q>", "t")
wait(function()
  return vim.fn.getfsize(vim.env.PRS_APPLIED) > 2
end)
local applied = vim.json.decode(table.concat(vim.fn.readfile(vim.env.PRS_APPLIED), "\n"))
assert(
  #applied.comments == 1 and applied.comments[1].newLine == 1 and applied.comments[1].author == "bob",
  "only current GitHub anchors imported"
)
key("s")
wait(function()
  return vim.bo.filetype == "envi-pr-confirm"
end)
key("<Esc>")
assert(vim.fn.filereadable(vim.fn.stdpath("cache") .. "/envi-pr/last-review.json") == 0, "Esc never submits")
for _, pair in ipairs({ { "c", "COMMENT" }, { "a", "APPROVE" }, { "r", "REQUEST_CHANGES" } }) do
  key("s")
  wait(function()
    return vim.bo.filetype == "envi-pr-confirm"
  end)
  key(pair[1])
  wait(function()
    return vim.bo.filetype == "envi-prs"
  end)
  local payload =
    vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath("cache") .. "/envi-pr/last-review.json"), "\n"))
  assert(payload.event == pair[2] and payload.commit_id == "head")
  assert(payload.comments[1].side == "RIGHT" and payload.comments[1].line == 1)
  assert(payload.comments[2].side == "LEFT" and payload.comments[2].start_line == 2 and payload.comments[2].line == 4)
end
key("s")
wait(function()
  return vim.bo.filetype == "envi-pr-confirm"
end)
vim.env.PRS_HEAD = "moved-at-confirm"
key("a")
wait(function()
  return vim.bo.filetype == "envi-prs"
end)
vim.env.PRS_HEAD = nil
assert(table.concat(notifications, " "):find("PR moved", 1, true), "head rechecked after confirmation")
-- Dry-run preserves the session/drafts, because nothing was actually submitted.
assert(#kills == 0)
vim.env.PRS_HEAD = "moved"
key("s")
wait(function()
  return table.concat(notifications, " "):find("PR moved", 1, true)
end)
assert(vim.bo.filetype == "envi-prs")
vim.env.PRS_HEAD = nil
vim.env.PRS_NOTES = vim.json.encode({
  { source = "user", noteId = "bad", filePath = "a.lua", body = "ambiguous", oldRange = { 1, 1 }, newRange = { 1, 1 } },
})
key("s")
wait(function()
  return vim.bo.filetype == "envi-pr-confirm"
end)
assert(text():find("ambiguous") and text():find("refused"))
key("a")
assert(vim.bo.filetype == "envi-pr-confirm")
key("<Esc>")
vim.env.PRS_NOTES = vim.json.encode(notes)
key("s")
wait(function()
  return vim.bo.filetype == "envi-pr-confirm"
end)
key("<Esc>")
vim.env.PRS_EXIT = "1"
wait(function()
  return not text():find("◉ hunk", 1, true)
end)
key("s")
wait(function()
  return vim.bo.filetype == "envi-pr-confirm"
end)
assert(text():find("hunk closed; using comments captured at", 1, true))
key("<Esc>")
key("x")
wait(function()
  return vim.bo.filetype == "envi-pr-confirm"
end)
assert(text():find("Discard 2 drafted"))
key("n")
assert(#kills == 0)
key("x")
wait(function()
  return vim.bo.filetype == "envi-pr-confirm"
end)
key("y")
assert(#kills == 1)
vim.env.PRS_EXIT = nil
key("q")
assert(not prs.active and #vim.api.nvim_list_wins() == baseline, "no float leaks")
vim.o.columns = 100
prs.open({ repo = "acme/repo" })
wait(function()
  return text():find("Zebra", 1, true)
end)
assert(#vim.api.nvim_list_wins() == baseline + 2)
key("K")
assert(vim.bo.filetype == "markdown")
key("q")
vim.env.PRS_LOCAL = "1"
key("<CR>")
wait(function()
  return #opens == 2
end)
assert(table.concat(opens[2].argv, " "):find("hunk diff mergebase head", 1, true) and opens[2].opts.cwd == temp)
key("<C-Q>", "t")
key("q")
assert(not prs.active)
prs.open({ repo = "acme/repo" })
wait(function()
  return text():find("◉ hunk", 1, true)
end)
key("q")
vim.api.nvim_exec_autocmds("VimLeavePre", {})
assert(#kills == 1 and calltext():find('"args": ["kill", "our-terminal-2"]', 1, true), "shutdown only owned hunks")
assert(#vim.api.nvim_list_wins() == baseline)
print("prs: UI, hunk lifecycle, submit, ownership checks passed")
