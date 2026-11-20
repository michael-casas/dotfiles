#!/usr/bin/env python3
"""Fail-open lifecycle hooks for the session scratchpad.

Usage: hook.py <session-start|pre-compact|post-compact|stop> --harness <claude|codex>

Reads the harness hook JSON on stdin. Never blocks compaction and never stops a
session on failure: errors surface as a systemMessage and the hook exits 0. The
only blocking output is the Stop gate, at most once per compaction.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
from pathlib import Path

from scratchpad_store import (
    HARNESSES,
    claim_nudge,
    db_path_for,
    format_entries,
    active_entries,
    normalize_session_id,
    open_session,
    pending_hydration,
    prune,
    record_postcompact,
    record_precompact,
    record_restored,
    session_id_from_env,
)


MAX_CONTEXT_CHARS = 6000
MAX_CONTEXT_ROWS = 40
EVENT_NAMES = {
    "session-start": "SessionStart",
    "pre-compact": "PreCompact",
    "post-compact": "PostCompact",
    "stop": "Stop",
}


def cli_path() -> str:
    path = os.environ.get("SCRATCHPAD_CLI") or str(Path(__file__).resolve().parent / "scratch")
    home = str(Path.home())
    return "~" + path[len(home):] if path.startswith(home + os.sep) else path


def mandate(session_id: str) -> str:
    cli = cli_path()
    return f"""Session scratchpad (mandatory): {db_path_for(session_id)}
Record durable working state as you go so it survives compaction. Write when you learn a constraint,
make a decision, verify a fact (with its source), open or finish a todo, or before any long operation:
  {cli} add <kind> "<content>" [--subject S] [--source S] [--certainty verified|reported|inferred|hypothesis]
  {cli} list | resolve <id> | supersede <id> "<content>" | hydrate
Kinds: constraint, fact, decision, todo, question, artifact, command_result, checkpoint, note.
If the session cannot be detected, pass --session {session_id}. Never write secrets or credentials."""


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False))


def context(event: str, text: str) -> None:
    emit({"continue": True, "hookSpecificOutput": {"hookEventName": event, "additionalContext": text}})


def export_session_env(harness: str, session_id: str) -> None:
    """Expose the session ID to later shell commands where the harness supports it."""
    env_file = os.environ.get("CLAUDE_ENV_FILE") if harness == "claude" else None
    if env_file:
        with open(env_file, "a", encoding="utf-8") as stream:
            stream.write(f"export SCRATCHPAD_SESSION_ID={shlex.quote(session_id)}\n")


def session_start(event: dict, harness: str, session_id: str, cwd: str) -> None:
    source = str(event.get("source") or "startup").strip().lower()
    conn = open_session(session_id, harness=harness, cwd=cwd)
    try:
        export_session_env(harness, session_id)
        prune(keep=db_path_for(session_id))
        parts = [mandate(session_id)]
        if source == "compact":
            record_restored(conn)
            rows = active_entries(conn, limit=MAX_CONTEXT_ROWS)
            parts.append(
                "You were just compacted. Restored scratchpad entries (bounded, newest first; verify against current files):\n"
                + format_entries(rows, max_chars=MAX_CONTEXT_CHARS)
            )
            if pending_hydration(conn) is not None:
                parts.append(f"Before continuing, run `{cli_path()} hydrate` to read the full state and acknowledge the restore.")
        elif source == "resume":
            rows = active_entries(conn, limit=MAX_CONTEXT_ROWS)
            if rows:
                parts.append("Resumed session. Active scratchpad entries:\n" + format_entries(rows, max_chars=MAX_CONTEXT_CHARS))
    finally:
        conn.close()
    context("SessionStart", "\n\n".join(parts))


def pre_compact(event: dict, harness: str, session_id: str, cwd: str) -> None:
    conn = open_session(session_id, harness=harness, cwd=cwd)
    try:
        record_precompact(conn, trigger=str(event.get("trigger") or "auto"), turn_id=event.get("turn_id"))
    finally:
        conn.close()


def post_compact(event: dict, harness: str, session_id: str, cwd: str) -> None:
    conn = open_session(session_id, harness=harness, cwd=cwd)
    try:
        record_postcompact(conn)
    finally:
        conn.close()


def stop(event: dict, harness: str, session_id: str, cwd: str) -> None:
    if event.get("stop_hook_active"):
        return
    path = db_path_for(session_id)
    if not path.is_file():
        return
    conn = open_session(session_id, harness=harness, cwd=cwd)
    try:
        row = claim_nudge(conn)
    finally:
        conn.close()
    if row is not None:
        emit({
            "decision": "block",
            "reason": f"Compaction #{row['id']} has not been hydrated. Run `{cli_path()} hydrate`, "
                      "review the restored state, then finish your turn.",
        })


HANDLERS = {"session-start": session_start, "pre-compact": pre_compact, "post-compact": post_compact, "stop": stop}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("event", choices=sorted(HANDLERS))
    parser.add_argument("--harness", choices=sorted(HARNESSES), required=True)
    args = parser.parse_args(argv)
    try:
        raw = sys.stdin.read()
        event = json.loads(raw) if raw.strip() else {}
        if not isinstance(event, dict):
            raise ValueError("hook input must be a JSON object")
        actual = event.get("hook_event_name")
        if actual and actual != EVENT_NAMES[args.event]:
            raise ValueError(f"expected {EVENT_NAMES[args.event]} hook input, received {actual}")
        session_id = normalize_session_id(event.get("session_id") or session_id_from_env())
        cwd = str(event.get("cwd") or os.getcwd())
        HANDLERS[args.event](event, args.harness, session_id, cwd)
    except Exception as exc:  # fail open: never block compaction or kill the session
        emit({"systemMessage": f"Scratchpad {args.event} hook failed (non-blocking): {exc}"})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
