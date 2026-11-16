-- Thread snapshot -> sidebar. One asynchronous NDJSON feed per Neovim.
local M = {}
local source = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)) or debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":h:h:h")
local hub_file = vim.fn.fnamemodify(root, ":h") .. "/theme/theme.json"
local ns = vim.api.nvim_create_namespace("envi.t3side")
local buf, job, selected, message
local rows, snapshot = {}, { projects = {}, threads = {} }
local group = vim.api.nvim_create_augroup("envi.t3side", { clear = true })
local stopping = false
local collapsed, settled_open = {}, false
local subscribers = {}

local function highlights()
  local colors = { working = "#81a1c1", attention = "#bf616a", done = "#a3be8c", idle = "#9aa3b5", error = "#bf616a" }
  local ok, theme = pcall(function()
    local hub = vim.json.decode(table.concat(vim.fn.readfile(vim.env.ENVI_THEME_FILE or hub_file), "\n"))
    local t = hub.themes[vim.env.ENVI_THEME or hub.active]
    local function resolve(value)
      local color = value:sub(1, 1) == "#" and value or t.palette[value]
      assert(color and color:match("^#%x%x%x%x%x%x$"))
      return color
    end
    return {
      working = resolve(t.tokens.status.info), -- blue, like T3 desktop's "Working"
      attention = resolve(t.tokens.status.error),
      done = resolve(t.tokens.status.success),
      idle = resolve(t.tokens.ui.muted),
      error = resolve(t.tokens.status.error),
      claude = resolve(t.tokens.ui.accent),
    }
  end)
  colors = ok and theme or colors
  for _, status in ipairs({ "working", "attention", "done", "idle", "error" }) do
    vim.api.nvim_set_hl(0, "EnviT3Side_" .. status, { fg = colors[status] })
  end
  vim.api.nvim_set_hl(0, "EnviT3SideSelected", { bg = "#4d6376" })
  vim.api.nvim_set_hl(0, "EnviT3SideUnread", { fg = "#fffeff", bold = true })
  vim.api.nvim_set_hl(0, "EnviT3SideGroup", { bold = true })
  vim.api.nvim_set_hl(0, "EnviT3SideBranch", { fg = "#a4a6ac" })
  vim.api.nvim_set_hl(0, "EnviT3SideClaude", { fg = colors.claude or "#b18171" })
  vim.api.nvim_set_hl(0, "EnviT3SidePi", { fg = "#ffda61" })
  for index, color in ipairs({ "#ffdc02", "#5dc8ff", "#e88efd", "#c2f342", "#59e3ff", "#66deac" }) do
    vim.api.nvim_set_hl(0, "EnviT3SideBadge" .. index, { fg = color, bold = true })
  end
end

local function clean(s)
  return tostring(s or ""):gsub("[%c]", " ")
end

local function truncate(s, width)
  s = clean(s)
  if vim.fn.strdisplaywidth(s) <= width then
    return s
  end
  local result = ""
  for char in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if vim.fn.strdisplaywidth(result .. char .. "…") > width then
      break
    end
    result = result .. char
  end
  return width > 0 and result .. "…" or ""
end

local function age(value)
  local y, m, d, h, min, sec = tostring(value):match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
  if not y then
    return ""
  end
  -- Feed timestamps are UTC. Convert the current local UTC offset as well.
  local now = os.time()
  local utc = os.date("!*t", now)
  utc.isdst = os.date("*t", now).isdst
  local offset = os.difftime(now, os.time(utc))
  local seconds = math.max(0, now - (os.time({
    year = tonumber(y),
    month = tonumber(m),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(min),
    sec = tonumber(sec),
    isdst = utc.isdst,
  }) + offset))
  if seconds < 60 then
    return "now"
  end
  if seconds < 3600 then
    return math.floor(seconds / 60) .. "m"
  end
  if seconds < 86400 then
    return math.floor(seconds / 3600) .. "h"
  end
  return math.floor(seconds / 86400) .. "d"
end

-- Prefer feed provenance; a GPT model alone cannot identify its harness.
local function harness(thread)
  if thread.harness == "claudeAgent" then
    return "✳", "EnviT3SideClaude"
  end
  if thread.harness == "pi" then
    return "π", "EnviT3SidePi"
  end
  if thread.harness == "codex" then
    return "", "EnviT3Side_idle"
  end
  local model = (thread.model or ""):lower()
  if model:match("^pi/") then
    return "π", "EnviT3SidePi"
  end
  if model:find("claude", 1, true) then
    return "✳", "EnviT3SideClaude"
  end
  return "◇", "EnviT3Side_idle"
end

local function badge(project)
  local name = clean(project.name or project.id)
  local slug = name:match("([^/]+)$") or name
  local known = {
    [".dotfiles"] = { "DS", 1 },
    dotfiles = { "DS", 1 },
    ["ops-platform"] = { "OP", 2 },
    ["symbios-systems"] = { "SS", 3 },
    ["Agent Wiki"] = { "AW", 4 },
    Workspace = { "WE", 5 },
    ["atlantis-electrical"] = { "AE", 6 },
  }
  if known[slug] then
    return unpack(known[slug])
  end
  local initials = ""
  for word in slug:gmatch("[%w]+") do
    initials = initials .. word:sub(1, 1):upper()
  end
  initials = (initials .. slug:upper()):sub(1, 2)
  local hash = 0
  for i = 1, #slug do
    hash = (hash + slug:byte(i)) % 6
  end
  return initials, hash + 1
end

local function recent(a, b)
  local function priority(t)
    if t.status == "working" then
      return 0
    end
    if t.status == "attention" or t.status == "error" then
      return 1
    end
    if t.status == "done" and t.unread then
      return 2
    end
    return 3
  end
  if priority(a) ~= priority(b) then
    return priority(a) < priority(b)
  end
  if (a.updatedAt or "") ~= (b.updatedAt or "") then
    return (a.updatedAt or "") > (b.updatedAt or "")
  end
  return a.id < b.id
end

function M.render()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  highlights()
  local wins, cursors = vim.fn.win_findbuf(buf), {}
  local width = 36
  for _, win in ipairs(wins) do
    width = math.min(width, vim.api.nvim_win_get_width(win))
    local line = vim.api.nvim_win_get_cursor(win)[1]
    cursors[win] = { row = rows[line], line = line }
  end
  local lines, marks, next_rows = {}, {}, {}
  local function add(text, row, group_name)
    text = truncate(text, width)
    lines[#lines + 1], next_rows[#lines + 1] = text, row
    if group_name then
      marks[#marks + 1] = { line = #lines - 1, start = 0, finish = #text, hl = group_name }
    end
    return #lines
  end
  local function mark(line, start, finish, hl)
    if finish > start then
      marks[#marks + 1] = { line = line - 1, start = start, finish = finish, hl = hl }
    end
  end
  -- Reserve the suffix before truncating the title, using display cells for
  -- alignment and byte offsets only for highlights (wide UTF-8 titles work).
  local function paired(left, right, row, left_hl, right_hl)
    right = truncate(right, math.max(0, width - 2))
    left = truncate(left, math.max(0, width - vim.fn.strdisplaywidth(right) - 1))
    local pad = math.max(1, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right))
    local prefix = left .. string.rep(" ", pad)
    local line = add(prefix .. right, row)
    if left_hl then
      mark(line, 0, #left, left_hl)
    end
    if right_hl then
      mark(line, #prefix, #prefix + #right, right_hl)
    end
    return line, #prefix
  end
  local function thread_row(t, pinned_project)
    local status = ({ working = "◌ Working", attention = "? Input", done = "✓ Done", error = "! Error" })[t.status]
      or age(t.updatedAt)
    local status_hl = "EnviT3Side_"
      .. (({ working = true, attention = true, done = true, error = true })[t.status] and t.status or "idle")
    local icon, icon_hl = harness(t)
    local branch = t.branch ~= vim.NIL and t.branch or nil
    if not branch or branch == "" then
      branch = t.worktreePath and t.worktreePath ~= vim.NIL and vim.fs.basename(t.worktreePath) or nil
    end
    local row = { id = t.id, part = "title", key = "thread:" .. t.id .. ":title" }
    if pinned_project then
      local code, color = badge(pinned_project)
      local line = paired(
        " " .. code .. " 📌 " .. clean(pinned_project.name),
        status,
        { id = t.id, part = "project", key = "thread:" .. t.id .. ":project" },
        "EnviT3SideBranch",
        status_hl
      )
      mark(line, 1, 1 + #code, "EnviT3SideBadge" .. color)
    end
    local suffix = pinned_project and "" or (branch and status or (icon .. " " .. status))
    local line, suffix_start = paired(
      "  " .. clean(t.title or t.id),
      suffix,
      row,
      t.unread and "EnviT3SideUnread" or nil,
      not pinned_project and status_hl or nil
    )
    if not branch and not pinned_project then
      mark(line, suffix_start, suffix_start + #icon, icon_hl)
    end
    if branch then
      paired(
        "     " .. clean(branch),
        icon,
        { id = t.id, part = "branch", key = "thread:" .. t.id .. ":branch" },
        "EnviT3SideBranch",
        icon_hl
      )
    elseif pinned_project then
      paired("", icon, { id = t.id, part = "harness", key = "thread:" .. t.id .. ":harness" }, nil, icon_hl)
    end
  end
  if message then
    add("T3 unavailable: " .. message, nil, "EnviT3Side_error")
  end
  local projects = vim.deepcopy(snapshot.projects or {})
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local repo = vim.fs.root(cwd, ".git") or cwd
  local function here(p)
    local path = vim.fs.normalize(p.cwd or "")
    return path == cwd or path == repo or cwd:sub(1, #path + 1) == path .. "/"
  end
  table.sort(projects, function(a, b)
    if here(a) ~= here(b) then
      return here(a)
    end
    return (a.name or a.id) < (b.name or b.id)
  end)
  local by_project, pinned, settled, known = {}, {}, {}, {}
  for _, p in ipairs(projects) do
    known[p.id] = p
  end
  for _, t in ipairs(snapshot.threads or {}) do
    if not t.archived and t.listed ~= false then
      local project_id = t.projectId ~= vim.NIL and t.projectId or "no-project"
      if not known[project_id] then
        local p = { id = project_id, name = "No project" }
        projects[#projects + 1] = p
        known[project_id] = p
      end
      if t.settled then
        settled[#settled + 1] = t
      end
      if t.pinned and not t.settled then
        pinned[#pinned + 1] = t
      elseif not t.settled or t.id == selected then
        by_project[project_id] = by_project[project_id] or {}
        table.insert(by_project[project_id], t)
      end
    end
  end
  table.sort(pinned, recent)
  if #pinned > 0 then
    add(" PINNED", { key = "pinned" }, "EnviT3SideBranch")
    for _, t in ipairs(pinned) do
      thread_row(t, known[t.projectId])
    end
    add("")
  end
  for _, p in ipairs(projects) do
    local threads = by_project[p.id] or {}
    if #threads > 0 then
      table.sort(threads, recent)
      local count = 0
      for _, t in ipairs(threads) do
        if t.status == "done" then
          count = count + 1
        end
      end
      local code, color = badge(p)
      local suffix = collapsed[p.id] and ("● " .. count .. " ›") or "⌄"
      local line, start = paired(
        " " .. code .. " " .. clean(p.name),
        suffix,
        { group = p.id, key = "project:" .. p.id },
        "EnviT3SideGroup",
        "EnviT3Side_idle"
      )
      mark(line, 1, 1 + #code, "EnviT3SideBadge" .. color)
      if collapsed[p.id] then
        mark(line, start, start + #"●", "EnviT3Side_done")
      end
      for _, t in ipairs(threads) do
        if not collapsed[p.id] or t.id == selected or t.status == "working" then
          thread_row(t)
        end
      end
      add("")
    end
  end
  if settled_open then
    table.sort(settled, recent)
    for _, t in ipairs(settled) do
      if t.id ~= selected then
        thread_row(t)
      end
    end
  end
  add(
    " Settled  " .. #settled .. " " .. (settled_open and "⌄" or "›"),
    { settled = true, key = "settled" },
    "EnviT3SideBranch"
  )
  rows = next_rows
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, m.line, m.start, { end_col = m.finish, hl_group = m.hl, priority = 200 })
  end
  for line, row in pairs(rows) do
    if row.id == selected then
      vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, { line_hl_group = "EnviT3SideSelected" })
    end
  end
  for win, cursor in pairs(cursors) do
    local line = math.min(cursor.line, #lines)
    if cursor.row then
      local exact
      for index, row in pairs(rows) do
        if row.key == cursor.row.key then
          exact = index
          break
        end
        if cursor.row.id and row.id == cursor.row.id and row.part == "title" then
          line = index
        end
      end
      line = exact or line
    end
    vim.api.nvim_win_set_cursor(win, { line, 0 })
  end
end

function M.select(id)
  selected = id
  M.render()
end

--- Move this bar window to an exact rendered title (never a metadata line).
function M.focus_card(win, id)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
    return
  end
  for line, row in pairs(rows) do
    if row.id == id and row.part == "title" then
      vim.api.nvim_win_set_cursor(win, { line, 0 })
      return
    end
  end
end

function M.title(id)
  for _, thread in ipairs(snapshot.threads or {}) do
    if thread.id == id then
      return thread.title
    end
  end
end

function M.update(value)
  if value.type == "snapshot" and type(value.projects) == "table" and type(value.threads) == "table" then
    snapshot, message = value, nil
  elseif value.type == "error" then
    message = clean(value.message or "feed failed")
  else
    message = "invalid thread snapshot"
  end
  M.render()
  for callback in pairs(subscribers) do
    callback(M.snapshot())
  end
end

--- Shared feed, independent of the sidebar buffer. Call start() to ensure the job.
function M.snapshot()
  return vim.deepcopy(snapshot), message
end

--- Subscribe immediately; returns an unsubscribe function. Closing a consumer
--- never stops the shared job (which lives until VimLeavePre).
function M.subscribe(callback)
  subscribers[callback] = true
  callback(M.snapshot())
  return function()
    subscribers[callback] = nil
  end
end

-- One presentation vocabulary for both catalogue and AGENT cards.
M.presentation =
  { highlights = highlights, clean = clean, truncate = truncate, age = age, harness = harness, recent = recent }

-- Navigation uses only rendered title anchors, never metadata or hidden cards.
local function move_card(direction, count)
  local win = vim.api.nvim_get_current_win()
  local line = vim.api.nvim_win_get_cursor(win)[1]
  local current = rows[line]
  local cards, seen, origin = {}, {}, nil
  for index = 1, vim.api.nvim_buf_line_count(buf) do
    local row = rows[index]
    if row and row.id and row.part == "title" and not seen[row.id] then
      seen[row.id] = true
      cards[#cards + 1] = index
      if current and current.id == row.id then
        origin = #cards
      end
    end
  end
  if #cards == 0 then
    return
  end
  local target
  if origin then
    target = origin + direction * count
  elseif direction > 0 then
    target = #cards
    for index, anchor in ipairs(cards) do
      if anchor > line then
        target = index + count - 1
        break
      end
    end
  else
    target = 1
    for index = #cards, 1, -1 do
      if cards[index] < line then
        target = index - count + 1
        break
      end
    end
  end
  target = math.max(1, math.min(#cards, target))
  vim.api.nvim_win_set_cursor(win, { cards[target], 0 })
end

--- Full, UI-independent title candidates. Context is displayed, not matched.
function M.search_items()
  local value = M.snapshot()
  local ui = M.presentation
  local projects, items = {}, {}
  for _, project in ipairs(value.projects or {}) do
    projects[project.id] = ui.clean(project.name or project.id)
  end
  for _, thread in ipairs(value.threads or {}) do
    if not thread.archived and thread.listed ~= false then
      items[#items + 1] = {
        id = thread.id,
        text = ui.clean(thread.title or thread.id),
        project = projects[thread.projectId] or "No project",
        age = ui.age(thread.updatedAt),
      }
    end
  end
  return items
end

function M.search()
  if not (_G.Snacks and Snacks.picker) then
    return vim.notify("T3: snacks.nvim picker is required", vim.log.levels.ERROR)
  end
  local sidebar = vim.api.nvim_get_current_win()
  return Snacks.picker.pick({
    title = "Search thread titles",
    -- Snacks otherwise prefers file buffers over this scratch sidebar on close.
    main = { current = true },
    items = M.search_items(),
    matcher = { fuzzy = true, ignorecase = true, smartcase = false, filename_bonus = false, file_pos = false },
    format = function(item)
      return {
        { item.text, "Normal" },
        { "  · " .. item.project .. " · " .. item.age, "EnviT3SideBranch" },
      }
    end,
    preview = false,
    layout = { preset = "select", preview = false },
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      -- Let the picker restore its invoker before the layout opens the client.
      vim.schedule(function()
        require("hcmux.layout").open_thread(item.id)
        if vim.api.nvim_win_is_valid(sidebar) and vim.api.nvim_win_get_buf(sidebar) == buf then
          for line, row in pairs(rows) do
            if row.id == item.id and row.part == "title" then
              vim.api.nvim_win_set_cursor(sidebar, { line, 0 })
              break
            end
          end
        end
      end)
    end,
    win = {
      input = { keys = { ["<Esc>"] = { "close", mode = { "n", "i" } } } },
      list = { keys = { ["<Esc>"] = "close" } },
    },
  })
end

function M.buffer()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "envi-t3-sidebar"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  local function open()
    local row = rows[vim.api.nvim_win_get_cursor(0)[1]]
    if not row then
      return
    end
    if row.group then
      collapsed[row.group] = not collapsed[row.group]
      M.render()
    elseif row.settled then
      settled_open = not settled_open
      M.render()
    elseif row.id then
      local win = vim.api.nvim_get_current_win()
      require("hcmux.layout").open_thread(row.id)
      M.focus_card(win, row.id)
    end
  end
  -- Native press selects the target window, including from terminal INSERT.
  -- Act only on release: leave drag selection and wheel scrolling to Neovim.
  -- A drag enters Visual mode, where this normal-only mapping does not apply.
  vim.keymap.set("n", "<LeftRelease>", function()
    if vim.o.mouse == "" then
      return
    end
    local mouse = vim.fn.getmousepos()
    if
      not mouse.winid
      or not vim.api.nvim_win_is_valid(mouse.winid)
      or vim.api.nvim_win_get_buf(mouse.winid) ~= buf
      or not mouse.line
      or mouse.line < 1
      or not rows[mouse.line]
    then
      return
    end
    vim.api.nvim_set_current_win(mouse.winid)
    vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, 0 })
    open()
  end, { buffer = buf, silent = true, desc = "T3: click thread card or disclosure" })
  for _, key in ipairs({ "<CR>", "o" }) do
    vim.keymap.set("n", key, open, { buffer = buf, silent = true, desc = "T3: open thread" })
  end
  vim.keymap.set("n", "R", function()
    M.start(true)
  end, { buffer = buf, desc = "T3: refresh threads" })
  -- j/k step visible distinct cards (counts, clamped), landing on titles without
  -- opening clients. Native gg/G and the mouse still reach disclosure headers.
  -- Search is local to this bar; no global or leader maps.
  for key, direction in pairs({ j = 1, k = -1 }) do
    vim.keymap.set("n", key, function()
      move_card(direction, vim.v.count1)
    end, { buffer = buf, silent = true, desc = "T3: " .. (direction > 0 and "next" or "previous") .. " thread card" })
  end
  vim.keymap.set("n", "/", M.search, { buffer = buf, silent = true, desc = "T3: search thread titles" })
  local ok, value = pcall(function()
    return vim.json.decode(
      table.concat(vim.fn.readfile(root .. "/tools/t3-thread/test/fixtures/threads-snapshot.json"), "\n")
    )
  end)
  if ok and not snapshot.type then
    M.update(value)
  end
  M.render()
  vim.api.nvim_exec_autocmds("User", { pattern = "EnviT3Sidebar", data = { buf = buf } })
  return buf
end

function M.start(refresh)
  if job and not refresh then
    return
  end
  if job then
    local old = job
    job = nil
    vim.fn.jobstop(old)
  end
  stopping = false
  local partial = ""
  local id
  id = vim.fn.jobstart({ "node", root .. "/tools/t3-thread/threads.mjs" }, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if stopping or job ~= id then
        return
      end
      data[1] = partial .. data[1]
      partial = table.remove(data)
      for _, line in ipairs(data) do
        if line ~= "" then
          local ok, value = pcall(vim.json.decode, line)
          M.update(ok and type(value) == "table" and value or { type = "error", message = "invalid feed data" })
        end
      end
    end,
    on_exit = function(_, code)
      if stopping or job ~= id then
        return
      end
      job = nil
      M.update({ type = "error", message = "thread feed exited (" .. code .. "); R to retry" })
    end,
  })
  job = id > 0 and id or nil
  if not job then
    M.update({ type = "error", message = "could not start thread feed; R to retry" })
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  callback = function()
    stopping = true
    if job then
      vim.fn.jobstop(job)
      job = nil
    end
  end,
})
vim.api.nvim_create_autocmd({ "ColorScheme", "WinResized" }, { group = group, callback = M.render })
return M
