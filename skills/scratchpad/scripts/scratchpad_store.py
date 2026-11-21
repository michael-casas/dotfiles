#!/usr/bin/env python3
"""Canonical SQLite store for per-session agent scratchpads (Claude Code, Codex)."""

from __future__ import annotations

import datetime as dt
import os
import re
import sqlite3
import stat
import sys
import time
from pathlib import Path


SCHEMA_VERSION = 3
SESSION_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$")
HARNESSES = {"claude", "codex"}
KINDS = ("constraint", "fact", "decision", "todo", "question", "artifact", "command_result", "checkpoint", "note")
CERTAINTIES = ("verified", "reported", "inferred", "hypothesis")
SESSION_ENV = ("SCRATCHPAD_SESSION_ID", "CODEX_THREAD_ID", "CODEX_SESSION_ID", "CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID")
DEFAULT_RETENTION_DAYS = 30
SECRET_PATTERNS = (
    (re.compile(r"(?i)\b(api[_ -]?key|token|password|passwd|secret|authorization)\b(\s*[:=]\s*)(\"[^\"]*\"|'[^']*'|\S+)"), r"\1\2[REDACTED]"),
    (re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{12,}"), "Bearer [REDACTED]"),
    (re.compile(r"\b(sk|pk|rk)-[A-Za-z0-9_-]{12,}\b"), "[REDACTED_KEY]"),
    (re.compile(r"\b(ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{20,}\b"), "[REDACTED_KEY]"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[REDACTED_KEY]"),
    (re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"), "[REDACTED_KEY]"),
)


class ScratchpadError(RuntimeError):
    """Raised when the scratchpad cannot satisfy its contract."""


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def redact(value: str) -> str:
    for pattern, replacement in SECRET_PATTERNS:
        value = pattern.sub(replacement, value)
    return value


def normalize_session_id(value: object) -> str:
    session_id = str(value or "").strip()
    if not SESSION_ID_PATTERN.fullmatch(session_id):
        raise ScratchpadError("missing or invalid session_id")
    return session_id


def session_id_from_env() -> str | None:
    for name in SESSION_ENV:
        if os.environ.get(name):
            return os.environ[name]
    return None


def store_root() -> Path:
    override = os.environ.get("SCRATCHPAD_HOME")
    if override:
        return Path(override).expanduser()
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "agent-scratchpad"


def db_path_for(session_id: str) -> Path:
    return store_root() / f"session-{normalize_session_id(session_id)}.db"


def project_name(cwd: str) -> str:
    """Git toplevel basename when available, else the cwd basename."""
    path = Path(cwd or ".").expanduser().resolve()
    for candidate in (path, *path.parents):
        if (candidate / ".git").exists():
            return candidate.name
    return path.name


STORE_DIR_NAME = "agent-scratchpad"
SIDECAR_SUFFIXES = ("", "-wal", "-shm", "-journal")


def secure_store(root: Path) -> None:
    """Keep the store owner-only. A directory this code creates, or the
    dedicated `agent-scratchpad` store, becomes 0700. An existing directory
    with any other name (a custom SCRATCHPAD_HOME) keeps its mode; the session
    files inside it are still made private."""
    created = not root.exists()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if (created or root.name == STORE_DIR_NAME) and not root.is_symlink():
        os.chmod(root, 0o700)


def secure_files(db_path: Path, *, best_effort: bool = False) -> None:
    """Make the session database and its SQLite sidecars 0600.

    A file can vanish between the check and the chmod: SQLite deletes a
    session's WAL and SHM when its last connection closes. That path is
    skipped. With best_effort (another session's files), any other OS error is
    reported on stderr and skipped too; for the current session it is raised.
    """
    for suffix in SIDECAR_SUFFIXES:
        path = Path(f"{db_path}{suffix}")
        try:
            metadata = path.lstat()
            if stat.S_ISREG(metadata.st_mode) and metadata.st_uid == os.getuid():
                os.chmod(path, 0o600)
        except FileNotFoundError:
            continue
        except OSError as exc:
            if not best_effort:
                raise
            print(f"scratchpad: could not make {path} private: {exc}", file=sys.stderr)


SESSION_DB_NAME = re.compile(r"^session-(.+)\.db$")


def secure_existing_sessions(root: Path) -> None:
    """Migrate files an earlier version created with the umask's mode: every
    owner-owned regular `session-<id>.db` in the store, and its sidecars, becomes
    0600, whether or not this run opens it. Symlinks, names that are not session
    ids, and unrelated files are left alone. Other sessions are migrated
    best-effort: nothing here stops the current session from opening."""
    try:
        entries = list(root.iterdir())
    except OSError:
        return
    for path in entries:
        match = SESSION_DB_NAME.fullmatch(path.name)
        if not (match and SESSION_ID_PATTERN.fullmatch(match.group(1))):
            continue
        try:
            if not stat.S_ISREG(path.lstat().st_mode):
                continue
        except FileNotFoundError:
            continue
        except OSError as exc:
            print(f"scratchpad: could not inspect {path}: {exc}", file=sys.stderr)
            continue
        secure_files(path, best_effort=True)


def connect(db_path: Path, *, must_exist: bool = False) -> sqlite3.Connection:
    if must_exist and not db_path.is_file():
        raise ScratchpadError(f"session scratchpad does not exist: {db_path}")
    secure_store(db_path.parent)
    secure_existing_sessions(db_path.parent)
    if not db_path.exists():
        # Create the file 0600 first; SQLite gives its WAL and SHM files the
        # database file's mode.
        os.close(os.open(db_path, os.O_CREAT | os.O_WRONLY, 0o600))
    secure_files(db_path)
    conn = sqlite3.connect(db_path, timeout=5)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA busy_timeout = 5000")
    conn.execute("PRAGMA synchronous = FULL")
    conn.execute("PRAGMA journal_mode = WAL")
    secure_files(db_path)
    return conn


def ensure_schema(conn: sqlite3.Connection, session_id: str, *, harness: str | None = None, cwd: str | None = None) -> None:
    kinds = ", ".join(f"'{k}'" for k in KINDS)
    certainties = ", ".join(f"'{c}'" for c in CERTAINTIES)
    conn.executescript(
        f"""
        CREATE TABLE IF NOT EXISTS session_meta (
          session_id TEXT PRIMARY KEY,
          schema_version INTEGER NOT NULL,
          harness TEXT,
          cwd TEXT,
          project TEXT,
          created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        );
        CREATE TABLE IF NOT EXISTS entry (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL CHECK (kind IN ({kinds})),
          subject TEXT,
          content TEXT NOT NULL CHECK (length(trim(content)) > 0),
          source TEXT,
          certainty TEXT NOT NULL DEFAULT 'reported' CHECK (certainty IN ({certainties})),
          status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'superseded', 'resolved')),
          supersedes_id INTEGER REFERENCES entry(id) ON DELETE SET NULL,
          created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
          updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        );
        CREATE TABLE IF NOT EXISTS compaction (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trigger TEXT NOT NULL CHECK (trigger IN ('manual', 'auto')),
          turn_id TEXT,
          active_entries INTEGER NOT NULL DEFAULT 0,
          pre_at TEXT NOT NULL,
          post_at TEXT,
          restored_at TEXT,
          hydrated INTEGER NOT NULL DEFAULT 0 CHECK (hydrated IN (0, 1)),
          hydrated_at TEXT,
          nudged_at TEXT
        );
        CREATE INDEX IF NOT EXISTS entry_active_idx ON entry (status, updated_at DESC, id DESC);
        CREATE INDEX IF NOT EXISTS entry_subject_idx ON entry (subject, status, id);
        """
    )
    existing = [str(row[0]) for row in conn.execute("SELECT session_id FROM session_meta")]
    if existing and existing != [session_id]:
        raise ScratchpadError("scratchpad session_meta does not match the active session")
    if not existing:
        conn.execute(
            "INSERT INTO session_meta(session_id, schema_version, harness, cwd, project) VALUES (?, ?, ?, ?, ?)",
            (session_id, SCHEMA_VERSION, harness, cwd, project_name(cwd) if cwd else None),
        )
    conn.commit()


def open_session(session_id: str, *, harness: str | None = None, cwd: str | None = None, must_exist: bool = False) -> sqlite3.Connection:
    conn = connect(db_path_for(session_id), must_exist=must_exist)
    try:
        ensure_schema(conn, session_id, harness=harness, cwd=cwd)
    except Exception:
        conn.close()
        raise
    return conn


def assert_integrity(conn: sqlite3.Connection) -> None:
    result = conn.execute("PRAGMA quick_check").fetchone()
    if not result or str(result[0]).lower() != "ok":
        raise ScratchpadError("SQLite quick_check failed for the session scratchpad")


# --- entries -----------------------------------------------------------------

def add_entry(conn: sqlite3.Connection, *, kind: str, content: str, subject: str | None = None,
              source: str | None = None, certainty: str = "reported", supersedes_id: int | None = None) -> int:
    if kind not in KINDS:
        raise ScratchpadError(f"kind must be one of: {', '.join(KINDS)}")
    if certainty not in CERTAINTIES:
        raise ScratchpadError(f"certainty must be one of: {', '.join(CERTAINTIES)}")
    content = redact(content).strip()
    if not content:
        raise ScratchpadError("content must not be empty")
    cursor = conn.execute(
        "INSERT INTO entry(kind, subject, content, source, certainty, supersedes_id) VALUES (?, ?, ?, ?, ?, ?)",
        (kind, subject, content, redact(source) if source else None, certainty, supersedes_id),
    )
    conn.commit()
    return int(cursor.lastrowid)


def set_status(conn: sqlite3.Connection, entry_id: int, status: str) -> None:
    cursor = conn.execute(
        "UPDATE entry SET status = ?, updated_at = ? WHERE id = ? AND status = 'active'",
        (status, utc_now(), entry_id),
    )
    conn.commit()
    if cursor.rowcount != 1:
        raise ScratchpadError(f"no active entry with id {entry_id}")


def supersede(conn: sqlite3.Connection, entry_id: int, content: str, *, certainty: str | None = None,
              source: str | None = None) -> int:
    row = conn.execute("SELECT kind, subject, certainty FROM entry WHERE id = ? AND status = 'active'", (entry_id,)).fetchone()
    if not row:
        raise ScratchpadError(f"no active entry with id {entry_id}")
    set_status(conn, entry_id, "superseded")
    return add_entry(conn, kind=row["kind"], subject=row["subject"], content=content, source=source,
                     certainty=certainty or row["certainty"], supersedes_id=entry_id)


def active_entries(conn: sqlite3.Connection, *, kind: str | None = None, limit: int | None = None) -> list[sqlite3.Row]:
    sql = "SELECT id, kind, subject, content, certainty, source, updated_at FROM entry WHERE status = 'active'"
    params: list[object] = []
    if kind:
        sql += " AND kind = ?"
        params.append(kind)
    sql += " ORDER BY updated_at DESC, id DESC"
    if limit:
        sql += " LIMIT ?"
        params.append(limit)
    return conn.execute(sql, params).fetchall()


def format_entries(rows: list[sqlite3.Row], *, max_chars: int | None = None) -> str:
    lines = []
    for row in rows:
        label = f"{row['kind']}/{row['subject']}" if row["subject"] else str(row["kind"])
        lines.append(f"- #{row['id']} [{row['certainty']}] {label}: {redact(str(row['content'])).strip()}")
    text = "\n".join(lines) if lines else "- (no active entries)"
    if max_chars and len(text) > max_chars:
        text = text[:max_chars].rstrip() + "\n- … truncated; run `scratch list` for the rest"
    return text


# --- compaction lifecycle ------------------------------------------------------

def record_precompact(conn: sqlite3.Connection, *, trigger: str, turn_id: str | None = None) -> int:
    trigger = str(trigger or "").strip().lower()
    if trigger not in ("manual", "auto"):
        trigger = "auto"
    count = conn.execute("SELECT count(*) FROM entry WHERE status = 'active'").fetchone()[0]
    cursor = conn.execute(
        "INSERT INTO compaction(trigger, turn_id, active_entries, pre_at) VALUES (?, ?, ?, ?)",
        (trigger, turn_id or None, count, utc_now()),
    )
    conn.commit()
    assert_integrity(conn)
    conn.execute("PRAGMA wal_checkpoint(PASSIVE)")
    return int(cursor.lastrowid)


def latest_compaction(conn: sqlite3.Connection) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM compaction ORDER BY id DESC LIMIT 1").fetchone()


def _touch_latest(conn: sqlite3.Connection, column: str) -> sqlite3.Row | None:
    row = latest_compaction(conn)
    if row is None:
        return None
    conn.execute(f"UPDATE compaction SET {column} = ? WHERE id = ?", (utc_now(), row["id"]))
    conn.commit()
    return row


def record_postcompact(conn: sqlite3.Connection) -> sqlite3.Row | None:
    return _touch_latest(conn, "post_at")


def record_restored(conn: sqlite3.Connection) -> sqlite3.Row | None:
    return _touch_latest(conn, "restored_at")


def pending_hydration(conn: sqlite3.Connection) -> sqlite3.Row | None:
    row = latest_compaction(conn)
    return row if row is not None and not row["hydrated"] else None


def mark_hydrated(conn: sqlite3.Connection) -> int:
    cursor = conn.execute("UPDATE compaction SET hydrated = 1, hydrated_at = ? WHERE hydrated = 0", (utc_now(),))
    conn.commit()
    return cursor.rowcount


def claim_nudge(conn: sqlite3.Connection) -> sqlite3.Row | None:
    """Return the pending compaction if it has not been nudged yet, marking it nudged."""
    row = pending_hydration(conn)
    if row is None or row["nudged_at"]:
        return None
    conn.execute("UPDATE compaction SET nudged_at = ? WHERE id = ?", (utc_now(), row["id"]))
    conn.commit()
    return row


# --- retention ----------------------------------------------------------------

def prune(*, days: int | None = None, keep: Path | None = None) -> int:
    if days is None:
        try:
            days = int(os.environ.get("SCRATCHPAD_RETENTION_DAYS", DEFAULT_RETENTION_DAYS))
        except ValueError:
            days = DEFAULT_RETENTION_DAYS
    if days <= 0:
        return 0
    root = store_root()
    if not root.is_dir():
        return 0
    cutoff = time.time() - days * 86400
    removed = 0
    for db in root.glob("session-*.db"):
        if keep is not None and db == keep:
            continue
        try:
            if db.stat().st_mtime >= cutoff:
                continue
            for suffix in ("", "-wal", "-shm"):
                Path(f"{db}{suffix}").unlink(missing_ok=True)
            removed += 1
        except OSError:
            continue
    return removed
