"""The sandbox harness every installer test uses: a temp git checkout whose path
has a space, a temp HOME and a private probe scratch root beside them, real
/bin/bash and real dotbot as subprocesses under a minimal PATH."""
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest

from support import CONFIGS, DOTBOT, REPO, expand, links_for_this_os

DECLARED = links_for_this_os()
GIT = ['git', '-c', 'user.name=test', '-c', 'user.email=test@example.invalid',
       '-c', 'init.defaultBranch=main', '-c', 'commit.gpgsign=false',
       '-c', 'protocol.file.allow=always']


def stub(directory, name, body):
    path = directory / name
    path.write_text('#!/bin/sh\n' + body + '\n')
    path.chmod(0o755)
    return path


def marker_launcher(path, marker):
    """A dotbot launcher that records each call, then runs the pinned dotbot.
    ./install runs every launcher with the selected Python, so this is Python."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('import os, sys\n'
                    f'open({str(marker)!r}, "a").write("called\\n")\n'
                    f'os.execv(sys.executable, [sys.executable, {str(DOTBOT)!r}] + sys.argv[1:])\n')
    path.chmod(0o755)
    return path


class InstallCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles install ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / 'checkout with spaces'
        self.home = self.root / 'home'
        self.probe_root = self.root / 'probe root'
        self.home.mkdir()
        self.probe_root.mkdir()
        self.make_checkout(self.repo)
        self.env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.home), 'LC_ALL': 'C',
                    'DOTBOT_BIN': str(DOTBOT), 'PYTHONDONTWRITEBYTECODE': '1',
                    'DOTFILES_PROBE_ROOT': str(self.probe_root)}

    def tearDown(self):
        # Every probe directory is removed before ./install exits.
        self.assertEqual(list(self.probe_root.iterdir()), [])

    def make_checkout(self, repo, git=True):
        (repo / 'install.d').mkdir(parents=True)
        for name in ['install'] + CONFIGS:
            shutil.copy2(REPO / name, repo / name)
        for pattern in ('*.sh', '*.py'):
            for script in (REPO / 'install.d').glob(pattern):
                shutil.copy2(script, repo / 'install.d' / script.name)
        for _, source in DECLARED:
            path = repo / source
            if (REPO / source).is_dir():
                path.mkdir(parents=True, exist_ok=True)
                (path / 'fixture').write_text('fixture\n')
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('# fixture\n')
        if git:
            self.git(repo, 'init', '-q')
            self.git(repo, 'add', '-A')
            self.git(repo, 'commit', '-q', '-m', 'fixture')

    def git(self, repo, *args):
        return subprocess.run(GIT + ['-C', str(repo), *args], check=True, capture_output=True,
                              text=True, env={'PATH': '/usr/bin:/bin', 'HOME': str(self.root)})

    def run_install(self, *args, repo=None, wrapper=()):
        script = (repo or self.repo) / 'install'
        return subprocess.run([*wrapper, '/bin/bash', str(script), *args], cwd=self.root,
                              env=self.env, capture_output=True, text=True, timeout=120)

    def home_entries(self):
        return sorted(str(p.relative_to(self.home)) for p in self.home.rglob('*'))

    def lines(self, result, status):
        return [line for line in result.stdout.splitlines() if line.startswith(status + ' ')]

    def link_everything(self, xdg=None):
        for dest, source in DECLARED:
            path = expand(dest, self.home, xdg)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(self.repo / source)

    def stub_dir(self):
        path = self.root / 'stub bin'
        path.mkdir(exist_ok=True)
        return path

    def marker_dotbot(self, name='marker dotbot'):
        """A launcher that records each call (see marker_launcher).

        Its lib/ points at the real one, so the installer finds the same
        vendored PyYAML beside it that it finds beside the real launcher."""
        top = self.root / name
        (top / 'bin').mkdir(parents=True)
        (top / 'lib').symlink_to(DOTBOT.parents[1] / 'lib')
        self.marker = self.root / f'{name}.called'
        marker_launcher(top / 'bin' / 'dotbot', self.marker)
        self.env['DOTBOT_BIN'] = str(top / 'bin' / 'dotbot')
        return self.marker

    def stub_account_home(self, home):
        """Make the user database report `home` as this account's home."""
        bin_dir = self.stub_dir()
        if platform.system() == 'Darwin':
            stub(bin_dir, 'id', f'if [ "$1" = -P ]; then echo "u:*:501:20::0:0:U:{home}:/bin/sh"; '
                                'else exec /usr/bin/id "$@"; fi')
        else:
            stub(bin_dir, 'getent', f'echo "u:x:1000:1000::{home}:/bin/sh"')
        self.env['PATH'] = f'{bin_dir}:/usr/bin:/bin'
