# Remote Agent Launch in cmux Splits

Verified on cmux 0.64.13, macOS 26.3, controlled from Hermes/Django via Discord agent session. Socket access mode must be `automation` (not the default `cmuxOnly`) — see `socket-troubleshooting.md` for setup.

## Launch Two Agents in a Split

### Preferred: New Workspace + Split Panes

```bash
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
AGENT_DIR="/path/to/repo"

# 1. Ensure cmux is running
open -a cmux
sleep 2

# 2. Create a dedicated workspace (or use an existing one)
$CMUX workspace create --name "Agent Workspace" --cwd "$AGENT_DIR"
# Returns: OK workspace:N

# 3. Split: create a second pane to the right
$CMUX new-pane --workspace workspace:N --type terminal --direction right --focus false
# Returns: OK surface:X pane:Y workspace:N

# 4. Launch agents — send `claude\n` separately from `cd`
#    (shell chaining like `cd /path && claude\n` can fail on login shells)
$CMUX send --surface surface:SURFACE_A "claude\n"
$CMUX send --surface surface:SURFACE_B "claude\n"
```

### Alternative: Fresh Tab via `new-surface`
If you already have a pane but want a clean terminal tab (login shell that inherits the workspace cwd):

```bash
$CMUX new-surface --pane pane:N --type terminal --focus false
# Returns: OK surface:X pane:N workspace:Z
$CMUX send --surface surface:X "claude\n"
```

Tab-based surfaces avoid the `cd ... && claude\n` pitfall because they start in the workspace's working directory.

## Launch Two Agents in an Existing Workspace

```bash
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
WS="workspace:1"            # target workspace
AGENT_DIR="/path/to/repo"

# 1. Ensure cmux is running
open -a cmux
sleep 2
test -S ~/.local/state/cmux/cmux.sock || exit 1

# 2. Select workspace
$CMUX workspace select "$WS"

# 3. Create a horizontal (down) split
$CMUX new-pane --workspace "$WS" --type terminal --direction down --focus false

# 4. Send cd to both surfaces first, then launch claude
$CMUX send --surface surface:1 "cd $AGENT_DIR\n"
sleep 1
$CMUX send --surface surface:4 "cd $AGENT_DIR\n"
sleep 1
$CMUX send --surface surface:1 "claude\n"
$CMUX send --surface surface:4 "claude\n"

# 5. Verify both are running
$CMUX read-screen --surface surface:1 --lines 5
$CMUX read-screen --surface surface:4 --lines 5
```

## Interacting With Running Agents

```bash
# Send a command (include \\n for Enter)
$CMUX send --surface surface:1 "/model\\n"

# Send keyboard keys
$CMUX send-key --surface surface:1 escape
$CMUX send-key --surface surface:4 ctrl+c

# Read screen output
$CMUX read-screen --surface surface:1 --lines 20
$CMUX read-screen --surface surface:4 --lines 20 --scrollback
```

## Agent CLI Discovery

| Agent | Binary Path |
|---|---|
| Claude Code | `~/.local/bin/claude` |
| Codex | `~/.nvm/versions/node/v24.15.0/bin/codex` |
| OpenCode | `~/.opencode/bin/opencode` |

## Tips

- **Always use `--focus false`** when creating panes/surfaces from an agent to avoid yanking the user's focus.
- **Bare `claude\n` is more reliable than `cd ... && claude\n`** — the shell chaining can cause claude to exit prematurely on login shells. Split into two separate sends with a `sleep 1` in between.
- **Fresh surfaces show "Last login"** — they are login shells (new TTY). This is normal.
- **Verify with `read-screen`** after a few seconds — agents may print setup noise before their prompt appears.
- **Dismiss interactive menus** with `send-key escape` before sending further commands.
