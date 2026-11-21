-- The board's key registration table (the seam WP2–WP5 extend; see README.md).
-- A handler is registered per game mode ("normal" | "insert" | "search") or for
-- every mode ("*", the fallback). The board buffer only carries Neovim Normal
-- maps for the keys that have a handler in the current game mode, so a key is
-- free for counts and native use in the modes where nothing claims it.
local M = { version = 0 }
local registry, order = {}, {} -- lhs -> { [mode] = spec }; lhs in registration order
local attached = {} -- buf -> { mode, version, lhs list }

--- spec = { lhs, mode = "normal"|"insert"|"search"|"*", desc = "Sudoku: …", fn = function(game, ctx) }
--- ctx = { lhs, count = v:count, count1 = v:count1 }. The board re-renders after fn.
--- A later registration for the same lhs and mode replaces the earlier one.
function M.register(spec)
  assert(type(spec.lhs) == "string" and type(spec.fn) == "function", "register: lhs and fn")
  assert(type(spec.desc) == "string" and spec.desc:find("^Sudoku: "), "register: desc must start 'Sudoku: '")
  local mode = spec.mode or "normal"
  if not registry[spec.lhs] then
    registry[spec.lhs] = {}
    order[#order + 1] = spec.lhs
  end
  registry[spec.lhs][mode] = vim.tbl_extend("force", spec, { mode = mode })
  M.version = M.version + 1
  if M.on_change then
    M.on_change()
  end
end

--- The handler `lhs` runs in game `mode` (a mode-specific one first, then "*").
function M.handler(lhs, mode)
  local h = registry[lhs]
  return h and (h[mode] or h["*"]) or nil
end

--- Install `buf`'s maps for game `mode`; dispatch(lhs) runs on each key.
--- Cheap to call on every render: it only rebuilds after a mode or registry change.
function M.attach(buf, mode, dispatch)
  local cur = attached[buf]
  if cur and cur.mode == mode and cur.version == M.version then
    return
  end
  for _, lhs in ipairs(cur and cur.lhs or {}) do
    pcall(vim.keymap.del, "n", lhs, { buffer = buf })
  end
  local lhs_list = {}
  for _, lhs in ipairs(order) do
    local spec = M.handler(lhs, mode)
    if spec then
      lhs_list[#lhs_list + 1] = lhs
      vim.keymap.set("n", lhs, function()
        dispatch(lhs)
      end, { buffer = buf, nowait = true, silent = true, desc = spec.desc })
    end
  end
  attached[buf] = { mode = mode, version = M.version, lhs = lhs_list }
end

function M.detach(buf)
  attached[buf] = nil
end

return M
