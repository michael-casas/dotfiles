-- Root cause of the T3 black bars: `hc attach` opens with ESC[?1049l, which
-- also restores the saved cursor. Neovim's terminal restores a never-saved
-- cursor with an explicit black pen, so blank rows and the unwritten rest of
-- each line render #000000 whatever the window's Normal. Found with a private
-- herdr-core replay probe (real Ink client, real `hc attach --history`).
--
-- This suite runs the viewer command exactly as term.lua builds it; only the
-- `hc` executable is swapped for test/support/fake-hc-attach.sh, which emits
-- the same opening sequence and default-background history. Cell colours are
-- read from an embedded RGB UI: for the T3 popover (float grid) and for an
-- ordinary hcmux terminal in a split (default grid).
local root = vim.fn.getcwd()
local support = root .. "/nvim/tools/t3-thread/test/support/strike-child.lua"
local fake = root .. "/nvim/tools/t3-thread/test/support/fake-hc-attach.sh"
local hub = vim.json.decode(table.concat(vim.fn.readfile(root .. "/theme/theme.json"), "\n"))
local nord = hub.themes.nord
local POPOVER = (nord.palette[nord.tokens.ui.popover] or nord.tokens.ui.popover):lower()
local O = {
  normal_fg = "#ffffff",
  normal_bg = "#101010",
  cursor = "#ff00ff",
  code_bg = "#000001",
  bubble_bg = "#000002",
  logdir = vim.fn.tempname(),
}
vim.fn.mkdir(O.logdir, "p")
assert(hub.active == "nord" and POPOVER ~= O.normal_bg)

local failures = {}

local function run_case(name, open, want)
  local ch = vim.fn.jobstart({ "nvim", "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
  assert(ch > 0, "could not start an embedded nvim")
  local function L(code, ...)
    return vim.rpcrequest(ch, "nvim_exec_lua", code, { ... })
  end
  local ok, err = pcall(function()
    vim.rpcrequest(ch, "nvim_ui_attach", 120, 40, { rgb = true })
    L("_G.REAL_JOBSTART = vim.fn.jobstart") -- before strike-child replaces it
    assert(L("return dofile(...)(select(2, ...))", support, root, O))
    -- Run the viewer exactly as term.lua builds it, with `hc` -> the fake.
    L(
      [=[
      local fake = ...
      local stub = vim.fn.jobstart
      vim.fn.jobstart = function(argv, opts)
        if type(argv) == "table" then
          for i, a in ipairs(argv) do
            if a == "hc" and argv[i + 1] == "attach" then
              local cmd = vim.list_slice(argv)
              cmd[i] = fake
              table.insert(cmd, i, "sh") -- no exec bit needed
              STRIKE.viewer_argv = argv
              local job = REAL_JOBSTART(cmd, opts)
              STRIKE.jobs[argv[#argv]] = job
              return job
            end
          end
        end
        return stub(argv, opts)
      end
    ]=],
      fake
    )
    L(open)
    assert(
      L(
        "return vim.wait(8000, function() return vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false), 'PEN_READY') end, 20)"
      ),
      "fake viewer never finished"
    )
    vim.wait(200)
    vim.rpcrequest(ch, "nvim_input", "<C-\\><C-n>")
    vim.wait(250)
    vim.rpcrequest(ch, "nvim_input", "gg")
    vim.wait(250)
    local s = L([[
      vim.cmd.redraw()
      local win = vim.api.nvim_get_current_win()
      local pos = vim.api.nvim_win_get_position(win)
      return {
        float = vim.api.nvim_win_get_config(win).relative ~= "",
        row = pos[1], col = pos[2],
        width = vim.api.nvim_win_get_width(win), height = vim.api.nvim_win_get_height(win),
        topline = vim.fn.line("w0"),
        lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        argv = STRIKE.viewer_argv,
      }
    ]])
    assert(s.topline == 1 and #s.lines > s.height, name .. ": history must be scrolled to its top")
    -- The viewer job: /bin/sh prelude, then the untouched hc argv.
    local argv = s.argv or {}
    local tail = vim.list_slice(argv, #argv - 4)
    if not (argv[1] == "/bin/sh" and tail[1] == "hc" and tail[2] == "attach" and tail[3] == "--history") then
      failures[#failures + 1] = name .. ": unexpected viewer argv " .. vim.inspect(argv)
    end
    -- Floats have their own grid (border at row/col 0); splits draw on grid 1.
    local g, dr, dc = 1, s.row, s.col
    if s.float then
      for i = 2, 400 do
        local okc, tl = pcall(vim.rpcrequest, ch, "nvim__inspect_cell", i, 0, 0)
        local okr, tr = pcall(vim.rpcrequest, ch, "nvim__inspect_cell", i, 0, s.width + 1)
        if okc and okr and tl[1] == "╭" and tr[1] == "╮" then
          g = i
        end
      end
      assert(g > 1, name .. ": popover grid not found")
      dr, dc = 1, 1
    end
    local bad, rows = {}, 0
    for r = 0, s.height - 1 do
      local text = s.lines[s.topline + r] or ""
      if text:match("^PEN_ROW_") or vim.trim(text) == "" then
        rows = rows + 1
        for col = 0, s.width - 1 do
          local cell = vim.rpcrequest(ch, "nvim__inspect_cell", g, dr + r, dc + col)
          local bg = cell[2].background and ("#%06x"):format(cell[2].background) or "default"
          if bg ~= want then
            bad[#bad + 1] = ("row %d col %d %q bg %s"):format(r, col, text, bg)
          end
        end
      end
    end
    assert(rows >= 12, name .. ": visible history rows: " .. rows)
    if #bad > 0 then
      failures[#failures + 1] = ("%s: %d history cells are not %s (e.g. %s)"):format(name, #bad, want, bad[1])
    end
  end)
  pcall(vim.rpcrequest, ch, "nvim_exec_lua", "STRIKE.stop_all()", {})
  pcall(vim.rpcnotify, ch, "nvim_command", "qa!")
  vim.wait(100)
  pcall(vim.fn.jobstop, ch)
  if not ok then
    failures[#failures + 1] = name .. ": " .. tostring(err)
  end
end

run_case("T3 popover", 'require("hcmux.t3").toggle("owned-pen")', POPOVER)
run_case("ordinary terminal", 'require("hcmux.term").open(nil, { where = "split" })', O.normal_bg)
vim.fn.delete(O.logdir, "rf")
if #failures > 0 then
  error(("%d failure(s):\n  %s"):format(#failures, table.concat(failures, "\n  ")), 0)
end
print("viewer pen: history blank cells use the window background (T3 popover and ordinary terminal)")
