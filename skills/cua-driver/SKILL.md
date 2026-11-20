---
name: cua-driver
description: 'Drive and inspect macOS desktop apps from Claude Code with the cua-driver MCP server (mcp__cua-driver__* tools): list windows, read accessibility trees and window screenshots, click, type, press keys, and verify the visible result. Use for GUI tasks, desktop acceptance checks, and observing iOS Simulator / Android Emulator windows. Not for Pi: Pi has its own computer-use router skill with Codemode, runtime lifecycle and identity pinning.'
metadata:
  version: '1.0.0'
---

# cua-driver from Claude Code

**Setup:** a user-scope stdio MCP server.

```sh
claude mcp add -s user cua-driver -- /Applications/CuaDriver.app/Contents/MacOS/cua-driver mcp
```

**How it connects:**
- It proxies to the **already-running shared daemon** (`cua-driver serve`, socket `~/Library/Caches/cua-driver/cua-driver.sock`).
- If no daemon is running, `mcp` launches CuaDriver.app.

**What this skill does not cover:** the daemon lifecycle, identity pinning, owned daemons, and Codemode composition. Those live in Pi's `computer-use` router skill and the `packages/cua-driver` runtime. Do not reimplement them here.

**Tool names:** the tools appear as `mcp__cua-driver__<tool>`. If they are missing, run `/mcp` to reconnect, or report the gap. Do not substitute AppleScript, `osascript` keystrokes, or shell-generated input.

## Hard rules

- **Never touch the shared daemon's lifecycle:**
  - no `cua-driver stop`;
  - no raw `shutdown`;
  - never kill its pid;
  - never delete its socket or pid file.

  `kill_app` force-kills the target pid (`kill -9`). Use it only when the user explicitly names the process.
- **Never change trust or configuration without being asked:** no `set_config`, `check_permissions`-driven grants or `cua-driver permissions grant`, and no `browser_prepare` or `browser_download` unless the user explicitly asks for that action.
  - The MCP boundary auto-approves browser prepare and download. **The tool annotations are not consent.**
- **No outward or destructive effects:**
  - never sign out;
  - never send messages to people;
  - never delete, erase or reset data;
  - never dismiss unsaved work.

  The user's stricter rules always win.
- **One actor per window.** Do not act on a window another agent or the user is driving.
- **Screenshots create and remove a private temp file.** `get_window_state` with a screenshot, every pixel action, `zoom`, click `debug_image_out` and `get_desktop_state` each write and then delete `$TMPDIR/cua-driver-rs-capture-<pid>-<uuid>/`. If the user has a strict no-deletion rule, ask before taking any capture.
  - Accessibility-only calls do not capture: `list_windows`, and `get_window_state` with `include_screenshot:false`.
  - Keyboard calls with no x/y do not capture: `press_key`, `type_text` and `hotkey`.

## The loop: observe, act, re-observe

1. **Session (optional, recommended):** call `start_session {session:"<unique-id>", capture_scope:"window"}`. Window scope is the default safe choice; never use `desktop` unless the user asks.
   - Sessions are labels for the cursor and policy, not credentials.
   - Call `end_session` for your own id when done.
2. **Find the target** with `list_windows` (optionally filtered by `pid`). Bind to an exact `pid` + `window_id`.
   - **Titles are not identity.** For example, two simulators can both be titled `iPhone 17`.
   - Check `is_on_screen` and `on_current_space`.
3. **Observe** with `get_window_state {pid, window_id}`. Prefer `structuredContent.elements` (`element_index`, `element_token`, role, label, value, frame).
   - Pass `include_screenshot:false` when you only need to re-index.
   - Re-snapshot before every element action, because indices are replaced by each snapshot.
4. **Act, preferring the accessibility path:**
   - **Accessibility:** `click`, `set_value` or `type_text` with `element_index` or `element_token` plus `pid` + `window_id`. This works on background windows and does not steal focus.
   - **Pixel:** use `x,y` only for canvas, GPU or custom surfaces, or an empty AX tree (`degraded_reason: ax_window_unresolved`).
     - Read coordinates **straight off the returned image**. The image is downscaled so its longest side is at most 1568 px, and the driver undoes both the downscale and the Retina scale itself.
     - **Never** compute coordinates from window bounds × scale.
   - **Keys:** `press_key`, `hotkey` or `type_text` with `pid` + `window_id`. They are delivered via `CGEventPostToPid`.
   - **Delivery ladder:** background accessibility, then a screenshot, then background pixel, then a screenshot, then `delivery_mode:"foreground"`. Foreground briefly fronts the window and restores it, so it is visible to the user; escalate one rung at a time.
5. **Re-observe** with a *fresh* `get_window_state`, taken after the UI settles and after the action.
   - A successful dispatch, `verified:false` or `effect:"unverifiable"` is **not** proof.
   - Report the result as unverified until a fresh observation shows the effect.
   - Never retry blindly an action that may already have completed.

## Failure meanings

| Signal | Meaning and response |
|---|---|
| `px_capture_unavailable` | The window can't be captured (typically off screen, minimized or on another Space; GPU-rendered windows such as the Android Emulator have no off-screen surface). The pixel action was **refused, not sent**. Ask the user to bring the window on screen, or `bring_to_front {pid, window_id}`, which persistently steals focus and may switch Spaces. Then re-check `list_windows`. |
| `px_window_not_found` / `px_frame_mismatch` | The window bounds or capture scale can't be proven. The action was refused. Re-list and re-observe. |
| `window_id_not_found` / `window_owner_pid_mismatch` | The window is stale, or belongs to another process (for example a sandboxed Open/Save panel). Use the `owner_pid` it reports. |
| `stale` element token | Re-snapshot, then act. |
| JSON-RPC `-32603` "daemon transport error … Connection refused" | The daemon is gone. The MCP proxy stays alive, but every call fails. Stop and report; do not restart the daemon yourself. |

## Mobile simulators and emulators (observation via the desktop window)

- **iOS Simulator** on Xcode 26 may be hosted by **Device Hub** (`com.apple.dt.Devices`), not `Simulator.app`.
  - Its AX tree is often empty, so use the pixel path off the image.
  - Bind the window to the device by its effect, not its title.
- **Android Emulator** windows belong to `qemu-system-aarch64`. The device surface has no AX tree, and it must be **on screen** to capture.
- Use `agent-device` or `xcrun simctl` / `adb` only for device identity and independent checks. Claims that cua-driver drove the app need cua-driver input plus a fresh cua-driver observation.
- Never erase, reset, wipe, uninstall or cold-boot a device.

## Discovery

The server exposes about 49 tools, and their schemas are authoritative. Read a tool's schema before first use.

Useful read-only tools:
- `list_apps`
- `list_windows`
- `get_window_state`
- `get_accessibility_tree`
- `get_screen_size`
- `get_session_state`
- `health_report`
- `check_permissions`
- `get_config`

For a browser tab, prefer Chrome DevTools or the browser tools you were given over pixel-driving the page. `type_text` into web content reports `unverifiable` by design.
