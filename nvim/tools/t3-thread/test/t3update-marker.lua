-- B-R1-05/06: the marker contract at millisecond precision, the malformed
-- fallback, concurrent removal, and status file I/O off the UI loop.
local F = dofile("nvim/tools/t3-thread/test/support/t3update-fixture.lua")
local U = F.U
U.config.poll_ms = 30
U.config.start_timeout_ms = 200
U.config.timeout_ms = 1000

-- Freeze wall-clock time at `ms` (both os.time and gettimeofday).
local function freeze(ms)
  local time, tod = os.time, vim.uv.gettimeofday
  os.time = function()
    return math.floor(ms / 1000)
  end
  vim.uv.gettimeofday = function()
    return math.floor(ms / 1000), (ms % 1000) * 1000
  end
  return function()
    os.time, vim.uv.gettimeofday = time, tod
  end
end

local function fresh()
  F.reset()
  F.server(true)
  F.set_runtime(1000, "1.0.0")
  F.reply.osascript = { code = 0, stdout = "clicked Check for Updates…" }
end

local function status_text()
  F.notices = {}
  U.status()
  F.until_true(function()
    return #F.notices > 0
  end, 1000, "status notice")
  return F.last()
end

-- Admission: the trigger runs (osascript) or the run refuses as in progress.
local function admitted()
  F.calls, F.notices = {}, {}
  U.update()
  F.until_true(function()
    return #F.of("osascript") > 0 or F.has("already in progress")
  end, 1000, "update decision")
  local ok = #F.of("osascript") > 0
  F.stop(U)
  return ok
end

local base = (os.time() + 100) * 1000 + 100

F.case("last fractional second before expiry is still in progress", function()
  fresh()
  F.write(F.marker, vim.json.encode({ startedAt = base - 59600, expiresAt = base + 400 }))
  local thaw = freeze(base)
  local ok, err = pcall(function()
    local text = status_text()
    assert(text:find("update in progress %(1 s left%)"), text)
    assert(not admitted(), "400 ms before expiry must refuse")
  end)
  thaw()
  assert(ok, err)
end)

F.case("exactly at expiry counts as absent", function()
  fresh()
  F.write(F.marker, vim.json.encode({ startedAt = base - 60000, expiresAt = base }))
  local thaw = freeze(base)
  local ok, err = pcall(function()
    local text = status_text()
    assert(text:find("no update in progress %(marker expired 0 s ago%)"), text)
    assert(admitted(), "expired marker admits the trigger")
  end)
  thaw()
  assert(ok, err)
end)

F.case("partial marker with a past expiry uses the mtime fallback", function()
  fresh()
  F.write(F.marker, vim.json.encode({ expiresAt = (os.time() - 5) * 1000 }))
  local text = status_text()
  local left = tonumber(text:match("update in progress %((%d+) s left%)"))
  assert(left and left >= 59 and left <= 60, text)
  assert(not admitted(), "a fresh malformed marker refuses")
  local old = os.time() - 61
  vim.uv.fs_utime(F.marker, old, old)
  text = status_text()
  assert(text:find("no update in progress %(marker expired"), text)
  assert(admitted(), "after mtime + 60 s the malformed marker is absent")
end)

F.case("non-numeric timestamps are malformed too", function()
  fresh()
  F.write(F.marker, vim.json.encode({ startedAt = "x", expiresAt = tostring((os.time() + 30) * 1000) }))
  local left = tonumber(status_text():match("update in progress %((%d+) s left%)"))
  assert(left and left >= 59, F.last())
end)

F.case("a marker removed between stat and read is absent", function()
  fresh()
  F.set_marker(40)
  local open = vim.uv.fs_open
  vim.uv.fs_open = function(path, ...)
    if path == F.marker then
      os.remove(F.marker)
    end
    return open(path, ...)
  end
  local ok, err = pcall(function()
    local text = status_text()
    assert(text:find("no update in progress") and not text:find("expired"), text)
  end)
  vim.uv.fs_open = open
  assert(ok, err)
end)

F.case("status reads files off the UI loop", function()
  fresh()
  F.set_marker(40)
  local open, uv_open = io.open, vim.uv.fs_open
  local blocking = 0
  io.open = function(path, mode)
    if path == F.runtime or path == F.marker then
      blocking = blocking + 1
      vim.uv.sleep(75)
    end
    return open(path, mode)
  end
  -- Async opens of the state files complete 75 ms later, on the event loop.
  vim.uv.fs_open = function(path, flags, mode, cb)
    if cb and (path == F.runtime or path == F.marker) then
      return uv_open(path, flags, mode, function(...)
        local args = { ... }
        local t = vim.uv.new_timer()
        t:start(75, 0, function()
          t:close()
          cb(unpack(args))
        end)
      end)
    end
    return uv_open(path, flags, mode, cb)
  end
  local ui_tick, notice_at
  local ok, err = pcall(function()
    F.notices = {}
    U.status()
    vim.defer_fn(function()
      ui_tick = vim.uv.hrtime()
    end, 40)
    F.until_true(function()
      if #F.notices > 0 and not notice_at then
        notice_at = vim.uv.hrtime()
      end
      return notice_at ~= nil and ui_tick ~= nil
    end, 2000, "notice and UI tick")
  end)
  io.open, vim.uv.fs_open = open, uv_open
  assert(ok, err)
  assert(blocking == 0, "state files read with blocking io.open")
  assert(ui_tick < notice_at, "a UI timer must run before the status notice")
  assert(#F.notices == 1, "still exactly one notice")
  assert(F.last():find("update in progress"), F.last())
end)

F.case("T3CODE_HOME is trimmed like the desktop does", function()
  fresh()
  F.set_runtime(777, "7.7.7")
  vim.env.T3CODE_HOME = "  " .. F.home .. "\t"
  local ok, err = pcall(function()
    local text = status_text()
    assert(text:find("pid 777"), text)
  end)
  vim.env.T3CODE_HOME = F.home
  assert(ok, err)
end)

F.case("an oversized marker is unreadable, never a decoded prefix", function()
  fresh()
  local now = os.time() * 1000
  local prefix = vim.json.encode({ startedAt = now - 65000, expiresAt = now - 5000 })
  F.write(F.marker, prefix .. string.rep(" ", 65536 - #prefix) .. "malformed trailing bytes")
  local left = tonumber(status_text():match("update in progress %((%d+) s left%)"))
  assert(left and left >= 59, "mtime fallback while fresh: " .. F.last())
  assert(not admitted(), "a fresh oversized marker refuses")
  local old = os.time() - 61
  vim.uv.fs_utime(F.marker, old, old)
  assert(status_text():find("no update in progress %(marker expired"), F.last())
  assert(admitted(), "after mtime + 60 s it is absent")
end)

F.done()
