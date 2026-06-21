# cmux Delegation Pattern — Successor to `claude -p`

## Context

Anthropic restricted `claude -p` (pipe mode) to API billing after **June 15, 2026**. Pro subscription users can no longer delegate to Claude Code via `claude -p "$PROMPT"` without burning API credits.

The replacement: **cmux surfaces** — interactive Claude Code TUI sessions running in cmux panes, controlled programmatically via `cmux send`, `cmux read-screen`, and `cmux send-key`. Interactive TUI sessions remain on Pro billing.

## Proven Architecture (June 4, 2026)

```mermaid
flowchart LR
    Django -->|COMMAND.md| cmux-send
    cmux-send -->|cmux send --surface S "prompt\\n"| Agent[TUI Agent in cmux Pane]
    Agent -->|stdout output| cmux-read[cmux read-screen --surface S]
    cmux-read -->|poll until delimiter| Capture[Output captured]
    Capture -->|ready for next task| cmux-send
```

### Proven Commands (Discord -> cmux, tested June 4, 2026)

```bash
# Launch agents in horizontal split
CMUX=/Applications/cmux.app/Contents/Resources/bin/cmux
WS="workspace:1"
$CMUX new-pane --workspace "$WS" --type terminal --direction down --focus false

# Start Claude Code in top surface
$CMUX send --surface surface:1 "cd /path/to/repo && claude\n"

# Start Codex in bottom surface
$CMUX send --surface surface:4 "cd /path/to/repo && codex\n"

# Send work to a specific surface
$CMUX send --surface surface:1 "<task prompt>\n"

# Read output (poll until delimiter appears)
$CMUX read-screen --surface surface:1 --lines 20

# Dismiss interactive menus
$CMUX send-key --surface surface:1 escape

# Interrupt if hung
$CMUX send-key --surface surface:1 ctrl+c
```

### Delimiter-Based Output Capture Pattern

Reliable output capture from a terminal surface requires a delimiter:

1. Send command with end marker: `$CMUX send --surface S "echo '===TASK_DONE===' && <actual_command>\n"`
2. Poll `read-screen` until `===TASK_DONE===` appears
3. Extract content between task start marker and delimiter
4. Surface is ready for next task

### Pool of Agent Surfaces

Maintain N warm cmux panes (e.g. 2 Claude, 1 Codex, 1 Hermes):

- **Dispatch**: find an idle surface, send the task prompt
- **Monitor**: poll `read-screen` for delimiter
- **Capture**: grab output, store in process artifacts
- **Cleanup**: `send-key ctrl+c` if hung, or leave warm for next task

### vs. `claude -p`

| Dimension | `claude -p` | cmux delegation |
|-----------|-------------|-----------------|
| Billing | API credits after June 15 | Pro sub stays |
| Cold start | ~2-3s per task | Zero - session is warm |
| Context persistence | None per task | Full dialogue history |
| Output capture | Clean stdout | Terminal screen text (needs parsing) |
| Parallelism | Multiple subprocesses | Multi-pane layout, cmux manages |
| Visual monitoring | None | Full cmux UI visibility |
| Cross-platform | Linux/macOS | macOS only |
| Failure recovery | Process exits, retry clean | May have stranded terminal state |

## Implementation Status

- **Proof-of-concept**: Proven June 4, 2026 — Django launched Claude Code + Codex in cmux panes, sent /model commands, read output, dismissed dialogs, all from Discord
- **Hermes script**: `cmux-delegate.py` — production script at `~/.hermes/skills/process/async-delegation/scripts/cmux-delegate.py`
  - Same env var interface as `async-delegate.py` (PROMPT, RUNTIME, WORKDIR, MODEL, etc.)
  - Modes: deploy (default), `--capture`, `--kill`, `--list`, `--help`
  - Surface auto-discovery via `cmux tree --json` + `surface-health`
  - Delimiter-based output capture via `read-screen` polling
  - Configurable timeout and poll interval
  - Replaces `tmux-delegate.py` — tmux sessions deprecated for cmux surfaces

## Related Skills

- `cmux-control` - how to use cmux CLI (send, read-screen, send-key, topology)
- `autonomous-ai-agents/async-delegation` - the delegation skill this pattern extends
- `process/async-delegation` - process-scoped copy with Postgres-backed delegation
