# cmux Socket Troubleshooting

Discovered on cmux 0.64.13 (build 93), macOS 26.3. Run from an external agent shell (Hermes/Django on Discord, not inside a cmux terminal).

## Full Troubleshooting Flow

### 1. Check if cmux is installed

```bash
/Applications/cmux.app/Contents/Resources/bin/cmux --version
# cmux 0.64.13 (93) [beb0d8f93]
```

The binary lives inside the `.app` bundle. It may not be symlinked into PATH.

### 2. Check if cmux is running

```bash
pgrep -fl cmux
# 95834 /Applications/cmux.app/Contents/MacOS/cmux
```

### 3. Find the socket

The socket is NOT at `/tmp/cmux.sock` as older docs suggest. cmux 0.64.13 uses:

```
~/.local/state/cmux/cmux.sock
```

Check with `$CMUX_SOCKET_PATH` override:

```bash
test -S "${CMUX_SOCKET_PATH:-$HOME/.local/state/cmux/cmux.sock}" && echo "SOCKET UP" || echo "NO SOCKET"
```

### 4. Launch cmux if not running

```bash
open -a cmux
# Wait ~1-2s for socket to appear
```

### 5. Test CLI access

```bash
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
$CMUX workspace list --json
```

Possible errors:
- `Error: Failed to connect to socket at ~/.local/state/cmux/cmux.sock (Connection refused, errno 61)` — stale socket from a killed process. Kill cmux, remove socket: `rm -f ~/.local/state/cmux/cmux.sock`, relaunch.
- `Error: Failed to write to socket (Broken pipe, errno 32)` — socket exists but access is denied by security mode.

### 6. Test raw socket access

```bash
echo '{"id":"1","method":"workspace.list","params":{}}' | nc -U ~/.local/state/cmux/cmux.sock
```

If blocked, returns:

```
ERROR: Access denied — only processes started inside cmux can connect
```

### 7. Resolve `cmuxOnly` block

The default socket access mode is `cmuxOnly` — only processes spawned inside a cmux terminal can connect. External agents (Discord Hermes, SSH, standalone terminals) get denied.

**Fix:** cmux > Settings > Automation > change socket mode from `cmuxOnly` to `automation`.

| Mode | Behavior |
|---|---|
| `cmuxOnly` | Default — only cmux-spawned processes |
| `automation` | Any local process (required for agent control) |
| `password` | Password-gated access |
| `allowAll` | Unsafe — open to all |

### Quick Diagnostic One-liner

```bash
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
echo "CMUX BINARY: $($CMUX --version 2>&1)"
echo "PROCESS: $(pgrep -fl cmux | head -3)"
echo "SOCKET: $(test -S ~/.local/state/cmux/cmux.sock && echo 'FOUND' || echo 'MISSING')"
echo "CLI TEST: $($CMUX workspace list --json 2>&1 | head -1)"
echo "SOCKET TEST: $(echo '{"id":"1","method":"workspace.list","params":{}}' | nc -U ~/.local/state/cmux/cmux.sock 2>&1)"
```
