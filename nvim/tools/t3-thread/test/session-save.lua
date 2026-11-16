-- Autosave regression/characterization tests. No real core or user documents.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local docs, notices, writes = {}, {}, 0
local fail, delayed, callback
local function put(name, value, version)
  if fail then
    return nil, "newer version", "conflict"
  end
  local old = docs[name]
  if (old and old.version or 0) ~= version then
    return nil, "newer version", "conflict"
  end
  writes = writes + 1
  docs[name] = { value = vim.deepcopy(value), version = version + 1 }
  return version + 1
end
package.loaded["hcmux.core"] = {
  available = function()
    return true
  end,
  doc_get = function(name)
    local d = docs[name]
    return d and vim.deepcopy(d.value), d and d.version or 0
  end,
  doc_set = put,
  rpc_async = function(_, p, cb)
    local function complete()
      local v, err, kind = put(p.name, p.value, p.version)
      cb(v and { version = v }, err, nil, kind)
    end
    if delayed then
      local v, err, kind = put(p.name, p.value, p.version)
      callback = function()
        cb(v and { version = v }, err, nil, kind)
      end
    else
      complete()
    end
  end,
  list = function()
    return {}
  end,
}
package.loaded["hcmux.term"] = { config = {} }
vim.notify = function(msg)
  notices[#notices + 1] = msg
end
local s = require("hcmux.session")
s.setup({ debounce = 15 })
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local cases, failures = 0, {}
local function settle()
  vim.wait(80, function()
    return false
  end)
end
local function reset()
  s.name, s.state, s.last_text = nil, "off", nil
  s.loading, s.saving, s.pending, s.released = false, false, false, false
  vim.g.SessionLoad = nil
  fail, delayed, callback = nil, nil, nil
  vim.cmd("silent! %bwipeout!")
  vim.cmd.edit(dir .. "/keep")
  docs, notices, writes = {}, {}, 0
  s.attach("unit-save")
  settle()
end
local function test(name, fn)
  cases = cases + 1
  reset()
  local ok, err = pcall(fn)
  if ok then
    print("PASS " .. name)
  else
    failures[#failures + 1] = name .. ": " .. tostring(err)
    print("FAIL " .. failures[#failures])
  end
end
local function saved()
  return docs["nvs.unit-save"].value.layout
end
local function has(name)
  return saved():find("/" .. name, 1, true) ~= nil
end
local function add(name)
  vim.cmd.badd(dir .. "/" .. name)
  settle()
end
local function deleted(name)
  assert(not has(name), name .. " must not return in the saved layout")
end

test("holder has a persistent machine identity", function()
  local a, b = s.holder(), s.holder()
  assert(type(a.machine) == "string" and #a.machine > 0, "holder needs stable machine identity")
  assert(a.machine == b.machine)
  a.host = "changed-host.example"
  assert(s.holder_alive(a), "same-machine live pid survives hostname changes")
  local current = docs["nvs.unit-save"].value
  current.holder = a
  s.attach("unit-save")
  settle()
  assert(s.state == "attached", "changed hostname must not make this nvim readonly")
end)
test("dead legacy hostname does not lock forever", function()
  docs["nvs.unit-save"].value.holder = { host = "old-host.example", pid = 2147483647 }
  s.attach("unit-save")
  settle()
  assert(s.state == "attached", "dead legacy holder should be reclaimed")
  add("stale")
  vim.cmd("bdelete " .. vim.fn.bufnr(dir .. "/stale"))
  settle()
  deleted("stale")
end)
test("known remote identity remains protected", function()
  assert(s.holder_alive({ machine = "remote-machine", host = "host-b.example", pid = 2147483647 }))
  assert(s.holder_alive({ host = "host-b.example", pid = 2147483647, terminal = "remote/t7" }))
end)
test("live local holder is not automatically taken", function()
  local h = s.holder()
  h.pid = (vim.uv or vim.loop).os_getppid()
  docs["nvs.unit-save"].value.holder = h
  s.attach("unit-save")
  settle()
  assert(s.state == "readonly")
end)
test("permission denied probing a pid means alive", function()
  local uv = vim.uv or vim.loop
  local kill = uv.kill
  uv.kill = function()
    return nil, "EPERM: operation not permitted", "EPERM"
  end
  local ok = s.holder_alive(s.holder())
  uv.kill = kill
  assert(ok, "permission denied is not proof of a dead holder")
end)
test("explicit save cannot bypass readonly ownership", function()
  s.state = "readonly"
  local before = writes
  s.commands.save()
  assert(writes == before, "only take may reclaim ownership")
end)
test("readonly edits rewarn and remain unwritten", function()
  s.state = "readonly"
  notices = {}
  local before = writes
  add("unsaved")
  add("also-unsaved")
  assert(writes == before, "readonly must not write")
  assert(#notices == 1 and notices[1]:find(":Session take", 1, true), "warn once per throttle window on changes")
end)
test("conflict edits rewarn and explicit take recovers", function()
  fail = true
  s.save({ sync = true, force = true })
  assert(s.state == "conflict")
  notices = {}
  add("conflicted")
  assert(#notices == 1 and notices[1]:find(":Session take", 1, true), "conflict changes must warn again")
  fail = nil
  s.take()
  assert(s.state == "attached" and has("conflicted"))
end)
test("failed take never claims success", function()
  fail = true
  notices = {}
  s.take()
  assert(s.state == "conflict")
  for _, msg in ipairs(notices) do
    assert(not msg:find("is now attached here", 1, true), "take must not announce success on failure")
  end
end)
test("bdelete persists after its pre-deletion event", function()
  add("deleted")
  local target = vim.fn.bufnr(dir .. "/deleted")
  local listed_during_event = false
  local id = vim.api.nvim_create_autocmd("BufDelete", {
    callback = function(e)
      if e.buf == target then
        listed_during_event = vim.bo[e.buf].buflisted
      end
    end,
  })
  vim.cmd("bdelete " .. vim.fn.bufnr(dir .. "/deleted"))
  settle()
  vim.api.nvim_del_autocmd(id)
  assert(listed_during_event, "BufDelete is before delisting")
  deleted("deleted")
  assert(has("keep"))
end)
test("bwipeout persists", function()
  add("wiped")
  vim.cmd("bwipeout " .. vim.fn.bufnr(dir .. "/wiped"))
  settle()
  deleted("wiped")
end)
test("nobufflisted persists", function()
  add("unlisted")
  vim.bo[vim.fn.bufnr(dir .. "/unlisted")].buflisted = false
  settle()
  deleted("unlisted")
end)
test("Snacks delete-other persists through LazyVim route", function()
  add("other-one")
  add("other-two")
  -- Exercise the shipped Snacks module when installed; otherwise the same public bdelete route.
  local file = vim.fn.stdpath("data") .. "/lazy/snacks.nvim/lua/snacks/bufdelete.lua"
  if vim.fn.filereadable(file) == 1 then
    dofile(file).other()
  else
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= vim.api.nvim_get_current_buf() and vim.bo[b].buflisted then
        vim.cmd("bdelete " .. b)
      end
    end
  end
  settle()
  deleted("other-one")
  deleted("other-two")
  assert(has("keep"))
end)
test("deleting the last named buffer saves an intentionally empty editor", function()
  vim.cmd("bdelete " .. vim.fn.bufnr(dir .. "/keep"))
  settle()
  deleted("keep")
end)
test("rapid open and final delete from an empty session persists", function()
  vim.cmd("%bwipeout!")
  s.save({ sync = true, force = true })
  s.had_content = false
  vim.cmd.edit(dir .. "/briefly-open")
  vim.cmd("bdelete")
  settle()
  assert(not s.last_text:find("/briefly-open", 1, true))
  assert(s.had_content, "user activity, not only a completed save, marks intentional emptying")
end)
test("blocked reminder rearms after one minute", function()
  s.state = "readonly"
  notices = {}
  local uv = vim.uv or vim.loop
  local hrtime = uv.hrtime
  local tick = hrtime()
  uv.hrtime = function()
    return tick
  end
  s.schedule()
  tick = tick + 59000 * 1e6
  s.schedule()
  tick = tick + 1000 * 1e6
  s.schedule()
  uv.hrtime = hrtime
  assert(#notices == 2, "warn at first activity and again after one minute, not before")
end)
test("unchanged layouts do not write repeatedly", function()
  s.save({ sync = true })
  local before = writes
  s.save({ sync = true })
  assert(writes == before)
end)
test("overlapping async save and exit flush keeps latest deletion", function()
  add("pending")
  delayed = true
  vim.cmd.badd(dir .. "/newer")
  settle()
  assert(callback and s.saving)
  vim.cmd("bdelete " .. vim.fn.bufnr(dir .. "/pending"))
  -- The old asynchronous write has reached the core but not its scheduled callback.
  local old = callback
  delayed = nil
  vim.defer_fn(old, 20)
  s.save({ sync = true, force = true, release = true })
  deleted("pending")
  assert(not docs["nvs.unit-save"].value.holder)
end)
test("load flags reset on ordinary and interrupted scripts", function()
  local text = assert(s.serialize())
  s.load_layout(text)
  assert(not s.loading and not vim.g.SessionLoad)
  s.load_layout("let SessionLoad = 1\nthrow 'synthetic layout failure'\n")
  assert(not s.loading and not vim.g.SessionLoad, "failed layout must not disable every future save")
end)
s.name, s.state = nil, "off"
vim.fn.delete(dir, "rf")
print(("session-save: %d cases, %d failures"):format(cases, #failures))
assert(#failures == 0, table.concat(failures, "\n"))
