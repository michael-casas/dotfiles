import importlib.machinery
import importlib.util
import os
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

    def probe(self, tools):
        with tempfile.TemporaryDirectory() as name:
            p = Path(name)
            for tool, text in tools.items():
                path = p / tool
                path.write_text('#!/bin/bash\n' + text + '\n')
                path.chmod(0o755)
            return subprocess.run(['/bin/bash', str(ROOT / 'remote/bootstrap.sh'), 'probe'],
                                  env={'PATH': name}, capture_output=True)

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


if __name__ == '__main__':
    unittest.main()
