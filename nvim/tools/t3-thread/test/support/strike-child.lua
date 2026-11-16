-- Loaded inside an embedded child Neovim (nvim --embed with an RGB UI) by
-- test/scrollback-strikes.lua. Real hcmux.t3/term/core/agent modules; every
-- external process is substituted: `hc connect` RPCs are answered in memory
-- and `hc attach <addr>` runs test/support/fake-viewer.mjs on a real PTY in
-- the real popover window. No hc, no T3 server, no real thread.
return function(root, o)
  vim.opt.rtp:prepend(root .. "/nvim")
  vim.g.mapleader = " "
  vim.o.termguicolors = true
  vim.o.laststatus, vim.o.showtabline, vim.o.cmdheight = 0, 0, 1
  vim.api.nvim_set_hl(0, "Normal", { fg = o.normal_fg, bg = o.normal_bg })
  vim.api.nvim_set_hl(0, "Cursor", { fg = o.normal_bg, bg = o.cursor })
  -- The fixture project the AGENT board fills its slots from (as test/agent.lua).
  package.loaded["hcmux.session"] = { name = "strike-test", root = "/projects/project-3" }
  package.loaded["lualine"] = { refresh = function() end }

  local H = { runs = {}, facts = {}, docs = {}, attaches = {}, jobs = {} }
  _G.STRIKE = H
  local viewer = root .. "/nvim/tools/t3-thread/test/support/fake-viewer.mjs"

  local core = require("hcmux.core")
  core.available = function()
    return true
  end
  core.get = function(addr)
    return H.facts[addr]
  end
  core.list = function(filter)
    local ret = {}
    for key, fact in pairs(H.facts) do
      if key == fact.address and (not filter or filter(fact)) then
        ret[#ret + 1] = fact
      end
    end
    return ret
  end
  core.doc_get = function(name)
    local d = H.docs[name]
    return d and vim.deepcopy(d.value), d and d.version or 0
  end
  core.doc_set = function(name, value, version)
    H.docs[name] = { value = vim.deepcopy(value), version = (version or 0) + 1 }
    return H.docs[name].version
  end
  core.exec = function()
    return true
  end
  core.exec_async = function() end

  vim.system = function(argv, opts)
    assert(argv[1] == "hc" and argv[2] == "connect", "unexpected process " .. table.concat(argv, " "))
    local rpc = vim.json.decode(opts.stdin)
    local reply
    if rpc.method == "terminal.run" then
      local n = #H.runs + 1
      local thread = rpc.params.labels and rpc.params.labels["t3.thread"]
      local fact = {
        address = "synthetic-" .. n,
        state = "live",
        name = rpc.params.name,
        labels = rpc.params.labels,
        argv = rpc.params.argv,
        cwd = rpc.params.cwd,
        params = rpc.params,
        marker = (thread and thread ~= "") and thread:gsub("[^%w]", "") or ("ORD" .. n),
      }
      H.runs[n] = fact
      H.facts[fact.address] = fact
      if fact.name then
        H.facts[fact.name] = fact
      end
      reply = { jsonrpc = "2.0", id = 1, result = { address = fact.address } }
    else
      reply = { jsonrpc = "2.0", id = 1, error = { message = "unsupported " .. rpc.method } }
    end
    local res = { code = 0, stderr = "", stdout = vim.json.encode(reply) .. "\n" }
    return {
      wait = function()
        return res
      end,
    }
  end

  local jobstart, jobstop = vim.fn.jobstart, vim.fn.jobstop
  local fake_jobs = 0
  vim.fn.jobstart = function(argv, opts)
    -- term.lua runs the viewer behind a small `sh -c` prelude; find `hc attach`.
    local at = type(argv) == "table"
      and vim.iter(ipairs(argv)):find(function(i, a)
        return a == "hc" and argv[i + 1] == "attach"
      end)
    if at then
      local fact = assert(H.facts[argv[#argv]], "attach to an unknown terminal")
      H.attaches[fact.address] = (H.attaches[fact.address] or 0) + 1
      opts = vim.tbl_extend("force", opts or {}, {
        env = {
          FAKE_MARKER = fact.marker,
          FAKE_RUN_BG = fact.params.display and fact.params.display.bg or "",
          FAKE_CODE_BG = o.code_bg,
          FAKE_BUBBLE_BG = o.bubble_bg,
          FAKE_LOG = o.logdir .. "/" .. fact.marker .. ".log",
        },
      })
      local job = jobstart({ "node", viewer }, opts)
      H.jobs[fact.address] = job
      return job
    end
    fake_jobs = fake_jobs + 1 -- e.g. the AGENT feed process: never started
    return 90000 + fake_jobs
  end
  vim.fn.jobstop = function(id)
    if type(id) == "number" and id > 90000 then
      return 1
    end
    return jobstop(id)
  end

  require("hcmux.term").setup({ restore = false })
  require("hcmux.t3").setup()

  function H.popover()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_win_get_config(win).relative ~= "" and vim.b[buf].hcmux_float == "t3" then
        return win, buf
      end
    end
  end

  function H.ready(marker, ms)
    return vim.wait(ms or 8000, function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
            if line == "READY_" .. marker then
              return true
            end
          end
        end
      end
      return false
    end, 20)
  end

  local function hl(name)
    local h = vim.api.nvim_get_hl(0, { name = name, link = false })
    return { fg = h.fg, bg = h.bg }
  end

  function H.state()
    local win, buf = H.popover()
    local s = {
      mode = vim.api.nvim_get_mode().mode,
      normal = hl("Normal"),
      cursor = hl("Cursor"),
      popover_hl = hl("EnviT3Normal"),
      runs = #H.runs,
    }
    if win then
      local job = vim.b[buf].terminal_job_id
      s.win, s.buf, s.job = win, buf, job
      s.alive = job and vim.fn.jobwait({ job }, 0)[1] == -1
      s.lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      s.width, s.height = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
      s.topline = vim.fn.line("w0", win)
      s.winhl = vim.wo[win].winhighlight
      s.addr = vim.b[buf].hcmux_addr
    end
    return s
  end

  -- Production TermRequest callback answers for one buffer (OSC 10/11/12).
  function H.osc(buf)
    local cb
    for _, a in ipairs(vim.api.nvim_get_autocmds({ group = "hcmux.term", event = "TermRequest" })) do
      cb = a.callback
    end
    local sent = {}
    local send = vim.api.nvim_chan_send
    vim.api.nvim_chan_send = function(_, data)
      sent[#sent + 1] = data
    end
    local ok, err = pcall(function()
      for _, code in ipairs({ "10", "11", "12" }) do
        cb({ buf = buf, data = { sequence = "\27]" .. code .. ";?" } })
      end
    end)
    vim.api.nvim_chan_send = send
    assert(ok, err)
    return sent
  end

  function H.job_alive(addr)
    local job = H.jobs[addr]
    return job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1
  end

  function H.stop_all()
    for _, job in pairs(H.jobs) do
      pcall(jobstop, job)
    end
  end
  return true
end
