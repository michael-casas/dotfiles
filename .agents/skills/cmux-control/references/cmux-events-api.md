# cmux Events Streaming API

Reference: discovered live June 4, 2026 against cmux v0.64.13.

## Connection Model

- **Persistent TCP/Unix connection** — events push as they occur; no polling.
- **Heartbeat** — `heartbeat_interval_seconds` (default 15s) in the ack frame keeps the connection alive.
- **Cursor-file** — updated monotonically as events are received. On reconnect (even after full process restart), stream resumes exactly where it left off.
- **Auto-reconnect** — `--reconnect` reconnects forever.

## Command

```bash
cmux events [options]

Options:
  --after <seq>          Replay retained events after this sequence
  --cursor-file <path>   Read starting seq from file, update after each event
  --name <event>         Filter by event name, repeatable
  --category <name>      Filter by category, repeatable
  --reconnect            Reconnect forever, resume from last received seq
  --limit <n>            Exit after n event frames
  --no-ack               Do not print the subscription ack frame
  --no-heartbeat         Do not print heartbeat frames
```

## Ack Frame (first event)

```json
{
  "type": "ack",
  "boot_id": "UUID",
  "protocol": "cmux-events",
  "subscription_id": "UUID",
  "heartbeat_interval_seconds": 15,
  "resume": {
    "oldest_seq": 1,
    "latest_seq": 179,
    "next_seq": 180,
    "gap": false
  }
}
```

## Event Frame

```json
{
  "type": "event",
  "seq": 175,
  "name": "surface.closed",
  "category": "surface",
  "occurred_at": "2026-06-04T15:46:33.430Z",
  "workspace_id": "UUID",
  "surface_id": "UUID",
  "pane_id": "UUID",
  "payload": {
    "kind": "terminal",
    "origin": "tab_close",
    "surface_id": "UUID"
  },
  "source": "workspace.lifecycle"
}
```

## Key Design Points

- `oldest_seq` starts at 1 — events are retained durably.
- `gap: false` means no events were missed between resume points.
- The `--cursor-file` approach is preferred over `--after` for durable subscribers.
- Heartbeat frames are JSON with `type: "heartbeat"`. Use `--no-heartbeat` to suppress.
