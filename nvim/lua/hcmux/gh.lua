-- GitHub's CLI owns authentication. Never read, store, or log credentials here.
local M = {}
local cache, details, generations = {}, {}, {}
local login, login_waiters
local fields = table.concat({
  "number",
  "title",
  "url",
  "author",
  "isDraft",
  "updatedAt",
  "headRefName",
  "baseRefName",
  "headRefOid",
  "baseRefOid",
  "body",
  "state",
  "labels",
  "latestReviews",
  "reviewRequests",
  "reviewDecision",
  "statusCheckRollup",
  "additions",
  "deletions",
  "changedFiles",
  "comments",
}, ",")

function M.error(text)
  text = (text or ""):lower()
  if
    text:find("not logged")
    or text:find("authentication")
    or text:find("gh auth login", 1, true)
    or text:find("bad credentials", 1, true)
    or text:find("http 401", 1, true)
  then
    return { kind = "auth", message = "GitHub: not logged in · run gh auth login" }
  end
  if text:find("rate limit") or text:find("secondary rate") then
    return { kind = "rate", message = "offline · rate limited · r to retry" }
  end
  -- GitHub answered but refused (e.g. 422 on a review): say so instead of "offline".
  local code = text:match("http (4%d%d)")
  if code then
    local first = (text:match("[^\n]+") or ""):gsub("%c", " "):sub(1, 120)
    return { kind = "api", message = "GitHub: HTTP " .. code .. " · " .. first }
  end
  return { kind = "offline", message = "offline · r to retry" }
end

-- Callbacks always run on Neovim's main loop. Failures expose safe messages only.
function M.run(argv, opts, cb)
  opts = vim.tbl_extend("force", { text = true, timeout = 30000 }, opts or {})
  if vim.fn.executable(argv[1]) ~= 1 then
    return cb(nil, { kind = "missing", message = argv[1] .. " not installed" })
  end
  local ok = pcall(vim.system, argv, opts, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        cb(nil, M.error(res.stderr))
      else
        cb(res.stdout)
      end
    end)
  end)
  if not ok then
    cb(nil, { kind = "offline", message = "Could not start " .. argv[1] })
  end
end

function M.json(args, cb, opts)
  M.run(vim.list_extend({ "gh" }, args), opts, function(out, err)
    if err then
      return cb(nil, err)
    end
    local ok, value = pcall(vim.json.decode, out)
    if not ok then
      return cb(nil, { kind = "invalid", message = "GitHub returned invalid data · r to retry" })
    end
    cb(value)
  end)
end

local function present(value)
  return value ~= vim.NIL and value or nil
end

function M.normalize(row, repo)
  local r = vim.deepcopy(row)
  r.repo = repo
    or (type(r.repository) == "table" and r.repository.nameWithOwner)
    or (r.url or ""):match("github.com/([^/]+/[^/]+)/pull/")
  r.author = type(r.author) == "table" and r.author.login or "unknown"
  r.commentCount = type(r.comments) == "table" and #r.comments or r.commentsCount or 0
  r.reviewRequested = false
  for _, request in ipairs(present(r.reviewRequests) or {}) do
    if login and request.login == login then
      r.reviewRequested = true
    end
  end
  r.checks = { pass = 0, fail = 0, pending = 0 }
  for _, check in ipairs(present(r.statusCheckRollup) or {}) do
    local state = present(check.conclusion) or present(check.state) or present(check.status) or "PENDING"
    local bucket = ({
      SUCCESS = "pass",
      NEUTRAL = "pass",
      SKIPPED = "pass",
      FAILURE = "fail",
      ERROR = "fail",
      TIMED_OUT = "fail",
      CANCELLED = "fail",
      ACTION_REQUIRED = "fail",
      STARTUP_FAILURE = "fail",
    })[state] or "pending"
    r.checks[bucket] = r.checks[bucket] + 1
  end
  return r
end

local function sort(rows)
  table.sort(rows, function(a, b)
    if a.reviewRequested ~= b.reviewRequested then
      return a.reviewRequested
    end
    if not not a.isDraft ~= not not b.isDraft then
      return not a.isDraft
    end
    if a.updatedAt ~= b.updatedAt then
      return (a.updatedAt or "") > (b.updatedAt or "")
    end
    return a.url < b.url
  end)
end

-- Shared queue: simultaneous scope enrichment never exceeds four view processes.
local view_queue, view_running = {}, 0
local function pump_views()
  while view_running < 4 and #view_queue > 0 do
    local job = table.remove(view_queue, 1)
    view_running = view_running + 1
    M.json({ "pr", "view", tostring(job.pr.number), "-R", job.pr.repo, "--json", fields }, function(row, err)
      view_running = view_running - 1
      job.cb(row and M.normalize(row, job.pr.repo), err)
      pump_views()
    end)
  end
end
function M.view(pr, cb)
  view_queue[#view_queue + 1] = { pr = pr, cb = cb }
  pump_views()
end

local function viewer(cb)
  if login then
    return cb()
  end
  if login_waiters then
    login_waiters[#login_waiters + 1] = cb
    return
  end
  login_waiters = { cb }
  M.json({ "api", "user" }, function(value, err)
    if value and type(value.login) == "string" then
      login = value.login
    end
    local callbacks = login_waiters
    login_waiters = nil
    for _, done in ipairs(callbacks) do
      done(err)
    end
  end)
end

-- cb(rows, error, refreshing); first callback is synchronous cached content.
-- Search metadata is rendered before up to four concurrent detail requests fill it in.
function M.list(scope, repo, cb)
  local key = scope == "Repo" and ("Repo:" .. (repo or "")) or scope
  generations[key] = (generations[key] or 0) + 1
  local generation = generations[key]
  local function emit(rows, err, loading)
    if generation ~= generations[key] then
      return
    end
    if rows then
      cache[key] = vim.deepcopy(rows)
    end
    cb(vim.deepcopy(cache[key] or {}), err, loading)
  end
  emit(nil, nil, true)
  if scope == "Repo" and not repo then
    return emit({}, nil, false)
  end
  local args
  if scope == "Repo" then
    args = { "pr", "list", "-R", repo, "--state", "open", "--limit", "100", "--json", fields }
  else
    local flag = ({ Review = "--review-requested", Mine = "--author", Involved = "--involves" })[scope]
    assert(flag, "unknown PR scope")
    args = {
      "search",
      "prs",
      "--state",
      "open",
      flag,
      "@me",
      "--limit",
      "100",
      "--json",
      "number,title,url,author,isDraft,updatedAt,repository,commentsCount",
    }
  end
  viewer(function(auth_error)
    if auth_error then
      return emit(nil, auth_error, false)
    end
    M.json(args, function(raw, err)
      if err then
        return emit(nil, err, false)
      end
      local rows = {}
      for _, row in ipairs(raw) do
        local r = M.normalize(row, scope == "Repo" and repo or nil)
        if scope == "Review" then
          r.reviewRequested = true
        end
        local d = details[r.url]
        if scope ~= "Repo" and d and d.updatedAt == r.updatedAt then
          r = vim.deepcopy(d)
        end
        rows[#rows + 1] = r
      end
      sort(rows)
      if scope == "Repo" then
        return emit(rows, nil, false)
      end
      emit(rows, nil, true)
      local next_index, running, finished, failure = 1, 0, 0, nil
      local pump
      pump = function()
        if generation ~= generations[key] then
          return
        end
        while running < 4 and next_index <= #rows do
          local index = next_index
          next_index, running = next_index + 1, running + 1
          local pr = rows[index]
          local function complete(value, e)
            running, finished = running - 1, finished + 1
            failure = e or failure
            if value then
              value.reviewRequested = scope == "Review" or value.reviewRequested
              rows[index], details[value.url] = value, vim.deepcopy(value)
            end
            if finished == #rows then
              sort(rows)
              emit(rows, failure, false)
            else
              emit(rows, failure, true)
              pump()
            end
          end
          if pr.headRefOid then
            complete(pr)
          else
            M.view(pr, complete)
          end
        end
      end
      if #rows == 0 then
        return emit(rows, nil, false)
      end
      pump()
    end)
  end)
end

function M.origin(cwd, cb)
  M.run({ "git", "remote", "get-url", "origin" }, { cwd = cwd }, function(out)
    local repo = out and vim.trim(out):match("github%.com[:/]([^/]+/[^/]+)$")
    cb(repo and repo:gsub("%.git$", "") or nil)
  end)
end

function M.diff(pr, cb)
  M.run({ "gh", "pr", "diff", tostring(pr.number), "-R", pr.repo }, {}, cb)
end

return M
