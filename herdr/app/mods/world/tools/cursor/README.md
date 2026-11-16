# world-cursor

A small macOS helper for the `world` mod. While the person holds the right mouse
button to turn the camera, it hides the cursor and keeps it from getting stuck at
a screen edge. The gpui-shell mod runtime has no API to hide the cursor or lock the
pointer, so the mod starts this helper and sends it signals.

## Commands

| Command | Effect |
| --- | --- |
| `world-cursor hold` | Saves the cursor position P, hides the cursor for the whole system, then blocks. `SIGUSR1` moves the cursor back to P. `SIGTERM`, `SIGINT`, `SIGHUP`, or 120 s moves it back to P, shows it again, and exits 0. If a holder is already running, the new one stops it first. |
| `world-cursor release` | Tells the running holder to exit. Exits 0 when no holder is running. |
| `world-cursor recenter` | Sends `SIGUSR1` to the running holder. Exits 0 when no holder is running. |
| `world-cursor visible` | Debugging aid: prints `true` or `false` from `CGCursorIsVisible()`. |

The holder's pid is stored in `$TMPDIR/world-cursor.pid`. A pid is used only if
that process is alive and its name is still `world-cursor`. That way a stale file
left behind by `SIGKILL` can't lead to signalling a process that reused the pid.

## Private API

A background process can't normally hide the cursor while another app is
frontmost. Before it calls `CGDisplayHideCursor`, the helper calls:

```c
CGSSetConnectionProperty(_CGSDefaultConnection(), _CGSDefaultConnection(),
                         CFSTR("SetsCursorInBackground"), kCFBooleanTrue);
```

These symbols are looked up at runtime with `dlsym`. If they're missing, the
helper falls back to `SLSMainConnectionID` and `SLSSetConnectionProperty`. If
neither pair is found, `hold` exits 1 with an error message.

Moving the cursor uses `CGWarpMouseCursorPosition`, followed straight away by
`CGAssociateMouseAndMouseCursorPosition(1)`. The second call stops input from
freezing for about 250 ms after the move.

The hide is tied to the helper's WindowServer connection, so macOS shows the
cursor again whenever the process dies, including after `SIGKILL`.

## Build and test

```bash
bash build.sh        # swiftc -O -> ../../bin/world-cursor; skips the build if it's already up to date
B=../../bin/world-cursor
$B hold & sleep 0.5; $B visible; $B recenter; $B release   # visible prints false
$B visible                                                 # true
```

Tested on macOS 26.7 (arm64) with Swift 6.4.
