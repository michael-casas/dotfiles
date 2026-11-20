"""Isolated regression tests; never read or write the real Claude config."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('enable-computer-use.py')


class EnableComputerUseTests(unittest.TestCase):
    def run_hook(self, config, payload=None, args=()):
        with tempfile.TemporaryDirectory() as home:
            path = Path(home) / '.claude.json'
            path.write_text(json.dumps(config))
            result = subprocess.run(
                ['python3', str(SCRIPT), *args],
                input=json.dumps(payload or {'cwd': '/new/project'}),
                text=True, capture_output=True, env={**os.environ, 'HOME': home},
                check=True,
            )
            self.assertEqual(result.stdout, '')
            return json.loads(path.read_text())

    def test_new_project_preserves_other_keys(self):
        before = {'other': {'unchanged': True}, 'projects': {'/old': {'trust': True}}}
        after = self.run_hook(before)
        self.assertEqual(after['other'], before['other'])
        self.assertEqual(after['projects']['/old'], before['projects']['/old'])
        self.assertEqual(after['projects']['/new/project'], {'enabledMcpServers': ['computer-use']})

    def test_existing_list_and_disabled_servers_preserved(self):
        project = {'enabledMcpServers': ['other'], 'disabledMcpServers': ['computer-use'], 'trust': True}
        after = self.run_hook({'projects': {'/new/project': project}})
        self.assertEqual(after['projects']['/new/project'], {**project, 'enabledMcpServers': ['other', 'computer-use']})

    def test_idempotent(self):
        before = {'projects': {'/new/project': {'enabledMcpServers': ['computer-use', 'other']}}}
        self.assertEqual(self.run_hook(before), before)

    def test_all_existing_projects(self):
        before = {'other': 42, 'projects': {'/a': {}, '/b': {'enabledMcpServers': ['computer-use']}}}
        after = self.run_hook(before, args=('--all',))
        self.assertEqual(after['other'], 42)
        self.assertEqual(set(after['projects']), {'/a', '/b'})
        self.assertTrue(all(p['enabledMcpServers'] == ['computer-use'] for p in after['projects'].values()))

    def test_noop_preserves_bytes_and_modification_time(self):
        with tempfile.TemporaryDirectory() as home:
            path = Path(home) / '.claude.json'
            original = '{"projects":{"/new/project":{"enabledMcpServers":["computer-use"]}}}'
            path.write_text(original)
            before = path.stat().st_mtime_ns
            subprocess.run(['python3', str(SCRIPT)], input=json.dumps({'cwd': '/new/project'}),
                           text=True, env={**os.environ, 'HOME': home}, check=True)
            self.assertEqual(path.read_text(), original)
            self.assertEqual(path.stat().st_mtime_ns, before)

    def test_malformed_config_fails_open_without_change(self):
        with tempfile.TemporaryDirectory() as home:
            path = Path(home) / '.claude.json'
            path.write_text('{invalid')
            result = subprocess.run(['python3', str(SCRIPT)], input=json.dumps({'cwd': '/new/project'}),
                                    text=True, capture_output=True,
                                    env={**os.environ, 'HOME': home}, check=True)
            self.assertEqual(path.read_text(), '{invalid')
            self.assertEqual(result.stdout, '')
            self.assertIn('opt-in not saved', result.stderr)

    def test_invalid_payload_fails_open_without_change(self):
        before = {'projects': {}}
        self.assertEqual(self.run_hook(before, payload={'cwd': 'relative'}), before)


if __name__ == '__main__':
    unittest.main()
