import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class EditorTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which('nvim'), 'nvim unavailable locally')
    def test_offline_edit_save_search_split_without_services(self):
        with tempfile.TemporaryDirectory() as name:
            base = Path(name).resolve()
            home = base / 'home'
            home.mkdir()
            (home / '.config').mkdir()
            state = base / 'state'
            state.mkdir()
            env = dict(os.environ, HOME=str(home), ENVI_REMOTE_RELEASE=str(ROOT / 'remote/profile'),
                       ENVI_REMOTE_STATE=str(state), EDITOR_FIXTURE=str(base / 'sample.txt'))
            # Reproduce the extracted destination layout, not the source layout.
            release = base / 'release'
            shutil.copytree(ROOT / 'remote/profile', release)
            (release / 'config').mkdir()
            (release / 'nvim').rename(release / 'config/envi-remote')
            env['ENVI_REMOTE_RELEASE'] = str(release)
            result = subprocess.run([str(release / 'bin/editor'), '--headless',
                                     '+luafile ' + str(ROOT / 'remote/test/editor.lua'), '+qa!'],
                                    env=env, capture_output=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b'remote editor offline tests passed', result.stderr)
            self.assertEqual((base / 'sample.txt').read_text(), 'offline alpha\nneedle beta\n')
            self.assertEqual([p.name for p in home.iterdir()], ['.config'])
            self.assertEqual(list((home / '.config').iterdir()), [])

    def test_missing_editor_is_explicit(self):
        with tempfile.TemporaryDirectory() as name:
            result = subprocess.run(['/bin/bash', str(ROOT / 'remote/profile/bin/editor')],
                                    env={'PATH': name}, capture_output=True)
            self.assertEqual(result.returncode, 25)
            self.assertIn(b'vi -u NONE', result.stderr)

    def test_unsupported_editor_version(self):
        with tempfile.TemporaryDirectory() as name:
            nvim = Path(name) / 'nvim'
            nvim.write_text('#!/bin/sh\necho "NVIM v0.4.0"\n')
            nvim.chmod(0o755)
            result = subprocess.run(['/bin/bash', str(ROOT / 'remote/profile/bin/editor')],
                                    env={'PATH': name}, capture_output=True)
            self.assertEqual(result.returncode, 25)
            self.assertIn(b'0.9', result.stderr)


if __name__ == '__main__':
    unittest.main()
