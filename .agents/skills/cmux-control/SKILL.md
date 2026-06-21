---
name: cmux-control
description: Drive the cmux native macOS terminal app from CLI or socket — workspaces, panes, surfaces, browser automation, notifications, sidebar metadata, session restore. Use whenever the user mentions cmux, wants to control terminal layout from an agent, automate browser panels on macOS, send notifications/flashes to the sidebar, or integrate an AI agent with cmux hooks. macOS only (14.0+).
version: 1.4.0
metadata:
  hermes:
    tags: [cmux, control, cmux-control, terminal-control, terminal, command-line]
    category: cmux 
---

# cmux Control

cmux is a native macOS terminal app for running multiple AI coding agents in parallel. It exposes a CLI (`cmux`) and a Unix-socket JSON-RPC API at `~/.local/state/cmux/cmux.sock` (override with `$CMUX_SOCKET_PATH`) for full topology and browser control.

## Core Concepts

- **Window** — top-level macOS cmux window
- **Workspace** — sidebar tab within a window (one git branch / project context)
- **Pane** — split region inside a workspace
- **Surface** — tab inside a pane (terminal or browser)

Handles default to short refs (`workspace:2`, `pane:1`, `surface:7`); UUIDs accepted as input. Add `--id-format uuids|both` for full IDs in output.

## Detect cmux in a Shell

```bash
[ -S "${CMUX_SOCKET_PATH:-$HOME/.local/state/cmux/cmux.sock}" ] || exit 0   # bail if not in cmux
[ -n "${CMUX_WORKSPACE_ID:-}" ] && echo "inside cmux surface"
```

Injected env vars in every cmux-spawned terminal: `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, `CMUX_SOCKET_PATH`, `CMUX_PORT`. **Always anchor automation to `CMUX_WORKSPACE_ID`** — the visually focused workspace may not be the agent's caller workspace.

## Fast Start — Topology

```bash
cmux identify --json                              # who am I (window/workspace/pane/surface)
cmux current-workspace                            # active workspace ref (returns "workspace:N")
cmux tree                                         # full hierarchy
cmux list-workspaces --json
cmux list-panes --workspace "$CMUX_WORKSPACE_ID"
cmux list-surfaces --workspace "$CMUX_WORKSPACE_ID"

cmux new-workspace --name "feature-x" --cwd /path/to/repo
cmux new-pane --workspace "$CMUX_WORKSPACE_ID" --type terminal --direction right --focus false
cmux new-pane --workspace "$CMUX_WORKSPACE_ID" --type browser  --direction right --url http://localhost:3000
cmux move-surface --surface surface:7 --pane pane:2 --focus false
cmux split-off --surface surface:7 right
cmux reorder-surface --surface surface:7 --before surface:3
cmux close-surface --surface surface:7
```

## Send Input

```bash
cmux send "echo hi\n"                                                    # focused terminal
cmux send-key "ctrl+c"                                                    # enter|tab|esc|backspace|arrows|ctrl+x|shift+tab
cmux send --surface surface:7 "npm run build\n"                           # specific surface
cmux send-key --surface surface:7 enter                                   # submit pending prompt
cmux send-key --surface surface:7 shift+tab                               # Codex plan mode toggle (confirmed live June 4, 2026)
```

**Notable key names:** `enter`, `tab`, `shift+tab`, `escape`, `ctrl+c`, `ctrl+x`, `backspace`, `up`, `down`, `left`, `right`.

**Send semantics:** `cmux send --surface S "text\n"` — the `\n` in double-quoted shell strings is interpreted as Enter by the shell before cmux receives it. Works for most cases. If the target shows the prompt as pending (not submitted), follow up with `cmux send-key --surface S enter`.

**Codex dispatch pattern (proven June 4, 2026):**
1. Launch Codex: `cmux send --surface S "cd /path && codex\n"`
2. Wait for Codex to show `Ready` (poll `read-screen`)
3. Toggle plan mode: `cmux send-key --surface S shift+tab`
4. Send prompt: `cmux send --surface S "$(cat prompt.md)\n"`
5. Submit: `cmux send-key --surface S enter`
6. Confirm: `cmux read-screen --surface S --scrollback` shows `Working` + `Plan mode`

## Notifications & Sidebar Metadata

```bash
cmux notify --title "Done" --body "tests passed"
cmux set-status build "compiling" --icon hammer --color "#ff9500"
cmux set-progress 0.5 --label "Building..."
cmux log --level success "All 42 tests passed"               # info|progress|success|warning|error
cmux trigger-flash --workspace "$CMUX_WORKSPACE_ID"          # blue-ring attention cue
cmux sidebar-state --json                                    # dump all sidebar metadata
```

## Browser Automation (WKWebView)

Workflow: open → wait → snapshot → act → re-snapshot.

```bash
S=$(cmux --json browser open https://example.com | jq -r .result.surface_ref)
cmux browser "$S" wait --load-state complete --timeout-ms 15000
cmux browser "$S" snapshot --interactive                     # returns elements as e1, e2, ...
cmux browser "$S" fill e1 "jane@example.com"
cmux browser "$S" click e2 --snapshot-after

# Navigation / inspection
cmux browser "$S" goto URL | back | forward | reload
cmux browser "$S" get url | get title | get text body | get value "#email" | get count ".row"
cmux browser "$S" eval 'return document.title'

# Waits
cmux browser "$S" wait --selector "#ready" --timeout-ms 10000
cmux browser "$S" wait --url-contains "/dashboard" --timeout-ms 10000

# Session
cmux browser "$S" cookies get | cookies set --name foo --value bar
cmux browser "$S" state save /tmp/auth.json | state load /tmp/auth.json

# Diagnostics
cmux browser "$S" console list | errors list | screenshot
```

**Not supported by WKWebView** (return `not_supported`): viewport emulation, geolocation/offline emulation, trace recording, network route interception, raw input injection.

## Markdown Viewer

```bash
cmux markdown open plan.md --direction right                 # live-watching renderer
cmux open file.pdf                                           # auto-routes to right viewer
```

## Settings & Config

```bash
cmux docs settings        # prints paths, schema URL, reload cmd — read BEFORE editing
cmux settings path        # path to cmux.json
cmux settings cmux-json   # open in editor
cmux reload-config        # hot-reload cmux.json + ~/.config/ghostty/config (Cmd+Shift+,)
```

Locations:
- cmux settings: `~/.config/cmux/cmux.json` (canonical). Project-local override: `.cmux/cmux.json` or `./cmux.json`.
- Terminal rendering (font, cursor, theme, scrollback, opacity, blur): `~/.config/ghostty/config` — NOT cmux.json.

Before editing `cmux.json`, copy it to a timestamped `.bak` next to it so the user can revert. Schema: `https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json`.

## Agent Hooks & Install

```bash
brew tap manaflow-ai/cmux && brew install --cask cmux
sudo ln -sf /Applications/cmux.app/Contents/Resources/bin/cmux /usr/local/bin/cmux
cmux hooks setup                                             # all detected agents
cmux hooks setup codex|grok|antigravity|opencode             # specific agent
npx skills add manaflow-ai/cmux -g -y                        # install cmux skills for agents
```

Native session-resume supported for: Claude Code, Codex, Grok, OpenCode, Pi, Amp, Cursor CLI, Gemini, Antigravity, Rovo Dev, Hermes, Copilot, CodeBuddy, Factory, Qoder.

## Socket API (advanced)

`~/.local/state/cmux/cmux.sock` — Unix socket, JSON-RPC v2. Override location with `$CMUX_SOCKET_PATH`. Use for tight loops where subprocess spawn cost matters; otherwise prefer the CLI.

```bash
echo '{"id":"1","method":"workspace.list","params":{}}' | nc -U ~/.local/state/cmux/cmux.sock
```

Method prefixes: `system.*`, `window.*`, `workspace.*`, `pane.*`, `surface.*`, `notification.*`, `browser.*`. Full list and Python client example in `references/socket-troubleshooting.md`.

Access modes: `cmuxOnly` (default — only cmux-spawned processes), `automation` (any local process), `password`, `allowAll` (unsafe). If you hit `Failed to connect to socket`, switch mode in Settings > Automation or run inside a cmux terminal. See `references/socket-troubleshooting.md`.

## Critical Rules — Non-Disruptive Automation

1. **Anchor to `CMUX_WORKSPACE_ID`.** Never assume the visually focused workspace is the target.
2. **Never call focus-changing verbs speculatively.** `select-workspace`, `focus-pane`, `focus-panel`, `focus-surface` only on explicit user request. Pass `--focus false` whenever available.
3. **Build layout additively in one call.** `cmux new-pane --type … --focus false` beats create-then-move-then-focus chains.
4. **Right-side helper pane pattern.** Reuse an existing non-caller helper pane if present; otherwise create exactly one right-side pane.
5. **Never send input to surfaces you don't own.** Only target surfaces in the caller's workspace unless the user explicitly asks for cross-workspace routing.
6. **Check surface health before routing input** when UI state may be stale: `cmux surface-health`.
7. **Never poll a cmux-delegate with sleep + read-screen in the same turn.** Fire a command via `cmux send`, then move on. The `cmux-events` hook or the user's next message will surface results. Polling blocks the agent turn and was explicitly corrected.

## Common Pitfalls

- **`split-off` fails on lone surfaces.** Use `cmux new-pane --direction <dir>` instead.
- **`claude` launch with `&&` chaining may fail.** Send `cd /path\n` then `claude\n` separately. Or use `new-surface` (inherits workspace cwd).
- **`new-workspace` aliased to `workspace create`.** Legacy form works; prefer the new form.
- **`surface-health` `in_window` != visible.** Surfaces with `in_window=false` still accept send commands.
- **`send --surface` replaces deprecated `send-surface`.**
- **External agents blocked by `cmuxOnly`.** Switch to `automation` mode in Settings.
- **macOS only.**
- **Symlink loops in skill paths break agent skill loading.** If an agent can't find skills (empty list, ELOOP error), check for circular symlinks in `~/.<agent>/skills/`. See `references/skill-symlink-resolution.md`. Every agent should point directly to the real skill directory — no chained symlinks.
- **WKWebView ≠ CDP.** No network mocking or viewport emulation.
- **Resume strips sensitive env vars.** Re-inject tokens at resume.
- **Skills snapshot at app start.** Restart consuming agent after skill edits.
- **Legacy v1 socket payloads rejected.** Use v2 JSON-RPC only.

## Events Streaming API

cmux exposes a long-lived streaming event subscription — push-based, not poll.

```bash
# Basic stream (limit 5 events, exit)
cmux events --limit 5 --no-heartbeat

# Persistent subscription with cursor-file durability
cmux events --cursor-file ~/.cache/cmux/events.seq --reconnect

# Filter by name or category
cmux events --name surface.closed,surface.created
cmux events --category notification

# Replay historical events
cmux events --after 170 --limit 10
```

See `references/cmux-events-api.md` for full details: ack frame structure, event frame schema, recognized event names, and the cursor-file durability contract.

### Quick Reference (Confirmed Event Names)

| Category | Names | Fires When |
|----------|-------|-----------|
| `window` | `window.keyed`, `window.unkeyed` | Window focused/unfocused |
| `surface` | `surface.selected`, `surface.focused`, `surface.closed`, `surface.created` | Surface lifecycle |
| `pane` | `pane.focused` | Pane focus changes |
| `notification` | (use `--category notification`) | Sidebar notification sent |

The `--cursor-file` defines the durability contract: the consumer can crash or restart and pick up exactly where it left off with zero event loss.

## cmux-events Hook (Hermes Gateway Integration)

A Hermes gateway hook at `~/.hermes/hooks/cmux-events/` provides post-turn reactivity — after each agent turn, it scans cmux surfaces for completion markers and Postgres for recently finished delegates, then injects findings into the next turn's context via the MemoryProvider's `prefetch()`. See `references/cmux-events-hook.md` for the full architecture.

## Browser Harness (CDP Browser Automation)

For full Chrome CDP control beyond cmux's WKWebView, see `references/browser-harness-setup.md`. Covers install, Chrome remote debugging, coordinate-click pattern, and remote cloud browsers.

## Remote Agent Launch

For using cmux surfaces as the delegation mechanism for Claude Code (replacing `claude -p` which moved to API billing after June 15, 2026), see `references/cmux-delegation-pattern.md`. Covers: pool-of-surfaces dispatch, delimiter-based output capture, lifecycle management, and comparison vs. `claude -p`.

## Reference: Full CLI Help

For any command, `cmux <cmd> --help` is authoritative. Use `cmux capabilities --json` to enumerate available socket methods in the current build.

## Keyboard Shortcuts (most-used)

Workspaces: ⌘N new, ⌘1–8 jump, ⌃⌘[ / ⌃⌘] prev/next, ⌘⇧W close, ⌘B sidebar.
Surfaces: ⌘T new, ⌘⇧[ / ⌘⇧] prev/next, ⌘W close, ⌃1–8 jump.
Splits: ⌘D right, ⌘⇧D down, ⌥⌘D browser right, ⌥⌘←→↑↓ focus directional, ⌘⇧↵ zoom.
Browser: ⌘⇧L open, ⌘L address bar, ⌘[/⌘] back/forward, ⌥⌘I devtools.
App: ⌘, settings, ⌘⇧, reload-config, ⌘⇧P palette, ⌘⇧O restore session, ⌃⌥⌘. system-wide show/hide.
