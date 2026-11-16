-- AGENT is a buffer-local board/search popover, not an editor-wide key layer.
local M = { active = false }
local side = require("hcmux.t3side")
local ui = side.presentation
local ns = vim.api.nvim_create_namespace("envi.agent")
local group = vim.api.nvim_create_augroup("envi.agent", { clear = true })
local buf, win, unsubscribe
local help_buf, help_win
local query_row = 2
local view, query, selected, hit = "board", "", 1, 1
local project, threads, slots, hits = nil, {}, {}, {}
local snapshot, message, anchors = {}, nil, {}
local rendered = {}
local editing, drawing, guarding = false, false, false
local marks, doc, version = {}, nil, 0
local memory = {} -- no-session marks are local to this Neovim, keyed by root
local render, changed, position_help

local function refresh()
  local ok, lualine = pcall(require, "lualine")
  if ok then
    lualine.refresh()
  end
  vim.cmd.redrawstatus({ bang = true })
end

local function root()
  local session = require("hcmux.session")
  return vim.fs.normalize(session.root or vim.fs.root(vim.fn.getcwd(), ".git") or vim.fn.getcwd())
end

local function load_marks()
  local name = require("hcmux.session").name
  -- Core names are 32 bytes max; retain readable short session names without
  -- colliding when long names share a prefix.
  doc = name and ("envi-agent." .. name) or nil
  if doc and (#doc > 32 or doc:find("[^a-z0-9._-]")) then
    doc = "envi-agent." .. vim.fn.sha256(name):sub(1, 21)
  end
  marks, version = {}, 0
  if doc then
    local value, ver, err = require("hcmux.core").doc_get(doc)
    version = ver or 0
    if err then
      vim.notify("AGENT marks: " .. err, vim.log.levels.WARN)
    end
    local used = {}
    for i = 1, 9 do
      local id = type(value) == "table" and type(value.slots) == "table" and value.slots[tostring(i)]
      if type(id) == "string" and not used[id] then
        marks[tostring(i)], used[id] = id, true
      end
    end
  else
    marks = vim.deepcopy(memory[root()] or {})
  end
end

local function save_marks(next_marks)
  if doc then
    local value = { slots = vim.tbl_extend("force", vim.empty_dict(), next_marks) }
    local ver, err = require("hcmux.core").doc_set(doc, value, version)
    if not ver then
      vim.notify(
        "AGENT marks not saved: " .. (err or "document write failed") .. "; reopen to reload",
        vim.log.levels.WARN
      )
      return false -- never overwrite another viewer's document after a conflict
    end
    version = ver
  else
    memory[root()] = vim.deepcopy(next_marks)
  end
  marks = next_marks
  return true
end

local function resolve()
  project, threads = nil, {}
  for _, p in ipairs(snapshot.projects or {}) do
    if type(p.cwd) == "string" and vim.fs.normalize(p.cwd) == root() then
      project = p
      break
    end
  end
  if project then
    for _, t in ipairs(snapshot.threads or {}) do
      if t.projectId == project.id and t.listed ~= false and not t.archived then
        threads[#threads + 1] = t
      end
    end
  end
  local by_id, used, auto = {}, {}, {}
  for _, t in ipairs(threads) do
    by_id[t.id] = t
  end
  slots = {}
  for i = 1, 9 do
    local id = marks[tostring(i)]
    if id then
      slots[i], used[id] = { thread = by_id[id], id = id, marked = true }, true
    end
  end
  for _, t in ipairs(threads) do
    if not t.settled and not used[t.id] then
      auto[#auto + 1] = t
    end
  end
  table.sort(auto, function(a, b)
    if not not a.pinned ~= not not b.pinned then
      return not not a.pinned
    end
    return ui.recent(a, b)
  end)
  local index = 1
  for i = 1, 9 do
    if not slots[i] then
      local t = auto[index]
      slots[i] = { thread = t, id = t and t.id, auto = t ~= nil }
      index = index + 1
    end
  end
  hits = {}
  for _, t in ipairs(threads) do
    local positions, score = {}, 0
    if query ~= "" then
      local match = vim.fn.matchfuzzypos({ ui.clean(t.title or t.id) }, query)
      positions, score = match[2][1], match[3][1]
    end
    if positions then
      local slot
      for i = 1, 9 do
        if marks[tostring(i)] == t.id then
          slot = i
        end
      end
      hits[#hits + 1] =
        { thread = t, id = t.id, positions = positions, score = score, slot = slot, marked = slot ~= nil }
    end
  end
  table.sort(hits, function(a, b)
    if not not a.thread.settled ~= not not b.thread.settled then
      return not a.thread.settled
    end
    if query ~= "" and a.score ~= b.score then
      return a.score > b.score
    end
    if (a.thread.updatedAt or "") ~= (b.thread.updatedAt or "") then
      return (a.thread.updatedAt or "") > (b.thread.updatedAt or "")
    end
    return a.id < b.id
  end)
  hit = math.max(1, math.min(hit, #hits))
end

local function geometry()
  local width = math.max(10, math.min(vim.o.columns - 2, math.floor(vim.o.columns * 0.9)))
  local height = math.max(13, math.min(vim.o.lines - 4, math.floor(vim.o.lines * 0.85)))
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    style = "minimal",
    border = "rounded",
    title = " AGENT · " .. ui.truncate(project and project.name or "no project", width - 12) .. " ",
    title_pos = "center",
  }
end

local function branch(t)
  if type(t.branch) == "string" and t.branch ~= "" then
    return t.branch
  end
  return type(t.worktreePath) == "string" and vim.fs.basename(t.worktreePath) or ""
end

render = function()
  if not M.active or not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  resolve()
  ui.highlights()
  vim.api.nvim_set_hl(0, "EnviAgentAuto", { link = "EnviT3Side_idle" })
  -- Derive the chip from the existing selection palette, adding weight.
  local chip = vim.api.nvim_get_hl(0, { name = "EnviT3SideSelected", link = false })
  chip.bold = true
  vim.api.nvim_set_hl(0, "EnviAgentMark", chip)
  vim.api.nvim_set_hl(0, "EnviAgentSearchFocus", { link = "EnviT3Side_working" })
  vim.api.nvim_set_hl(0, "EnviAgentSearchBorder", { link = "EnviT3SideBranch" })
  local config = geometry()
  vim.api.nvim_win_set_config(win, config)
  local width, height = config.width, config.height
  local lines, highlights = {}, {}
  anchors = {}
  local function mark(row, start, finish, hl)
    if finish > start then
      highlights[#highlights + 1] = { row, start, finish, hl }
    end
  end
  local function append(row, text)
    lines[row] = (lines[row] or "") .. text
  end
  -- Coordinates use display cells; highlight ranges use UTF-8 byte offsets.
  local function card(row, col, w, h, entry, number, chosen)
    local muted = "EnviT3SideBranch"
    local border = chosen and "EnviT3Side_working" or entry.auto and "EnviAgentAuto" or muted
    local t = entry.thread
    local function line(offset, content, hl, left, right)
      local r = row + offset
      local before = lines[r] or ""
      local pad = math.max(0, col - vim.fn.strdisplaywidth(before))
      append(r, string.rep(" ", pad))
      local start = #(lines[r] or "")
      local text = ui.truncate(content, w - 4)
      local inside = " " .. text .. string.rep(" ", math.max(0, w - 3 - vim.fn.strdisplaywidth(text)))
      append(r, left .. inside .. right)
      mark(r, start, start + #left, border)
      mark(r, start + #left, start + #left + #inside, hl or (entry.auto and muted or "Normal"))
      mark(r, start + #left + #inside, #lines[r], border)
      return start + #left + 1, text
    end
    local function edge(offset, left, right)
      local r = row + offset
      append(r, string.rep(" ", math.max(0, col - vim.fn.strdisplaywidth(lines[r] or ""))))
      local start = #(lines[r] or "")
      append(r, left .. string.rep(entry.id and "─" or "┄", w - 2) .. right)
      mark(r, start, #lines[r], border)
    end
    local icon, icon_hl = ui.harness({
      harness = t and t.harness,
      model = t and type(t.model) == "string" and t.model or "",
    })
    local label = (number and (number .. " ") or "") .. (entry.marked and "⚑ mark " or entry.auto and "auto " or "")
    local anchor
    edge(0, "┌", "┐")
    for offset = 1, h - 2 do
      local value, hl = "", muted
      if offset == 1 then
        value = label .. (t and icon or entry.id and "gone" or "empty · m to mark")
        hl = chosen and "EnviT3SideSelected" or entry.auto and "EnviAgentAuto" or muted
      elseif offset == 2 then
        value = t and ui.clean(t.title or t.id) or entry.id and "gone · x to clear" or ""
        hl = t and t.unread and "EnviT3SideUnread" or nil
      elseif offset == 3 and t then
        local status = ({ working = true, attention = true, error = true, done = true })[t.status] and t.status
          or "idle"
        value = status .. " · " .. ui.age(t.updatedAt) .. (t.settled and " · settled" or "")
        hl = "EnviT3Side_" .. status
      elseif offset == 4 and t then
        value = branch(t)
      end
      local start, shown = line(offset, value, hl, "│", "│")
      if offset == 1 then
        anchor = start
        if number and entry.marked then
          mark(row + offset, start - 1, start + #tostring(number) + 1, "EnviAgentMark")
        end
      end
      if offset == 1 and t then
        local icon_start = shown:find(icon, 1, true)
        if icon_start then
          mark(row + offset, start + icon_start - 1, start + icon_start - 1 + #icon, icon_hl)
        end
      elseif offset == 2 and t then
        -- Fuzzy positions count characters; extmarks count bytes. Match against
        -- the visible original prefix, not the truncation ellipsis.
        local original = ui.clean(t.title or t.id)
        for _, position in ipairs(entry.positions or {}) do
          local char = vim.fn.strcharpart(original, position, 1)
          local byte = vim.fn.byteidx(shown, position)
          if byte >= 0 and vim.fn.strcharpart(shown, position, 1) == char then
            mark(row + offset, start + byte, start + byte + #char, "Search")
          end
        end
      end
    end
    edge(h - 1, "└", "┘")
    return { row + 1, anchor }
  end
  if view == "board" then
    local w, h = math.floor((width - 2) / 3), math.floor((height - 1) / 3)
    for i = 1, 9 do
      anchors[i] = card(1 + math.floor((i - 1) / 3) * h, ((i - 1) % 3) * (w + 1), w, h, slots[i], i, i == selected)
    end
  else
    local border = editing and "EnviAgentSearchFocus" or "EnviAgentSearchBorder"
    local label = "─ ⌕ Search "
    lines[1] = "╭" .. label .. string.rep("─", width - vim.fn.strdisplaywidth(label) - 2) .. "╮"
    lines[query_row] = "  " .. query
    lines[3] = "╰" .. string.rep("─", width - 2) .. "╯"
    mark(1, 0, #lines[1], border)
    mark(3, 0, #lines[3], border)
    local h = math.min(6, math.max(4, height - 5))
    local count = math.max(1, math.floor((height - 5) / h))
    local first = math.floor((hit - 1) / count) * count + 1
    for i = first, math.min(#hits, first + count - 1) do
      anchors[i] = card(5 + (i - first) * h, 0, width, h, hits[i], hits[i].slot, i == hit)
    end
    if #hits == 0 then
      lines[5] = project and "  No matching threads" or "  No T3 project matches the session root"
    end
  end
  local hint = view == "board"
      and "1–9 open · hjkl move · i new · / search · mN mark · x clear · Tab · R · ? · q/Esc"
    or "j/k move · Enter open · i search · mN mark · x clear · Tab board · ? · q"
  lines[height] = ui.truncate(message and ("T3 unavailable: " .. message) or hint, width)
  for i = 1, height do
    lines[i] = lines[i] or ""
  end
  local old_cursor = vim.api.nvim_win_get_cursor(win)
  drawing = true
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(
      buf,
      ns,
      m[1] - 1,
      m[2],
      { end_col = m[3], hl_group = m[4], priority = (m[4] == "Search" or m[4] == "EnviAgentMark") and 250 or 200 }
    )
  end
  if view == "search" then
    local border = editing and "EnviAgentSearchFocus" or "EnviAgentSearchBorder"
    local function overlay(col, text, hl)
      vim.api.nvim_buf_set_extmark(buf, ns, query_row - 1, 0, {
        virt_text = { { text, hl } },
        virt_text_win_col = col,
        priority = 300,
      })
    end
    overlay(0, "│ ", border)
    if query == "" then
      overlay(2, "Search threads…", "EnviT3SideBranch")
    end
    local suffix = (" %d/%d │"):format(#hits, #threads)
    overlay(width - vim.fn.strdisplaywidth(suffix), suffix, border)
  end
  rendered = lines
  vim.bo[buf].modifiable = view == "search" and editing
  local cursor = view == "board" and anchors[selected]
    or (
      editing and { query_row, math.min(#lines[query_row], math.max(2, old_cursor[2])) }
      or anchors[hit]
      or { query_row, 1 }
    )
  vim.api.nvim_win_set_cursor(win, cursor)
  drawing = false
  if position_help then
    position_help()
  end
end

local function selected_entry()
  return view == "board" and slots[selected] or hits[hit]
end

local function open_entry(entry)
  if entry and entry.thread then
    local id = entry.id
    M.close()
    require("hcmux.t3").open(id)
  end
end

local function search_insert()
  view, editing = "search", true
  render()
  vim.api.nvim_win_set_cursor(win, { query_row, #("  " .. query) })
  vim.cmd.startinsert({ bang = true })
end

local function search_normal()
  changed() -- flush a final keystroke even when Esc precedes TextChangedI
  editing = false
  vim.cmd.stopinsert()
  render()
end

changed = function()
  if drawing or not M.active or view ~= "search" or not editing then
    return
  end
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.deep_equal(current, rendered) then
    return
  end
  local line = current[query_row] or ""
  -- Only the query row is accepted as input. Prefix and all card lines are redrawn;
  -- newline/paste/undo/insert-control motions cannot corrupt the card model.
  local next_query = line:sub(1, 2) == "  " and line:sub(3) or query
  if next_query ~= query then
    query, hit = next_query, 1
  end
  render()
end

local function move(delta)
  if view == "search" then
    hit = math.max(1, math.min(#hits, hit + delta))
  else
    local target = selected + delta
    if target >= 1 and target <= 9 then
      selected = target
    end
  end
  render()
end

local function switch()
  editing = false
  vim.cmd.stopinsert()
  view = view == "board" and "search" or "board"
  render()
end

local function close_help()
  local old_win, old_buf = help_win, help_buf
  help_win, help_buf = nil, nil
  if old_win and vim.api.nvim_win_is_valid(old_win) then
    vim.api.nvim_win_close(old_win, true)
  end
  if old_buf and vim.api.nvim_buf_is_valid(old_buf) then
    vim.api.nvim_buf_delete(old_buf, { force = true })
  end
end

position_help = function()
  if not help_win or not vim.api.nvim_win_is_valid(help_win) then
    return
  end
  local width = math.min(68, vim.o.columns - 6)
  local height = math.min(vim.api.nvim_buf_line_count(help_buf), vim.o.lines - 4)
  vim.api.nvim_win_set_config(help_win, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height - 2) / 2),
    col = math.floor((vim.o.columns - width - 2) / 2),
  })
end

local function help()
  if help_win and vim.api.nvim_win_is_valid(help_win) then
    return close_help()
  end
  local rows = {
    { "Board" },
    { "1–9 / Enter / o", "Open slot / selected thread" },
    { "hjkl / arrows", "Select card" },
    { "i / /", "New COMMAND / search INSERT" },
    { "m then 1–9 / x", "Mark (no timeout) / clear mark" },
    { "Tab / R", "Search NORMAL / refresh feed" },
    { "q / Esc / leader-a", "Close AGENT" },
    { "Search INSERT" },
    { "Type", "Fuzzy filter titles live" },
    { "Ctrl-n/p / arrows", "Select next / previous hit" },
    { "Enter / Esc", "Open hit / NORMAL (keep pane)" },
    { "Search NORMAL" },
    { "j/k / gg/G", "Next/previous / first/last hit" },
    { "Enter / o", "Open selected hit" },
    { "m then 1–9 / x", "Mark hit / clear its mark" },
    { "i / a / /", "INSERT at query end" },
    { "Tab / q / Esc", "Board / close / stay NORMAL" },
    { "?", "Help; q / Esc / ? dismiss help" },
  }
  local width = math.min(68, vim.o.columns - 6)
  local lines, headings = {}, {}
  for _, row in ipairs(rows) do
    if row[2] then
      lines[#lines + 1] = " " .. row[1] .. string.rep(" ", math.max(1, 21 - vim.fn.strdisplaywidth(row[1]))) .. row[2]
    else
      headings[#headings + 1] = #lines
      lines[#lines + 1] = " " .. row[1]
    end
  end
  help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].bufhidden, vim.bo[help_buf].filetype = "wipe", "envi-agent-help"
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
  vim.bo[help_buf].modifiable = false
  local height = math.min(#lines, vim.o.lines - 4)
  help_win = vim.api.nvim_open_win(help_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height - 2) / 2),
    col = math.floor((vim.o.columns - width - 2) / 2),
    style = "minimal",
    border = "rounded",
    title = " AGENT keys ",
    title_pos = "center",
    zindex = 60,
  })
  vim.api.nvim_set_option_value("winbar", "", { scope = "local", win = help_win })
  vim.wo[help_win].wrap = true
  for i, row in ipairs(rows) do
    if row[2] then
      vim.api.nvim_buf_set_extmark(help_buf, ns, i - 1, 1, { end_col = 1 + #row[1], hl_group = "EnviT3Side_working" })
    end
  end
  for _, line in ipairs(headings) do
    vim.api.nvim_buf_set_extmark(help_buf, ns, line, 0, { end_col = #lines[line + 1], hl_group = "EnviT3SideGroup" })
  end
  for _, key in ipairs({ "q", "<Esc>", "?" }) do
    vim.keymap.set("n", key, close_help, { buffer = help_buf, silent = true, nowait = true })
  end
end

local function maps()
  local function map(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, silent = true, nowait = true, desc = "AGENT: " .. lhs })
  end
  for i = 1, 9 do
    map("n", tostring(i), function()
      if view == "board" then
        open_entry(slots[i])
      end
    end)
  end
  -- `m` then a digit. Read the digit directly instead of mapping m1..m9: a
  -- two-key map times out after 'timeoutlen' (300 ms in LazyVim), and then
  -- Vim's own `m` swallows the digit as a mark name.
  map("n", "m", function()
    local entry = selected_entry()
    if not entry or not entry.thread then
      return
    end
    vim.api.nvim_echo({ { "AGENT mark: slot 1-9 (Esc cancels)", "ModeMsg" } }, false, {})
    local ok, key = pcall(vim.fn.getcharstr)
    vim.api.nvim_echo({ { "" } }, false, {})
    local i = ok and tonumber(key)
    if not i or i < 1 or i > 9 then
      return
    end
    local next_marks = vim.deepcopy(marks)
    for slot, id in pairs(next_marks) do
      if id == entry.id then
        next_marks[slot] = nil
      end
    end
    next_marks[tostring(i)] = entry.id
    save_marks(next_marks)
    render()
  end)
  map("n", "x", function()
    local next_marks = vim.deepcopy(marks)
    if view == "board" then
      next_marks[tostring(selected)] = nil
    else
      local entry = selected_entry()
      for slot, id in pairs(next_marks) do
        if entry and entry.id == id then
          next_marks[slot] = nil
        end
      end
    end
    save_marks(next_marks)
    render()
  end)
  for _, lhs in ipairs({ "<CR>", "o" }) do
    map("n", lhs, function()
      open_entry(selected_entry())
    end)
  end
  map("i", "<CR>", function()
    open_entry(selected_entry())
  end)
  for _, lhs in ipairs({ "j", "<Down>" }) do
    map("n", lhs, function()
      move(view == "board" and 3 or 1)
    end)
  end
  for _, lhs in ipairs({ "k", "<Up>" }) do
    map("n", lhs, function()
      move(view == "board" and -3 or -1)
    end)
  end
  for _, lhs in ipairs({ "h", "<Left>" }) do
    map("n", lhs, function()
      if view == "board" and selected % 3 ~= 1 then
        move(-1)
      end
    end)
  end
  for _, lhs in ipairs({ "l", "<Right>" }) do
    map("n", lhs, function()
      if view == "board" and selected % 3 ~= 0 then
        move(1)
      end
    end)
  end
  map("n", "gg", function()
    if view == "search" then
      hit = 1
      render()
    end
  end)
  map("n", "G", function()
    if view == "search" then
      hit = math.max(1, #hits)
      render()
    end
  end)
  for _, lhs in ipairs({ "<C-n>", "<Down>" }) do
    map("i", lhs, function()
      move(1)
    end)
  end
  for _, lhs in ipairs({ "<C-p>", "<Up>" }) do
    map("i", lhs, function()
      move(-1)
    end)
  end
  map("n", "i", function()
    if view == "search" then
      return search_insert()
    end
    if not project then
      return vim.notify("AGENT: no T3 project matches the session root", vim.log.levels.WARN)
    end
    local cwd = project.cwd
    M.close()
    require("hcmux.t3").open("new", { mode = "command", cwd = cwd })
  end)
  map("n", "a", function()
    if view == "search" then
      search_insert()
    end
  end)
  map("n", "/", search_insert)
  map("n", "<Tab>", switch)
  map("n", "R", function()
    side.start(true)
  end)
  map("n", "?", help)
  map("n", "q", M.close)
  map("n", "<leader>a", M.close)
  map("n", "<Esc>", function()
    if view == "board" then
      M.close()
    end
  end)
  map("i", "<Esc>", search_normal)
  -- Keep editing within the query, including backspace at the prompt boundary.
  vim.keymap.set("i", "<BS>", function()
    return vim.api.nvim_win_get_cursor(win)[2] > 2 and "<BS>" or ""
  end, { buffer = buf, expr = true, silent = true })
end

function M.close()
  if not M.active then
    return
  end
  M.active, editing = false, false
  close_help()
  vim.cmd.stopinsert()
  if unsubscribe then
    unsubscribe()
    unsubscribe = nil
  end
  local old_win, old_buf = win, buf
  win, buf = nil, nil
  if old_win and vim.api.nvim_win_is_valid(old_win) then
    vim.api.nvim_win_close(old_win, true)
  end
  if old_buf and vim.api.nvim_buf_is_valid(old_buf) then
    vim.api.nvim_buf_delete(old_buf, { force = true })
  end
  refresh()
end

function M.open(which)
  assert(which == nil or which == "board" or which == "search", "AGENT: expected board or search")
  if M.active then
    vim.api.nvim_set_current_win(win)
    if which == "search" then
      search_insert()
    elseif which == "board" then
      view, editing = "board", false
      vim.cmd.stopinsert()
      render()
    end
    return
  end
  view, selected, hit, editing = which or "board", 1, 1, false
  load_marks()
  snapshot, message = side.snapshot()
  resolve()
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden, vim.bo[buf].filetype, vim.bo[buf].swapfile = "wipe", "envi-agent", false
  -- The query is a search field, not text: no completion menu (blink.cmp) or auto-pairs.
  vim.b[buf].completion, vim.b[buf].minipairs_disable = false, true
  vim.bo[buf].undolevels = -1
  win = vim.api.nvim_open_win(buf, true, geometry())
  vim.wo[win].wrap, vim.wo[win].cursorline, vim.wo[win].scrolloff = false, false, 0
  vim.api.nvim_set_option_value("winbar", "", { scope = "local", win = win })
  M.active = true
  maps()
  unsubscribe = side.subscribe(function(value, err)
    snapshot, message = value, err
    render()
  end)
  side.start()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { group = group, buffer = buf, callback = changed })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = buf,
    callback = function()
      if M.active and editing then
        search_normal()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      if drawing or not M.active or vim.api.nvim_get_current_buf() ~= buf then
        return
      end
      if editing then
        local c = vim.api.nvim_win_get_cursor(win)
        if c[1] ~= query_row or c[2] < 2 then
          vim.api.nvim_win_set_cursor(win, { query_row, math.max(2, math.min(c[2], #("  " .. query))) })
        end
      else
        local expected = view == "board" and anchors[selected] or anchors[hit] or { query_row, 1 }
        if not vim.deep_equal(vim.api.nvim_win_get_cursor(win), expected) then
          vim.api.nvim_win_set_cursor(win, expected)
        end
      end
    end,
  })
  -- on_lines also catches paste/API edits and restores any non-query lines.
  local owned_buf = buf
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if drawing or guarding or not M.active then
        return
      end
      guarding = true
      vim.schedule(function()
        guarding = false
        if M.active and buf == owned_buf then
          changed()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    once = true,
    callback = function()
      M.close()
    end,
  })
  render()
  if view == "search" then
    search_insert()
  end
  refresh()
end

function M.toggle()
  if M.active then
    M.close()
  else
    M.open("board")
  end
end

vim.api.nvim_create_autocmd({ "VimResized", "WinResized", "ColorScheme" }, {
  group = group,
  callback = function()
    if M.active then
      render()
    end
  end,
})
return M
