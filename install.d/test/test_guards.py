"""Guards that stop plan and doctor before dotbot runs, and the exit-code
contract for dotbot's own diagnostics (CRT-INSTALL F03 to F06)."""
import unittest

from harness import DECLARED, InstallCase, stub
from support import DOTBOT


class DotbotPinTests(InstallCase):
    """F03: an unpinned submodule is reported and never run."""

    def make_submodule(self):
        sub = self.repo / 'dotbot'
        (sub / 'bin').mkdir(parents=True)
        (sub / 'lib').symlink_to(DOTBOT.parents[1] / 'lib')
        self.marker = self.root / 'submodule dotbot.called'
        stub(sub / 'bin', 'dotbot', f'echo called >> "{self.marker}"\nexec "{DOTBOT}" "$@"')
        self.git(sub, 'init', '-q')
        self.git(sub, 'add', '-A')
        self.git(sub, 'commit', '-q', '-m', 'pinned')
        (self.repo / '.gitmodules').write_text('[submodule "dotbot"]\n\tpath = dotbot\n'
                                               '\turl = ./dotbot\n\tignore = dirty\n')
        self.git(self.repo, 'add', '.gitmodules', 'dotbot')
        self.git(self.repo, 'commit', '-q', '-m', 'pin dotbot')
        self.git(self.repo, 'submodule', 'init', '-q')
        self.env.pop('DOTBOT_BIN')
        return sub

    def test_mismatched_pin_stops_before_dotbot(self):
        sub = self.make_submodule()
        (sub / 'later').write_text('unpinned\n')
        self.git(sub, 'add', 'later')
        self.git(sub, 'commit', '-q', '-m', 'unpinned')
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('FAIL     links     dotbot submodule is not at the pinned commit; '
                      'run: git submodule update --init --recursive dotbot', result.stdout.splitlines())
        self.assertNotIn('Would create', result.stdout)
        self.assertFalse(self.marker.exists(), 'the unpinned launcher ran')
        self.git(sub, 'checkout', '-q', 'HEAD~1')
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('dotbot submodule at the pinned commit', result.stdout)
        self.assertEqual(result.stdout.count('Would create symlink '), len(DECLARED))
        self.assertEqual(self.home_entries(), [])


class CheckoutGuardTests(InstallCase):
    """F04: run only from the top of a checkout; map a slot to its main checkout
    only when that relationship verifies."""

    def setUp(self):
        super().setUp()
        self.marker_dotbot()

    def test_a_subdirectory_of_another_checkout_is_refused(self):
        nested = self.repo / 'nested copy'
        self.make_checkout(nested, git=False)
        result = self.run_install('plan', repo=nested)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn('not the top of a git checkout', result.stderr)
        self.assertFalse(self.marker.exists())

    def test_slot_with_the_account_home_checks_the_main_checkout(self):
        slot = self.root / 'slot one'
        self.git(self.repo, 'worktree', 'add', '-q', '--detach', str(slot))
        self.stub_account_home(self.home)
        result = self.run_install('plan', repo=slot)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f'checked against the main checkout {self.repo}', result.stdout)
        self.assertIn(f'-> {self.repo}/bash/.bashrc', result.stdout)
        self.assertNotIn(f'-> {slot}/', result.stdout)

    def test_unmappable_slot_with_the_account_home_is_refused(self):
        main, meta, slot = self.root / 'main', self.root / 'meta', self.root / 'slot two'
        self.make_checkout(main, git=False)
        self.git(self.root, 'init', '-q', '--separate-git-dir', str(meta), str(main))
        self.git(main, 'add', '-A')
        self.git(main, 'commit', '-q', '-m', 'fixture')
        self.git(main, 'worktree', 'add', '-q', '--detach', str(slot))
        self.stub_account_home(self.home)
        result = self.run_install('plan', repo=slot)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn('run the preview from the main checkout', result.stderr)
        self.assertFalse(self.marker.exists())


class ManagedParentTests(InstallCase):
    """F05: every existing directory on the way to a managed destination, and
    every cleanup root, must be a real directory before dotbot runs."""

    def setUp(self):
        super().setUp()
        self.marker_dotbot()
        self.outside = self.root / 'outside'
        self.outside.mkdir()

    def assert_refused(self, offending, xdg=None):
        for command in ('plan', 'doctor'):
            with self.subTest(command=command, offending=str(offending)):
                result = self.run_install(command)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertTrue(any(str(offending) in line and line.startswith('FAIL     links')
                                    for line in result.stdout.splitlines()), result.stdout)
                self.assertFalse(self.marker.exists(), 'dotbot ran past a bad parent')
        self.assertEqual(list(self.outside.iterdir()), [])

    def test_symlinked_nested_parent(self):
        (self.home / '.config').mkdir()
        (self.home / '.config' / 'opencode').symlink_to(self.outside)
        self.assert_refused(self.home / '.config' / 'opencode')

    def test_dangling_parent_symlink(self):
        (self.home / '.config').mkdir()
        (self.home / '.config' / 'ghostty').symlink_to(self.root / 'gone')
        self.assert_refused(self.home / '.config' / 'ghostty')

    def test_regular_file_in_a_parent_position(self):
        (self.home / '.config').mkdir()
        (self.home / '.config' / 'fd').write_text('not a directory\n')
        self.assert_refused(self.home / '.config' / 'fd')

    def test_custom_xdg_with_spaces(self):
        xdg = self.home / 'my config dir'
        (xdg).mkdir()
        (xdg / 'pgcli').symlink_to(self.outside)
        self.env['XDG_CONFIG_HOME'] = str(xdg)
        self.assert_refused(xdg / 'pgcli')

    def test_symlinked_xdg_root(self):
        xdg = self.home / 'linked config'
        xdg.symlink_to(self.outside)
        self.env['XDG_CONFIG_HOME'] = str(xdg)
        self.assert_refused(xdg)

    def test_symlinked_skills_cleanup_root(self):
        (self.home / '.agents').mkdir()
        (self.home / '.agents' / 'skills').symlink_to(self.outside)
        self.assert_refused(self.home / '.agents' / 'skills')

    def test_herdr_parent_outside_xdg(self):
        (self.home / '.config').mkdir()
        (self.home / '.config' / 'herdr').symlink_to(self.outside)
        self.assert_refused(self.home / '.config' / 'herdr')

    def test_real_parents_pass(self):
        self.link_everything()
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(self.marker.exists())


class DiagnosticsTests(InstallCase):
    """F06: exit 4 only when recognised conflicts explain the whole failure."""

    def test_missing_source_and_conflict_is_a_failure(self):
        (self.repo / 'ghostty' / 'config').unlink()
        (self.home / '.bashrc').write_text('local configuration')
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('Nonexistent target', result.stdout)
        self.assertIn('already exists but is a regular file or directory', result.stdout)
        self.assertEqual(self.lines(result, 'CONFLICT'), [])
        self.assertEqual((self.home / '.bashrc').read_text(), 'local configuration')

    def test_missing_source_alone_is_a_failure(self):
        (self.repo / 'ghostty' / 'config').unlink()
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('Nonexistent target', result.stdout)


if __name__ == '__main__':
    unittest.main()
