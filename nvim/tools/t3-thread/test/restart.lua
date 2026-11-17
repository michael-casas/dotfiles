-- Read-only/unit harness: no hc process is called and no real terminal is killed.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local killed, opened = {}, {}
local fact
local fail
package.loaded["hcmux.core"] = {
  get = function()
    return fact
  end,
  terms = {},
  exec = function(args)
    killed[#killed + 1] = args
    if fail == args[1] then
      return nil, "test refusal"
    end
    return "{}"
  end,
}
package.loaded["hcmux.term"] = {
  addr_of = function()
    return "test-terminal"
  end,
  buf_of = function()
    return nil
  end,
  open = function(argv, options)
    opened[#opened + 1] = { argv = argv, options = options }
    return nil, "fresh-terminal"
  end,
}
local notices = {}
vim.notify = function(text)
  notices[#notices + 1] = text
end
local main = vim.fn.getcwd() .. "/nvim/tools/t3-thread/main.mjs"
local M = dofile("nvim/lua/hcmux/t3.lua")
local function show()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].hcmux_float = "t3"
  vim.api.nvim_open_win(buf, true, { relative = "editor", width = 30, height = 5, row = 0, col = 0 })
end
local function reset(value)
  fact = value
  killed, opened = {}, {}
  fail = nil
end
local valid = {
  address = "test-terminal",
  cwd = "/tmp",
  name = "test",
  labels = { ["t3.thread"] = "throwaway" },
  argv = { "node", main, "throwaway" },
}
for _, value in ipairs({
  { address = "other", labels = {} },
  { address = "other", labels = { ["t3.thread"] = "different" }, argv = valid.argv },
  { address = "other", labels = valid.labels, argv = { "node", "/another/main.mjs", "throwaway" } },
}) do
  reset(value)
  show()
  M.restart()
  assert(#killed == 0 and #opened == 0, "unverified terminal must never be killed")
end
reset(valid)
fail = "kill"
M.restart()
assert(#killed == 1 and #opened == 0, "failed kill must not create a second client")
reset(valid)
fail = "rm"
M.restart()
assert(#opened == 0, "failed removal must not launch a replacement")
reset(valid)
show()
M.restart()
assert(killed[1][1] == "kill" and killed[1][2] == "test-terminal")
assert(killed[2][1] == "rm")
assert(#opened == 1 and opened[1].argv[3] == "throwaway")
assert(opened[1].options.labels["t3.thread"] == "throwaway")
assert(opened[1].options.cwd == "/tmp")
-- The last client may also be restarted while hidden; verification still applies.
reset(valid)
for _, win in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    vim.api.nvim_win_close(win, true)
  end
end
M.restart()
assert(#opened == 1, "hidden last client must restart with the same checks")
print("T3Restart safety tests passed")
