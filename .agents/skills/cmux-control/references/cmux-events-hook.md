# cmux-events Hook Pattern — Post-Turn Reactivity

Created June 4, 2026. Lives at `~/.hermes/hooks/cmux-events/`.

## Architecture

```
Agent turn completes (agent:end event fires)
  →
cmux-events hook handler.py:
  ├─ cmux read-screen --scrollback on tracked surfaces
  │    → detects ===CMUX_TASK_DONE=== delimiter
  ├─ Postgres query on process.execution
  │    → finds recently completed delegates
  └─ Writes ~/.hermes/cmux-events/pending.md
      →
Next turn: MemoryProvider.prefetch() reads pending.md
  → injects findings into Django's context
  → Django sees completions without polling
```

## Files

| File | Purpose |
|------|---------|
| `HOOK.yaml` | Declares `agent:end` event subscription |
| `handler.py` | Python hook — scans cmux surfaces + Postgres, writes context file |

## Requirements

- cmux running with socket mode = automation
- Postgres with `process.execution` and `memory.entry` tables
- MemoryProvider plugin with `prefetch()` that reads `~/.hermes/cmux-events/pending.md`

## Event Lifecycle

The hook fires on `agent:end` — after each assistant turn completes. It does NOT block the pipeline (errors are caught and logged). State is tracked via `~/.hermes/cmux-events/state.json` with deduplication keys (`cmux:<surface_ref>:<timestamp>`, `pg:<execution_id>`). Previously reported completions are skipped until the state file is cleared.

## Key Methods in handler.py

| Method | What It Does |
|--------|-------------|
| `_surfaces_with_health()` | Runs `cmux tree --json` + `cmux surface-health` per surface |
| `_detect_surface_completions()` | Scans `cmux read-screen --scrollback` for `===CMUX_TASK_DONE===` |
| `_fetch_recent_completions()` | Queries `process.execution` for recently finished delegates |
| `_render_context()` | Writes structured markdown to `pending.md` |
