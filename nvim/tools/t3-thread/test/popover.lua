-- Mocked hc/term: real Neovim windows and local maps, no processes or threads.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local opened = 0
local facts = {}
local base = vim.api.nvim_get_current_win()
package.loaded["hcmux.core"] = {
  get = function(addr)
    return facts[addr]
  end,
}
local bufs = {}
-- Like term.lua: "float" opens a new float; nil/"current" uses the current window.
local function place(buf, where)
  if where == "float" then
    vim.api.nvim_open_win(buf, true, { relative = "editor", width = 30, height = 5, row = 0, col = 0 })
  else
    vim.api.nvim_set_current_buf(buf)
  end
end
local function open(argv, o)
  opened = opened + 1
  local addr = "test-" .. opened
  facts[addr] = { address = addr, state = "live", labels = { ["t3.thread"] = argv[3] } }
  facts[o.name] = facts[addr] -- core.get resolves names as well as addresses
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].test_addr = addr
  bufs[addr] = buf
  place(buf, o.where)
  return buf, addr
end
package.loaded["hcmux.term"] = {
  open = open,
  attach = function(addr, where)
    place(bufs[addr], where)
    return bufs[addr]
  end,
  addr_of = function(buf)
    return vim.b[buf].test_addr
  end,
}
local M = dofile("nvim/lua/hcmux/t3.lua")
M.open("throwaway")
local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.api.nvim_set_current_win(base)
vim.wait(25, function()
  return false
end)
assert(vim.api.nvim_win_is_valid(win), "leaving the float must not hide it")
M.toggle("throwaway")
assert(vim.api.nvim_get_current_win() == win, "toggle must focus the shown float")
M.toggle("throwaway")
assert(vim.api.nvim_get_current_win() == win and opened == 1, "focused toggle must do nothing")
M.open()
M.open("throwaway")
assert(opened == 1 and vim.api.nvim_win_is_valid(win), "no-arg and same-id open must not replace")
assert(vim.fn.maparg("q", "n") == "", "COMMAND q uses native macro recording")
for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "t")) do
  assert(map.lhs ~= "q", "INSERT q must remain text")
end
vim.api.nvim_feedkeys(":q\r", "mtx", false)
assert(not vim.api.nvim_win_is_valid(win), "COMMAND :q must close the float")
M.open("other")
local other = vim.api.nvim_get_current_win()
local other_buf = vim.api.nvim_get_current_buf()
M.toggle("third")
assert(vim.api.nvim_get_current_win() == other and opened == 3, "a different thread switches in the same window")
assert(vim.api.nvim_get_current_buf() ~= other_buf, "the window now shows the other client")
vim.api.nvim_set_current_win(base)
M.toggle("other")
assert(vim.api.nvim_get_current_win() == other, "switching back reuses the same window")
assert(vim.api.nvim_get_current_buf() == other_buf and opened == 3, "switching back reattaches the existing client")
assert(#vim.tbl_filter(function(w)
  return vim.api.nvim_win_get_config(w).relative ~= ""
end, vim.api.nvim_list_wins()) == 1, "only one popover window at a time")
-- INSERT <Esc>/<C-]> -> COMMAND: never a raw Esc to the client, only the private
-- "dismiss" action (6); COMMAND <C-]> -> INSERT; COMMAND <Esc> stays a no-op.
local sent, real_chansend = {}, vim.fn.chansend
vim.fn.chansend = function(job, data)
  sent[#sent + 1] = { job, data }
  return #data
end
vim.b[buf].terminal_job_id = 4242
local function local_map(mode, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if map.lhs == lhs then
      return map
    end
  end
end
for _, lhs in ipairs({ "<Esc>", "<C-]>" }) do
  sent = {}
  local map = assert(local_map("t", lhs), "INSERT " .. lhs .. " must be mapped")
  assert(map.expr == 1 and map.callback() == "<C-\\><C-N>", "INSERT " .. lhs .. " must go to COMMAND")
  assert(#sent == 1 and sent[1][1] == 4242, "INSERT " .. lhs .. " must send exactly one control to the client")
  assert(sent[1][2] == "\27[>777;6u", "INSERT " .. lhs .. " must send dismiss, got " .. vim.inspect(sent[1][2]))
  for _, s in ipairs(sent) do
    assert(s[2] ~= "\27", "INSERT " .. lhs .. " must never forward a raw Esc")
  end
end
local toggle = assert(local_map("n", "<C-]>"), "COMMAND <C-]> must be mapped")
assert(toggle.desc == "T3: INSERT mode", "COMMAND <C-]> must return to INSERT")
local esc = assert(local_map("n", "<Esc>"), "COMMAND <Esc> must be mapped")
assert(esc.rhs == "" or esc.rhs:lower() == "<nop>", "COMMAND <Esc> must stay a no-op")
vim.fn.chansend = real_chansend
print("T3 popover focus/q tests passed")
