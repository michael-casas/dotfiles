#!/usr/bin/env python3
"""Opt interactive project paths into Claude's built-in computer-use MCP.

SessionStart is too late to guarantee tools in a new path's first session.
The sidecar lock serializes our hooks, not Claude's own configuration writers.
"""
import fcntl
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


def enable(all_projects=False):
    cwd = None
    if not all_projects:
        cwd = json.load(sys.stdin).get('cwd')
        if not isinstance(cwd, str) or not os.path.isabs(cwd):
            return
    config = Path.home() / '.claude.json'
    with open(config.with_name('.claude.json.cu-enable.lock'), 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        original = config.read_bytes()
        data = json.loads(original)
        projects = data.setdefault('projects', {})
        targets = list(projects) if all_projects else [cwd]
        changed = False
        for target in targets:
            project = projects.setdefault(target, {})
            enabled = project.get('enabledMcpServers', [])
            if not isinstance(enabled, list):
                raise ValueError('Invalid enabledMcpServers')
            if 'computer-use' not in enabled:
                project['enabledMcpServers'] = [*enabled, 'computer-use']
                changed = True
        if not changed:
            return
        serialized = json.dumps(data, indent=2, ensure_ascii=False) + '\n'
        assert json.loads(serialized) == data
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=config.parent,
                                             prefix='.claude.json.cu-', delete=False) as out:
                temporary = out.name
                os.fchmod(out.fileno(), stat.S_IMODE(config.stat().st_mode))
                out.write(serialized)
                out.flush()
                os.fsync(out.fileno())
            # Refuse a detected concurrent Claude write rather than replacing it.
            if config.read_bytes() != original:
                raise RuntimeError('Concurrent config write')
            os.replace(temporary, config)
            temporary = None
            current = json.loads(config.read_bytes())
            if any('computer-use' not in current.get('projects', {}).get(p, {}).get(
                    'enabledMcpServers', []) for p in targets):
                raise RuntimeError('Config overwritten after enable')
        finally:
            if temporary is not None:
                os.unlink(temporary)


if __name__ == '__main__':
    try:
        enable(all_projects=sys.argv[1:] == ['--all'])
    except (OSError, ValueError, TypeError, AttributeError, RuntimeError):
        # Never expose config contents or block a Claude session on hook failure.
        print('computer-use opt-in not saved; retry next session.', file=sys.stderr)
