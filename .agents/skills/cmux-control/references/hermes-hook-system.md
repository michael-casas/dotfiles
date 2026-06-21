# Hermes Gateway Hook System

## Discovery (June 4, 2026)

The Hermes gateway has a built-in event hook system at `~/.hermes/hooks/<name>/` that fires at lifecycle points through the agent and gateway. It's distinct from the plugin system and the MemoryProvider ABC.

## Structure

Each hook needs two files:

```
~/.hermes/hooks/<name>/
├── HOOK.yaml   # metadata + event subscription
└── handler.py  # handle(event_type, context) function
```

### HOOK.yaml

```yaml
name: my-hook
version: 1.0.0
description: "What this hook does."
author: Django
events:
  - agent:end
```

### handler.py

```python
import logging
from typing import Any, Dict, Optional

logger = logging.getLogger("hooks.my_hook")

async def handle(event_type: str, context: Optional[Dict[str, Any]] = None) -> None:
    """Called by the gateway hook registry on matching events.

    Errors are caught and logged — never block the pipeline.
    Runs in the gateway event loop context.
    """
    try:
        _run(event_type, context or {})
    except Exception:
        logger.exception("my-hook failed")


def _run(event_type: str, context: Dict[str, Any]) -> None:
    """Synchronous core — runs work in a daemon thread if needed."""
    pass
```

## Available Events

| Event | When Fires | Use Case |
|-------|-----------|----------|
| `gateway:startup` | Gateway process starts | One-time init |
| `session:start` | New session created | Welcome context |
| `session:end` | Session ends (/new, /reset) | Final flush |
| `session:reset` | Session reset completed | State cleanup |
| `agent:start` | Agent begins processing a message | Pre-turn logic |
| `agent:step` | Each tool-calling iteration | Progress tracking |
| `agent:end` | Agent finishes processing | Post-turn completion check |
| `command:*` | Any slash command (wildcard) | Policy/rewrite hooks |

## Key Properties

- **Errors never block** — exceptions are logged and swallowed
- **Sync or async** — the registry handles both via `asyncio.iscoroutine()`
- **Wildcard matching** — `command:*` matches `command:reset`, `command:new`, etc.
- **`emit_collect()`** variant returns handler return values for decision-style hooks
- **No context injection** — hooks are fire-and-forget

## Hook Registry

The `HookRegistry` class in `gateway/hooks.py`:
- Discovers hooks from `~/.hermes/hooks/` at startup
- Loads handler.py modules dynamically (registers in sys.modules before exec)
- Registers handlers by event type
- Built-in hooks directory at `gateway/builtin_hooks/` (currently empty)

## vs. MemoryProvider.prefetch()

| Aspect | Gateway Hooks | MemoryProvider.prefetch() |
|--------|--------------|--------------------------|
| Fires on | Gateway lifecycle events | Every turn, before LLM call |
| Returns | Nothing (fire-and-forget) | String → system prompt |
| Block pipeline? | No (errors logged) | No (errors return empty) |
| Use for | Side effects, logging, completion detection | Context injection, memory recall |

## Reference Implementation

See `~/.hermes/hooks/cmux-events/` for a production hook that:
- Fires on `agent:end`
- Scans cmux surfaces for completion markers (`===CMUX_TASK_DONE===`)
- Queries Postgres `process.execution` for recently-finished delegates
- Writes a `pending.md` file that the MemoryProvider reads on the next turn
