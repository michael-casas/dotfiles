---
name: scratchpad
description: Mandatory per-session SQLite scratchpad for Claude Code and Codex. Use it throughout substantive work to record constraints, decisions, verified facts, todos, open questions, artifacts, and key command results so they survive compaction. Use it immediately after any compaction or resume to hydrate — read the restored state with `scratch hydrate` before continuing. Also use to inspect, repair, or wire the scratchpad hooks.
---

# Scratchpad

Every Claude Code and Codex session has a private SQLite (WAL) scratchpad. Compaction discards the
conversation; the scratchpad is how durable working state survives it. Keeping it current is
mandatory, not optional.

The `SessionStart` hook injects the database path, the session ID, and the CLI path at the start of
every session. The CLI lives at `scripts/scratch` in this skill and resolves the session from the
environment; pass `--session <id>` when it cannot.

## Write as you go

```bash
scratch add decision "Use central storage; per-project dirs leaked into git" --subject storage
scratch add fact "Codex PreCompact payload includes turn_id" --source "hook log" --certainty verified
scratch add todo "Add Stop gate tests" --subject tests
scratch resolve 7              # done or no longer relevant
scratch supersede 3 "Retention is 14 days, not 30"
scratch list [--kind todo] [--json]
scratch status                 # db path, active count, latest compaction
```

Write when you learn a constraint, make a decision, verify a fact (cite its source), open or close
a todo, produce an artifact, or before a long operation that may trigger compaction. Mark certainty
honestly (`verified`, `reported`, `inferred`, `hypothesis`). Never write secrets or credentials;
common token shapes are redacted on write, but do not rely on that.

Kinds: `constraint`, `fact`, `decision`, `todo`, `question`, `artifact`, `command_result`,
`checkpoint`, `note`.

## After compaction: hydrate

1. `PreCompact` (hook) inserts a `compaction` row with `hydrated = 0`. It never blocks compaction.
2. `SessionStart(compact)` (hook) injects the newest active entries (bounded) and asks you to hydrate.
3. You run `scratch hydrate`: it prints the full active state and sets `hydrated = 1`. Read it and
   reconcile with the current files before continuing.
4. `Stop` (hook) blocks the end of your turn once per compaction if it is still unhydrated.

Claude Code has no `PostCompact` event, so `SessionStart(compact)` is the post-compaction point in
both harnesses. Codex additionally records `post_at` from `PostCompact`.

## Storage

- Databases: `${SCRATCHPAD_HOME:-${XDG_DATA_HOME:-~/.local/share}/agent-scratchpad}/session-<id>.db`.
  `session_meta` records the harness, cwd, and project.
- Retention: databases untouched for `SCRATCHPAD_RETENTION_DAYS` (default 30; `0` disables) are
  pruned at session start.
- Schema: `entry` (working state), `compaction` (lifecycle and hydration audit), `session_meta`.

## Hooks

`scripts/hook.py <session-start|pre-compact|post-compact|stop> --harness <claude|codex>` reads the
harness hook JSON on stdin. Every hook fails open: errors surface as a `systemMessage` and never
block compaction or stop the session. The only blocking output is the once-per-compaction Stop gate.

Registration snippets live in `hooks/claude.json` and `hooks/codex.json`; wire them into
`~/.claude/settings.json` and `~/.codex/hooks.json`. Keep one handler per event so hooks do not race
over the same database. After changing a Codex hook definition, review and trust it with `/hooks`.

Tests: `python3 -m unittest discover -s tests` from this skill directory.
