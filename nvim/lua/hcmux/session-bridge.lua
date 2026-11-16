-- hcmux session bridge: nvim sessions <-> herdr-core terminals.
--
-- A session (hcmux.session, or any plain :mksession) already
-- records hcmux windows: with "terminal" in 'sessionoptions', mksession writes
-- them by buffer name (`edit hc://t15v/bash`). What nvim lacks is a way to
-- read such a name back, so a restored session showed empty buffers.
--
-- The bridge teaches nvim the `hc://` scheme, the way it knows `term://`:
--
--   * BufReadCmd hc://*  — the buffer becomes a view onto that terminal. It
--     attaches in place, so the session's layout comes back with the live
--     programs in it, scrollback included. One that has ended leaves a note
--     in its window rather than collapsing the layout.
--   * SessionLoadPost   — adopts the session's hidden hc:// buffers, then
--     lists the project's other live terminals (the session's folder).
--
-- Saving is hcmux.session's job (sessions live in herdr-core); the bridge
-- only reads layouts back, whoever wrote them.
--
-- Programs are never started by a session load: a terminal is either still
-- alive in herdr-core and re-attached, or it is reported as ended.
local core = require("hcmux.core")
local term = require("hcmux.term")

local M = {}

M.config = {}

local group = vim.api.nvim_create_augroup("hcmux.session-bridge", { clear = true })

--- `hc://t15v/title` -> `t15v`
function M.addr_of_name(name)
  return name and name:match("^hc://([%w_-]+)")
end

--- Make `buf` (named hc://…) a view onto its terminal, or merge it into the
--- buffer that already is one.
function M.adopt(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].hcmux_addr then
    return
  end
  local addr = M.addr_of_name(vim.api.nvim_buf_get_name(buf))
  if not addr then
    return
  end
  local existing = term.buf_of(addr)
  if existing and existing ~= buf then
    -- Already listed (hcmux's startup restore, or a title that changed since
    -- the session was saved): show that buffer and drop the duplicate.
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.api.nvim_win_set_buf(win, existing)
    end
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) and not vim.b[buf].hcmux_addr then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end)
    return existing
  end
  term.placeholder(addr, buf)
  -- Windows showing it attach now; hidden ones attach when first shown.
  vim.schedule(function()
    term._wake(buf)
  end)
  return buf
end

function M.setup(cfg)
  M.config = vim.tbl_deep_extend("force", M.config, cfg or {})

  -- Sessions record terminal windows only with "terminal" in 'sessionoptions'.
  if not vim.o.sessionoptions:find("terminal", 1, true) then
    vim.opt.sessionoptions:append("terminal")
  end

  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "hc://*",
    callback = function(ev)
      M.adopt(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd("SessionLoadPost", {
    group = group,
    callback = function()
      -- `badd hc://…` buffers are listed but not loaded: adopt them now so
      -- the project restore below sees them and adds no duplicates.
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if not vim.b[b].hcmux_addr and M.addr_of_name(vim.api.nvim_buf_get_name(b)) then
          M.adopt(b)
        end
      end
      vim.schedule(function()
        if core.available() then
          term.restore() -- the session may have changed directory
        end
        term.refresh_names() -- titles may have changed since it was saved
      end)
    end,
  })
end

return M
