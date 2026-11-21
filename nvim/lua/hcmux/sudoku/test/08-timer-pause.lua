-- features/08-timer-pause.feature: "timer runs", ":q pauses…", "reopening resumes" (WP1).
local H = require("hcmux.sudoku.test.harness")
H.boot()

H.scenario("the timer runs while the popover is open", function()
  H.background()
  H.eq(H.footer(), "NORMAL  R1C1  00:00 RUNNING", "00:00 at the start")
  H.clock(3000) -- only the clock moves: the board's own tick must redraw the footer
  H.eq(H.state().timer, { status = "running", elapsed_ms = 3000 }, "elapsed_ms == 3000")
  H.ok(
    H.wait(function()
      return H.footer() == "NORMAL  R1C1  00:03 RUNNING"
    end),
    "the footer timer reads 00:03 RUNNING (got " .. H.footer() .. ")"
  )
end)

H.scenario(":q pauses and the paused time survives closing", function()
  H.background()
  H.advance(5000)
  H.ok(H.footer():find("00:05 RUNNING", 1, true), "the timer reads 00:05")
  H.type(":q<CR>")
  H.advance(10000)
  H.eq(H.state().timer, { status = "paused", elapsed_ms = 5000 }, "paused at 5000 ms")
  H.ok(not H.state().open, "the popover is closed")
end)

H.scenario("reopening resumes the timer from the paused value", function()
  H.background()
  H.advance(5000)
  H.type(":q<CR>")
  H.advance(10000)
  H.type(":EnviSudoku<CR>")
  H.eq(H.footer(), "NORMAL  R1C1  00:05 RUNNING", "the footer reads 00:05 RUNNING")
  H.advance(1000)
  H.eq(H.state().timer, { status = "running", elapsed_ms = 6000 }, "and it runs on")
end)

H.finish()
