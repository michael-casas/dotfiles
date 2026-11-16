vim.env.ENVI_PR_NO_BROWSER = "1"
vim.env.ENVI_PR_DRY_RUN = "1"
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local temp = vim.fn.tempname()
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
vim.env.PATH = temp .. ":" .. vim.env.PATH
local system = vim.system
local view_live, view_peak = 0, 0
vim.system = function(argv, opts, cb)
  local view = argv[1] == "gh" and argv[2] == "pr" and argv[3] == "view"
  if view then
    view_live = view_live + 1
    view_peak = math.max(view_peak, view_live)
  end
  return system(argv, opts, function(res)
    if view then
      view_live = view_live - 1
    end
    cb(res)
  end)
end
local gh = require("hcmux.gh")
local function await(fn)
  local done, rows, err, loading
  fn(function(r, e, l)
    rows, err, loading = r, e, l
    done = not l
  end)
  assert(
    vim.wait(5000, function()
      return done
    end),
    "async completed"
  )
  return rows, err, loading
end
vim.env.PRS_EMPTY = nil
local rows = await(function(cb)
  gh.list("Repo", "acme/repo", cb)
end)
assert(#rows == 3 and rows[1].number == 2 and rows[2].number == 3 and rows[3].number == 1, "review/draft/time sort")
assert(rows[1].checks.pass == 1 and rows[1].checks.fail == 1 and rows[1].checks.pending == 1)
assert(rows[1].repo == "acme/repo" and rows[1].commentCount == 3)
for _, scope in ipairs({ "Review", "Mine", "Involved" }) do
  rows = await(function(cb)
    gh.list(scope, "acme/repo", cb)
  end)
  assert(#rows == 3 and rows[1].headRefName == "fix/build" and rows[1].headRefOid == "head", scope .. " enriched")
end
local instant = false
vim.env.PRS_DELAY = "0.05"
gh.list("Mine", "acme/repo", function(r, _, loading)
  if loading and #r == 3 then
    instant = true
  end
end)
assert(instant, "cache delivered synchronously while refreshing")
vim.wait(1000, function()
  return false
end)
vim.env.PRS_DELAY = nil
for _, entry in ipairs({
  { "not logged into any GitHub hosts", "auth" },
  { "API rate limit exceeded", "rate" },
  { "error connecting to api.github.com", "offline" },
}) do
  vim.env.PRS_ERROR = entry[1]
  local cached, err = await(function(cb)
    gh.list("Mine", "acme/repo", cb)
  end)
  assert(#cached == 3 and err.kind == entry[2], "classified error preserves cache")
end
vim.env.PRS_ERROR = nil
assert(view_peak <= 4, "view enrichment bounded at four")
local incomplete = gh.normalize({
  number = 9,
  url = "https://github.com/acme/repo/pull/9",
  author = { login = "alice" },
  reviewRequests = { { login = "someone-else" } },
  statusCheckRollup = { { conclusion = vim.NIL, status = "QUEUED" } },
}, "acme/repo")
assert(not incomplete.reviewRequested and incomplete.checks.pending == 1, "only current viewer review requests lead")
local calls = table.concat(vim.fn.readfile(vim.env.PRS_LOG), "\n")
assert(calls:find("%-%-review%-requested") and calls:find("%-%-author") and calls:find("%-%-involves"))
vim.env.PATH = temp .. "/missing"
local _, missing = await(function(cb)
  gh.list("Repo", "acme/repo", cb)
end)
assert(missing.kind == "missing", "missing gh is explicit")
print("prs-gh: data, cache, error and concurrency checks passed")
