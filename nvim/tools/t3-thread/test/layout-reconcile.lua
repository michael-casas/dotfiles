-- Real Neovim windows/layout + controlled asynchronous hc/PTY/action-9 peers.
-- Synthetic facts only: never contacts hc, T3, a desktop or another viewer.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.o.columns, vim.o.lines = 120, 40
local facts, bufs, reads, sent, resized, notices = {}, {}, {}, {}, {}, {}
local callbacks, timers = {}, {}
local pty = { cols = 1, rows = 1 }
local converge, hold, answer, reflowed = true, false, true, 1
local real_defer = vim.defer_fn
vim.defer_fn = function(fn, ms)
  timers[#timers + 1] = ms
  return real_defer(fn, ms)
end
vim.notify = function(message)
  notices[#notices + 1] = message
end
vim.system = function(argv, opts, cb)
  assert(vim.deep_equal(argv, { "hc", "get", vim.b.hcmux_addr, "--json" }), "only current viewer hc get")
  assert(opts.text and opts.timeout and cb, "bounded asynchronous read, no :wait")
  reads[#reads + 1] = vim.deepcopy(pty)
  local function finish()
    cb({ code = 0, stdout = vim.json.encode(pty), stderr = "" })
  end
  if hold then
    callbacks[#callbacks + 1] = finish
  else
    vim.schedule(finish)
  end
  return {
    wait = function()
      error("UI must never wait for hc")
    end,
  }
end
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
    vim.api.nvim_open_win(
      buf,
      true,
      { relative = "editor", width = 50, height = 12, row = 1, col = 1, style = "minimal" }
    )
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
  detach = function() end,
  -- Fresh replay is covered by layout-rebuild; this seam keeps window identity.
  reattach = function()
    return nil
  end,
  attach = function(addr, where)
    place(bufs[addr], where)
    return bufs[addr]
  end,
  open = function(_, opts)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].hcmux_addr, vim.b[buf].terminal_job_id = opts.name, 4242
    facts[opts.name] = { address = opts.name, state = "live", labels = opts.labels }
    bufs[opts.name] = buf
    place(buf, opts.where)
    return buf, opts.name
  end,
}
vim.fn.jobresize = function(job, cols, rows)
  assert(job == 4242)
  resized[#resized + 1] = { cols = cols, rows = rows }
  if converge then
    pty = { cols = cols, rows = rows }
  end
  return 1
end
local function reply(buf, id, cols, rows, suffix)
  vim.api.nvim_exec_autocmds("TermRequest", {
    buffer = buf,
    data = {
      sequence = ("\27]7503;envi-t3-layout=%s;cols=%d;rows=%d;frozen=60;reflowed=%d%s"):format(
        id,
        cols,
        rows,
        reflowed,
        suffix or ""
      ),
    },
  })
end
vim.fn.chansend = function(job, data)
  assert(job == 4242)
  local id = data:match("^\27%[>777;9;(%d+)u$")
  if id then
    sent[#sent + 1] = { id = id, win = vim.api.nvim_get_current_win(), buf = vim.api.nvim_get_current_buf() }
    if answer then
      local buf, cols, rows =
        vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_width(0), vim.api.nvim_win_get_height(0)
      vim.schedule(function()
        reply(buf, id, cols, rows)
      end) -- actual stripped terminator contract
    end
  end
  return #data
end
local side = require("hcmux.t3side")
side.start = function() end
local layout, t3 = require("hcmux.layout"), require("hcmux.t3")
t3.setup()
local function drain(ms)
  vim.wait(ms or 350, function()
    return false
  end, 10)
end
local function reset()
  drain(180)
  reads, sent, resized, notices, timers = {}, {}, {}, {}, {}
  callbacks = {}
  converge, hold, answer, reflowed = true, false, true, 1
end
local function size()
  return { cols = vim.api.nvim_win_get_width(0), rows = vim.api.nvim_win_get_height(0) }
end
layout.go("T3")
local bar = vim.api.nvim_get_current_win()
layout.open_thread("synthetic")
local main, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
local cases = {
  {
    "H2.1 attach settles once, resends exact geometry and confirms asynchronously",
    function()
      assert(#reads == 0, "attach read must be debounced")
      drain()
      assert(#reads == 2 and #resized == 1 and #sent == 1, "attach must read, resize, re-read, then action 9")
      assert(vim.deep_equal(resized[1], size()), "real width/height only")
      assert(#notices == 0, "automatic checks stay quiet")
    end,
  },
  {
    "H2.1 sidebar hide/show and VimResized coalesce at final geometry",
    function()
      reset()
      layout.sidebar_toggle()
      layout.sidebar_toggle()
      layout.sidebar_toggle()
      vim.api.nvim_exec_autocmds("VimResized", {})
      drain()
      assert(#sent == 1 and #resized == 1 and vim.deep_equal(resized[1], size()), "one final-size check")
      reset()
      layout.sidebar_toggle()
      drain()
      assert(#sent == 1 and #resized == 1 and vim.deep_equal(resized[1], size()), "show bar checks too")
    end,
  },
  {
    "H2.1 WinResized T3 window checks without layout role flag",
    function()
      reset()
      local prior = vim.api.nvim_get_autocmds({ event = "WinResized" })
      local checked = false
      for _, a in ipairs(prior) do
        if a.group_name == "hcmux.t3.layout" then
          checked = true
          -- Actual v:event is populated by Neovim, not writable. No windows means a conservative current-view check.
          a.callback({ event = "WinResized" })
        end
      end
      drain()
      assert(checked and #sent == 1, "resize handler checks a marked T3 buffer")
    end,
  },
  {
    "H2.2 stale async read and background same-client window never resize",
    function()
      reset()
      hold = true
      pty = { cols = 1, rows = 1 }
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "envi-t3-sidebar" then
          bar = win
        end
      end
      vim.api.nvim_exec_autocmds("VimResized", {})
      drain(180)
      assert(#callbacks == 1, "async read in flight")
      vim.api.nvim_set_current_win(bar)
      for _, fn in ipairs(callbacks) do
        fn()
      end
      drain()
      assert(#resized == 0 and #sent == 0, "leave invalidates queued callback")
      vim.api.nvim_set_current_win(main)
      hold = false
      drain()
      assert(#resized == 1 and #sent == 1, "most recently focused viewer wins")
      reset()
      local pop = vim.api.nvim_open_win(
        buf,
        true,
        { relative = "editor", width = 50, height = 12, row = 1, col = 1, style = "minimal" }
      )
      drain()
      assert(#sent == 1 and #resized == 1 and resized[1].cols == 50, "focused popover owns width")
      reset()
      vim.api.nvim_set_current_win(main)
      drain()
      assert(#sent == 1 and #resized == 1 and vim.deep_equal(resized[1], size()), "focus transfers ownership")
      vim.api.nvim_win_close(pop, true)
    end,
  },
  {
    "H2.3 old client still gets PTY repair, one silent timeout and no polling",
    function()
      reset()
      answer = false
      pty = { cols = 1, rows = 1 }
      vim.api.nvim_exec_autocmds("VimResized", {})
      drain(1450)
      assert(#resized == 1 and #sent == 1 and #notices == 0, "old client repair is silent")
      local count = #reads
      drain(1250)
      assert(#reads == count and #sent == 1, "no repeat check/restart")
    end,
  },
  {
    "H2.4 manual command immediately checks and notifies once with reflow",
    function()
      reset()
      pty = { cols = 60, rows = 20 }
      vim.cmd("T3Recenter")
      assert(#reads == 1, "manual read immediate, not debounce")
      drain()
      assert(
        #notices == 1
          and notices[1]:find("re%-applied")
          and notices[1]:find("was 60×20", 1, true)
          and notices[1]:find("client reflowed", 1, true),
        "one useful result"
      )
      reset()
      answer = false
      vim.cmd("T3Recenter")
      drain(1200)
      assert(
        #notices == 1 and notices[1]:find("client did not answer (older client)", 1, true),
        "manual old-client result"
      )
    end,
  },
  {
    "H2.5 bounded failure, no fake widths, reply correlation and debug-only mismatch",
    function()
      reset()
      converge = false
      answer = false
      pty = { cols = 1, rows = 1 }
      vim.cmd("T3Recenter")
      drain()
      assert(#reads == 3 and #resized == 2 and #sent == 1, "at most two repair attempts")
      for _, s in ipairs(resized) do
        assert(vim.deep_equal(s, size()), "never fake width")
      end
      local request = sent[1]
      reply(buf, tonumber(request.id) + 1, 1, 1)
      drain(20)
      reply(side.buffer(), request.id, 1, 1)
      drain(20)
      assert(#notices == 0, "wrong id/buffer ignored")
      reply(buf, request.id, 1, 1, "\27\\")
      drain(20)
      assert(#notices == 1 and notices[1]:find("mismatch", 1, true), "manual mismatch isn't false ok")
      local path = vim.fn.stdpath("state") .. "/hcmux/t3-layout.log"
      assert(
        vim.fn.filereadable(path) == 1 and table.concat(vim.fn.readfile(path), "\n"):find("client cols=1", 1, true),
        "client mismatch logged"
      )
      drain(1200)
      assert(#reads == 4 and #notices == 1, "one final handoff read, reply and timeout cannot repeat result")
    end,
  },
}
cases[#cases + 1] = {
  "H2 focus handoff confirms core size after action 9",
  function()
    reset()
    converge, pty = false, { cols = 1, rows = 1 }
    local send = vim.fn.chansend
    vim.fn.chansend = function(job, data)
      if data:match("^\27%[>777;9;") then
        pty = size()
      end
      return send(job, data)
    end
    vim.cmd("T3Recenter")
    drain()
    vim.fn.chansend = send
    assert(
      #notices == 1 and notices[1]:find("re%-applied") and not notices[1]:find("mismatch", 1, true),
      "last-input ownership handoff must not report stale pre-action9 mismatch"
    )
  end,
}
cases[#cases + 1] = {
  "H2 leave invalidates replies even after returning to the same window",
  function()
    reset()
    answer = false
    vim.cmd("T3Recenter")
    drain(50)
    local old = assert(sent[1])
    vim.api.nvim_set_current_win(bar)
    vim.api.nvim_set_current_win(main)
    reply(buf, old.id, size().cols, size().rows, "\7")
    drain(20)
    assert(#notices == 0, "replayed acknowledgement cannot revive a departed manual invocation")
    drain(150)
    local fresh = sent[#sent]
    assert(fresh.id ~= old.id, "focus return has fresh request identity")
    reply(buf, fresh.id, size().cols, size().rows, "\7")
    drain(20)
    assert(#notices == 0, "automatic focus check stays quiet")
  end,
}
cases[#cases + 1] = {
  "H2 failed core read degrades safely and cannot report false PTY ok",
  function()
    reset()
    local system = vim.system
    vim.system = function(_, _, cb)
      vim.schedule(function()
        cb({ code = 0, stdout = "not JSON" })
      end)
      return {}
    end
    vim.cmd("T3Recenter")
    drain(50)
    vim.system = system
    assert(
      #resized == 0 and #sent == 1 and #notices == 1 and notices[1]:find("PTY size unavailable", 1, true),
      "invalid fact never causes invented geometry or false ok"
    )
  end,
}
cases[#cases + 1] = {
  "H2 unfocused editor cannot reclaim ownership on geometry events",
  function()
    reset()
    pty = { cols = 1, rows = 1 }
    vim.api.nvim_exec_autocmds("FocusLost", {})
    vim.api.nvim_exec_autocmds("VimResized", {})
    drain()
    assert(#reads == 0 and #resized == 0 and #sent == 0, "background editor is not a controlling viewer")
    vim.api.nvim_exec_autocmds("FocusGained", {})
    drain()
    assert(#resized == 1 and #sent == 1, "editor focus gain reclaims current viewer")
  end,
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
print("T3 layout reconcile: " .. #cases .. " cases passed")
