"""One meaning for every managed path (CRT-INSTALL F13, F15, F17).

HOME and XDG_CONFIG_HOME must be absolute and free of `.` and `..`
components, or ./install refuses with exit 3 before any tool runs. Then the
guard, the Bash phases and dotbot all address the same directories, and the
parent walk is exact. `create` roots are walked like cleanup roots.
"""
import importlib.util
import os
from pathlib import Path
import unittest

from harness import DECLARED, InstallCase
from support import REPO


def load_parents():
    spec = importlib.util.spec_from_file_location('parents', REPO / 'install.d' / 'parents.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CanonicalPathTests(InstallCase):
    def setUp(self):
        super().setUp()
        self.marker_dotbot()
        self.outside = self.root / 'outside'
        self.outside.mkdir()
        (self.outside / 'sentinel').write_text('keep\n')

    def assert_refused(self, variable, cwd=None):
        status = self.checkout_status()
        for command in ('plan', 'doctor'):
            with self.subTest(command=command, variable=variable):
                result = self.run_install(command, cwd=cwd)
                self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
                self.assertIn(f'install: {variable} must', result.stderr)
                self.assertNotIn('Would create', result.stdout)
                self.assertFalse(self.marker.exists(), 'dotbot ran')
        self.assertEqual(sorted(p.name for p in self.outside.iterdir()), ['sentinel'])
        self.assertEqual(self.checkout_status(), status)

    def test_f13_xdg_through_a_missing_component_and_dot_dot(self):
        real = self.outside / 'real config'
        real.mkdir()
        external = self.root / 'external'
        external.mkdir()
        (real / 'opencode').symlink_to(external)
        self.env['XDG_CONFIG_HOME'] = f'{real}/not-created/..'
        self.assert_refused('XDG_CONFIG_HOME')
        self.assertEqual(list(external.iterdir()), [])

    def test_f13_control_existing_symlink_then_dot_dot(self):
        real = self.outside / 'real config'
        real.mkdir()
        external = self.root / 'external'
        external.mkdir()
        (real / 'opencode').symlink_to(external)
        self.env['XDG_CONFIG_HOME'] = f'{real}/opencode/..'
        self.assert_refused('XDG_CONFIG_HOME')

    def test_f15_home_through_a_symlink_and_dot_dot(self):
        (self.root / 'far' / 'sub').mkdir(parents=True)
        (self.root / 'far' / 'home').mkdir()
        (self.root / 'lnk').symlink_to(self.root / 'far' / 'sub')
        (self.home / '.config').symlink_to(self.outside)
        self.env['HOME'] = f'{self.root}/lnk/../home'
        self.assert_refused('HOME')

    def test_f15_relative_xdg_config_home(self):
        cwd = self.root / 'cwd'
        (cwd / 'cfg').mkdir(parents=True)
        self.env['XDG_CONFIG_HOME'] = 'cfg'
        self.assert_refused('XDG_CONFIG_HOME', cwd=cwd)
        self.assertFalse((self.repo / 'cfg').exists())

    def test_f15_relative_home(self):
        self.env['HOME'] = 'home'
        self.assert_refused('HOME', cwd=self.root)
        self.assertFalse((self.repo / 'home').exists())

    def test_f15_dot_component(self):
        self.env['HOME'] = f'{self.root}/./home'
        self.assert_refused('HOME')

    def test_redundant_slashes_still_pass(self):
        clean = self.run_install('plan')
        self.assertEqual(clean.returncode, 0, clean.stdout + clean.stderr)
        for xdg in (f'{self.home}/.config/', f'{self.home}//.config'):
            with self.subTest(xdg=xdg):
                self.env['XDG_CONFIG_HOME'] = xdg
                result = self.run_install('plan')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stdout.count('Would create symlink '), len(DECLARED))
        self.assertEqual(clean.stdout.count('Would create symlink '), len(DECLARED))


class CreateRootTests(InstallCase):
    """F17: a `create` entry's whole path is walked, like a cleanup root."""

    def setUp(self):
        super().setUp()
        self.marker_dotbot()
        self.outside = self.root / 'outside'
        self.outside.mkdir()

    def add_create(self, path):
        with open(self.repo / 'install.conf.yaml', 'a', encoding='utf-8') as handle:
            handle.write(f'\n- create:\n    - {path}\n')

    def test_symlinked_create_parent_is_refused(self):
        for name, path in (('.local', '~/.local/share/fixture'), ('.cache', '~/.cache/fixture')):
            with self.subTest(parent=name):
                self.add_create(path)
                (self.home / name).symlink_to(self.outside)
                for command in ('plan', 'doctor'):
                    result = self.run_install(command)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertIn(f'FAIL     links     {self.home / name} is a symlink', result.stdout)
                    self.assertNotIn('Would create', result.stdout)
                    self.assertFalse(self.marker.exists())
                self.assertEqual(list(self.outside.iterdir()), [])
                (self.home / name).unlink()

    def test_real_create_parent_passes(self):
        self.add_create('~/.local/share/fixture')
        (self.home / '.local').mkdir()
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.marker.exists())
        self.assertFalse((self.home / '.local' / 'share').exists())


class ManagedHelperTests(unittest.TestCase):
    """The one helper every managed path goes through."""

    def setUp(self):
        self.parents = load_parents()
        self.saved = {k: os.environ.get(k) for k in ('HOME', 'XDG_CONFIG_HOME')}
        os.environ['HOME'] = '/home/someone'
        os.environ['XDG_CONFIG_HOME'] = '/cfg root'

    def tearDown(self):
        for key, value in self.saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_rejects_relative_and_dot_paths(self):
        for bad in ('relative/path', 'cfg', '/a/./b', '/a/../b', '/a/b/..', '/a/.', './x'):
            with self.subTest(path=bad):
                with self.assertRaises(ValueError):
                    self.parents.managed(bad)

    def test_expands_like_dotbot_and_normalises_slashes(self):
        managed = self.parents.managed
        self.assertEqual(managed('~/.bashrc'), '/home/someone/.bashrc')
        self.assertEqual(managed('$XDG_CONFIG_HOME/nvim'), '/cfg root/nvim')
        self.assertEqual(managed('/x//cfg/'), '/x/cfg')
        self.assertEqual(managed('~'), '/home/someone')


if __name__ == '__main__':
    unittest.main()
