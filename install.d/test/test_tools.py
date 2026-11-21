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
        self.with_skills()
        self.link_everything()
        before = xcrun_cache()
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
        self.assertEqual(xcrun_cache(), before, 'xcrun cache changed')

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


if __name__ == '__main__':
    unittest.main()
