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

    def legacy_store(self, store: Path, dir_mode: int) -> dict[str, Path]:
        """A store left by an earlier version: several sessions at 0644 with
        sidecars, plus things that are not ours to change."""
        store.mkdir(parents=True, exist_ok=True)
        os.chmod(store, dir_mode)
        files = {}
        for sid in ("legacy-one", "legacy-two", SESSION):
            db = store / f"session-{sid}.db"
            conn = sqlite3.connect(db)
            conn.execute("CREATE TABLE t (x)")
            conn.commit()
            conn.close()
            files[sid] = db
        for suffix in ("-wal", "-shm"):
            Path(f"{files['legacy-two']}{suffix}").write_bytes(b"")
        outside = Path(self.tempdir.name) / "outside.db"
        outside.write_bytes(b"")
        files["outside"] = outside
        files["link"] = store / "session-linked.db"
        files["link"].symlink_to(outside)
        files["unrelated"] = store / "notes.txt"
        files["unrelated"].write_text("not ours")
        files["odd"] = store / "session-bad name.db"
        files["odd"].write_bytes(b"")
        for path in store.iterdir():
            if not path.is_symlink():
                os.chmod(path, 0o644)
        os.chmod(outside, 0o644)
        return files

    def assert_legacy_migrated(self, store: Path, files: dict[str, Path], dir_mode: int) -> None:
        for sid in ("legacy-one", "legacy-two", SESSION):
            self.assertEqual(self.mode(files[sid]), 0o600, f"{sid} database")
        for suffix in ("-wal", "-shm"):
            self.assertEqual(self.mode(Path(f"{files['legacy-two']}{suffix}")), 0o600, f"unopened {suffix}")
        self.assertEqual(self.mode(files["unrelated"]), 0o644, "unrelated file")
        self.assertEqual(self.mode(files["odd"]), 0o644, "a name that is not a session id")
        self.assertTrue(files["link"].is_symlink())
        self.assertEqual(self.mode(files["outside"]), 0o644, "a symlink's target is not ours")
        self.assertEqual(self.mode(store), dir_mode)

    def test_upgrade_tightens_every_legacy_session_in_a_custom_store(self) -> None:
        files = self.legacy_store(self.home, 0o755)
        previous = os.umask(0o022)
        try:
            self.cli("add", "note", "opens only the current session")
        finally:
            os.umask(previous)
        self.assert_legacy_migrated(self.home, files, 0o755)

    def test_upgrade_tightens_every_legacy_session_in_the_default_store(self) -> None:
        data = Path(self.tempdir.name) / "data"
        store = data / "agent-scratchpad"
        files = self.legacy_store(store, 0o755)
        self.env.pop("SCRATCHPAD_HOME")
        self.env["XDG_DATA_HOME"] = str(data)
        previous = os.umask(0o022)
        try:
            self.hook("session-start", {"hook_event_name": "SessionStart", "source": "startup"})
        finally:
            os.umask(previous)
        self.assert_legacy_migrated(store, files, 0o700)

    # --- Another session's files can change or vanish while this one starts ---

    def store_module(self):
        import importlib
        import sys
        sys.path.insert(0, str(SCRIPTS))
        try:
            return importlib.import_module("scratchpad_store")
        finally:
            sys.path.remove(str(SCRIPTS))

    def other_session_with_live_wal(self) -> tuple[sqlite3.Connection, Path]:
        """A real second session whose open connection holds a WAL file."""
        self.home.mkdir(parents=True, exist_ok=True)
        other = self.home / "session-other.db"
        conn = sqlite3.connect(other)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("CREATE TABLE fixture (n INTEGER)")
        conn.execute("INSERT INTO fixture VALUES (1)")
        conn.commit()
        self.assertTrue(Path(f"{other}-wal").is_file())
        return conn, other

    def test_other_session_closing_mid_scan_does_not_block_startup(self) -> None:
        from unittest import mock
        store = self.store_module()
        conn, other = self.other_session_with_live_wal()
        wal = Path(f"{other}-wal")
        real_chmod = os.chmod
        injected = []

        def chmod_after_close(path, mode, *args, **kwargs):
            if Path(path) == wal and wal.is_file():
                conn.close()  # SQLite removes the WAL on the last close
                injected.append(path)
            return real_chmod(path, mode, *args, **kwargs)

        with mock.patch.dict(os.environ, {"SCRATCHPAD_HOME": str(self.home)}), \
                mock.patch.object(store.os, "chmod", chmod_after_close):
            session = store.open_session(SESSION, harness="claude", cwd=self.tempdir.name)
            session.close()
        self.assertTrue(injected, "the close was injected before chmod of the listed WAL")
        self.assertTrue(self.db.is_file(), "the starting session's database exists")
        self.assertEqual(self.rows("SELECT session_id FROM session_meta"), [(SESSION,)])
        self.assertEqual(self.mode(other), 0o600, "files still present are still migrated")

    def test_installed_session_start_hook_survives_a_concurrent_close(self) -> None:
        inject = Path(self.tempdir.name) / "inject"
        inject.mkdir()
        (inject / "sitecustomize.py").write_text(
            "import os, sqlite3, sys\n"
            "from pathlib import Path\n"
            "root = os.environ.get('SCRATCHPAD_RACE_ROOT')\n"
            "if root and 'session-start' in sys.argv:\n"
            "    root = Path(root); root.mkdir(parents=True, exist_ok=True)\n"
            "    db = root / 'session-other.db'; wal = Path(f'{db}-wal')\n"
            "    conn = sqlite3.connect(db); conn.execute('PRAGMA journal_mode=WAL')\n"
            "    conn.execute('CREATE TABLE IF NOT EXISTS fixture (n INTEGER)')\n"
            "    conn.execute('INSERT INTO fixture VALUES (1)'); conn.commit()\n"
            "    real_chmod = os.chmod\n"
            "    def chmod_after_close(path, mode, *a, **k):\n"
            "        if Path(path) == wal and wal.is_file():\n"
            "            conn.close(); (root / 'injected').write_text('closed')\n"
            "        return real_chmod(path, mode, *a, **k)\n"
            "    os.chmod = chmod_after_close\n")
        out = self.hook("session-start", {"hook_event_name": "SessionStart", "source": "startup"},
                        CLAUDE_ENV_FILE=str(self.env_file), PYTHONPATH=str(inject),
                        SCRATCHPAD_RACE_ROOT=str(self.home))
        self.assertTrue((self.home / "injected").is_file(), "the close was injected")
        self.assertNotIn("systemMessage", out)
        self.assertIn(str(self.db), out["hookSpecificOutput"]["additionalContext"])
        self.assertTrue(self.db.is_file())
        self.assertIn(f"export SCRATCHPAD_SESSION_ID={SESSION}", self.env_file.read_text())

    def test_other_session_permission_errors_are_best_effort(self) -> None:
        import contextlib
        import io
        from unittest import mock
        store = self.store_module()
        conn, other = self.other_session_with_live_wal()
        conn.close()
        real_chmod = os.chmod

        def deny_other(path, mode, *args, **kwargs):
            if Path(path) == other:
                raise PermissionError(1, "Operation not permitted", str(path))
            return real_chmod(path, mode, *args, **kwargs)

        err = io.StringIO()
        with mock.patch.dict(os.environ, {"SCRATCHPAD_HOME": str(self.home)}), \
                mock.patch.object(store.os, "chmod", deny_other), contextlib.redirect_stderr(err):
            store.open_session(SESSION, harness="claude").close()
        self.assertTrue(self.db.is_file())
        self.assertIn("session-other.db", err.getvalue())

    def deny_metadata(self, path: Path) -> None:
        """Apply a macOS ACL that denies the owner `readattr` on path, so lstat
        raises EACCES while the file itself stays in place."""
        import shutil
        import sys
        if sys.platform != "darwin" or not shutil.which("chmod"):
            self.skipTest("needs macOS ACLs (chmod +a)")
        user = subprocess.check_output(["id", "-un"], text=True).strip()
        entry = f"{user} deny readattr"
        if subprocess.run(["chmod", "+a", entry, str(path)], capture_output=True).returncode != 0:
            self.skipTest("this filesystem does not accept ACLs")
        self.addCleanup(subprocess.run, ["chmod", "-a", entry, str(path)], capture_output=True)
        try:
            os.lstat(path)
        except PermissionError:
            return
        self.skipTest("the ACL did not deny lstat here")

    def test_unreadable_legacy_metadata_is_diagnosed_not_fatal(self) -> None:
        """A legacy session file whose metadata cannot be read must not stop
        the starting session; the migration reports it and moves on. Runs the
        SessionStart hook with the interpreter running this suite."""
        import sys
        self.home.mkdir(mode=0o755)
        legacy = self.home / "session-other.db"
        conn = sqlite3.connect(legacy)
        conn.execute("CREATE TABLE fixture (value TEXT)")
        conn.commit()
        conn.close()
        os.chmod(legacy, 0o644)
        self.deny_metadata(legacy)
        result = subprocess.run(
            [sys.executable, str(HOOK), "session-start", "--harness", "claude"],
            input=json.dumps({"session_id": SESSION, "cwd": self.tempdir.name,
                              "hook_event_name": "SessionStart", "source": "startup"}),
            text=True, capture_output=True,
            env={**self.env, "CLAUDE_ENV_FILE": str(self.env_file), "PYTHONDONTWRITEBYTECODE": "1"})
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        self.assertNotIn("systemMessage", out)
        self.assertIn(str(self.db), out["hookSpecificOutput"]["additionalContext"])
        self.assertTrue(self.db.is_file(), "the starting session's database exists")
        self.assertIn(f"export SCRATCHPAD_SESSION_ID={SESSION}", self.env_file.read_text())
        self.assertIn("session-other.db", result.stderr, "the skipped legacy file is reported")

    def test_current_session_permission_error_still_fails(self) -> None:
        from unittest import mock
        store = self.store_module()
        real_chmod = os.chmod

        def deny_current(path, mode, *args, **kwargs):
            if Path(path) == self.db:
                raise PermissionError(1, "Operation not permitted", str(path))
            return real_chmod(path, mode, *args, **kwargs)

        with mock.patch.dict(os.environ, {"SCRATCHPAD_HOME": str(self.home)}), \
                mock.patch.object(store.os, "chmod", deny_current):
            with self.assertRaises(PermissionError):
                store.open_session(SESSION, harness="claude")


if __name__ == "__main__":
    unittest.main()
