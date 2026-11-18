-- Shared fixture for the t3update suites: a throwaway T3CODE_HOME, a stubbed
-- vim.system (curl/osascript never run), a stubbed hcmux.core cache and
-- captured notices. Nothing here reads or writes the real ~/.t3.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local F = {}

F.home = vim.fn.tempname() .. "-t3home"
vim.fn.mkdir(F.home .. "/runtime", "p")
vim.fn.mkdir(F.home .. "/userdata", "p")
vim.env.T3CODE_HOME = F.home
vim.env.T3_URL = "http://127.0.0.1:39999"
local real = vim.fs.normalize("~/.t3")
assert(not vim.startswith(F.home, real), "fixture must not use the real T3 home")

F.marker = F.home .. "/runtime/desktop-update-in-progress"
F.runtime = F.home .. "/userdata/server-runtime.json"

function F.write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

function F.set_runtime(pid, version, extra)
  local value =
    vim.tbl_extend("force", { pid = pid, serverVersion = version, startedAt = "2026-11-18T02:33:13Z" }, extra or {})
  F.write(F.runtime, vim.json.encode(value))
end

function F.set_marker(seconds_left)
  local now = os.time() * 1000
  F.write(F.marker, vim.json.encode({ startedAt = now - 1000, expiresAt = now + seconds_left * 1000 }))
end

function F.clear()
  os.remove(F.marker)
  os.remove(F.runtime)
end

-- vim.system: every call is recorded; `F.reply[argv[1]]` answers it (a table
-- or a function of argv), asynchronously like the real thing.
F.calls, F.reply = {}, {}
vim.system = function(argv, opts, cb)
  F.calls[#F.calls + 1] = { argv = argv, opts = opts }
  local reply = F.reply[argv[1]] or { code = 127, stdout = "", stderr = "not stubbed" }
  if type(reply) == "function" then
    reply = reply(argv)
  end
  vim.defer_fn(function()
    cb(vim.tbl_extend("keep", reply, { code = 0, stdout = "", stderr = "", signal = 0 }))
  end, 5)
  return {}
end
function F.server(up)
  F.reply.curl = { code = up and 0 or 7, stdout = up and "200" or "000" }
end
function F.of(name)
  local out = {}
  for _, call in ipairs(F.calls) do
    if call.argv[1] == name then
      out[#out + 1] = call
    end
  end
  return out
end

F.core = { terms = {} }
package.loaded["hcmux.core"] = F.core
F.feed = { snapshot = { projects = {}, threads = {} } }
package.loaded["hcmux.t3side"] = {
  snapshot = function()
    return vim.deepcopy(F.feed.snapshot), F.feed.message
  end,
}

-- A T3 client buffer as t3.lua marks it.
function F.client(addr, state)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].hcmux_float = "t3"
  vim.b[buf].hcmux_addr = addr
  F.core.terms[addr] = { address = addr, name = addr, state = state }
  return buf
end

F.notices = {}
vim.notify = function(text, level)
  F.notices[#F.notices + 1] = { text = text, level = level }
end
function F.last()
  local n = F.notices[#F.notices]
  return n and n.text or ""
end
function F.wait_notice(pattern, ms)
  local ok = vim.wait(ms or 2000, function()
    for _, n in ipairs(F.notices) do
      if n.text:find(pattern) then
        return true
      end
    end
    return false
  end, 10)
  assert(
    ok,
    ("no notice matching %q; got:\n%s"):format(
      pattern,
      table.concat(
        vim.tbl_map(function(n)
          return n.text
        end, F.notices),
        "\n"
      )
    )
  )
end
function F.reset()
  F.calls, F.notices = {}, {}
  F.reply = {}
  F.core.terms = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].hcmux_float == "t3" then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  F.feed.snapshot, F.feed.message = { projects = {}, threads = {} }, nil
  F.clear()
end

-- Collected so a failure names every broken case, then fails the suite.
local failures = {}
function F.case(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    failures[#failures + 1] = name .. ": " .. tostring(err)
  end
end
function F.done()
  vim.fn.delete(F.home, "rf")
  if #failures > 0 then
    error(table.concat(failures, "\n"), 0)
  end
end

return F
