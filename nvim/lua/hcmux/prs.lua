-- PR board owns only its buffers and the hunk terminals it starts. No global keys.
local M = { active = false }
local gh = require("hcmux.gh")
local ui = require("hcmux.t3side").presentation
local ns = vim.api.nvim_create_namespace("envi.prs")
local group = vim.api.nvim_create_augroup("envi.prs", { clear = true })
local scopes = { "Repo", "Review", "Mine", "Involved" }
local board, detail, search, modal
local rows, hits, counts, reviews = {}, {}, {}, {}
local scope, repo, selected, query, loading, message = 1, nil, 1, "", false, nil
local generation, opened, editing, drawing, detail_visible = 0, 0, false, false, false
local timer, render, capture, review, submit, refresh_scope
local default_scope = false
local submit_epoch = 0
local source = debug.getinfo(1, "S").source:sub(2)
local hub_file = vim.fn.fnamemodify(source, ":h:h:h:h") .. "/theme/theme.json"
local theme_name, normal, border = nil, "NormalFloat", "FloatBorder"
local cache_dir = vim.fn.stdpath("cache") .. "/envi-pr"

local function root()
  return require("hcmux.session").root or vim.fs.root(vim.fn.getcwd(), ".git") or vim.fn.getcwd()
end
local function key(pr)
  return pr.repo .. "#" .. pr.number
end
local function stem(pr)
  return cache_dir .. "/" .. pr.repo:gsub("/", "-") .. "-" .. pr.number
end
local function valid(view)
  return view and vim.api.nvim_win_is_valid(view.win)
end
local function status()
  local ok, lualine = pcall(require, "lualine")
  if ok then
    lualine.refresh()
  end
  vim.cmd.redrawstatus({ bang = true })
end
local function notify(text)
  vim.notify("PR: " .. text, vim.log.levels.INFO)
end
local function clean(s)
  return ui.clean(s)
end
local function destroy(view)
  if not view then
    return
  end
  if valid(view) then
    pcall(vim.api.nvim_win_close, view.win, true)
  end
  if vim.api.nvim_buf_is_valid(view.buf) then
    pcall(vim.api.nvim_buf_delete, view.buf, { force = true })
  end
end
local function return_board()
  if M.active and valid(board) then
    vim.api.nvim_set_current_win(board.win)
  end
end
local function close_modal()
  submit_epoch = submit_epoch + 1
  local old = modal
  modal, detail_visible = nil, false
  destroy(old)
  return_board()
end
local function geometry(size)
  local width = math.max(1, math.min(vim.o.columns - 4, math.floor(vim.o.columns * (size or 0.92))))
  local height = math.max(1, math.min(vim.o.lines - 5, math.floor(vim.o.lines * 0.85)))
  return {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    zindex = 60,
  }
end
local function theme()
  ui.highlights()
  vim.api.nvim_set_hl(0, "EnviPRPass", { link = "EnviT3Side_done" })
  vim.api.nvim_set_hl(0, "EnviPRFail", { link = "EnviT3Side_error" })
  vim.api.nvim_set_hl(0, "EnviPRDraft", { link = "EnviT3SideBranch" })
  vim.api.nvim_set_hl(0, "EnviPRPending", { link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "EnviPRMatch", { link = "Search" })
  local ok, t = pcall(function()
    local hub = vim.json.decode(table.concat(vim.fn.readfile(vim.env.ENVI_THEME_FILE or hub_file), "\n"))
    local name = vim.env.ENVI_THEME or hub.active
    theme_name = ({ nord = "nord", ["gruvbox-dark"] = "gruvbox-dark-hard" })[name]
    return hub.themes[name]
  end)
  if not ok or not t then
    return
  end
  local function color(token)
    return t.palette[token] or token
  end
  for name, tokens in pairs({
    Normal = { "fg", "popover" },
    Border = { "border", "popover" },
    Title = { "title", "popover" },
  }) do
    vim.api.nvim_set_hl(0, "EnviPR" .. name, { fg = color(t.tokens.ui[tokens[1]]), bg = color(t.tokens.ui[tokens[2]]) })
  end
  vim.api.nvim_set_hl(0, "EnviPRPending", { fg = color(t.tokens.status.warning) })
  normal, border = "EnviPRNormal", "EnviPRBorder"
end
local function window_style(win)
  vim.wo[win].winhl = "Normal:"
    .. normal
    .. ",NormalFloat:"
    .. normal
    .. ",FloatBorder:"
    .. border
    .. ",FloatTitle:EnviPRTitle"
  vim.wo[win].winbar, vim.wo[win].wrap, vim.wo[win].scrolloff = "", false, 0
end
local function map(view, mode, lhs, fn)
  vim.keymap.set(mode, lhs, fn, { buffer = view.buf, nowait = true, silent = true })
end
local function create(config, ft, enter)
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden, vim.bo[b].filetype, vim.bo[b].swapfile = "wipe", ft, false
  local w = vim.api.nvim_open_win(b, enter or false, config)
  window_style(w)
  return { buf = b, win = w }
end
local function write(view, lines)
  vim.bo[view.buf].modifiable = true
  vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
  vim.bo[view.buf].modifiable = false
end
local function popup(title, lines, ft)
  close_modal()
  local g = geometry(0.8)
  g.height, g.zindex, g.title = math.min(g.height, math.max(3, #lines)), 80, " " .. title .. " "
  g.row = math.max(0, math.floor((vim.o.lines - g.height - 2) / 2))
  modal = create(g, ft or "envi-pr-help", true)
  modal.lines = lines
  write(modal, lines)
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    map(modal, "n", lhs, close_modal)
  end
  return modal
end
local function current()
  return hits[selected] and hits[selected].pr
end
local function filter()
  hits = {}
  for _, pr in ipairs(rows) do
    local text =
      clean("#" .. pr.number .. " " .. pr.title .. " " .. (pr.headRefName or "") .. " " .. pr.author .. " " .. pr.repo)
    local positions, score = {}, 0
    if query ~= "" then
      local match = vim.fn.matchfuzzypos({ text }, query)
      positions, score = match[2][1], match[3][1]
    end
    if positions then
      hits[#hits + 1] = { pr = pr, positions = positions, score = score }
    end
  end
  if query ~= "" then
    table.sort(hits, function(a, b)
      return a.score > b.score
    end)
  end
  selected = math.max(1, math.min(selected, #hits))
end
local function decision(pr)
  return ({ APPROVED = "approved", CHANGES_REQUESTED = "changes", REVIEW_REQUIRED = "review" })[pr.reviewDecision]
    or "review"
end
local function checks(pr)
  local result = {}
  for _, c in ipairs(type(pr.statusCheckRollup) == "table" and pr.statusCheckRollup or {}) do
    local state = type(c.conclusion) == "string" and c.conclusion ~= "" and c.conclusion
      or type(c.state) == "string" and c.state
      or type(c.status) == "string" and c.status
      or "PENDING"
    local duration = ""
    if type(c.startedAt) == "string" and type(c.completedAt) == "string" then
      local a = vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", c.startedAt)
      local b = vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", c.completedAt)
      if a > 0 and b >= a then
        duration = " · " .. tostring(b - a) .. "s"
      end
    end
    result[#result + 1] = {
      text = clean((c.name or c.context or "check") .. " · " .. state .. duration),
      url = c.detailsUrl or c.targetUrl,
    }
  end
  return result
end
local function detail_lines(pr)
  if not pr then
    return { "No PR selected" }
  end
  local lines = {
    "#" .. pr.number .. " " .. clean(pr.title),
    "",
    clean(pr.state or "OPEN") .. (pr.isDraft and " · DRAFT" or ""),
    "",
    "## Labels",
  }
  for _, label in ipairs(pr.labels or {}) do
    lines[#lines + 1] = "- " .. clean(label.name)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Reviewers"
  for _, r in ipairs(pr.latestReviews or {}) do
    lines[#lines + 1] = "- " .. clean(r.author and r.author.login) .. " · " .. clean(r.state)
  end
  for _, r in ipairs(pr.reviewRequests or {}) do
    lines[#lines + 1] = "- " .. clean(r.login or r.name) .. " · REQUESTED"
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Checks"
  for _, c in ipairs(checks(pr)) do
    lines[#lines + 1] = "- " .. c.text
  end
  lines[#lines + 1] = ""
  vim.list_extend(
    lines,
    vim.split(type(pr.body) == "string" and pr.body or "Details loading…", "\n", { plain = true })
  )
  return lines
end
local function move(delta)
  selected = math.max(1, math.min(#hits, selected + delta))
  render()
end

render = function()
  if not M.active or not valid(board) then
    return
  end
  drawing = true
  theme()
  local prior = current()
  filter()
  if prior then
    for i, h in ipairs(hits) do
      if h.pr.url == prior.url then
        selected = i
        break
      end
    end
  end
  local g = geometry()
  local wide = vim.o.columns >= 140
  local whole = g.width
  if wide then
    g.width = math.floor(whole * 0.6) - 1
  end
  local tabs = {}
  for i, name in ipairs(scopes) do
    tabs[#tabs + 1] = (i == scope and "▸ " or "") .. name .. " [" .. (counts[name] or "…") .. "]"
  end
  g.title = " PR · " .. scopes[scope] .. (loading and " ◌ refreshing" or "") .. " "
  vim.api.nvim_win_set_config(board.win, g)
  window_style(board.win)
  local lines, marks, anchors =
    { " " .. table.concat(tabs, "   "), "", "", " / search   Enter review   ? help" }, {}, {}
  local function hl(row, first, last, name)
    if last > first then
      marks[#marks + 1] = { row - 1, first, last, name }
    end
  end
  local page = math.max(1, math.floor((g.height - 6) / 5))
  local start = math.floor((selected - 1) / page) * page + 1
  for i = start, math.min(#hits, start + page - 1) do
    local pr, first = hits[i].pr, #lines + 1
    local live = reviews[key(pr)]
    local drafted = live and live.snapshot and #live.snapshot.comments or 0
    local chip = live and live.live and " ◉ hunk" or ""
    if drafted > 0 then
      chip = chip .. " ✎ " .. drafted .. (live.live and "" or " drafted")
    end
    local prefix = "#" .. pr.number .. "  "
    local suffix = "  " .. ui.age(pr.updatedAt) .. (pr.isDraft and "  DRAFT" or "") .. chip
    local title = ui.truncate(clean(pr.title), math.max(0, g.width - 4 - vim.fn.strdisplaywidth(prefix .. suffix)))
    local content = {
      prefix .. title .. suffix,
      (scope ~= 1 and pr.repo .. " · " or "")
        .. pr.author
        .. " · "
        .. clean(pr.headRefName or "…")
        .. " → "
        .. clean(pr.baseRefName or "…"),
      ("✓ %d  ✗ %d  ● %d   %s   +%s −%s · %s files · %d 💬"):format(
        pr.checks.pass,
        pr.checks.fail,
        pr.checks.pending,
        decision(pr),
        pr.additions or "…",
        pr.deletions or "…",
        pr.changedFiles or "…",
        pr.commentCount
      ),
    }
    local border_hl = i == selected and "EnviT3Side_working" or "EnviPRDraft"
    lines[#lines + 1] = "╭" .. string.rep("─", math.max(0, g.width - 2)) .. "╮"
    hl(#lines, 0, #lines[#lines], border_hl)
    for j, text in ipairs(content) do
      text = ui.truncate(clean(text), math.max(0, g.width - 4))
      lines[#lines + 1] = "│ "
        .. text
        .. string.rep(" ", math.max(0, g.width - 4 - vim.fn.strdisplaywidth(text)))
        .. " │"
      local n = #lines
      hl(n, 0, 3, border_hl)
      hl(n, #lines[n] - 3, #lines[n], border_hl)
      if j == 1 and pr.isDraft then
        hl(n, 4, #lines[n] - 3, "EnviPRDraft")
      end
      if j == 3 then
        for _, part in ipairs({
          { "✓ %d+", "EnviPRPass" },
          { "✗ %d+", "EnviPRFail" },
          { "● %d+", "EnviPRPending" },
          {
            decision(pr),
            decision(pr) == "approved" and "EnviPRPass"
              or decision(pr) == "changes" and "EnviPRFail"
              or "EnviPRPending",
          },
        }) do
          local a, b = lines[n]:find(part[1])
          if a then
            hl(n, a - 1, b, part[2])
          end
        end
      end
      if j == 1 and query ~= "" then
        local match = vim.fn.matchfuzzypos({ clean("#" .. pr.number .. " " .. pr.title) }, query)
        for _, pos in ipairs(match[2][1] or {}) do
          local a = vim.fn.byteidx(text, pos)
          local b = vim.fn.byteidx(text, pos + 1)
          if a >= 0 then
            hl(n, 4 + a, 4 + (b >= 0 and b or #text), "EnviPRMatch")
          end
        end
      end
    end
    lines[#lines + 1] = "╰" .. string.rep("─", math.max(0, g.width - 2)) .. "╯"
    hl(#lines, 0, #lines[#lines], border_hl)
    anchors[i] = first + 1
  end
  if #hits == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  " .. (query ~= "" and "No matching PRs" or "No open PRs in " .. scopes[scope])
    lines[#lines + 1] = "  <Tab> other scopes"
  end
  if message then
    lines[#lines + 1] = "  " .. message
  end
  write(board, lines)
  vim.api.nvim_buf_clear_namespace(board.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(board.buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  vim.api.nvim_win_set_cursor(board.win, { anchors[selected] or 1, 0 })
  if not valid(search) then
    search = create({
      relative = "editor",
      row = g.row + 2,
      col = g.col + 2,
      width = math.max(1, g.width - 4),
      height = 1,
      style = "minimal",
      border = "rounded",
      zindex = 65,
    }, "envi-pr-search")
    vim.b[search.buf].completion, vim.b[search.buf].minipairs_disable = false, true
    vim.bo[search.buf].undolevels = -1
    map(search, "i", "<Esc>", function()
      editing = false
      vim.cmd.stopinsert()
      return_board()
      render()
    end)
    map(search, "i", "<CR>", function()
      editing = false
      vim.cmd.stopinsert()
      selected = 1
      review(current())
    end)
    map(search, "n", "<Esc>", M.close)
    map(search, "n", "q", M.close)
    map(search, "n", "<CR>", function()
      selected = 1
      review(current())
    end)
    for _, lhs in ipairs({ "/", "i", "a" }) do
      map(search, "n", lhs, function()
        editing = true
        vim.cmd.startinsert({ bang = true })
      end)
    end
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = group,
      buffer = search.buf,
      callback = function()
        if drawing or not M.active then
          return
        end
        local value = vim.api.nvim_buf_get_lines(search.buf, 0, 1, false)[1] or ""
        query, selected = value, 1
        render()
      end,
    })
  end
  vim.api.nvim_win_set_config(search.win, {
    relative = "editor",
    row = g.row + 2,
    col = g.col + 2,
    width = math.max(1, g.width - 4),
    height = 1,
    title = " / Search PRs · " .. #hits .. "/" .. #rows .. " ",
    border = "rounded",
    zindex = 65,
  })
  vim.bo[search.buf].modifiable = true
  vim.api.nvim_buf_set_lines(search.buf, 0, -1, false, { query })
  vim.api.nvim_buf_clear_namespace(search.buf, ns, 0, -1)
  if query == "" then
    vim.api.nvim_buf_set_extmark(
      search.buf,
      ns,
      0,
      0,
      { virt_text = { { "Search #number title branch author repo…", "EnviPRDraft" } }, virt_text_pos = "overlay" }
    )
  end
  vim.wo[search.win].winhl = "Normal:" .. normal .. ",FloatBorder:" .. (editing and "EnviT3Side_working" or border)
  if wide and detail_visible then
    detail_visible = false
  end
  if wide then
    local dg =
      vim.tbl_extend("force", g, { col = g.col + g.width + 2, width = whole - g.width - 2, title = " Details " })
    if not valid(detail) then
      detail = create(dg, "markdown")
    else
      vim.api.nvim_win_set_config(detail.win, dg)
    end
    vim.wo[detail.win].wrap = true
    write(detail, detail_lines(current()))
    for _, lhs in ipairs({ "q", "<Esc>" }) do
      map(detail, "n", lhs, M.close)
    end
  elseif detail then
    destroy(detail)
    detail = nil
  end
  drawing = false
end

refresh_scope = function()
  generation = generation + 1
  local token, index = generation, scope
  gh.list(scopes[scope], repo, function(value, err, busy)
    if not M.active or token ~= generation then
      return
    end
    rows, loading, message = value, busy, err and err.message
    if not busy or #value > 0 then
      counts[scopes[index]] = #value
    end
    render()
    if not busy and not err and index == 1 and #value == 0 and default_scope then
      default_scope = false
      scope, query, selected = 4, "", 1
      refresh_scope()
    end
  end)
end

local function ensure_cache()
  vim.fn.mkdir(cache_dir, "p", "0700")
end
local function save_snapshot(rec, comments)
  rec.snapshot = {
    repo = rec.pr.repo,
    number = rec.pr.number,
    head = rec.head,
    capturedAt = os.date("%H:%M:%S"),
    comments = comments,
  }
  ensure_cache()
  local path = stem(rec.pr) .. ".comments.json"
  local ok = pcall(vim.fn.writefile, { vim.json.encode(rec.snapshot) }, path)
  if ok then
    vim.fn.setfperm(path, "rw-------")
  else
    notify("Could not save captured comments")
  end
end
local function session_matches(session, marker)
  for _, location in ipairs(session.terminal and session.terminal.locations or {}) do
    if location.sessionId == marker then
      return true
    end
  end
  return false
end
local function hunk_json(args, cb, stdin)
  gh.run(vim.list_extend({ "hunk" }, args), { stdin = stdin }, function(out, err)
    if err then
      return cb(nil, err)
    end
    local ok, value = pcall(vim.json.decode, out)
    cb(ok and value or nil, not ok and { message = "Invalid hunk session response" } or nil)
  end)
end
local function import_comments(rec)
  if rec.imported or not rec.id then
    return
  end
  rec.imported = true
  gh.json(
    { "api", "repos/" .. rec.pr.repo .. "/pulls/" .. rec.pr.number .. "/comments", "--paginate", "--slurp" },
    function(pages, err)
      if rec.discarded or not rec.live then
        return
      end
      if err then
        notify("GitHub inline comments unavailable; hunk is still usable")
        return
      end
      local comments, skipped = {}, 0
      for _, page in ipairs(pages) do
        for _, c in ipairs(page) do
          if type(c.line) == "number" and c.line > 0 and (c.side == "LEFT" or c.side == "RIGHT") then
            local comment = {
              filePath = c.path,
              summary = (c.body or "Comment"):match("[^\n]+") or "Comment",
              rationale = (c.body or "") .. "\n" .. (c.html_url or ""),
              author = c.user and c.user.login or "GitHub",
            }
            if c.side == "LEFT" then
              comment.oldLine = c.line
            else
              comment.newLine = c.line
            end
            comments[#comments + 1] = comment
          else
            skipped = skipped + 1
          end
        end
      end
      if #comments > 0 then
        hunk_json({ "session", "comment", "apply", rec.id, "--stdin", "--json" }, function(_, apply_err)
          if apply_err then
            notify("Some GitHub anchors are not in this diff; inline import skipped")
          end
        end, vim.json.encode({ comments = comments }))
      end
      if skipped > 0 then
        notify("Skipped " .. skipped .. " outdated/unmapped GitHub comment(s)")
      end
    end
  )
end
capture = function(rec, cb, fresh)
  cb = cb or function() end
  if rec.discarded then
    return cb()
  end
  if rec.capturing then
    rec.waiters[#rec.waiters + 1] = fresh and function()
      capture(rec, cb, true)
    end or cb
    return
  end
  if not rec.live then
    return cb()
  end
  rec.capturing, rec.waiters = true, { cb }
  local function finish()
    rec.capturing = false
    local waiters = rec.waiters
    rec.waiters = {}
    for _, done in ipairs(waiters) do
      done()
    end
    render()
  end
  local function read_notes()
    hunk_json({ "session", "comment", "list", rec.id, "--type", "user", "--json" }, function(value, err)
      if not rec.discarded and value and type(value.comments) == "table" then
        save_snapshot(rec, value.comments)
        rec.capture_error = nil
        return finish()
      end
      rec.capture_error = err and err.message or "Comment capture failed"
      hunk_json({ "session", "list", "--json" }, function(list)
        if list then
          local found = false
          for _, s in ipairs(list.sessions or {}) do
            if s.sessionId == rec.id then
              found = true
            end
          end
          if not found then
            rec.live = false
          end
        end
        finish()
      end)
    end)
  end
  if rec.id then
    return read_notes()
  end
  hunk_json({ "session", "list", "--json" }, function(list, err)
    if rec.discarded then
      return finish()
    end
    local matches = {}
    for _, s in ipairs(list and list.sessions or {}) do
      if session_matches(s, rec.marker) then
        matches[#matches + 1] = s
      end
    end
    if #matches == 1 then
      rec.id = matches[1].sessionId
      import_comments(rec)
      return read_notes()
    end
    rec.capture_error = err and err.message or "Waiting for exact hunk session identity"
    if vim.uv.now() - rec.started > 10000 and not rec.identity_notice then
      rec.identity_notice = true
      notify("Cannot identify this hunk session reliably; comment capture/import disabled until it connects")
    end
    finish()
  end)
end
local function tick()
  for _, rec in pairs(reviews) do
    if rec.live then
      capture(rec)
    end
  end
end
local function start_timer()
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(tick))
end
local function hide_hunk(rec)
  capture(rec, nil, true)
  vim.cmd.stopinsert()
  if rec.buf and vim.api.nvim_buf_is_valid(rec.buf) then
    vim.bo[rec.buf].bufhidden = "hide"
    for _, win in ipairs(vim.fn.win_findbuf(rec.buf)) do
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  return_board()
  render()
end
local function show_hunk(rec)
  if not rec.buf or not vim.api.nvim_buf_is_valid(rec.buf) then
    return false
  end
  local wins = vim.fn.win_findbuf(rec.buf)
  if wins[1] then
    vim.api.nvim_set_current_win(wins[1])
  else
    local g = geometry()
    g.zindex = 75
    g.title = " PR #" .. rec.pr.number .. " · " .. rec.pr.repo .. " "
    vim.api.nvim_open_win(rec.buf, true, g)
  end
  window_style(vim.api.nvim_get_current_win())
  vim.cmd.startinsert()
  return true
end
local function end_review(rec)
  rec.discarded = true
  if rec.addr then
    require("hcmux.term").kill(rec.addr, false)
  end
  if rec.buf and vim.api.nvim_buf_is_valid(rec.buf) then
    for _, win in ipairs(vim.fn.win_findbuf(rec.buf)) do
      pcall(vim.api.nvim_win_close, win, true)
    end
    pcall(vim.api.nvim_buf_delete, rec.buf, { force = true })
  end
  if reviews[key(rec.pr)] == rec then
    reviews[key(rec.pr)] = nil
  end
  -- Keep an empty tombstone snapshot rather than resurrecting discarded drafts.
  if rec.snapshot then
    save_snapshot(rec, {})
  end
  return_board()
  render()
end
local function candidates()
  local paths, seen = {}, {}
  local function add(path)
    if type(path) == "string" and not seen[path] and vim.fn.isdirectory(path) == 1 then
      seen[path] = true
      paths[#paths + 1] = path
    end
  end
  add(root())
  local snap = require("hcmux.t3side").snapshot()
  for _, p in ipairs(snap.projects or {}) do
    add(p.workspaceRoot or p.cwd)
  end
  return paths
end
local function local_checkout(pr, cb)
  local paths = candidates()
  local function next_path(i)
    if not paths[i] then
      return cb()
    end
    gh.origin(paths[i], function(origin)
      if origin and origin:lower() == pr.repo:lower() then
        cb(paths[i])
      else
        next_path(i + 1)
      end
    end)
  end
  next_path(1)
end
local function patch(pr, cb)
  gh.diff(pr, function(out, err)
    if err then
      return cb(nil, err)
    end
    ensure_cache()
    local path = stem(pr) .. ".diff"
    local ok = pcall(vim.fn.writefile, vim.split(out, "\n", { plain = true }), path)
    if not ok then
      return cb(nil, { message = "Cannot write PR patch cache" })
    end
    cb(path)
  end)
end
local function fallback(pr)
  notify("hunk not installed; showing read-only diff")
  gh.diff(pr, function(out, err)
    if not M.active then
      return
    end
    if err then
      return notify(err.message)
    end
    popup("PR #" .. pr.number .. " · " .. pr.repo, vim.split(out, "\n", { plain = true }), "diff")
  end)
end
local launching = {}
review = function(pr)
  if not pr then
    return
  end
  local existing = reviews[key(pr)]
  if existing and existing.live then
    if show_hunk(existing) then
      return
    end
    notify("Hunk is still running without a viewer; use x to end it before reopening")
    return
  end
  if existing and existing.snapshot and #existing.snapshot.comments > 0 then
    notify("Captured drafts exist; submit or x to discard before starting another review")
    return
  end
  if vim.fn.executable("hunk") ~= 1 then
    return fallback(pr)
  end
  if launching[key(pr)] then
    return
  end
  launching[key(pr)] = true
  local launch_epoch = opened
  local function failed(err)
    launching[key(pr)] = nil
    notify(err.message)
  end
  gh.view(pr, function(fresh, err)
    if err then
      return failed(err)
    end
    if not M.active or opened ~= launch_epoch then
      launching[key(pr)] = nil
      return
    end
    pr = fresh
    local function launch(args, cwd)
      launching[key(pr)] = nil
      if not M.active or opened ~= launch_epoch then
        return
      end
      theme()
      if theme_name then
        vim.list_extend(args, { "--theme", theme_name })
      end
      vim.list_extend(args, { "--no-transparent-bg" })
      -- Hunk publishes TERM_SESSION_ID in terminal.locations. A unique, inherited
      -- marker avoids repo/cwd guessing, including concurrent reviews in one repo.
      local marker = "envi-pr-" .. vim.fn.getpid() .. "-" .. tostring(vim.uv.hrtime())
      local argv = { "env", "TERM_SESSION_ID=" .. marker }
      vim.list_extend(argv, args)
      local b, addr = require("hcmux.term").open(argv, {
        where = "float",
        size = 0.92,
        title = "PR #" .. pr.number .. " · " .. pr.repo,
        cwd = cwd,
        session = false,
        listed = false,
      })
      if not b or not addr then
        return
      end
      local rec =
        { pr = pr, head = pr.headRefOid, marker = marker, buf = b, addr = addr, live = true, started = vim.uv.now() }
      reviews[key(pr)] = rec
      vim.bo[b].bufhidden = "hide"
      vim.bo[b].buflisted = false
      -- term.open's float sits at the default zindex (50), under the board (60):
      -- give it the same geometry and layer as a re-shown hunk.
      local win, g = vim.api.nvim_get_current_win(), geometry()
      g.zindex = 75
      g.title = " PR #" .. pr.number .. " · " .. pr.repo .. " "
      vim.api.nvim_win_set_config(win, g)
      window_style(win)
      vim.keymap.set("t", "<C-q>", function()
        hide_hunk(rec)
      end, { buffer = b, nowait = true, silent = true })
      vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        buffer = b,
        once = true,
        callback = function()
          if not rec.discarded then
            vim.schedule(function()
              capture(rec)
              return_board()
              render()
            end)
          end
        end,
      })
      start_timer()
      capture(rec)
      render()
    end
    local_checkout(pr, function(cwd)
      local function use_patch()
        patch(pr, function(path, e)
          if e then
            return failed(e)
          end
          launch({ "hunk", "patch", path }, root())
        end)
      end
      if not cwd then
        return use_patch()
      end
      gh.run(
        { "git", "fetch", "--no-tags", "--refmap=", "origin", "refs/pull/" .. pr.number .. "/head" },
        { cwd = cwd },
        function(_, fetch_err)
          if fetch_err then
            return use_patch()
          end
          gh.run({ "git", "rev-parse", "FETCH_HEAD" }, { cwd = cwd }, function(head, e)
            if e or vim.trim(head) ~= pr.headRefOid then
              return failed({ message = "PR moved during fetch; r to retry" })
            end
            gh.run({ "git", "merge-base", pr.baseRefOid, pr.headRefOid }, { cwd = cwd }, function(base, base_err)
              if base_err then
                return use_patch()
              end
              launch({ "hunk", "diff", vim.trim(base), pr.headRefOid }, cwd)
            end)
          end)
        end
      )
    end)
  end)
end

local function map_notes(notes)
  local comments, ambiguous = {}, {}
  for _, note in ipairs(notes) do
    local range = note.newRange or note.oldRange
    local side = note.newRange and "RIGHT" or "LEFT"
    local path = note.filePath
    if
      type(path) ~= "string"
      or path == ""
      or path:sub(1, 1) == "/"
      or path:find("%c")
      or path:match("^%.%./")
      or path:find("/../", 1, true)
      or type(note.body) ~= "string"
      or vim.trim(note.body) == ""
      or (note.newRange and note.oldRange)
      or type(range) ~= "table"
      or #range ~= 2
      or type(range[1]) ~= "number"
      or type(range[2]) ~= "number"
      or range[1] < 1
      or range[2] < range[1]
      or range[1] % 1 ~= 0
      or range[2] % 1 ~= 0
    then
      ambiguous[#ambiguous + 1] = clean(note.noteId or "unknown") .. " · " .. clean(path) .. " · ambiguous anchor"
    else
      local comment = { path = path, body = note.body, line = range[2], side = side }
      if range[1] ~= range[2] then
        comment.start_line, comment.start_side = range[1], side
      end
      comments[#comments + 1] = comment
    end
  end
  return comments, ambiguous
end
submit = function(pr)
  submit_epoch = submit_epoch + 1
  local epoch = submit_epoch
  if not pr then
    return
  end
  local rec = reviews[key(pr)]
  if not rec then
    return notify("Review this PR in hunk first")
  end
  capture(rec, function()
    if rec.discarded or not M.active or epoch ~= submit_epoch then
      return
    end
    if not rec.snapshot then
      return notify("No captured comments yet; keep hunk open until capture succeeds")
    end
    if rec.live and rec.capture_error then
      return notify("Cannot refresh live comments; submission refused")
    end
    gh.view(pr, function(fresh, err)
      if not M.active or rec.discarded or epoch ~= submit_epoch then
        return
      end
      if err then
        return notify(err.message)
      end
      if fresh.headRefOid ~= rec.snapshot.head then
        return notify("PR moved since capture; submit refused. Discard drafts and review the new head")
      end
      -- Freeze the confirmed body; a later timer capture cannot change this request.
      local snapshot = vim.deepcopy(rec.snapshot)
      local comments, ambiguous = map_notes(snapshot.comments)
      local lines = {
        "Submit review to " .. pr.repo .. "#" .. pr.number .. ": " .. #comments .. " comments as",
        "[c]omment / [a]pprove / [r]equest changes, Esc cancels",
      }
      if not rec.live then
        lines[#lines + 1] = "hunk closed; using comments captured at " .. snapshot.capturedAt
      end
      if vim.env.ENVI_PR_DRY_RUN == "1" then
        lines[#lines + 1] = "DRY RUN · writes last-review.json; no GitHub write"
      end
      if #ambiguous > 0 then
        lines[#lines + 1] = "Submission refused: remove ambiguous notes in hunk first"
        vim.list_extend(lines, ambiguous)
      end
      local confirm = popup("Submit review", lines, "envi-pr-confirm")
      local sending = false
      for lhs, event in pairs({ c = "COMMENT", a = "APPROVE", r = "REQUEST_CHANGES" }) do
        map(confirm, "n", lhs, function()
          if #ambiguous > 0 or sending then
            return
          end
          sending = true
          -- Revalidate after confirmation: the PR can move while the dialog is open.
          gh.view(pr, function(now, e)
            if modal ~= confirm or rec.discarded then
              return
            end
            if e then
              sending = false
              return notify(e.message)
            end
            if now.headRefOid ~= snapshot.head then
              close_modal()
              return notify("PR moved; submission refused")
            end
            local body = { event = event, commit_id = snapshot.head, comments = comments }
            if vim.env.ENVI_PR_DRY_RUN == "1" then
              ensure_cache()
              local path = cache_dir .. "/last-review.json"
              local ok = pcall(vim.fn.writefile, { vim.json.encode(body) }, path)
              if not ok then
                sending = false
                return notify("Cannot write dry-run review")
              end
              vim.fn.setfperm(path, "rw-------")
              close_modal()
              notify("Dry-run review: " .. path)
              return
            end
            gh.json(
              { "api", "repos/" .. pr.repo .. "/pulls/" .. pr.number .. "/reviews", "--method", "POST", "--input", "-" },
              function(_, post_err)
                if post_err then
                  sending = false
                  notify(post_err.message)
                  return
                end
                close_modal()
                end_review(rec)
                notify("Review submitted")
                refresh_scope()
              end,
              { stdin = vim.json.encode(body) }
            )
          end)
        end)
      end
    end)
  end, true)
end

local function discard(pr)
  local rec = pr and reviews[key(pr)]
  if not rec then
    return
  end
  capture(rec, function()
    if rec.discarded or not M.active then
      return
    end
    local n = rec.snapshot and #rec.snapshot.comments or 0
    local confirm = popup("Discard review", {
      "Discard " .. n .. " drafted comment(s)? y/n",
      rec.capture_error and "Live capture unavailable; this also discards any uncaptured notes"
        or "End this PR's hunk; no GitHub changes",
    }, "envi-pr-confirm")
    map(confirm, "n", "n", close_modal)
    map(confirm, "n", "y", function()
      close_modal()
      end_review(rec)
    end)
  end)
end
local function help()
  local view = popup("PR keys", {
    "Board                           Action",
    "j/k · gg/G · Ctrl-d/u           Select card / first / last / page",
    "Enter / l                       Review in hunk (re-show same live terminal)",
    "/                               Fuzzy search #number title branch author repo",
    "Search INSERT Esc / Enter       NORMAL / review top hit",
    "Tab / Shift-Tab                 Next / previous scope",
    "K                               Details overlay on narrow editors",
    "o / y                           Open PR in browser / yank URL",
    "c                               Checks; Enter opens selected check URL",
    "r / R                           Refresh / pick Repo scope repository",
    "s                               Confirm comment / approve / request changes",
    "x                               Discard drafts and end this PR's hunk",
    "q / Esc                         Close this view (board leaves hunks alive)",
    "Hunk <C-q>                      Hide float, capture drafts, return to board",
    "Hunk q                          Hunk's own quit; last captured drafts remain",
    "?                               Help (q / Esc / ? dismiss)",
  })
  map(view, "n", "?", close_modal)
end
local function check_view(pr)
  if not pr then
    return
  end
  local list, lines = checks(pr), {}
  for _, c in ipairs(list) do
    lines[#lines + 1] = c.text
  end
  if #lines == 0 then
    lines = { "No checks reported" }
  end
  local view = popup("Checks · #" .. pr.number, lines, "envi-pr-checks")
  map(view, "n", "<CR>", function()
    local c = list[vim.api.nvim_win_get_cursor(view.win)[1]]
    if c and type(c.url) == "string" and c.url:match("^https://") then
      if vim.env.ENVI_PR_NO_BROWSER == "1" then
        notify("Browser suppressed: " .. c.url)
      else
        vim.ui.open(c.url)
      end
    end
  end)
end
local function pick_repo()
  local choices, seen = {}, {}
  local function add(name)
    if name and not seen[name] then
      seen[name] = true
      choices[#choices + 1] = name
    end
  end
  add(repo)
  local paths = candidates()
  local remaining = #paths + 1
  local function done()
    remaining = remaining - 1
    if remaining > 0 or not M.active then
      return
    end
    vim.ui.select(choices, { prompt = "Repo scope repository" }, function(choice)
      if choice and M.active then
        repo, scope, query, selected = choice, 1, "", 1
        refresh_scope()
      end
    end)
  end
  for _, path in ipairs(paths) do
    gh.origin(path, function(name)
      add(name)
      done()
    end)
  end
  gh.json({ "repo", "list", "--limit", "50", "--json", "nameWithOwner,updatedAt" }, function(value)
    table.sort(value or {}, function(a, b)
      return (a.updatedAt or "") > (b.updatedAt or "")
    end)
    for _, row in ipairs(value or {}) do
      add(row.nameWithOwner)
    end
    done()
  end)
end
local function maps()
  for _, pair in ipairs({ { "j", 1 }, { "<Down>", 1 }, { "k", -1 }, { "<Up>", -1 } }) do
    map(board, "n", pair[1], function()
      move(pair[2])
    end)
  end
  map(board, "n", "gg", function()
    selected = 1
    render()
  end)
  map(board, "n", "G", function()
    selected = #hits
    render()
  end)
  for _, pair in ipairs({ { "<C-d>", 1 }, { "<C-u>", -1 } }) do
    map(board, "n", pair[1], function()
      move(pair[2] * math.max(1, math.floor((vim.api.nvim_win_get_height(board.win) - 6) / 5)))
    end)
  end
  for _, lhs in ipairs({ "<CR>", "l" }) do
    map(board, "n", lhs, function()
      review(current())
    end)
  end
  map(board, "n", "/", function()
    editing = true
    render()
    vim.api.nvim_set_current_win(search.win)
    vim.api.nvim_win_set_cursor(search.win, { 1, #query })
    vim.cmd.startinsert({ bang = true })
  end)
  for _, pair in ipairs({ { "<Tab>", 1 }, { "<S-Tab>", -1 } }) do
    map(board, "n", pair[1], function()
      default_scope = false
      scope = (scope - 1 + pair[2]) % #scopes + 1
      query, selected = "", 1
      refresh_scope()
    end)
  end
  map(board, "n", "K", function()
    if vim.o.columns >= 140 then
      return
    end
    if detail_visible then
      close_modal()
      detail_visible = false
      return
    end
    popup("PR details", detail_lines(current()), "markdown")
    detail_visible = true
  end)
  map(board, "n", "o", function()
    local pr = current()
    if pr then
      if vim.env.ENVI_PR_NO_BROWSER == "1" then
        return notify("Browser suppressed: " .. pr.url)
      end
      gh.run({ "gh", "pr", "view", tostring(pr.number), "-R", pr.repo, "--web" }, {}, function(_, err)
        if err then
          notify(err.message)
        end
      end)
    end
  end)
  map(board, "n", "y", function()
    local pr = current()
    if pr then
      vim.fn.setreg("+", pr.url)
      notify("Yanked " .. pr.url)
    end
  end)
  map(board, "n", "c", function()
    check_view(current())
  end)
  map(board, "n", "s", function()
    submit(current())
  end)
  map(board, "n", "x", function()
    discard(current())
  end)
  map(board, "n", "r", refresh_scope)
  map(board, "n", "R", pick_repo)
  map(board, "n", "?", help)
  map(board, "n", "q", M.close)
  map(board, "n", "<Esc>", M.close)
end

function M.close()
  if not M.active then
    return
  end
  for _, rec in pairs(reviews) do
    if rec.live then
      hide_hunk(rec)
    end
  end
  M.active, editing = false, false
  generation = generation + 1
  vim.cmd.stopinsert()
  close_modal()
  local old_board, old_detail, old_search = board, detail, search
  board, detail, search = nil, nil, nil
  destroy(old_search)
  destroy(old_detail)
  destroy(old_board)
  status()
end

function M.open(opts)
  opts = opts or {}
  if M.active then
    return return_board()
  end
  opened = opened + 1
  local token = opened
  scope, query, selected, rows = 1, "", 1, {}
  default_scope = opts.scope == nil
  for i, name in ipairs(scopes) do
    if opts.scope == name then
      scope = i
    end
  end
  if opts.repo then
    repo = opts.repo
  end
  theme()
  board = create(geometry(), "envi-prs", true)
  M.active = true
  maps()
  render()
  status()
  local owned = board
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(board.win),
    once = true,
    callback = function()
      if board == owned then
        M.close()
      end
    end,
  })
  -- Capture on focus as well as hide/timer/submit. Never start another terminal.
  vim.api.nvim_create_autocmd("BufEnter", { group = group, buffer = board.buf, callback = tick })
  local function initial()
    if not M.active or token ~= opened then
      return
    end
    refresh_scope()
    for _, name in ipairs(scopes) do
      if name ~= scopes[scope] and name ~= "Repo" then
        gh.list(name, repo, function(value, _, busy)
          if not M.active or token ~= opened then
            return
          end
          if not busy or #value > 0 then
            counts[name] = #value
            render()
          end
        end)
      end
    end
  end
  if opts.repo then
    initial()
  else
    gh.origin(root(), function(name)
      repo = name
      initial()
    end)
  end
end
function M.toggle()
  if M.active then
    M.close()
  else
    M.open()
  end
end

vim.api.nvim_create_autocmd({ "VimResized", "WinResized", "ColorScheme" }, {
  group = group,
  callback = function()
    render()
    if valid(modal) then
      local g = geometry(0.8)
      g.height = math.min(g.height, math.max(3, #modal.lines))
      g.zindex = 80
      vim.api.nvim_win_set_config(modal.win, g)
    end
    for _, rec in pairs(reviews) do
      for _, w in ipairs(rec.buf and vim.api.nvim_buf_is_valid(rec.buf) and vim.fn.win_findbuf(rec.buf) or {}) do
        local g = geometry()
        g.zindex = 75
        g.title = " PR #" .. rec.pr.number .. " · " .. rec.pr.repo .. " "
        vim.api.nvim_win_set_config(w, g)
        window_style(w)
      end
    end
  end,
})
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    for _, rec in pairs(reviews) do
      rec.discarded = true
      -- On exit asynchronous jobs may not finish. Bound the owned-terminal cleanup;
      -- never enumerate or kill another module's/session's terminals.
      if rec.addr then
        pcall(function()
          vim.system({ "hc", "kill", rec.addr }, { timeout = 1500 }):wait()
        end)
      end
    end
  end,
})
return M
