import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProfileTest(unittest.TestCase):
    def test_git_shim_preserves_target_identity_and_config(self):
        with tempfile.TemporaryDirectory() as name:
            home = Path(name)
            config = home / '.gitconfig'
            original = '[user]\n name = Target Fixture\n email = target@example.invalid\n[alias]\n localonly = status\n'
            config.write_text(original)
            env = dict(os.environ, HOME=name, ENVI_REMOTE_RELEASE=str(ROOT / 'remote/profile'))
            env.pop('GIT_CONFIG_GLOBAL', None)
            env.pop('GIT_CONFIG_SYSTEM', None)
            for key, expected in [('user.name', b'Target Fixture\n'), ('alias.localonly', b'status\n'),
                                  ('alias.st', b'status --short\n')]:
                result = subprocess.run([str(ROOT / 'remote/profile/bin/git'), 'config', '--get', key],
                                        env=env, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected)
            self.assertEqual(config.read_text(), original)

    def test_missing_optional_search_tools_use_explicit_helpers(self):
        with tempfile.TemporaryDirectory() as name:
            base = Path(name)
            (base / 'needle.txt').write_text('sample needle\n')
            tools = base / 'tools'
            tools.mkdir()
            for tool in ['find', 'grep']:
                (tools / tool).symlink_to(shutil.which(tool))
            script = 'source "$1"; ff "*.txt"; search needle'
            result = subprocess.run(['/bin/bash', '--noprofile', '--rcfile', '/dev/null', '-ic',
                                     script, '--', str(ROOT / 'remote/profile/shell/bashrc')],
                                    cwd=base, env={'PATH': str(tools), 'HOME': name},
                                    capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b'./needle.txt', result.stdout)
            self.assertIn(b'sample needle', result.stdout)
            self.assertFalse((base / '.bash_history').exists())


if __name__ == '__main__':
    unittest.main()
