import importlib.machinery
import importlib.util
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader('cli', str(ROOT / 'remote/bin/envi-remote'))
spec = importlib.util.spec_from_loader('cli', loader)
cli = importlib.util.module_from_spec(spec)
loader.exec_module(cli)


class ProbeTest(unittest.TestCase):
    def test_malformed_identifiers(self):
        for value in ['-option', 'white space', 'x;touch', 'x\n', 'x/..', '', 'a' * 65]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                cli.identifier(value)

    def probe(self, tools, locale=None, env=None, terminfo=None):
        with tempfile.TemporaryDirectory() as name:
            p = Path(name)
            import shutil
            for tool in ['head', 'tr', 'uname']:
                (p / tool).symlink_to(shutil.which(tool))
            tools = {'infocmp': 'exit 0', **tools}
            # None means the tool is absent, not a failing infocmp shim.
            tools = {tool: text for tool, text in tools.items() if text is not None}
            for tool, text in tools.items():
                path = p / tool
                path.write_text('#!/bin/bash\n' + text + '\n')
                path.chmod(0o755)
            script = (ROOT / 'remote/bootstrap.sh').read_text()
            if terminfo is not None:
                # Isolate system terminfo searches from the developer's installed DB.
                # Keep their paths/order in the script, rebased inside a fixture root.
                script = re.sub(r'/etc/terminfo|/usr/share/terminfo|/usr/lib/terminfo|/lib/terminfo',
                                lambda match: str(terminfo) + match[0], script)
            return subprocess.run(['/bin/bash', '-c', script, 'bootstrap', 'probe', *([locale] if locale else [])],
                                  env={'PATH': name, **(env or {})}, capture_output=True)

    def test_unsupported_tar(self):
        r = self.probe({'tar': 'echo unsupported', 'sha256sum': 'exit 0'})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(b'unsupported tar', r.stderr)

    def test_missing_hash(self):
        r = self.probe({'tar': 'echo "tar (GNU tar) fixture"'})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(b'SHA-256 unavailable', r.stderr)

    def test_bsd_tar_and_shasum_probe(self):
        r = self.probe({'tar': 'echo "bsdtar fixture"', 'shasum': 'exit 0', 'locale': 'echo UTF-8'})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(r.stdout.startswith(b'protocol=1\ntar=ustar\nhash=shasum\ncharmap=UTF-8\n'))
        self.assertIn(b'nvim=0', r.stdout)

    def test_gnu_tar_probe(self):
        r = self.probe({'tar': 'echo "tar (GNU tar) fixture"', 'sha256sum': 'exit 0', 'locale': 'echo UTF-8'})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(b'hash=sha256sum', r.stdout)

    def test_locale_codeset_spelling_uses_actual_host_name(self):
        for host, requested in [('C.utf8', 'C.UTF-8'), ('C.UTF-8', 'C.utf8'), ('C.UTF8', 'C.UTF-8'), ('en_US.utf8', 'en_US.UTF-8')]:
            tools = {'tar': 'echo bsdtar', 'shasum': 'exit 0',
                     'locale': f'if [ "$1" = -a ]; then echo "{host}"; elif [ "$LC_ALL" = "{host}" ]; then echo UTF-8; else echo wrong; fi'}
            with self.subTest(host=host):
                r = self.probe(tools, requested)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn(('locale=' + host + '\n').encode(), r.stdout)
                self.assertIn(b'os=', r.stdout)
                self.assertIn(b'arch=', r.stdout)
                self.assertIn(b'bash=GNU bash, version', r.stdout)
                self.assertIn(b'nvim_version=unavailable', r.stdout)
                self.assertIn(b'terminfo_xterm=1', r.stdout)

    def test_compiled_terminfo_without_tools(self):
        tools = {'infocmp': None, 'tar': 'echo bsdtar', 'shasum': 'exit 0', 'locale': 'echo UTF-8'}
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            # Exercise every search location and both common compiled layouts.
            for source in ['TERMINFO', 'HOME', 'TERMINFO_DIRS', '/etc/terminfo', '/lib/terminfo',
                           '/usr/share/terminfo', '/usr/lib/terminfo']:
                for layout in ['x', '78']:
                    with self.subTest(source=source, layout=layout):
                        home = root / 'home'
                        env = {'HOME': str(home), 'TERM': 'absent-terminal'}
                        if source == 'HOME':
                            directory = home / '.terminfo'
                        elif source.startswith('/'):
                            directory = root / source.lstrip('/')
                        else:
                            directory = root / 'custom'
                            env[source] = str(directory)
                            if source == 'TERMINFO_DIRS':
                                env[source] = str(root / 'missing') + ':' + str(directory) + ':'
                        entry = directory / layout / 'xterm-256color'
                        entry.parent.mkdir(parents=True, exist_ok=True)
                        entry.write_bytes(b'compiled fixture')
                        r = self.probe(tools, env=env, terminfo=root)
                        self.assertEqual(r.returncode, 0, r.stderr)
                        self.assertIn(b'term=xterm-256color\n', r.stdout)
                        self.assertIn(b'terminfo_xterm=1\n', r.stdout)
                        self.assertIn(b'terminfo_tmux=0\n', r.stdout)
                        entry.unlink()

    def test_compiled_terminfo_fallback_order_and_probe_flags(self):
        tools = {'infocmp': None, 'tar': 'echo bsdtar', 'shasum': 'exit 0', 'locale': 'echo UTF-8'}
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            db = root / 'db'
            entries = ['custom-term', 'xterm-256color', 'vt100', 'dumb', 'tmux-256color']
            for term in entries:
                path = db / term[0] / term
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'compiled fixture')
            for term in entries[:-1]:
                with self.subTest(term=term):
                    r = self.probe(tools, env={'TERMINFO': str(db), 'TERM': 'custom-term'}, terminfo=root)
                    self.assertEqual(r.returncode, 0, r.stderr)
                    self.assertIn(('term=' + term + '\n').encode(), r.stdout)
                    self.assertIn(b'terminfo_tmux=1\n', r.stdout)
                    self.assertIn(b'terminfo_xterm=' + (b'1' if term in entries[:2] else b'0') + b'\n', r.stdout)
                    (db / term[0] / term).unlink()

    def test_no_compiled_terminfo_stops_with_22(self):
        from unittest.mock import patch
        tools = {'infocmp': None, 'tar': 'echo bsdtar', 'shasum': 'exit 0', 'locale': 'echo UTF-8'}
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            r = self.probe(tools, env={'HOME': str(root), 'TERMINFO': str(root / 'empty')}, terminfo=root)
        self.assertEqual(r.returncode, 23, r.stderr)
        self.assertIn(b'no supported terminal', r.stderr)
        # The local wrapper maps the bootstrap error to public code 22.
        policy = {'target': 'fixture.invalid', 'port': 22, 'user': None}
        with patch.object(cli.subprocess, 'run', return_value=r):
            with self.assertRaises(cli.RemoteError) as caught:
                cli.control(policy, '', ['inspect'])
        self.assertEqual(caught.exception.code, 22)


if __name__ == '__main__':
    unittest.main()
