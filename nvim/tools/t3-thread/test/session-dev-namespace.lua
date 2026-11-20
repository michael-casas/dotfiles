-- A dev profile (NVIM_APPNAME envi-dev/<slot>) keeps its sessions in their own
-- core namespace (nvsdev.<name>, nvsdev-index, herdr.nvsdev labels): it never
-- reads or writes a production session, even one whose name starts with dev-.
-- No real core: every core call is recorded by a stub.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local docs, touched, execs, facts = {}, {}, {}, {}
local function put(name, value, version)
  touched[#touched + 1] = "set " .. name
  local old = docs[name]
  if (old and old.version or 0) ~= version then
    return nil, "newer version", "conflict"
  end
  docs[name] = value ~= nil and { value = vim.deepcopy(value), version = version + 1 } or nil
  return version + 1
end
package.loaded["hcmux.core"] = {
  available = function()
    return true
  end,
  doc_get = function(name)
    touched[#touched + 1] = "get " .. name
    local d = docs[name]
    return d and vim.deepcopy(d.value), d and d.version or 0
  end,
  doc_set = put,
  rpc_async = function(_, p, cb)
    local v, err, kind = put(p.name, p.value, p.version)
    cb(v and { version = v }, err, nil, kind)
  end,
  json = function(args)
    execs[#execs + 1] = table.concat(args, " ")
    return { terminals = { { address = "t-" .. args[3] } } }
  end,
  label = function(addr, labels)
    for k, v in pairs(labels) do
      execs[#execs + 1] = "label " .. addr .. " " .. k .. "=" .. v
    end
    return true
  end,
  exec = function(args)
    execs[#execs + 1] = table.concat(args, " ")
    return "{}"
  end,
  LABEL = "herdr.nvim",
  is_ours = function()
    return true
  end,
  list = function()
    return facts
  end,
}
package.loaded["hcmux.term"] = {
  config = {},
  buf_of = function() end,
  placeholder = function() end,
}
vim.notify = function() end

local function load(appname)
  vim.env.NVIM_APPNAME = appname
  package.loaded["hcmux.session"] = nil
  local s = require("hcmux.session")
  vim.env.NVIM_APPNAME = nil
  return s
end
local function settle()
  vim.wait(60, function()
    return false
  end)
end
local function reset()
  docs, touched, execs, facts = {}, {}, {}, {}
end
local function production_touched()
  local bad = {}
  for _, t in ipairs(touched) do
    local name = t:match("^%a+ (.*)$")
    if name == "nvs-index" or name:sub(1, 4) == "nvs." then
      bad[#bad + 1] = t
    end
  end
  for _, e in ipairs(execs) do
    if e:find("herdr.nvs=", 1, true) then
      bad[#bad + 1] = e
    end
  end
  return bad
end

local failures = {}
local function test(name, fn)
  reset()
  local ok, err = pcall(fn)
  print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(err))))
  if not ok then
    failures[#failures + 1] = name
  end
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
vim.cmd.edit(dir .. "/keep")

local dev = load("envi-dev/slot3-0a1b2c3d")
test("dev profile: its own index and label; names get the dev- prefix, within 25 characters", function()
  assert(dev.dev and dev.INDEX == "nvsdev-index", dev.INDEX)
  assert(dev.LABEL == "herdr.nvsdev", dev.LABEL)
  assert(dev.doc_name("dev-x") == "nvsdev.dev-x")
  assert(dev.sanitize("dotfiles") == "dev-dotfiles", dev.sanitize("dotfiles"))
  assert(dev.sanitize("dev-slot3-0a1b2c3d") == "dev-slot3-0a1b2c3d")
  assert(dev.sanitize("") == "dev-session")
  local long = dev.sanitize(string.rep("x", 40))
  assert(#long <= 25 and #dev.doc_name(long) <= 32 and long:sub(1, 4) == "dev-", long)
end)
test("dev profile: attach, save, rename, list and kill touch only dev documents", function()
  dev.attach("dotfiles", { root = dir }) -- a production name, asked for by hand
  settle()
  assert(dev.name == "dev-dotfiles", dev.name)
  dev.save({ sync = true, force = true })
  assert(docs["nvsdev.dev-dotfiles"], "dev session document written")
  assert(docs["nvsdev-index"] and docs["nvsdev-index"].value.sessions["dev-dotfiles"], "dev index written")
  dev.rename("other")
  assert(dev.name == "dev-other", dev.name)
  dev.list()
  dev.kill("dev-other")
  dev.save({ sync = true, force = true, release = true })
  dev.name, dev.state = nil, "off"
  local bad = production_touched()
  assert(#bad == 0, "production touched: " .. table.concat(bad, ", "))
  assert(not docs["nvs.dotfiles"] and not docs["nvs-index"])
end)
test("dev profile: a production session named dev-* is never reached", function()
  docs["nvs.dev-existing"] = { value = { root = dir }, version = 3 }
  docs["nvs-index"] = { value = { sessions = { ["dev-existing"] = { root = dir } } }, version = 3 }
  local before = vim.deepcopy(docs)
  assert(not dev.read("dev-existing"), "the dev profile saw the production document")
  dev.kill("dev-existing")
  dev.kill("dotfiles")
  assert(vim.deep_equal(before["nvs.dev-existing"], docs["nvs.dev-existing"]), "production document changed")
  assert(vim.deep_equal(before["nvs-index"], docs["nvs-index"]), "production index changed")
  local bad = production_touched()
  assert(#bad == 0, "production touched: " .. table.concat(bad, ", "))
end)
test("dev profile: never adopts a production terminal, nor production a dev one", function()
  local cwd = { ["herdr.nvim.cwd"] = dir }
  facts = {
    { address = "prod", labels = vim.tbl_extend("force", cwd, { ["herdr.nvs"] = "dotfiles" }) },
    { address = "devt", labels = vim.tbl_extend("force", cwd, { ["herdr.nvsdev"] = "dev-other" }) },
    { address = "old", labels = vim.deepcopy(cwd) },
  }
  dev.name, dev.root = "dev-x", dir
  dev.list_terminals()
  dev.name, dev.root = nil, nil
  assert(#execs == 1 and execs[1] == "label old herdr.nvsdev=dev-x", table.concat(execs, ", "))
end)
test("envi-dev without a slot is a dev profile too", function()
  assert(load("envi-dev").dev)
  assert(not load("envi-development").dev and not load("envi").dev)
end)

local prod = load(nil)
test("production: names and the index are unchanged", function()
  assert(not prod.dev and prod.INDEX == "nvs-index")
  assert(prod.sanitize("dotfiles") == "dotfiles")
  assert(prod.doc_name("dotfiles") == "nvs.dotfiles")
  prod.attach("unit-prod", { root = dir })
  settle()
  prod.save({ sync = true, force = true, release = true })
  prod.name, prod.state = nil, "off"
  assert(docs["nvs.unit-prod"] and docs["nvs-index"], "production documents written")
  assert(not docs["nvsdev-index"])
end)
test("production: never adopts a dev terminal", function()
  local cwd = { ["herdr.nvim.cwd"] = dir }
  facts = { { address = "devt", labels = vim.tbl_extend("force", cwd, { ["herdr.nvsdev"] = "dev-other" }) } }
  prod.name, prod.root = "unit-prod", dir
  prod.list_terminals()
  prod.name, prod.root = nil, nil
  assert(#execs == 0, table.concat(execs, ", "))
end)

vim.fn.delete(dir, "rf")
if #failures > 0 then
  error(#failures .. " failure(s): " .. table.concat(failures, "; "))
end
