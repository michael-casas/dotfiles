"""The read-only contract: plan and doctor write nothing outside one private
probe scratch directory, which is removed before they exit (CRT-INSTALL F01, F02)."""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import unittest

from harness import InstallCase, stub

# A Neovim stand-in that writes wherever an inherited setting points it, the
# way nvim does with NVIM_LOG_FILE, TMPDIR and its state dir on any start.
NVIM = '''echo called >> "{marker}"
if [ -n "$NVIM_LOG_FILE" ]; then echo log >> "$NVIM_LOG_FILE"; fi
if [ -n "$TMPDIR" ]; then touch "$TMPDIR/nvim-stub.$$"; fi
if [ -n "$DOTFILES_STUB_LEAK" ]; then echo leaked >> "{marker}"; fi
mkdir -p "$HOME/.local/state/nvim" && touch "$HOME/.local/state/nvim/log"
echo "NVIM v0.11.6"'''


def snapshot(directory):
    """Names and directory metadata that a create-and-remove would change."""
    info = os.stat(directory)
    return sorted(os.listdir(directory)), info.st_mtime_ns, info.st_ctime_ns


class VersionProbeTests(InstallCase):
    def setUp(self):
        super().setUp()
        self.marker = self.root / 'nvim.called'
        stub(self.stub_dir(), 'nvim', NVIM.format(marker=self.marker))
        self.env['PATH'] = f'{self.stub_dir()}:/usr/bin:/bin'

    def probe_with_inherited_settings(self, tmpdir):
        tmpdir.mkdir(parents=True, exist_ok=True)
        log = self.home / 'Library' / 'Caches' / 'probe.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        self.env.update(TMPDIR=str(tmpdir), NVIM_LOG_FILE=str(log), DOTFILES_STUB_LEAK='1')
        home_before = self.home_entries()
        tmp_before = snapshot(tmpdir)
        for command, code in (('plan', 0), ('doctor', 1)):
            with self.subTest(command=command, tmpdir=str(tmpdir)):
                result = self.run_install(command)
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                self.assertIn('ok       tools     nvim 0.11.6', result.stdout.splitlines())
                self.assertFalse(log.exists(), 'the inherited NVIM_LOG_FILE was written')
                self.assertEqual(snapshot(tmpdir), tmp_before, 'TMPDIR was touched')
                self.assertEqual(self.home_entries(), home_before)
                self.assertEqual(list(self.probe_root.iterdir()), [])
        self.assertNotIn('leaked', self.marker.read_text(), 'the probe inherited the environment')

    def test_tmpdir_in_home_and_inherited_log_are_untouched(self):
        self.probe_with_inherited_settings(self.home / 'tmp')

    def test_tmpdir_in_the_checkout_is_untouched(self):
        self.probe_with_inherited_settings(self.repo / 'tmp')

    def test_no_scratch_means_the_probe_never_runs(self):
        for root in (self.root / 'absent root', self.home / 'scratch', self.repo / 'scratch',
                     self.home / '.config' / 'scratch'):
            with self.subTest(root=str(root)):
                if root.parent != self.root:
                    root.mkdir(parents=True, exist_ok=True)
                self.env['DOTFILES_PROBE_ROOT'] = str(root)
                result = self.run_install('plan')
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn('python3 version probe failed', result.stdout)
                self.assertTrue(any(l.startswith('warn     tools     nvim version probe failed')
                                    for l in result.stdout.splitlines()), result.stdout)
                self.assertFalse(self.marker.exists(), 'nvim ran without a private scratch dir')
                if root.exists():
                    self.assertEqual(list(root.iterdir()), [])
                    shutil.rmtree(root)

    @unittest.skipUnless(shutil.which('nvim', path='/opt/homebrew/bin:/usr/local/bin'),
                         'real Neovim is not installed')
    def test_real_neovim_writes_nothing(self):
        real = Path(shutil.which('nvim', path='/opt/homebrew/bin:/usr/local/bin')).parent
        self.env['PATH'] = f'{real}:/usr/bin:/bin'
        log = self.home / 'Library' / 'Caches' / 'probe.log'
        log.parent.mkdir(parents=True)
        tmpdir = self.home / 'tmp'
        tmpdir.mkdir()
        self.env.update(TMPDIR=str(tmpdir), NVIM_LOG_FILE=str(log))
        before, tmp_before = self.home_entries(), snapshot(tmpdir)
        for command in ('plan', 'doctor'):
            result = self.run_install(command)
            self.assertTrue(any(l.startswith('ok       tools     nvim 0.')
                                for l in result.stdout.splitlines()), result.stdout)
        self.assertFalse(log.exists())
        self.assertEqual(snapshot(tmpdir), tmp_before)
        self.assertEqual(self.home_entries(), before)


@unittest.skipUnless(platform.system() == 'Darwin' and shutil.which('sandbox-exec'),
                     'sandbox-exec is macOS-only')
class WriteDenyTests(InstallCase):
    """Stock Bash 3.2 under an OS sandbox that denies every write except the
    probe scratch root and /dev/null."""

    def sandbox(self):
        profile = ('(version 1)(allow default)(deny file-write*)'
                   f'(allow file-write* (subpath "{self.probe_root}") (literal "/dev/null"))')
        return ('/usr/bin/sandbox-exec', '-p', profile)

    def warm_xcrun_cache(self):
        """The stock /usr/bin tools are xcrun shims that cache per HOME in the
        per-user temp dir. On a real machine that entry exists for the real
        HOME; make it exist for the sandbox HOME too, outside the sandbox."""
        for tool in ('/usr/bin/git', '/usr/bin/python3'):
            subprocess.run([tool, '--version'], env=self.env, capture_output=True, check=True)

    def test_plan_doctor_and_help_run_complete(self):
        self.warm_xcrun_cache()
        self.link_everything()
        skills = self.repo / 'skills' / 'example'
        skills.mkdir(parents=True)
        (skills / 'SKILL.md').write_text('fixture\n')
        shutil.copy2(Path(__file__).resolve().parents[2] / 'skill-catalog.py', self.repo)
        expected = {'plan': 0, 'doctor': 1, '--help': 0}
        for command, code in expected.items():
            with self.subTest(command=command):
                result = self.run_install(command, wrapper=self.sandbox())
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                self.assertNotIn('Operation not permitted', result.stdout + result.stderr)
                self.assertNotIn('cannot create temp file', result.stderr)
                if command == '--help':
                    self.assertIn('./install doctor', result.stdout)
                else:
                    self.assertIn('plan     skills    2 skill links to create, 0 retired links to remove'
                                  if command == 'plan' else
                                  'FAIL     skills    2 skill links to create, 0 retired links to remove',
                                  result.stdout.splitlines())
                    self.assertIn('ok       tools     python3 3.', result.stdout)


if __name__ == '__main__':
    unittest.main()
