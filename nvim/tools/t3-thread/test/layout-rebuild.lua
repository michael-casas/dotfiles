-- Scenario 7: real windows/layout/maps, synthetic attach and OSC peers only.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 120, 40
local facts, bufs, attaches, sent, notices = {}, {}, 0, {}, {}
local answer = true
vim.notify = function(message)
  notices[#notices + 1] = message
end
vim.system = function(_, _, cb)
  assert(cb)
  local s = { cols = vim.api.nvim_win_get_width(0), rows = vim.api.nvim_win_get_height(0) }
  vim.schedule(function()
    cb({ code = 0, stdout = vim.json.encode(s) })
  end)
  return {}
end
local function fresh(addr)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].hcmux_addr, vim.b[buf].terminal_job_id = addr, 4242
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "NEW_HISTORY" })
  bufs[addr] = buf
  return buf
end
package.loaded["hcmux.core"] = {
  get = function(addr)
    return facts[addr]
  end,
  list = function()
    return {}
  end,
}
package.loaded["hcmux.term"] = {
  addr_of = function(buf)
    return vim.b[buf].hcmux_addr
  end,
  buf_of = function(addr)
    return bufs[addr]
  end,
  detach = function()
    error("never close a window or kill client")
  end,
  attach = function(addr, where)
    local buf = bufs[addr]
    if where == "float" then
      vim.api.nvim_open_win(
        buf,
        true,
        { relative = "editor", width = 50, height = 12, row = 1, col = 1, style = "minimal" }
      )
    else
      vim.api.nvim_set_current_buf(buf)
    end
    return buf
  end,
  reattach = function(win)
    assert(win == vim.api.nvim_get_current_win(), "never reattach background window")
    attaches = attaches + 1
    local old = vim.api.nvim_win_get_buf(win)
    local buf = fresh(vim.b[old].hcmux_addr)
    vim.api.nvim_win_set_buf(win, buf)
    if #vim.fn.win_findbuf(old) == 0 then
      vim.api.nvim_buf_delete(old, { force = true })
    end
    return buf
  end,
  open = function(_, o)
    facts[o.name] = { address = o.name, state = "live", labels = o.labels }
    local buf = fresh(o.name)
    vim.api.nvim_set_current_buf(buf)
    return buf, o.name
  end,
}
vim.fn.chansend = function(_, bytes)
  sent[#sent + 1] = bytes
  local id = bytes:match("^\27%[>777;9;(%d+)u$")
  if answer and id then
    local buf = vim.api.nvim_get_current_buf()
    local cols, rows = vim.api.nvim_win_get_width(0), vim.api.nvim_win_get_height(0)
    vim.schedule(function()
      vim.api.nvim_exec_autocmds("TermRequest", {
        buffer = buf,
        data = {
          sequence = ("\27]7503;envi-t3-layout=%s;cols=%d;rows=%d;frozen=%d;reflowed=0"):format(id, cols, rows, cols),
        },
      })
    end)
  end
  return #bytes
end
local t3 = require("hcmux.t3")
t3.setup()
local side = require("hcmux.t3side")
side.start = function() end
local layout = require("hcmux.layout")
layout.go("T3")
side.update({
  type = "snapshot",
  projects = { { id = "p", name = "Synthetic" } },
  threads = {
    { id = "synthetic", projectId = "p", title = "Synthetic", status = "idle" },
  },
})
layout.open_thread("synthetic")
local main, original = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
local function drain(ms)
  vim.wait(ms or 280, function()
    return false
  end, 10)
end
local function reply(buf, id, reflowed)
  vim.api.nvim_exec_autocmds("TermRequest", {
    buffer = buf,
    data = {
      sequence = ("\27]7503;envi-t3-layout=%d;cols=%d;rows=%d;frozen=60;reflowed=%d"):format(
        id,
        vim.api.nvim_win_get_width(0),
        vim.api.nvim_win_get_height(0),
        reflowed or 1
      ),
    },
  })
end
local function map(buf, mode, key)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhs == key then
      return m
    end
  end
  error("missing map " .. key)
end
local cases = {
  {
    "H2.7 unsolicited rebuild coalesces and replaces current viewer, keeping layout and COMMAND",
    function()
      drain()
      vim.cmd.stopinsert()
      local title = vim.wo[main].winbar
      reply(original, 0)
      reply(original, 0)
      reply(original, 0)
      assert(attaches == 0, "refresh is debounced")
      drain()
      local buf = vim.api.nvim_win_get_buf(main)
      assert(attaches == 1 and buf ~= original, "one fresh terminal for burst")
      assert(vim.b[buf].hcmux_addr == "t3-synthetic" and vim.b[buf].hcmux_float == "t3", "same core and mark")
      assert(
        vim.w[main].envi_t3_main
          and vim.wo[main].winbar == title
          and not vim.wo[main].number
          and vim.wo[main].signcolumn == "no",
        "window role, title and gutters persist"
      )
      assert(vim.fn.mode() == "n" and not vim.api.nvim_buf_is_valid(original), "COMMAND retained and old viewer wiped")
      map(buf, "n", "<C-]>")
      map(buf, "t", "<Esc>")
    end,
  },
  {
    "H2.7 stale shared-buffer background split waits for entry and preserves bar selection",
    function()
      local buf = vim.api.nvim_win_get_buf(main)
      local pop = vim.api.nvim_open_win(
        buf,
        true,
        { relative = "editor", width = 50, height = 12, row = 1, col = 1, style = "minimal" }
      )
      drain()
      local before = attaches
      reply(buf, 0)
      drain()
      assert(
        attaches == before + 1 and vim.api.nvim_win_get_buf(pop) ~= buf and vim.api.nvim_win_get_buf(main) == buf,
        "only current popover reattaches"
      )
      vim.api.nvim_set_current_win(main)
      drain()
      assert(attaches == before + 2 and vim.api.nvim_win_get_buf(main) ~= buf, "stale main refreshes on enter")
      assert(vim.api.nvim_win_is_valid(pop), "popover stays open")
      local current = vim.api.nvim_get_current_buf()
      sent = {}
      map(current, "t", "<Esc>").callback()
      local id = assert(sent[1]:match("^\27%[>777;7;(%d+)u$"), "fresh buffer action 7")
      vim.api.nvim_exec_autocmds(
        "TermRequest",
        { buffer = current, data = { sequence = "\27]7502;envi-t3-escape=" .. id .. ";overlay=0" } }
      )
      drain()
      assert(
        vim.bo.filetype == "envi-t3-sidebar" and vim.api.nvim_get_current_line():find("Synthetic", 1, true),
        "Esc selects same thread"
      )
      vim.api.nvim_win_close(pop, true)
      vim.api.nvim_set_current_win(main)
    end,
  },
  {
    "H2.7 hidden stale buffer waits, wrong solicited ids and no-reflow never reattach",
    function()
      drain()
      local buf, before = vim.api.nvim_get_current_buf(), attaches
      reply(buf, 123456789)
      reply(buf, 0, 0)
      drain()
      assert(attaches == before, "uncorrelated/no-reflow replies ignored")
      local scratch = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(scratch)
      reply(buf, 0)
      drain()
      assert(attaches == before and vim.api.nvim_get_current_buf() == scratch, "hidden view never reattaches")
      vim.api.nvim_set_current_buf(buf)
      drain()
      assert(attaches == before + 1 and vim.api.nvim_get_current_buf() ~= buf, "BufWinEnter refresh")
    end,
  },
  {
    "H2.7 solicited reflow refreshes once after successful correlation",
    function()
      local before = attaches
      sent = {}
      answer = false
      vim.cmd("T3Recenter")
      drain(30)
      local id
      for _, bytes in ipairs(sent) do
        id = id or tonumber(bytes:match("^\27%[>777;9;(%d+)u$"))
      end
      assert(id)
      answer = true -- the fresh viewer's ownership confirmation answers normally
      reply(vim.api.nvim_get_current_buf(), id)
      drain()
      assert(attaches == before + 1, "matching solicited rebuild reattaches")
      answer = true
    end,
  },
  {
    "H2.r1 real later same-width rebuild still refreshes and burst coalesces during check",
    function()
      drain()
      local before, buf = attaches, vim.api.nvim_get_current_buf()
      reply(buf, 0)
      reply(buf, 0)
      drain()
      assert(attaches == before + 1, "same-width rebuild after settle is not suppressed")
      buf = vim.api.nvim_get_current_buf()
      require("hcmux.t3layout").settle()
      reply(buf, 0)
      vim.defer_fn(function()
        reply(buf, 0)
      end, 80)
      drain(450)
      assert(attaches == before + 2, "settle and overlapping stale signals replay once")
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
print("T3 stale-viewer rebuild: " .. #cases .. " cases passed")
