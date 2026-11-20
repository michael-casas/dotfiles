#!/usr/bin/env python3
"""Regression tests for the session scratchpad hooks and CLI."""

from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
HOOK = SCRIPTS / "hook.py"
CLI = SCRIPTS / "scratch"
SESSION = "019f5c8d-41f7-7660-9118-de51a6ed019e"


class ScratchpadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.home = Path(self.tempdir.name) / "store"
        self.env_file = Path(self.tempdir.name) / "claude.env"
        self.env = {k: v for k, v in os.environ.items()
                    if k not in ("SCRATCHPAD_SESSION_ID", "CODEX_THREAD_ID", "CODEX_SESSION_ID",
                                 "CLAUDE_CODE_SESSION_ID", "CLAUDE_SESSION_ID", "CLAUDE_ENV_FILE")}
        self.env["SCRATCHPAD_HOME"] = str(self.home)
        self.db = self.home / f"session-{SESSION}.db"

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def hook(self, event: str, payload: dict, harness: str = "claude", **env: str) -> dict | None:
        result = subprocess.run(
            ["python3", str(HOOK), event, "--harness", harness],
            input=json.dumps({"session_id": SESSION, "cwd": self.tempdir.name, **payload}),
            text=True, capture_output=True, check=True, env={**self.env, **env},
        )
        self.assertEqual(result.stderr, "")
        return json.loads(result.stdout) if result.stdout.strip() else None

    def cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["python3", str(CLI), "--session", SESSION, *args], text=True,
                              capture_output=True, env=self.env)

    def rows(self, sql: str) -> list[tuple]:
        conn = sqlite3.connect(self.db)
        try:
            return conn.execute(sql).fetchall()
        finally:
            conn.close()

    def test_startup_injects_mandate_and_exports_session_for_claude(self) -> None:
        out = self.hook("session-start", {"hook_event_name": "SessionStart", "source": "startup"},
                        CLAUDE_ENV_FILE=str(self.env_file))
        text = out["hookSpecificOutput"]["additionalContext"]
        self.assertIn(str(self.db), text)
        self.assertIn("scratch add", text)
        self.assertIn(f"export SCRATCHPAD_SESSION_ID={SESSION}", self.env_file.read_text())
        self.assertEqual(self.rows("SELECT harness FROM session_meta"), [("claude",)])

    def test_cli_add_list_resolve_supersede_and_redaction(self) -> None:
        self.assertEqual(self.cli("add", "decision", "use", "central", "store", "--subject", "storage").stdout.strip(), "#1")
        self.cli("add", "fact", "api_key=abc123secretvalue in env")
        self.cli("add", "todo", "write tests")
        self.assertIn("#3 resolved", self.cli("resolve", "3").stdout)
        self.assertIn("superseded by #4", self.cli("supersede", "1", "use", "XDG", "store").stdout)
        listing = self.cli("list").stdout
        self.assertIn("decision/storage: use XDG store", listing)
        self.assertNotIn("abc123secretvalue", listing)
        self.assertNotIn("write tests", listing)
        self.assertEqual(self.rows("SELECT content FROM entry WHERE id = 2"), [("api_key=[REDACTED] in env",)])

    def test_cli_rejects_unknown_session_and_bad_ids(self) -> None:
        result = subprocess.run(["python3", str(CLI), "list"], text=True, capture_output=True, env=self.env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no session detected", result.stderr)
        self.assertEqual(self.cli("resolve", "99").returncode, 1)

    def test_claude_compaction_flow_without_postcompact(self) -> None:
        self.cli("add", "constraint", "never force push")
        self.assertIsNone(self.hook("pre-compact", {"hook_event_name": "PreCompact", "trigger": "auto"}))
        self.assertEqual(self.rows("SELECT trigger, turn_id, active_entries, hydrated FROM compaction"),
                         [("auto", None, 1, 0)])
        out = self.hook("session-start", {"hook_event_name": "SessionStart", "source": "compact"})
        text = out["hookSpecificOutput"]["additionalContext"]
        self.assertIn("never force push", text)
        self.assertIn("hydrate", text)

        block = self.hook("stop", {"hook_event_name": "Stop", "stop_hook_active": False})
        self.assertEqual(block["decision"], "block")
        self.assertIsNone(self.hook("stop", {"hook_event_name": "Stop", "stop_hook_active": False}),
                          "the Stop gate blocks at most once per compaction")

        hydrate = self.cli("hydrate").stdout
        self.assertIn("never force push", hydrate)
        self.assertIn("acknowledged 1", hydrate)
        self.assertEqual(self.rows("SELECT hydrated, restored_at IS NOT NULL FROM compaction"), [(1, 1)])

    def test_codex_flow_records_turn_and_postcompact(self) -> None:
        self.hook("pre-compact", {"hook_event_name": "PreCompact", "trigger": "manual", "turn_id": "t-1"}, harness="codex")
        self.hook("post-compact", {"hook_event_name": "PostCompact", "trigger": "manual", "turn_id": "t-1"}, harness="codex")
        self.assertEqual(self.rows("SELECT trigger, turn_id, post_at IS NOT NULL FROM compaction"), [("manual", "t-1", 1)])
        self.assertIn("acknowledged 1", self.cli("hydrate").stdout)
        self.assertIsNone(self.hook("stop", {"hook_event_name": "Stop"}, harness="codex"))

    def test_stop_respects_stop_hook_active_and_missing_db(self) -> None:
        self.assertIsNone(self.hook("stop", {"hook_event_name": "Stop"}))
        self.assertFalse(self.db.exists(), "Stop must not create a database")
        self.hook("pre-compact", {"hook_event_name": "PreCompact", "trigger": "auto"})
        self.assertIsNone(self.hook("stop", {"hook_event_name": "Stop", "stop_hook_active": True}))

    def test_hooks_fail_open(self) -> None:
        out = self.hook("pre-compact", {"hook_event_name": "PreCompact", "session_id": "../escape"})
        self.assertNotIn("continue", out)
        self.assertNotIn("decision", out)
        self.assertIn("non-blocking", out["systemMessage"])
        out = self.hook("session-start", {"hook_event_name": "PreCompact", "source": "startup"})
        self.assertIn("non-blocking", out["systemMessage"])

    def test_resume_restores_entries(self) -> None:
        self.cli("add", "decision", "keep codex hooks untracked")
        out = self.hook("session-start", {"hook_event_name": "SessionStart", "source": "resume"}, harness="codex")
        self.assertIn("keep codex hooks untracked", out["hookSpecificOutput"]["additionalContext"])

    def test_session_start_prunes_stale_databases(self) -> None:
        self.home.mkdir(parents=True)
        stale = self.home / "session-old.db"
        fresh = self.home / "session-new.db"
        for path in (stale, Path(f"{stale}-wal"), fresh):
            path.write_text("")
        old = time.time() - 40 * 86400
        os.utime(stale, (old, old))
        self.hook("session-start", {"hook_event_name": "SessionStart", "source": "startup"})
        self.assertFalse(stale.exists())
        self.assertFalse(Path(f"{stale}-wal").exists())
        self.assertTrue(fresh.exists())
        self.assertTrue(self.db.exists())

    def mode(self, path: Path) -> int:
        return path.stat().st_mode & 0o777

    def assert_private_files(self) -> None:
        for path in (self.db, Path(f"{self.db}-wal"), Path(f"{self.db}-shm")):
            if path.exists():
                self.assertEqual(self.mode(path), 0o600, path.name)

    def test_new_store_is_owner_only_under_default_umask(self) -> None:
        previous = os.umask(0o022)
        try:
            self.hook("session-start", {"hook_event_name": "SessionStart", "source": "startup"})
            self.cli("add", "note", "private record")
        finally:
            os.umask(previous)
        self.assertEqual(self.mode(self.home), 0o700)
        self.assert_private_files()
        # SQLite removes WAL/SHM when the last connection closes; check them
        # while a connection holds them open.
        import sys
        sys.path.insert(0, str(SCRIPTS))
        try:
            import scratchpad_store
        finally:
            sys.path.remove(str(SCRIPTS))
        previous = os.umask(0o022)
        try:
            conn = scratchpad_store.connect(self.db)
            conn.execute("INSERT INTO entry (kind, content) VALUES ('note', 'while open')")
            conn.commit()
            self.assertTrue(Path(f"{self.db}-wal").exists())
            self.assertTrue(Path(f"{self.db}-shm").exists())
            self.assert_private_files()
            conn.close()
        finally:
            os.umask(previous)

    def test_existing_dedicated_store_is_tightened(self) -> None:
        store = Path(self.tempdir.name) / "agent-scratchpad"
        store.mkdir(mode=0o755)
        os.chmod(store, 0o755)
        self.home, self.env["SCRATCHPAD_HOME"] = store, str(store)
        self.db = store / f"session-{SESSION}.db"
        previous = os.umask(0o022)
        try:
            self.cli("add", "note", "first")
            for path in (self.db, Path(f"{self.db}-wal"), Path(f"{self.db}-shm")):
                if path.exists():
                    os.chmod(path, 0o644)
            os.chmod(store, 0o755)
            self.cli("add", "note", "second")
        finally:
            os.umask(previous)
        self.assertEqual(self.mode(store), 0o700)
        self.assert_private_files()

    def test_existing_custom_directory_keeps_its_mode(self) -> None:
        self.home.mkdir(mode=0o755)
        os.chmod(self.home, 0o755)
        unrelated = self.home / "notes.txt"
        unrelated.write_text("not ours")
        os.chmod(unrelated, 0o644)
        previous = os.umask(0o022)
        try:
            self.cli("add", "note", "private record")
        finally:
            os.umask(previous)
        self.assertEqual(self.mode(self.home), 0o755, "an existing, non-dedicated directory is not ours to change")
        self.assertEqual(self.mode(unrelated), 0o644)
        self.assert_private_files()


if __name__ == "__main__":
    unittest.main()
