"""Tool selection and the one read-only Git path (CRT-INSTALL F10, F11).

F10: macOS /usr/bin/git and /usr/bin/python3 are xcrun shims, which write
xcrun's cache in the per-user temp dir for every new HOME. They are resolved
through `xcode-select -p` and never started. These tests use cold homes and
never warm that cache.

F11: inherited GIT_TRACE* and every Trace2 target, from the environment or
git config, are switched off for every git call.
"""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import time
import unittest

from harness import DECLARED, InstallCase, stub
import test_guards

DARWIN = platform.system() == 'Darwin'


def xcrun_cache():
    """Names, sizes and times of xcrun's cache files in the per-user temp dir."""
    temp = subprocess.run(['/usr/bin/getconf', 'DARWIN_USER_TEMP_DIR'],
                          capture_output=True, text=True, check=True).stdout.strip()
    found = []
    for name in sorted(os.listdir(temp)):
        if name.startswith('xcrun_db'):
            info = os.stat(os.path.join(temp, name))
            found.append((name, info.st_size, info.st_mtime_ns, info.st_ctime_ns))
    return found


def developer_dir():
    return subprocess.run(['/usr/bin/xcode-select', '-p'], capture_output=True,
                          text=True, check=True).stdout.strip()


@unittest.skipUnless(DARWIN and shutil.which('sandbox-exec'), 'xcrun shims are macOS-only')
class AppleShimTests(InstallCase):
    """Cold sandbox HOME, PATH=/usr/bin:/bin, writes only to the probe root."""

    def sandbox(self, deny_exec=()):
        profile = ('(version 1)(allow default)(deny file-write*)'
                   f'(allow file-write* (subpath "{self.probe_root}") (literal "/dev/null"))')
        for path in deny_exec:
            profile += f'(deny process-exec (literal "{path}"))'
        return ('/usr/bin/sandbox-exec', '-p', profile)

    def with_skills(self):
        skills = self.repo / 'skills' / 'example'
        skills.mkdir(parents=True)
        (skills / 'SKILL.md').write_text('fixture\n')
        shutil.copy2(Path(__file__).resolve().parents[2] / 'skill-catalog.py', self.repo)

    def assert_clean_run(self, dev):
        dev = os.path.realpath(dev)   # the installer reports canonical paths
        self.with_skills()
        self.link_everything()
        before, started = xcrun_cache(), time.monotonic()
        for command, code in (('plan', 0), ('doctor', 1)):
            with self.subTest(command=command, dev=dev):
                result = self.run_install(command, wrapper=self.sandbox(
                    deny_exec=('/usr/bin/git', '/usr/bin/python3', '/usr/bin/xcrun')))
                out = result.stdout + result.stderr
                self.assertEqual(result.returncode, code, out)
                for noise in ("couldn't create cache file", 'Operation not permitted', 'xcrun'):
                    self.assertNotIn(noise, out)
                lines = result.stdout.splitlines()
                self.assertTrue(any(l.startswith('ok       tools     python3 3.') and dev in l
                                    for l in lines), result.stdout)
                self.assertTrue(any(l.startswith('ok       tools     git 2.') and dev in l
                                    for l in lines), result.stdout)
                self.assertIn(f'{len(DECLARED)} declared links in place', result.stdout)
                self.assertIn('2 skill links to create, 0 retired links to remove', result.stdout)
        self.assert_cache_unchanged(before, time.monotonic() - started)

    def assert_cache_unchanged(self, before, duration):
        """The write-deny profile is the proof; this equality is a cross-check.
        Other processes in the session update the same cache, so when it
        changed, an idle control window of the same length decides: if the
        cache moves with no installer running either, only this check is
        skipped, with the reason."""
        after = xcrun_cache()
        if after == before:
            return
        idle = xcrun_cache()
        time.sleep(max(duration, 1.0))
        if xcrun_cache() != idle:
            with self.subTest(check='xcrun cache equality'):
                self.skipTest(f'xcrun cache also changed in an idle {duration:.1f}s control '
                              'window; another process is writing it')
            return
        self.assertEqual(after, before, 'xcrun cache changed, and it was quiet without the installer')

    def assert_shim_spelling(self, path_env, dev=None):
        if dev:
            self.env['DEVELOPER_DIR'] = dev
        self.env['PATH'] = path_env
        expected = os.path.realpath(dev or developer_dir())
        result = self.run_install('plan', wrapper=self.sandbox(
            deny_exec=('/usr/bin/git', '/usr/bin/python3', '/usr/bin/xcrun')))
        out = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, out)
        self.assertNotIn('Operation not permitted', out)
        lines = result.stdout.splitlines()
        for tool in ('git 2.', 'python3 3.'):
            self.assertTrue(any(l.startswith(f'ok       tools     {tool}') and expected in l
                                for l in lines), result.stdout)

    def shim_links(self):
        links = self.root / 'shim links'
        links.mkdir()
        (links / 'git').symlink_to('/usr/bin/git')
        (links / 'python3').symlink_to('/usr/bin/python3')
        return links

    def layouts(self):
        found = [None]
        for dev in ('/Applications/Xcode.app/Contents/Developer', '/Library/Developer/CommandLineTools'):
            if os.path.isfile(dev + '/usr/bin/git') and os.path.isfile(dev + '/usr/bin/python3'):
                found.append(dev)
        return found

    def test_f14_redundant_slash_reaches_the_developer_dir(self):
        for dev in self.layouts():
            with self.subTest(dev=dev):
                self.assert_shim_spelling('/usr/bin//:/bin', dev)

    def test_f14_symlinked_shim_dir_reaches_the_developer_dir(self):
        links = self.shim_links()
        for dev in self.layouts():
            with self.subTest(dev=dev):
                self.assert_shim_spelling(f'{links}:/usr/bin:/bin', dev)

    def test_f14_other_spellings_with_an_unmappable_developer_dir(self):
        marker = self.marker_dotbot()
        self.env['DEVELOPER_DIR'] = str(self.root / 'no developer dir')
        for path_env in ('/usr/bin//:/bin', f'{self.shim_links()}:/usr/bin:/bin'):
            with self.subTest(path=path_env):
                self.env['PATH'] = path_env
                result = self.run_install('plan', wrapper=self.sandbox(
                    deny_exec=('/usr/bin/git', '/usr/bin/python3', '/usr/bin/xcrun')))
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('is an xcrun shim', result.stderr)
                self.assertNotIn('not the top of a git checkout', result.stderr)
                self.assertFalse(marker.exists())

    def test_cold_home_with_the_selected_developer_dir(self):
        self.assert_clean_run(developer_dir())

    def test_xcode_layout(self):
        dev = '/Applications/Xcode.app/Contents/Developer'
        if not os.path.isfile(dev + '/usr/bin/git'):
            self.skipTest('no Xcode.app')
        self.env['DEVELOPER_DIR'] = dev
        self.assert_clean_run(dev)

    def test_command_line_tools_layout(self):
        dev = '/Library/Developer/CommandLineTools'
        if not os.path.isfile(dev + '/usr/bin/git'):
            self.skipTest('no Command Line Tools')
        self.env['DEVELOPER_DIR'] = dev
        self.assert_clean_run(dev)

    def test_unmappable_developer_dir_never_starts_a_shim(self):
        marker = self.marker_dotbot()
        self.env['DEVELOPER_DIR'] = str(self.root / 'no developer dir')
        result = self.run_install('plan', wrapper=self.sandbox(
            deny_exec=('/usr/bin/git', '/usr/bin/python3', '/usr/bin/xcrun')))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('/usr/bin/git is an xcrun shim', result.stderr)
        self.assertIn('xcode-select', result.stderr)
        self.assertNotIn('Operation not permitted', result.stdout + result.stderr)
        self.assertFalse(marker.exists())

    def test_unmappable_python_skips_dotbot(self):
        marker = self.marker_dotbot()
        dev = self.root / 'git only developer dir'
        (dev / 'usr' / 'bin').mkdir(parents=True)
        stub(dev / 'usr' / 'bin', 'git', f'exec "{developer_dir()}/usr/bin/git" "$@"')
        self.env['DEVELOPER_DIR'] = str(dev)
        result = self.run_install('plan', wrapper=self.sandbox(
            deny_exec=('/usr/bin/git', '/usr/bin/python3', '/usr/bin/xcrun')))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertTrue(any(l.startswith('FAIL     tools     python3') and 'xcrun shim' in l
                            for l in result.stdout.splitlines()), result.stdout)
        self.assertIn('links not checked: no usable python3', result.stdout)
        self.assertNotIn('Operation not permitted', result.stdout + result.stderr)
        self.assertFalse(marker.exists())

    def test_a_non_shim_choice_on_path_is_kept(self):
        bin_dir = self.stub_dir()
        stub(bin_dir, 'git', f'exec "{developer_dir()}/usr/bin/git" "$@"')
        self.env['PATH'] = f'{bin_dir}:/usr/bin:/bin'
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f'({bin_dir}/git)', result.stdout)


class GitTraceTests(test_guards.DotbotPinTests):
    """Every git call runs with tracing off, wherever the target comes from."""

    TRACE_VARS = ('GIT_TRACE', 'GIT_TRACE_SETUP', 'GIT_TRACE2', 'GIT_TRACE2_EVENT', 'GIT_TRACE2_PERF')

    def snapshot(self, directory):
        info = os.stat(directory)
        return sorted(os.listdir(directory)), info.st_mtime_ns, info.st_ctime_ns

    def traced(self, where):
        targets = {var: where / f'{var.lower()}.log' for var in self.TRACE_VARS}
        self.env.update({var: str(path) for var, path in targets.items()})
        return list(targets.values())

    def traced_by_config(self, where):
        config = self.root / 'traced gitconfig'
        targets = [where / name for name in ('cfg-normal', 'cfg-perf', 'cfg-event')]
        config.write_text('[trace2]\n'
                          f'\tnormalTarget = {targets[0]}\n\tperfTarget = {targets[1]}\n'
                          f'\teventTarget = {targets[2]}\n')
        self.env['GIT_CONFIG_GLOBAL'] = str(config)
        return targets

    def assert_untraced(self, targets, where):
        before = self.snapshot(where)
        for command, code in (('plan', 0), ('doctor', 1)):
            with self.subTest(command=command, where=str(where)):
                result = self.run_install(command)
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                self.assertIn('dotbot submodule at the pinned commit', result.stdout)
                for target in targets:
                    self.assertFalse(target.exists(), f'git traced to {target}')
                self.assertEqual(self.snapshot(where), before)

    def test_inherited_trace_targets_in_home_and_checkout(self):
        self.make_submodule()
        for where in (self.home, self.repo):
            self.assert_untraced(self.traced(where), where)

    def test_trace2_targets_from_git_config(self):
        self.make_submodule()
        for where in (self.home, self.repo):
            self.assert_untraced(self.traced_by_config(where), where)

    def test_checkout_guard_runs_untraced(self):
        nested = self.repo / 'nested copy'
        self.make_checkout(nested, git=False)
        targets = self.traced(self.home) + self.traced_by_config(self.home)
        result = self.run_install('plan', repo=nested)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        for target in targets:
            self.assertFalse(target.exists(), f'git traced to {target}')

    def test_mismatched_pin_stops_untraced(self):
        targets = self.traced(self.home) + self.traced_by_config(self.home)
        self.test_mismatched_pin_stops_before_dotbot()
        for target in targets:
            self.assertFalse(target.exists(), f'git traced to {target}')


def real_tool(name):
    """The real executable a fresh machine would run for `name`."""
    if DARWIN:
        return os.path.join(os.path.realpath(developer_dir()), 'usr', 'bin', name)
    return shutil.which(name, path='/usr/bin:/bin')


class SelectionTests(InstallCase):
    """F14 and F18 on every OS: selection does not depend on how PATH spells a
    directory, on the working directory, on CDPATH or on shell functions."""

    def relbin(self):
        relbin = self.root / 'relbin'
        relbin.mkdir()
        for name in ('git', 'python3'):
            stub(relbin, name, f'exec "{real_tool(name)}" "$@"')
        return relbin

    def test_caller_relative_path_entry_matches_the_absolute_one(self):
        relbin = self.relbin()
        self.env['PATH'] = f'{relbin}:/usr/bin:/bin'
        absolute = self.run_install('plan')
        self.assertEqual(absolute.returncode, 0, absolute.stdout + absolute.stderr)
        self.assertIn(f'({relbin}/git)', absolute.stdout)
        for cdpath in (None, str(self.decoy())):
            with self.subTest(cdpath=cdpath):
                self.env['PATH'] = 'relbin:/usr/bin:/bin'
                if cdpath:
                    self.env['CDPATH'] = cdpath
                relative = self.run_install('plan', cwd=self.root)
                self.assertEqual(relative.returncode, 0, relative.stdout + relative.stderr)
                self.assertEqual(relative.stdout, absolute.stdout)

    def decoy(self):
        decoy = self.root / 'decoy'
        (decoy / self.repo.name / 'install.d').mkdir(parents=True)
        (decoy / 'relbin').mkdir()
        return decoy

    def test_cdpath_does_not_move_the_checkout(self):
        control = self.run_install('plan', cwd=self.root, script=f'{self.repo.name}/install')
        self.assertEqual(control.returncode, 0, control.stdout + control.stderr)
        self.env['CDPATH'] = str(self.decoy())
        for command, code in (('plan', 0), ('doctor', 1)):
            with self.subTest(command=command):
                result = self.run_install(command, cwd=self.root, script=f'{self.repo.name}/install')
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)
                self.assertEqual(result.stdout.splitlines()[0], f'== dotfiles {command} ({self.repo})')
        self.assertEqual(result.stdout.replace('doctor', 'plan').splitlines()[0],
                         control.stdout.splitlines()[0])

    def test_an_exported_git_function_is_not_selected(self):
        self.env['BASH_FUNC_git%%'] = '() {  echo hijacked; return 1\n}'
        result = self.run_install('plan')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('hijacked', result.stdout + result.stderr)
        self.assertTrue(any(l.startswith('ok       tools     git 2.') and '(/' in l
                            for l in result.stdout.splitlines()), result.stdout)


def fsmonitor_supported():
    probe = subprocess.run(['git', 'fsmonitor--daemon', 'status'], capture_output=True, text=True,
                           cwd=REPO_DIR)
    return 'not supported' not in (probe.stdout + probe.stderr)


REPO_DIR = Path(__file__).resolve().parents[2]


@unittest.skipUnless(fsmonitor_supported(), "git's builtin fsmonitor is not available here")
class FsmonitorTests(test_guards.DotbotPinTests):
    """F16: no read-only git call starts the fsmonitor daemon, whatever scope
    turns it on, and none rewrites the index."""

    def git_dirs(self):
        return [self.repo / '.git', self.repo / 'dotbot' / '.git']

    def stop_daemons(self):
        for repo in (self.repo, self.repo / 'dotbot'):
            subprocess.run(GIT_ENVLESS + ['-C', str(repo), 'fsmonitor--daemon', 'stop'],
                           capture_output=True)

    def assert_no_daemon(self, expected):
        self.addCleanup(self.stop_daemons)
        for command, code in expected:
            with self.subTest(command=command):
                result = self.run_install(command)
                self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        for git_dir in self.git_dirs():
            self.assertEqual([p.name for p in git_dir.iterdir() if p.name.startswith('fsmonitor--daemon')],
                             [], f'fsmonitor daemon state in {git_dir}')
        for repo in (self.repo, self.repo / 'dotbot'):
            status = subprocess.run(GIT_ENVLESS + ['-C', str(repo), 'fsmonitor--daemon', 'status'],
                                    capture_output=True, text=True)
            self.assertNotEqual(status.returncode, 0, status.stdout)

    def test_fsmonitor_in_the_home_gitconfig(self):
        self.make_submodule()
        (self.home / '.gitconfig').write_text('[core]\n\tfsmonitor = true\n')
        self.assert_no_daemon((('plan', 4), ('doctor', 1)))

    def test_fsmonitor_from_git_config_count(self):
        self.make_submodule()
        self.env.update(GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.fsmonitor', GIT_CONFIG_VALUE_0='true')
        self.assert_no_daemon((('plan', 0), ('doctor', 1)))

    def test_fsmonitor_in_the_repository_config(self):
        self.make_submodule()
        self.git(self.repo, 'config', 'core.fsmonitor', 'true')
        self.assert_no_daemon((('plan', 0), ('doctor', 1)))

    def test_a_stat_dirty_tree_keeps_the_index(self):
        self.make_submodule()
        tracked = self.repo / 'bash' / '.bashrc'
        stamp = tracked.stat().st_mtime + 5
        os.utime(tracked, (stamp, stamp))
        index = self.repo / '.git' / 'index'
        before = (index.stat().st_ino, index.stat().st_mtime_ns)
        for command in ('plan', 'doctor'):
            self.run_install(command)
        self.assertEqual((index.stat().st_ino, index.stat().st_mtime_ns), before)
        self.git(self.repo, 'status', '--porcelain')       # control: plain git status rewrites it
        self.assertNotEqual((index.stat().st_ino, index.stat().st_mtime_ns), before)


GIT_ENVLESS = ['env', '-u', 'GIT_DIR', 'git']


if __name__ == '__main__':
    unittest.main()
