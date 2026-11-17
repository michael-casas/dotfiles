-- Real layout, thread bar and T3 maps. No hc/feed/processes; synthetic facts only.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 120, 40
-- Geometry is covered separately; never query the real core from this map test.
vim.system = function(_, _, cb)
  assert(cb, "unexpected blocking hc call")
  vim.schedule(function()
    cb({ code = 1, stdout = "", stderr = "synthetic" })
  end)
  return {}
end
local facts, bufs, sent = {}, {}, {}
package.loaded["hcmux.core"] = {
  get = function(addr)
    return facts[addr]
  end,
  list = function()
    return {}
  end,
}
local function place(buf, where)
  if where == "float" then
    vim.api.nvim_open_win(buf, true, { relative = "editor", width = 40, height = 10, row = 0, col = 0 })
  else
    vim.api.nvim_set_current_buf(buf)
  end
end
package.loaded["hcmux.term"] = {
  addr_of = function(buf)
    return vim.b[buf].hcmux_addr
  end,
  buf_of = function(addr)
    return bufs[addr]
  end,
  attach = function(addr, where)
    place(bufs[addr], where)
    return bufs[addr]
  end,
  detach = function() end,
  open = function(_, opts)
    local addr = opts.name
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].hcmux_addr, vim.b[buf].terminal_job_id = addr, 4242
    facts[addr] = { address = addr, state = "live", labels = opts.labels }
    bufs[addr] = buf
    place(buf, opts.where)
    return buf, addr
  end,
}
vim.fn.chansend = function(_, data)
  sent[#sent + 1] = data
  return #data
end
local side = require("hcmux.t3side")
side.start = function() end
local layout = require("hcmux.layout")
layout.go("T3")
side.update({
  type = "snapshot",
  projects = { { id = "p", name = "Synthetic" } },
  threads = {
    { id = "a", projectId = "p", title = "Alpha", branch = "test", status = "idle" },
    { id = "b", projectId = "p", title = "Beta", branch = "test", status = "idle" },
  },
})
layout.open_thread("b")
local main, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
local function bar()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "envi-t3-sidebar" then
      return win
    end
  end
end
local function mapping(mode, lhs, b)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(b or buf, mode)) do
    if map.lhs == lhs then
      return map
    end
  end
  error("missing map " .. lhs)
end
local function drain()
  vim.wait(30, function()
    return false
  end)
end
local function escape()
  sent = {}
  mapping("t", "<Esc>").callback()
  local id = sent[1] and sent[1]:match("^\27%[>777;7;(%d+)u$")
  assert(id, "layout Esc must request an overlay-aware dismiss acknowledgement")
  assert(#sent == 1, "one request per Esc")
  return id
end
local function reply(id, overlay, target)
  vim.api.nvim_exec_autocmds("TermRequest", {
    buffer = target or buf,
    data = { sequence = "\27]7502;envi-t3-escape=" .. id .. ";overlay=" .. overlay .. "\27\\" },
  })
  drain()
end
local cases = {
  {
    "G1 current card, NORMAL, immediate j/k",
    function()
      vim.api.nvim_set_current_win(bar())
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_set_current_win(main)
      local id = escape()
      reply(id, "0")
      assert(vim.api.nvim_get_current_win() == bar(), "Esc focuses thread bar")
      assert(vim.fn.mode() == "n", "bar is NORMAL")
      assert(vim.api.nvim_get_current_line():find("Beta", 1, true), "current thread title, not old bar cursor")
      mapping("n", "k", side.buffer()).callback()
      assert(vim.api.nvim_get_current_line():find("Alpha", 1, true), "k moves by card immediately")
      mapping("n", "j", side.buffer()).callback()
      assert(vim.api.nvim_get_current_line():find("Beta", 1, true))
    end,
  },
  {
    "G2 overlay consumes first Esc, next goes to bar",
    function()
      vim.api.nvim_set_current_win(main)
      local id = escape()
      reply(id, "1")
      assert(vim.api.nvim_get_current_win() == main, "overlay dismissal stays in thread")
      reply(escape(), "0")
      assert(vim.api.nvim_get_current_win() == bar(), "next Esc goes to bar")
    end,
  },
  {
    "G3 hidden bar is restored",
    function()
      vim.api.nvim_set_current_win(main)
      if bar() then
        layout.sidebar_toggle()
      end
      assert(not bar())
      -- Restore for later independent compatibility cases even if this RED fails.
      local id = escape()
      reply(id, "0")
      assert(bar() and vim.api.nvim_get_current_win() == bar(), "Esc shows and focuses hidden bar")
      assert(vim.api.nvim_get_current_line():find("Beta", 1, true))
    end,
  },
  {
    "G4 shared buffer popover unchanged",
    function()
      local pop = vim.api.nvim_open_win(buf, true, { relative = "editor", width = 40, height = 10, row = 0, col = 0 })
      sent = {}
      assert(mapping("t", "<Esc>").callback() == "<C-\\><C-N>")
      assert(vim.deep_equal(sent, { "\27[>777;6u" }), "popover sends existing dismiss")
      drain()
      assert(vim.api.nvim_get_current_win() == pop)
      vim.api.nvim_win_close(pop, true)
    end,
  },
  {
    "G5 Ctrl-] remains in-place COMMAND toggle",
    function()
      vim.api.nvim_set_current_win(main)
      sent = {}
      assert(mapping("t", "<C-]>").callback() == "<C-\\><C-N>")
      assert(vim.deep_equal(sent, { "\27[>777;6u" }))
      drain()
      assert(vim.api.nvim_get_current_win() == main)
      assert(mapping("n", "<C-]>").desc == "T3: INSERT mode")
    end,
  },
  {
    "G6 Enter/o still open main",
    function()
      for _, key in ipairs({ "<CR>", "o" }) do
        if not bar() then
          layout.sidebar_toggle()
        end
        vim.api.nvim_set_current_win(assert(bar()))
        for line, text in ipairs(vim.api.nvim_buf_get_lines(side.buffer(), 0, -1, false)) do
          if text:find("Beta", 1, true) then
            vim.api.nvim_win_set_cursor(0, { line, 0 })
          end
        end
        mapping("n", key, side.buffer()).callback()
        assert(vim.api.nvim_get_current_win() == main and vim.api.nvim_get_current_buf() == buf)
      end
    end,
  },
  {
    "late, wrong-buffer and unfocused replies never steal focus",
    function()
      vim.api.nvim_set_current_win(main)
      local id = escape()
      reply(tostring(tonumber(id) + 1), "0")
      assert(vim.api.nvim_get_current_win() == main)
      reply(id, "0", side.buffer())
      assert(vim.api.nvim_get_current_win() == main)
      vim.api.nvim_set_current_win(bar())
      reply(id, "0")
      vim.api.nvim_set_current_win(main)
      reply(id, "0") -- duplicate after invalidation
      assert(vim.api.nvim_get_current_win() == main)
    end,
  },
  {
    "missing acknowledgement never guesses overlay state",
    function()
      vim.api.nvim_set_current_win(main)
      local id = escape()
      vim.wait(1200, function()
        return false
      end)
      assert(vim.api.nvim_get_current_win() == main)
      reply(id, "0")
      assert(vim.api.nvim_get_current_win() == main, "timed-out reply ignored")
      assert(sent[#sent] == "\27[>777;6u", "old client still receives legacy dismiss on timeout")
    end,
  },
}
local failures = {}
for _, case in ipairs(cases) do
  local ok, err = pcall(case[2])
  print((ok and "PASS " or "FAIL ") .. case[1])
  if not ok then
    failures[#failures + 1] = case[1] .. ": " .. tostring(err)
  end
end
assert(#failures == 0, table.concat(failures, "\n"))
print("T3 Esc-to-bar: " .. #cases .. " cases passed")
