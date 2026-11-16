"""Closed-payload tests: fixtures never inspect HOME or connect to a host."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'remote'))
import pack


class PackTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        for name, mode in pack.ALLOWLIST.items():
            p = self.root / pack.source(name)
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('safe\n')
            p.chmod(mode)
        p = self.root / 'remote/profiles/minimal.manifest'
        p.parent.mkdir(parents=True)
        p.write_text(pack.manifest_text())
        self.commit()

    def commit(self):
        subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Fixture', '-c',
                        'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture'], check=True)

    def build(self, **kw):
        return pack.build(self.root, **kw)

    def test_deterministic(self):
        a, b = self.build(), self.build()
        self.assertEqual(a.archive, b.archive)
        self.assertEqual(a.digest, b.digest)
        self.assertLess(len(a.archive), 262144)
        pack.verify(a.archive, a.digest)

    def test_unlisted_manifest_entry(self):
        p = self.root / 'remote/profiles/minimal.manifest'
        p.write_text(p.read_text() + 'remote/profile/extra extra 0644\n')
        with self.assertRaises(ValueError):
            self.build(allow_dirty=True)

    def test_unlisted_source_does_not_travel(self):
        (self.root / 'remote/profile/password.env').write_text('do not export')
        with self.assertRaises(ValueError):
            self.build()
        artifact = self.build(allow_dirty=True)
        self.assertNotIn('password.env', [m.name for m in tarfile.open(fileobj=io.BytesIO(artifact.archive))])

    def test_dirty_requires_opt_in_and_records_provenance(self):
        (self.root / 'remote/profile/shell/bashrc').write_text('changed\n')
        with self.assertRaises(ValueError):
            self.build()
        a = self.build(allow_dirty=True)
        self.assertTrue(a.provenance['dirty'])
        self.assertNotEqual(a.digest, self.build(revision='HEAD').digest)

    def test_symlink_source(self):
        p = self.root / 'remote/profile/shell/bashrc'
        p.unlink()
        p.symlink_to('inputrc')
        with self.assertRaises(ValueError):
            self.build(allow_dirty=True)
        self.commit()
        with self.assertRaises(ValueError):
            self.build()

    def test_secret_content(self):
        for text in ['-----BEGIN OPENSSH PRIVATE KEY-----', 'AWS_SECRET_ACCESS_KEY=fixture',
                     'ghp_' + 'a' * 36]:
            (self.root / 'remote/profile/shell/bashrc').write_text(text)
            with self.assertRaises(ValueError):
                self.build(allow_dirty=True)

    def test_bad_source_mode(self):
        (self.root / 'remote/profile/bin/enter').chmod(0o777)
        with self.assertRaises(ValueError):
            self.build(allow_dirty=True)

    def test_traversal_duplicate_schema_mode_links_extra(self):
        a = self.build()
        def altered(kind):
            output = io.BytesIO()
            with tarfile.open(fileobj=output, mode='w:gz') as out:
                with tarfile.open(fileobj=io.BytesIO(a.archive)) as src:
                    for m in src:
                        data = src.extractfile(m).read()
                        if m.name == 'MANIFEST':
                            if kind == 'schema':
                                data = data.replace(b'schema 1', b'schema 9')
                            if kind == 'mode':
                                data = data.replace(b'0755', b'0777')
                        m.size = len(data)
                        out.addfile(m, io.BytesIO(data))
                    m = tarfile.TarInfo({'traversal': '../escape', 'absolute': '/escape',
                                         'duplicate': 'bin/enter'}.get(kind, 'extra'))
                    if kind == 'link':
                        m.type, m.linkname = tarfile.SYMTYPE, 'bin/enter'
                    out.addfile(m, io.BytesIO(b''))
            return output.getvalue()
        for kind in ['traversal', 'absolute', 'duplicate', 'schema', 'mode', 'link', 'extra']:
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                pack.verify(altered(kind), a.digest)

    def test_corrupt_archive(self):
        a = self.build()
        with self.assertRaises(ValueError):
            pack.verify(a.archive[:100], a.digest)


if __name__ == '__main__':
    unittest.main()
