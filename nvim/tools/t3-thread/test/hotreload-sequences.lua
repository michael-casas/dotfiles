-- Sequence test for the hot-reload config toast (Amendment B-2):
--   nvim/tools/t3-thread/test/run-lua.sh hotreload-sequences
-- hcmux/hotreload.lua runs on a virtual clock (its vim.uv, vim.defer_fn and
-- vim.schedule_wrap are fakes) against a fake snacks.notifier with a screen
-- that can run out of room. Every ordering of up to 3 commit arrivals (now, or
-- in the on-screen toast's 250 ms tail) interleaved with up to 3 events (show,
-- mid-life, displace, displace just before the on-screen toast's deadline,
-- room returns, expire, FocusGained) is played, plus displacements 1-25 ms
-- before the deadline, then the run settles (room, time, FocusGained) and the
-- invariant is checked. Every transition onto the screen counts, including a
-- re-show of the same id:
-- * a toast that left the screen never comes back (it is retired), and no
--   id is ever on screen in two notifications;
-- * the newest commit had exactly one full display (on screen from its first
--   display to its deadline, never displaced), or was covered by a toast that
--   stayed on screen from its arrival to its own deadline and had more than
--   the 250 ms tail left when it arrived;
-- * never more than one config toast on screen; no commit had two full
--   displays; only the newest commit is ever handed to snacks;
-- * each displayed toast lives 3750-4250 ms from its first display (never
--   longer when snacks took it off screen early); 100 ms between toasts;
-- * an unrelated notification is never hidden.
-- HOTRELOAD_SEQ_IMPL=<file> checks another version of hotreload.lua;
-- HOTRELOAD_SEQ_ONLY=<seq>[@<margin ms>],... plays only those (letters as in
-- `run`; the margin is for X, default 5).
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local impl = vim.env.HOTRELOAD_SEQ_IMPL or vim.fn.fnamemodify(here, ":h:h:h") .. "/lua/hcmux/hotreload.lua"
local chunk = assert(loadfile(impl))

-- ── virtual clock ──────────────────────────────────────────────────────────
local vnow, vseq, events = 0, 0, {}
local function at(ms, fn) -- one event; returns it (ev.live = false cancels)
  vseq = vseq + 1
  local ev = { due = vnow + ms, seq = vseq, fn = fn, live = true }
  events[#events + 1] = ev
  return ev
end
local function advance(ms)
  local target = vnow + ms
  while true do
    local best, live = nil, {}
    for _, ev in ipairs(events) do
      if ev.live then
        live[#live + 1] = ev
        if ev.due <= target and (not best or ev.due < best.due or (ev.due == best.due and ev.seq < best.seq)) then
          best = ev
        end
      end
    end
    events = live
    if not best then
      break
    end
    best.live = false
    vnow = math.max(vnow, best.due)
    best.fn()
  end
  vnow = target
end
local function realtime()
  return 1e6 + vnow / 1000
end
local fake_uv = setmetatable({
  now = function()
    return vnow
  end,
  update_time = function() end,
  hrtime = function()
    return vnow * 1e6
  end,
  clock_gettime = function()
    local t = realtime()
    return { sec = math.floor(t), nsec = math.floor((t % 1) * 1e9 + 0.5) }
  end,
  gettimeofday = function()
    local t = realtime()
    return math.floor(t), math.floor((t % 1) * 1e6)
  end,
  new_timer = function()
    local t = { closing = false }
    function t:start(timeout, rep, cb)
      self:stop()
      local function arm(ms)
        self.ev = at(ms, function()
          if rep and rep > 0 then
            arm(rep)
          end
          cb()
        end)
      end
      arm(timeout)
      return 0
    end
    function t:stop()
      if self.ev then
        self.ev.live = false
      end
    end
    function t:close()
      self:stop()
      self.closing = true
    end
    function t:is_closing()
      return self.closing
    end
    return t
  end,
}, { __index = vim.uv })
local fake_vim = setmetatable({
  uv = fake_uv,
  loop = fake_uv,
  defer_fn = function(fn, ms)
    at(ms, fn)
  end,
  schedule = function(fn)
    at(0, fn)
  end,
  schedule_wrap = function(fn)
    return fn
  end,
  notify = function() end,
}, { __index = vim })
setfenv(chunk, setmetatable({ vim = fake_vim }, { __index = _G }))

-- ── fake snacks.notifier ───────────────────────────────────────────────────
-- Shows what's queued 10 ms after a change while there's room; a displace
-- clears `shown` of everything on screen (back in the queue), as snacks'
-- layout does when there's no room. Like snacks (`refresh = 50`: it lays out
-- at most every 50 ms), two layout passes are at least 50 ms apart, so a
-- displaced toast stays off screen for at least one refresh.
local TOAST = "Your configuration has changed since the last time you reloaded, run :Reload"
local S -- per-run state
local function count_on_screen()
  local c = 0
  for _, n in ipairs(S.hist) do
    if n.msg == TOAST and n.shown and not n.hidden then
      c = c + 1
    end
  end
  S.max_on = math.max(S.max_on, c)
end
local function update()
  if not S.room then
    return
  end
  if vnow - S.layout_ms < 50 then
    return at(S.layout_ms + 50 - vnow, update)
  end
  S.layout_ms = vnow
  for _, n in ipairs(S.hist) do
    if not n.hidden and not n.shown then
      n.shown = realtime()
      n.first_ms = n.first_ms or vnow
      n.onto_screen = (n.onto_screen or 0) + 1 -- every transition, re-shows included
    end
  end
  count_on_screen()
end
local function new_snacks()
  return {
    notifier = {
      notify = function(msg, _, opts)
        local n = { id = opts.id, msg = msg, asked_ms = vnow, displaced = {} }
        if msg == TOAST then
          n.newest = S.latest
        end
        S.hist[#S.hist + 1] = n
        at(10, update)
        return n.id
      end,
      hide = function(id)
        for i = #S.hist, 1, -1 do
          local n = S.hist[i]
          if n.id == id and not n.hidden then
            n.hidden, n.hidden_ms = realtime(), vnow
            return
          end
        end
      end,
      get_history = function()
        return S.hist
      end,
    },
  }
end
local function displace()
  S.room, S.layout_ms = false, vnow
  for _, n in ipairs(S.hist) do
    if n.shown and not n.hidden then
      n.shown = nil
      n.displaced[#n.displaced + 1] = vnow
    end
  end
end
local function room()
  S.room = true
  at(10, update)
end

-- ── one run ────────────────────────────────────────────────────────────────
local function run(seq, margin)
  margin = margin or 5
  vnow, vseq, events = 0, 0, {}
  S = { hist = {}, room = true, max_on = 0, arrived = {}, k = 0, layout_ms = -math.huge }
  _G.Snacks = new_snacks()
  local hot = chunk() -- a fresh module
  Snacks.notifier.notify("unrelated", vim.log.levels.INFO, { id = "unrelated" })
  advance(20)
  local function arrive()
    S.k = S.k + 1
    local c = "c" .. S.k
    S.latest, S.arrived[c] = c, vnow
    hot.toast(c)
  end
  for i = 1, #seq do
    local e = seq:sub(i, i)
    if e == "a" then -- a commit arrives now
      arrive()
    elseif e == "t" then -- ... in the on-screen toast's tail (150 ms left)
      for _, n in ipairs(S.hist) do
        if n.msg == TOAST and n.shown and not n.hidden then
          advance(math.max(0, n.first_ms + 4000 - 150 - vnow))
          break
        end
      end
      arrive()
    elseif e == "s" then -- snacks shows what's queued
      advance(50)
    elseif e == "m" then -- mid-life
      advance(1000)
    elseif e == "D" then
      displace()
      advance(1)
    elseif e == "X" then -- displace `margin` ms before the on-screen toast's deadline
      for _, n in ipairs(S.hist) do
        if n.msg == TOAST and n.shown and not n.hidden then
          advance(math.max(0, n.first_ms + 4000 - margin - vnow))
          break
        end
      end
      displace()
      advance(1)
    elseif e == "R" then
      room()
    elseif e == "E" then -- long enough for any toast on screen to expire
      advance(5000)
    elseif e == "F" then -- FocusGained: the check offers the newest commit
      if S.latest then
        hot.toast(S.latest)
      end
    end
  end
  -- settle
  room()
  advance(10000)
  hot.toast(S.latest)
  advance(10000)
  hot.toast(S.latest)
  advance(10000)

  local bad = {}
  local function fail(fmt, ...)
    bad[#bad + 1] = fmt:format(...)
  end
  if S.max_on > 1 then
    fail("%d config toasts on screen at once", S.max_on)
  end
  local full, toasts = {}, {}
  for _, n in ipairs(S.hist) do
    if n.id == "unrelated" then
      if n.hidden then
        fail("the unrelated notification was hidden")
      end
    elseif n.msg == TOAST then
      local c = n.id:match("^envi%.hotreload%.([^#]+)")
      if n.newest ~= c then
        fail("a toast for %s while %s was the newest", tostring(c), tostring(n.newest))
      end
      if n.first_ms then
        toasts[#toasts + 1] = n
        if n.onto_screen > 1 then
          fail("%s re-shown after it left the screen (%d times on screen)", c, n.onto_screen)
        end
        if not n.hidden_ms then
          fail("%s never hidden", c)
        else
          local life = n.hidden_ms - n.first_ms
          if #n.displaced == 0 and (life < 3750 or life > 4250) then
            fail("%s on screen %d ms", c, life)
          elseif life > 4250 then
            fail("%s kept %d ms (displaced)", c, life)
          end
          if #n.displaced == 0 then
            full[c] = (full[c] or 0) + 1
          end
        end
      end
    end
  end
  local ids = {}
  for _, n in ipairs(toasts) do
    if ids[n.id] then
      fail("id %s on screen in two notifications", n.id)
    end
    ids[n.id] = true
  end
  for c, d in pairs(full) do
    if d > 1 then
      fail("%s displayed in full %d times", c, d)
    end
  end
  table.sort(toasts, function(x, y)
    return x.first_ms < y.first_ms
  end)
  for i = 2, #toasts do
    local p, n = toasts[i - 1], toasts[i]
    if p.hidden_ms and p.hidden_ms <= n.first_ms and n.first_ms - p.hidden_ms < 100 then
      fail("only %d ms between toasts", n.first_ms - p.hidden_ms)
    end
  end
  local L = S.latest
  if (full[L] or 0) ~= 1 then
    local by = (hot.state.covered or {})[L]
    local ok = false
    for _, n in ipairs(S.hist) do
      if by and n.id == "envi.hotreload." .. by and n.first_ms and n.hidden_ms then
        local life = n.hidden_ms - n.first_ms
        local stayed = true
        for _, d in ipairs(n.displaced) do
          if d >= S.arrived[L] then
            stayed = false
          end
        end
        -- and it had more than the 250 ms tail left when L arrived
        ok = stayed
          and life >= 3750
          and life <= 4250
          and n.first_ms <= S.arrived[L]
          and n.hidden_ms - S.arrived[L] > 250
      end
    end
    if not ok then
      fail(
        "newest %s displayed in full %d times and not covered by a toast that stayed (covered by %s)",
        L,
        full[L] or 0,
        tostring(by)
      )
    end
  end
  return bad
end

-- ── every ordering ─────────────────────────────────────────────────────────
local ARRIVALS, OTHERS = { "a", "t" }, { "s", "m", "D", "X", "R", "E", "F" }
local seqs = {}
local function gen(prefix, k, j, maxk, maxj)
  if k >= 1 then
    seqs[#seqs + 1] = prefix
  end
  if k < maxk then
    for _, e in ipairs(ARRIVALS) do
      gen(prefix .. e, k + 1, j, maxk, maxj)
    end
  end
  if j < maxj then
    for _, e in ipairs(OTHERS) do
      gen(prefix .. e, k, j + 1, maxk, maxj)
    end
  end
end
gen("", 0, 0, 3, 3)
local cases = {}
for _, seq in ipairs(seqs) do
  cases[#cases + 1] = { seq }
end
-- Displacement 1-25 ms before the deadline (between the 25 ms watch's ticks),
-- of a toast that covers a commit, has a successor waiting, or neither.
for margin = 1, 25 do
  for _, prefix in ipairs({ "as", "asa", "asam", "asat", "asas", "asaa" }) do
    for _, suffix in ipairs({ "", "R", "F", "sR", "Ra" }) do
      cases[#cases + 1] = { prefix .. "X" .. suffix, margin }
    end
  end
end
if vim.env.HOTRELOAD_SEQ_ONLY then
  cases = {}
  for _, seq in ipairs(vim.split(vim.env.HOTRELOAD_SEQ_ONLY, ",", { trimempty = true })) do
    local name, margin = seq:match("^([^@]+)@?(%d*)$")
    cases[#cases + 1] = { name, tonumber(margin) }
  end
end
local failed, kinds, example = 0, {}, {}
for _, case in ipairs(cases) do
  local seq = case[2] and (case[1] .. "@" .. case[2]) or case[1]
  local bad = run(case[1], case[2])
  if #bad > 0 then
    failed = failed + 1
    for _, b in ipairs(bad) do
      local kind = b:gsub("c%d", "cN"):gsub("%d+", "#")
      kinds[kind] = (kinds[kind] or 0) + 1
      example[kind] = example[kind] or seq
    end
  end
end
for kind, n in vim.spairs(kinds) do
  io.stderr:write(("FAIL %d sequence(s), e.g. %s: %s\n"):format(n, example[kind], kind))
end
_G.Snacks = nil
print(("hot reload sequences: %d cases, %d failed"):format(#cases, failed))
assert(failed == 0, ("%d of %d sequences break the toast invariant"):format(failed, #cases))
