# Verification: proving a change works

No Herdr app change is done until you have checked it in the window as well
as in the files. The old screen can look fine while a new file failed to
load.

## Checklist

1. **Error files:** after an edit, look for `<name>.error` in the app home
   (`layout.error`, `keys.error`, `settings.error`, `programs.error`). An
   invalid file keeps the last good version running.
   ```sh
   ls ~/.config/herdr-app/*.error ~/.config/herdr-app/layouts/*.error 2>/dev/null
   ```
2. **Status:** `herdr-app status` must show `"errors": []` and the expected
   `"layout"`.
3. **Mods:** `herdr-app check ~/.config/herdr-app/mods/<name>` must pass.
4. **Look at it:** take a screenshot of the window (below) and compare it
   with the intent.

## Screenshots

### `herdr-app shot`

```sh
herdr-app shot /tmp/herdr.png   # last rendered frame, physical pixels
```

This captures the app even when it is covered or minimized, and needs no
screen-recording permission. It fails before the first frame and during GPU
recovery.

### cua-driver through the `executor` MCP

Use this when you also need the accessibility tree, or want to click or
type:

```ts
// mcp__executor__execute
const w = await tools.cua_driver.org.default.list_windows({});
const win = w.data.structuredContent.windows
  .find(x => x.app_name === "herdr-app" && x.title === "Herdr" && x.is_on_screen);
const r = await tools.cua_driver.org.default.get_window_state({
  pid: win.pid, window_id: win.window_id, capture_mode: "vision", include_screenshot: true });
for (const c of r.data.content) if (c.type === "image") emit(c);
```

- `herdr-app` owns many off-screen helper windows. Pick the one titled
  `Herdr` that is on screen.
- `screenshot_out_file: "/tmp/…"` failed in testing with "the output
  path's existing ancestor is not a directory" (on macOS `/tmp` is a
  symlink). Omit the option and use the emitted image, or pass a real
  directory such as `/private/tmp/…` (not tested).

## Recovery

- `ctrl-alt-shift-escape` always works. It sets aside the shown layout and
  `keys.json` (as `*.reset-<time>`) and returns to the default screen.
- `herdr-app do layout.switch '{"name":"main"}'` returns to the shipped
  layout.
- `herdr-app do layout.reset '{"name":"main"}'` resets a shipped layout and
  its clicks.
- If you are testing a change to a live file such as `settings.json`, back
  it up first (`cp -p … /tmp/…`) and restore it afterwards.

## Sources

- `~/.config/herdr-app/AGENTS.md` (0.1.14): "Changing things safely", "Seeing the window"
- cua-driver via executor MCP, used on this machine 2026-11-09
