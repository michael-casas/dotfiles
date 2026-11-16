-- hcmux.picker: every herdr-core terminal in one list (tmux choose-tree).
-- nvim's own terminals first, then the rest (Herdr app panes, agents' helpers).
local core = require("hcmux.core")

local M = {}

M.icons = {
  working = { "󰔟 ", "DiagnosticWarn" },
  blocked = { " ", "DiagnosticError" },
  done = { " ", "DiagnosticOk" },
  idle = { "󰒲 ", "Comment" },
  none = { " ", "Comment" },
}

local function items()
  local term = require("hcmux.term")
  local ret = {}
  for _, t in ipairs(core.list()) do
    local ours = core.is_ours(t)
    local cwd = (t.foreground and t.foreground.cwd) or t.cwd or ""
    local where = t.labels and t.labels.where or ""
    ret[#ret + 1] = {
      text = table.concat({ t.address, core.title(t), t.name or "", where, cwd }, " "),
      addr = t.address,
      title = core.title(t),
      where = where,
      cwd = cwd,
      ours = ours,
      open = term.buf_of(t.address) ~= nil,
      status = core.status(t),
      fact = t,
    }
  end
  table.sort(ret, function(a, b)
    if a.ours ~= b.ours then
      return a.ours
    end
    if a.open ~= b.open then
      return a.open
    end
    return (a.fact.created_ms or 0) > (b.fact.created_ms or 0)
  end)
  return ret
end

local function format(item)
  local icon = M.icons[item.status or "none"] or M.icons.none
  local home = vim.env.HOME
  local cwd = home and item.cwd:gsub("^" .. vim.pesc(home), "~") or item.cwd
  return {
    { icon[1], icon[2] },
    { ("%-5s "):format(item.addr), "Number" },
    { item.open and "● " or "  ", "DiagnosticInfo" },
    { item.title .. "  ", item.ours and "Normal" or "Comment" },
    { item.where ~= "" and (item.where .. "  ") or "", "Special" },
    { cwd, "Comment" },
  }
end

local function preview(ctx)
  ctx.preview:reset()
  local addr = ctx.item.addr
  ctx.preview:set_title(("%s · %s"):format(addr, ctx.item.title))
  ctx.preview:set_lines({ "reading " .. addr .. "…" })
  core.exec_async({ "read", "--lines", "200", addr }, function(out, err)
    -- The cursor may have moved on while hc was reading.
    local cur = ctx.picker and not ctx.picker.closed and ctx.picker:current()
    if not cur or cur.addr ~= addr or not ctx.preview.win:buf_valid() then
      return
    end
    local lines = vim.split(out or ("hc read failed: " .. tostring(err)), "\n")
    while #lines > 0 and vim.trim(lines[#lines]) == "" do
      table.remove(lines)
    end
    ctx.preview:set_lines(lines)
    pcall(vim.api.nvim_win_set_cursor, ctx.win, { math.max(#lines, 1), 0 })
  end)
end

local function open_as(where)
  return function(picker, item)
    picker:close()
    if item then
      vim.schedule(function()
        require("hcmux.term").attach(item.addr, where)
      end)
    end
  end
end

--- Pick a terminal. Default action attaches it in the current window.
---@param o? {prompt?:string, on_pick?:fun(addr:string), filter?:fun(item):boolean}
function M.pick(o)
  o = o or {}
  if not (_G.Snacks and Snacks.picker) then
    return vim.notify("hcmux: snacks.nvim picker is required", vim.log.levels.ERROR)
  end
  return Snacks.picker.pick({
    title = "herdr-core terminals",
    prompt = o.prompt or "󰆍 ",
    finder = function()
      local list = items()
      return o.filter and vim.tbl_filter(o.filter, list) or list
    end,
    format = format,
    preview = preview,
    layout = { preset = "default" },
    confirm = o.on_pick and function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          o.on_pick(item.addr)
        end)
      end
    end or open_as("current"),
    actions = {
      hc_vsplit = open_as("vsplit"),
      hc_split = open_as("split"),
      hc_tab = open_as("tab"),
      hc_kill = function(picker, item)
        if not item then
          return
        end
        if vim.fn.confirm(("Kill %s (%s)?"):format(item.title, item.addr), "&Yes\n&No", 2) == 1 then
          require("hcmux.term").kill(item.addr, false)
          vim.defer_fn(function()
            picker:find({ refresh = true })
          end, 300)
        end
      end,
      hc_rename = function(picker, item)
        if not item then
          return
        end
        vim.ui.input({ prompt = "Rename: ", default = item.title }, function(t)
          if t and t ~= "" then
            core.label(item.addr, { [core.LABEL .. ".title"] = t })
            picker:find({ refresh = true })
          end
        end)
      end,
    },
    win = {
      input = {
        keys = {
          ["<c-v>"] = { "hc_vsplit", mode = { "n", "i" } },
          ["<c-s>"] = { "hc_split", mode = { "n", "i" } },
          ["<c-t>"] = { "hc_tab", mode = { "n", "i" } },
          ["<c-x>"] = { "hc_kill", mode = { "n", "i" } },
          ["<a-r>"] = { "hc_rename", mode = { "n", "i" } },
        },
      },
    },
  })
end

return M
