"""./install plan and doctor against a sandbox HOME; never the user's HOME.

Real Bash, real dotbot and a real git checkout whose path has a space, driven
as subprocesses with a minimal PATH, so the suite also proves the stock-macOS
interpreter path (/bin/bash 3.2, /usr/bin/python3). Ported from the slot 1
dotbot harness (tests/test_setup.py).
"""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest

from support import CONFIGS, DOTBOT, REPO, expand, links_for_this_os

DECLARED = links_for_this_os()
GIT = ['git', '-c', 'user.name=test', '-c', 'user.email=test@example.invalid',
       '-c', 'init.defaultBranch=main', '-c', 'commit.gpgsign=false']


def stub(directory, name, body):
    path = directory / name
    path.write_text('#!/bin/sh\n' + body + '\n')
    path.chmod(0o755)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles install ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / 'checkout with spaces'
        self.home = self.root / 'home'
        self.home.mkdir()
        self.make_checkout(self.repo)
        self.env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.home), 'LC_ALL': 'C',
                    'DOTBOT_BIN': str(DOTBOT), 'PYTHONDONTWRITEBYTECODE': '1'}

    def make_checkout(self, repo, git=True):
        (repo / 'install.d').mkdir(parents=True)
        for name in ['install'] + CONFIGS:
            shutil.copy2(REPO / name, repo / name)
        for script in (REPO / 'install.d').glob('*.sh'):
            shutil.copy2(script, repo / 'install.d' / script.name)
        for _, source in DECLARED:
            path = repo / source
            if (REPO / source).is_dir():
                path.mkdir(parents=True, exist_ok=True)
                (path / 'fixture').write_text('fixture\n')
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('fixture\n')
        if git:
            self.git(repo, 'init', '-q')
            self.git(repo, 'add', '-A')
            self.git(repo, 'commit', '-q', '-m', 'fixture')

    def git(self, repo, *args):
        subprocess.run(GIT + ['-C', str(repo), *args], check=True, capture_output=True,
                       env={'PATH': '/usr/bin:/bin', 'HOME': str(self.root)})

    def run_install(self, *args, repo=None):
        script = (repo or self.repo) / 'install'
        return subprocess.run(['/bin/bash', str(script), *args], cwd=self.root, env=self.env,
                              capture_output=True, text=True, timeout=60)

    def home_entries(self):
        return sorted(str(p.relative_to(self.home)) for p in self.home.rglob('*'))

    def lines(self, result, status):
        return [line for line in result.stdout.splitlines() if line.startswith(status + ' ')]

    def link_everything(self, xdg=None):
        for dest, source in DECLARED:
            path = expand(dest, self.home, xdg)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(self.repo / source)

    # --- plan ---------------------------------------------------------------
    def test_plan_on_empty_home_lists_every_link_and_writes_nothing(self):
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        would = [line for line in result.stdout.splitlines() if 'Would create symlink ' in line]
        self.assertEqual(len(would), len(DECLARED), result.stdout)
        self.assertIn(f'{len(DECLARED)} links to create, 0 dead links to remove', result.stdout)
        self.assertEqual(self.home_entries(), [])

    def test_plan_honours_xdg_config_home_with_a_space(self):
        xdg = self.home / 'custom config'
        self.env['XDG_CONFIG_HOME'] = str(xdg)
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f'{xdg}/nvim -> {self.repo}/nvim', result.stdout)
        self.assertIn(f'~/.config/starship.toml -> {self.repo}/starship/starship.toml', result.stdout)
        self.assertEqual(self.home_entries(), [])

    def test_converged_home_plans_nothing_and_doctor_passes(self):
        self.link_everything()
        before = self.home_entries()
        plan = self.run_install('plan')
        self.assertEqual(plan.returncode, 0, plan.stdout + plan.stderr)
        self.assertNotIn('Would ', plan.stdout)
        self.assertIn(f'{len(DECLARED)} declared links in place', plan.stdout)
        doctor = self.run_install('doctor')
        self.assertIn(doctor.returncode, (0, 10), doctor.stdout + doctor.stderr)
        self.assertEqual(self.lines(doctor, 'FAIL') + self.lines(doctor, 'CONFLICT'), [])
        self.assertEqual(self.home_entries(), before)

    def test_doctor_reports_drift_on_an_empty_home(self):
        result = self.run_install('doctor')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(f'{len(DECLARED)} links to create', result.stdout)
        self.assertTrue(any(line.startswith('FAIL     links') for line in result.stdout.splitlines()))
        self.assertEqual(self.home_entries(), [])

    def test_dead_link_into_the_checkout_is_planned_not_removed(self):
        self.link_everything()
        retired = self.home / '.tmux.conf'
        retired.symlink_to(self.repo / 'tmux' / 'tmux.conf')
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('0 links to create, 1 dead links to remove', result.stdout)
        self.assertIn(f'Would remove invalid link {retired}', result.stdout)
        self.assertTrue(retired.is_symlink())

    def test_an_unreadable_config_is_a_failure_not_a_conflict(self):
        (self.repo / 'install.conf.yaml').write_text('- link: [unclosed\n')
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('dotbot could not plan the links', result.stdout)
        self.assertEqual(self.lines(result, 'CONFLICT'), [])
        self.assertEqual(self.home_entries(), [])

    def test_conflicts_exit_4_and_stay_untouched(self):
        dest = self.home / '.bashrc'
        for kind in ('file', 'directory', 'broken-link', 'foreign-link'):
            with self.subTest(kind=kind):
                if kind == 'file':
                    dest.write_text('local configuration')
                elif kind == 'directory':
                    dest.mkdir()
                    (dest / 'keep').write_text('keep')
                elif kind == 'broken-link':
                    dest.symlink_to(self.home / 'missing')
                else:
                    dest.symlink_to(self.root / 'elsewhere')
                    (self.root / 'elsewhere').write_text('keep')
                before = self.home_entries()
                for command in ('plan', 'doctor'):
                    result = self.run_install(command)
                    self.assertEqual(result.returncode, 4 if command == 'plan' else 1, result.stdout)
                    self.assertEqual(len(self.lines(result, 'CONFLICT')), 1, result.stdout)
                self.assertEqual(self.home_entries(), before)
                if kind == 'file':
                    self.assertEqual(dest.read_text(), 'local configuration')
                    dest.unlink()
                elif kind == 'directory':
                    self.assertEqual((dest / 'keep').read_text(), 'keep')
                    shutil.rmtree(dest)
                else:
                    self.assertTrue(os.readlink(dest))
                    dest.unlink()

    def test_symlinked_parent_fails_and_nothing_is_written(self):
        elsewhere = self.root / 'other config'
        elsewhere.mkdir()
        (self.home / '.config').symlink_to(elsewhere)
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('.config is a symlink', result.stdout)
        self.assertEqual(list(elsewhere.iterdir()), [])

    @unittest.skipUnless(platform.system() == 'Darwin', 'Ghostty shadowing is macOS-only')
    def test_ghostty_application_support_config_is_reported(self):
        support = self.home / 'Library/Application Support/com.mitchellh.ghostty'
        support.mkdir(parents=True)
        (support / 'config.ghostty').write_text('font-size = 12\n')
        plan = self.run_install('plan')
        self.assertEqual(plan.returncode, 0, plan.stdout)
        self.assertEqual(len(self.lines(plan, 'warn     ghostty')), 1, plan.stdout)
        self.link_everything()
        doctor = self.run_install('doctor')
        self.assertEqual(doctor.returncode, 1, doctor.stdout)
        self.assertEqual(len(self.lines(doctor, 'FAIL     ghostty')), 1, doctor.stdout)
        self.assertEqual((support / 'config.ghostty').read_text(), 'font-size = 12\n')

    # --- guards and arguments -----------------------------------------------
    def test_bad_arguments_exit_2_and_write_nothing(self):
        for args in ((), ('apply',), ('--force',), ('plan', 'doctor'), ('links',)):
            with self.subTest(args=args):
                result = self.run_install(*args)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(self.home_entries(), [])

    def test_outside_a_git_checkout_is_refused(self):
        bare = self.root / 'not a checkout'
        self.make_checkout(bare, git=False)
        result = self.run_install('plan', repo=bare)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn('not a git checkout', result.stderr)

    def test_linked_worktree_with_sandbox_home_checks_itself(self):
        slot = self.root / 'slot one'
        self.git(self.repo, 'worktree', 'add', '-q', '--detach', str(slot))
        result = self.run_install('plan', repo=slot)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('linked worktree with a sandbox HOME', result.stdout)
        self.assertIn(f'-> {slot}/bash/.bashrc', result.stdout)
        self.assertEqual(self.home_entries(), [])

    def test_missing_dotbot_fails_and_writes_nothing(self):
        self.env['DOTBOT_BIN'] = str(self.root / 'absent' / 'dotbot')
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('dotbot not found', result.stdout)
        self.assertEqual(self.home_entries(), [])

    def test_plan_leaves_the_checkout_clean(self):
        self.run_install('plan')
        self.run_install('doctor')
        status = subprocess.run(['git', '-C', str(self.repo), 'status', '--porcelain', '--ignored'],
                                capture_output=True, text=True, check=True)
        self.assertEqual(status.stdout, '')

    # --- compatibility --------------------------------------------------------
    def test_too_old_python_is_a_failure(self):
        bin_dir = self.root / 'stub bin'
        bin_dir.mkdir()
        stub(bin_dir, 'python3', 'echo "Python 3.6.15"; exit 1')
        self.env['PATH'] = f'{bin_dir}:/usr/bin:/bin'
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn('python3 3.6.15 is older than 3.7', result.stdout)
        self.assertEqual(self.home_entries(), [])

    def test_missing_and_old_tools_are_warnings(self):
        bin_dir = self.root / 'stub bin'
        bin_dir.mkdir()
        stub(bin_dir, 'nvim', 'echo "NVIM v0.9.5"')
        stub(bin_dir, 'node', 'echo "v22.3.0"')
        self.env['PATH'] = f'{bin_dir}:/usr/bin:/bin'
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 0, result.stdout)
        out = result.stdout.splitlines()
        self.assertIn('warn     tools     nvim 0.9.5 is older than 0.11 (envi uses Neovim 0.11 APIs)', out)
        self.assertIn('ok       tools     node 22.3.0', out)
        self.assertTrue(any(line.startswith('ok       bash') for line in out), result.stdout)
        self.assertTrue(any(line.startswith('ok       tools     git ') for line in out), result.stdout)


if __name__ == '__main__':
    unittest.main()
