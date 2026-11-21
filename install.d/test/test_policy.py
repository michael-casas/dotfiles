"""Policy for the tracked dotbot configs: links only, never anything that replaces."""
import configparser
import subprocess
import unittest

from support import CONFIGS, REPO, links, load

ALLOWED_DIRECTIVES = {'defaults', 'link', 'create', 'clean'}
FORBIDDEN_KEYS = {'force', 'relink', 'backup', 'if', 'ignore-missing', 'shell', 'plugins'}
PINNED = 'a7fe585f087617f5d897754b970d1088af50084c'  # dotbot v1.24.1


def keys(value):
    """Every mapping key at any depth."""
    if isinstance(value, dict):
        for key, inner in value.items():
            yield key
            yield from keys(inner)
    elif isinstance(value, list):
        for inner in value:
            yield from keys(inner)


class PolicyTests(unittest.TestCase):
    def test_every_config_is_a_list_of_allowed_directives(self):
        for name in CONFIGS:
            tasks = load(name)
            self.assertIsInstance(tasks, list, name)
            for task in tasks:
                self.assertIsInstance(task, dict, name)
                self.assertLessEqual(set(task), ALLOWED_DIRECTIVES, name)

    def test_no_option_that_replaces_or_runs_anything(self):
        for name in CONFIGS:
            used = set(keys(load(name))) & FORBIDDEN_KEYS
            self.assertEqual(used, set(), f'{name} uses {sorted(used)}')

    def test_every_source_exists(self):
        for name in CONFIGS:
            for dest, source in links(name):
                self.assertTrue((REPO / source).exists(), f'{name}: {dest} -> missing {source}')

    def test_no_destination_is_declared_twice(self):
        seen = {}
        for name in CONFIGS:
            for dest, _ in links(name):
                key = dest.replace('$XDG_CONFIG_HOME', '~/.config').rstrip('/')
                self.assertNotIn(key, seen, f'{dest} in {name} and {seen.get(key)}')
                seen[key] = name

    def managed_paths(self, name):
        """Every path a config makes dotbot write to or clean: link
        destinations and clean and create roots (list or mapping form)."""
        paths = [dest for dest, _ in links(name)]
        for task in load(name):
            for directive, data in task.items():
                if directive in ('clean', 'create'):
                    paths.extend(data)
        return paths

    def test_managed_paths_stay_under_home_without_dot_components(self):
        for name in CONFIGS:
            for path in self.managed_paths(name):
                self.assertTrue(path == '~' or path.startswith(('~/', '$XDG_CONFIG_HOME/')),
                                f'{name}: {path}')
                for part in ('.', '..'):
                    self.assertNotIn(part, path.split('/'), f'{name}: {path}')

    def test_sources_under_bin_are_tracked_executable(self):
        for name in CONFIGS:
            for _, source in links(name):
                if 'bin' not in source.split('/')[:-1]:
                    continue
                mode = subprocess.run(['git', '-C', str(REPO), 'ls-files', '-s', '--', source],
                                      capture_output=True, text=True, check=True).stdout[:6]
                self.assertEqual(mode, '100755', f'{source} must be tracked as executable')

    def test_workflow_actions_are_pinned_to_full_commits(self):
        workflows = sorted((REPO / '.github' / 'workflows').glob('*.yml'))
        self.assertTrue(workflows)
        for workflow in workflows:
            for line in workflow.read_text().splitlines():
                ref = line.strip().removeprefix('- ').strip()
                if not ref.startswith('uses:'):
                    continue
                action = ref.split()[1]
                self.assertRegex(action, r'^[\w.-]+/[\w.-]+@[0-9a-f]{40}$', f'{workflow.name}: {line}')
                self.assertRegex(ref, r'# v\d+\.\d+\.\d+$', f'{workflow.name}: name the release: {line}')

    def test_dotbot_submodule_is_pinned_and_ignores_dirty(self):
        modules = configparser.ConfigParser()
        modules.read(REPO / '.gitmodules')
        section = 'submodule "dotbot"'
        self.assertEqual(modules[section]['path'], 'dotbot')
        self.assertEqual(modules[section]['ignore'], 'dirty')
        staged = subprocess.run(['git', '-C', str(REPO), 'ls-files', '-s', '--', 'dotbot'],
                                capture_output=True, text=True, check=True).stdout.split()
        self.assertEqual(staged[:2], ['160000', PINNED])


if __name__ == '__main__':
    unittest.main()
