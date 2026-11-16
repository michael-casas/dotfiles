"""Critic-round regressions. All transports are local shims, never SSH servers."""
import json
import os
import pwd
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from test_transport import TransportTest
from test_probe import cli
import pack


class RevisionTest(TransportTest):
    # Share fixture helpers, not the inherited tests (loader below selects these).
    def update(self, **changes):
        data = json.loads(self.policy.read_text())
        data['hosts']['fixture'].update(changes)
        self.policy.write_text(json.dumps(data))

    def no_upload(self):
        p = Path(str(self.log) + '.bytes')
        self.assertTrue(not p.exists() or all(n == '0' for n in p.read_text().splitlines()))

    def test_revision_login_shells(self):
        for shell in ['/bin/bash', '/bin/sh', '/bin/zsh', shutil.which('fish'), '/bin/csh', '/bin/tcsh']:
            if not shell or not Path(shell).exists():
                continue
            with self.subTest(shell=shell):
                result = self.cli('fixture', '--allow-dirty', FAKE_LOGIN_SHELL=shell)
                self.assertEqual(result.returncode, 7, result.stderr)
                self.assertIn(b'SESSION_OK', result.stdout)

    def test_revision_ssh_errors(self):
        for text in ['Host key verification failed.', 'Permission denied (publickey).',
                     'Could not resolve hostname fixture.invalid: unknown host', 'Connection timed out',
                     'ssh: Could not resolve hostname fixture.invalid: Name or service not known',
                     'ssh: connect to host fixture.invalid port 22: Connection refused',
                     'Connection closed by fixture.invalid port 22',
                     'kex_exchange_identification: Connection closed by remote host',
                     'No ED25519 host key is known for fixture.invalid and you have requested strict checking.',
                     'ssh: connect to host fixture.invalid port 22: Operation timed out',
                     'ssh: connect to host fixture.invalid port 22: Host is down',
                     'ssh: connect to host fixture.invalid port 22: Connection reset by peer',
                     'ssh: Could not resolve hostname fixture.invalid: nodename nor servname provided, or not known',
                     'ssh: Could not resolve hostname fixture.invalid: No address associated with nodename',
                     'ssh: Could not resolve hostname fixture.invalid: Non-recoverable failure in name resolution',
                     'Connection timed out during banner exchange',
                     'Connection reset by 192.0.2.1 port 22',
                     'Connection closed by 2001:db8::1 port 22',
                     'Connection to fixture.invalid closed by remote host.']:
            with self.subTest(text=text):
                r = self.cli('fixture', '--allow-dirty', FAKE_SSH_ERROR=text)
                self.assertEqual(r.returncode, 21)
                self.assertIn(text.encode(), r.stderr)
                self.assertIn(b'ssh -F /dev/null', r.stderr)
                self.no_upload()

    def test_revision_ssh_errors_real_client_forms(self):
        # N6: with no policy user, ssh prefixes the LOCAL login name.
        # N7: a banner timeout ends with "Connection to <peer> port N timed out".
        # N8: ssh prints the hostname lowercased.
        local = pwd.getpwuid(os.getuid()).pw_name
        cases = [(None, f'{local}@fixture.invalid: Permission denied (publickey).'),
                 (None, 'Connection to 192.0.2.1 port 22 timed out'),
                 (None, 'Connection to fixture.invalid port 22 timed out')]
        for _, text in cases:
            with self.subTest(text=text):
                r = self.cli('fixture', '--allow-dirty', FAKE_SSH_ERROR=text)
                self.assertEqual(r.returncode, 21)
                self.assertIn(text.encode(), r.stderr)
                self.no_upload()
        policy = dict(json.loads(self.policy.read_text())['hosts']['fixture'], target='Fixture.Invalid')
        for text in ['ssh: connect to host fixture.invalid port 22: Connection refused',
                     f'{local}@fixture.invalid: Permission denied (publickey).',
                     'Connection to fixture.invalid port 22 timed out']:
            with self.subTest(mixed_case=text):
                self.assertTrue(cli.ssh_client_error(policy, text))
        for text in ['someone-else@fixture.invalid: Permission denied (publickey).',
                     'Connection to other.invalid port 22 timed out',
                     'Connection to fixture.invalid port 2222 timed out']:
            with self.subTest(withheld=text):
                self.assertFalse(cli.ssh_client_error(policy, text))

    def test_revision_ssh_errors_pin_explicit_policy(self):
        self.update(user='fixture-user', port=2222)
        for text in ['fixture-user@fixture.invalid: Permission denied (publickey,password,keyboard-interactive,hostbased,gssapi-with-mic).',
                     'ssh: connect to host fixture.invalid port 2222: Operation timed out',
                     'Connection reset by 192.0.2.1 port 2222',
                     'No ED25519 host key is known for [fixture.invalid]:2222 and you have requested strict checking.']:
            with self.subTest(text=text):
                r = self.cli('fixture', '--allow-dirty', FAKE_SSH_ERROR=text)
                self.assertEqual(r.returncode, 21)
                self.assertIn(text.encode(), r.stderr)
                self.no_upload()

    def test_revision_lock_and_verify_diagnostics(self):
        a = pack.build(cli.ROOT, allow_dirty=True)
        self.assertEqual(self.stage(a).returncode, 0)
        release = self.store / 'releases' / a.digest
        shutil.rmtree(release)
        lock = self.store / 'locks' / a.digest
        lock.mkdir()
        r = self.cli('fixture', '--allow-dirty')
        self.assertEqual(r.returncode, 24, r.stderr)
        self.assertIn(b'release locked; never steal a stale lock', r.stderr)
        lock.rmdir()
        self.assertEqual(self.stage(a).returncode, 0)
        (release / 'bin/enter').write_text('corrupt')
        r = self.cli('fixture', '--allow-dirty')
        self.assertEqual(r.returncode, 25, r.stderr)
        self.assertIn(b'cached release invalid', r.stderr)

    def test_revision_symlink_policy(self):
        actual = self.base / 'actual.json'
        self.policy.rename(actual)
        self.policy.symlink_to(actual)
        self.assertEqual(self.cli('fixture').returncode, 20)
        self.assertFalse(self.log.exists())

    def test_revision_policy_inside_repo_and_dotdot(self):
        with tempfile.NamedTemporaryFile(dir=cli.ROOT / 'remote/test', suffix='.json') as f:
            path = Path(f.name)
            path.write_bytes(self.policy.read_bytes())
            path.chmod(0o600)
            sibling = path.parent / 'guard-fixture'
            sibling.mkdir()
            self.addCleanup(sibling.rmdir)
            for p in [path, sibling / '..' / path.name]:
                with self.subTest(path=str(p)), self.assertRaises(ValueError):
                    cli.load_policy(p)

    def test_revision_bad_roots(self):
        for root in ['/one', '/a/../b', '/a//b', '/a/b/', '/a/./b', '/volumeN/@tmp/fixture']:
            self.update(root=root)
            self.assertEqual(self.cli('fixture').returncode, 20)
        self.assertFalse(self.log.exists())
        self.no_upload()

    def test_revision_reserved_aliases(self):
        data = json.loads(self.policy.read_text())
        for reserved in ['plan', 'hosts']:
            data['hosts'][reserved] = data['hosts']['fixture']
            self.policy.write_text(json.dumps(data))
            self.assertEqual(self.cli('hosts').returncode, 20)
        self.assertFalse(self.log.exists())

    def test_revision_missing_cached_never_uploads(self):
        r = self.cli('fixture', '--use-cached', '--allow-dirty')
        self.assertEqual(r.returncode, 25, r.stderr)
        self.assertIn(b'cached release missing', r.stderr)
        self.no_upload()

    def test_revision_unrecognized_stderr_is_withheld(self):
        from unittest.mock import patch
        result = subprocess.CompletedProcess([], 23, stdout=b'', stderr=b'private server text')
        with patch.object(cli.subprocess, 'run', return_value=result):
            with self.assertRaises(cli.RemoteError) as caught:
                cli.control(json.loads(self.policy.read_text())['hosts']['fixture'], '', ['inspect'])
        self.assertEqual(caught.exception.code, 22)
        self.assertNotIn('private server text', str(caught.exception))

    def test_revision_remote_exit255_stderr_is_withheld(self):
        from unittest.mock import patch
        for text in ['private remote output', 'Host key verification failed. private remote suffix',
                     'Permission denied (publickey). private remote suffix',
                     'tok_9f8e7d6c5b4a: Permission denied (AKIA-SECRET-VALUE).',
                     'Connection closed by ' + 'a' * 400,
                     'ssh: connect to host other.invalid port 22: Operation timed out',
                     'ssh: connect to host fixture.invalid port 2222: Connection refused',
                     'ssh: Could not resolve hostname other.invalid: unknown host',
                     'Connection to other.invalid closed by remote host.',
                     'Connection reset by 192.0.2.1 port 2222',
                     'Connection closed by other.invalid port 22',
                     'wrong-user@fixture.invalid: Permission denied (publickey).',
                     'Permission denied (unknown-method).',
                     'No SECRET host key is known for fixture.invalid and you have requested strict checking.',
                     'No ED25519 host key is known for other.invalid and you have requested strict checking.']:
            with self.subTest(text=text):
                result = subprocess.CompletedProcess([], 255, stdout=b'', stderr=text.encode())
                with patch.object(cli.subprocess, 'run', return_value=result):
                    with self.assertRaises(cli.RemoteError) as caught:
                        cli.control(json.loads(self.policy.read_text())['hosts']['fixture'], '', ['inspect'])
                self.assertEqual(caught.exception.code, 21)
                self.assertNotIn(text, str(caught.exception))
                self.assertIn('output withheld', str(caught.exception))
                self.assertIn('ssh -F /dev/null', str(caught.exception))

    def test_revision_no_terminfo_fails_before_upload(self):
        (self.shims / 'infocmp').write_text('#!/bin/sh\nexit 1\n')
        r = self.cli('fixture', '--allow-dirty')
        self.assertEqual(r.returncode, 22, r.stderr)
        self.assertIn(b'no supported terminal', r.stderr)
        self.no_upload()

    def test_revision_noexec_stops_at_inspect_without_upload(self):
        real_chmod = shutil.which('chmod')
        for location in [self.store, self.store / 'releases']:
            with self.subTest(location=location):
                if self.store.exists():
                    shutil.rmtree(self.store)
                self.log.unlink(missing_ok=True)
                # Emulate execution denial on this filesystem without mounting:
                # intercept chmod only for the tiny executable preflight fixture.
                (self.shims / 'chmod').write_text(
                    '#!/bin/bash\n' +
                    f'case "$2" in "{location}"/exec-check.*) exec "{real_chmod}" 0600 "$2" ;; esac\n' +
                    f'exec "{real_chmod}" "$@"\n')
                (self.shims / 'chmod').chmod(0o755)
                r = self.cli('fixture', '--allow-dirty')
                self.assertEqual(r.returncode, 22, r.stderr)
                self.assertIn(b'approved root is on a noexec filesystem', r.stderr)
                self.assertNotIn(b'Permission denied', r.stderr)
                self.assertEqual(len(self.log.read_text().splitlines()), 1)
                self.no_upload()
                self.assertFalse((self.store / 'staging').exists())
                self.assertFalse(list(self.store.rglob('exec-check.*')))

    def test_revision_noexec_temporary_leaves_no_child(self):
        # A deterministic preflight failure must not leave its empty temporary child behind.
        real_chmod = shutil.which('chmod')
        for suffix in ['', '/releases']:
            with self.subTest(suffix=suffix):
                if self.store.exists():
                    shutil.rmtree(self.store)
                self.log.unlink(missing_ok=True)
                (self.shims / 'chmod').write_text(
                    '#!/bin/bash\n' +
                    f'case "$2" in "{self.store}"/temporary-*{suffix}/exec-check.*) exec "{real_chmod}" 0600 "$2" ;; esac\n' +
                    f'exec "{real_chmod}" "$@"\n')
                (self.shims / 'chmod').chmod(0o755)
                r = self.cli('fixture', '--temporary', '--allow-dirty')
                self.assertEqual(r.returncode, 22, r.stderr)
                self.assertIn(b'approved root is on a noexec filesystem', r.stderr)
                self.no_upload()
                self.assertTrue(self.store.is_dir())
                self.assertEqual(list(self.store.glob('temporary-*')), [])

    def test_revision_cached_release_noexec_rechecked_before_launch(self):
        artifact = pack.build(cli.ROOT, allow_dirty=True)
        self.assertEqual(self.stage(artifact).returncode, 0)
        location = self.store / 'releases'
        real_chmod = shutil.which('chmod')
        (self.shims / 'chmod').write_text(
            '#!/bin/bash\n' +
            f'case "$2" in "{location}"/exec-check.*) exec "{real_chmod}" 0600 "$2" ;; esac\n' +
            f'exec "{real_chmod}" "$@"\n')
        (self.shims / 'chmod').chmod(0o755)
        r = self.cli('fixture', '--use-cached', '--allow-dirty')
        self.assertEqual(r.returncode, 22, r.stderr)
        self.assertIn(b'approved root is on a noexec filesystem', r.stderr)
        self.assertEqual(len(self.log.read_text().splitlines()), 1)
        self.no_upload()
        # Even a mount change after inspect is rechecked by the launch operation.
        r = self.stage(artifact, operation='launch')
        self.assertEqual(r.returncode, 23, r.stderr)
        self.assertIn(b'approved root is on a noexec filesystem', r.stderr)
        self.assertNotIn(b'Permission denied', r.stderr)
        self.assertFalse(list(self.store.rglob('exec-check.*')))
        self.assertEqual(list((self.store / 'staging').iterdir()), [])

    def test_revision_exec_preflight_cleans_up_on_success(self):
        r = self.cli('fixture', '--allow-dirty')
        self.assertEqual(r.returncode, 7, r.stderr)
        self.assertFalse(list(self.store.rglob('exec-check.*')))

    def test_revision_ssh_argv(self):
        self.update(user='fixture-user', port=2222)
        r = self.cli('fixture', '--allow-dirty')
        self.assertEqual(r.returncode, 7, r.stderr)
        for line in self.log.read_text().splitlines():
            args = json.loads(line)
            self.assertEqual(args[args.index('-p') + 1], '2222')
            self.assertEqual(args[args.index('-l') + 1], 'fixture-user')
            self.assertEqual(args[-3:-1], ['--', 'fixture.invalid'])

    def test_revision_launch_rechecks_cache(self):
        r = self.cli('fixture', '--allow-dirty', FAKE_CORRUPT_BEFORE_LAUNCH='1')
        self.assertNotEqual(r.returncode, 7)
        self.assertNotIn(b'SESSION_OK', r.stdout)
        self.assertIn(b'cached release invalid', r.stderr)

    def test_revision_digest_state_and_login_counts(self):
        a = pack.build(cli.ROOT, allow_dirty=True)
        self.assertEqual(self.cli('fixture', '--allow-dirty').returncode, 7)
        self.assertEqual(len(self.log.read_text().splitlines()), 3)
        state = self.store / 'state' / a.digest
        self.assertEqual(len(list(state.glob('session.*'))), 1)
        self.assertEqual(self.cli('fixture', '--allow-dirty').returncode, 7)
        self.assertEqual(len(self.log.read_text().splitlines()), 5)

    @unittest.skipUnless(sys.platform == 'linux', 'requires Linux setgid-directory inheritance; BSD mkdir does not inherit it')
    def test_revision_setgid_parent(self):
        self.home.chmod(0o2755)
        r = self.stage()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.store.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.store.stat().st_mode & 0o5000, 0)

    def test_revision_sticky_system_temp(self):
        # Uses actual BSD /private/tmp metadata locally; no global mode mutation.
        with tempfile.TemporaryDirectory(dir=Path('/tmp').resolve()) as name:
            self.store = Path(name) / 'owned/root'
            r = self.stage()
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_revision_extra_path_and_remote_path(self):
        extra = self.base / 'approved-bin'
        extra.mkdir(mode=0o755)
        tool = extra / 'fixture-tool'
        tool.write_text('#!/bin/sh\nexit 0\n')
        tool.chmod(0o755)
        self.update(path_extra=[str(extra)])
        remote = self.base / 'remote-bin'
        remote.mkdir()
        (remote / 'remote-only-tool').write_text('#!/bin/sh\nexit 0\n')
        (remote / 'remote-only-tool').chmod(0o755)
        r = self.cli('fixture', '--allow-dirty', FAKE_CHECK_PATH=str(extra), FAKE_REMOTE_PATH=str(remote))
        self.assertEqual(r.returncode, 7, r.stderr)
        extra.chmod(0o777)
        r = self.cli('fixture', '--allow-dirty')
        self.assertEqual(r.returncode, 22, r.stderr)
        self.assertIn(b'unsafe extra PATH', r.stderr)

    def test_revision_term_fallback(self):
        (self.shims / 'infocmp').write_text('#!/bin/sh\n[ "$1" = dumb ]\n')
        for term in ['xterm-ghostty', 'bad;term', '']:
            r = self.cli('fixture', '--allow-dirty', TERM=term, FAKE_TERMINFO='dumb')
            self.assertEqual(r.returncode, 7, r.stderr)
            self.assertIn(b'TERM=dumb', r.stdout)


def load_tests(loader, tests, pattern):
    suite = unittest.TestSuite(RevisionTest(n) for n in loader.getTestCaseNames(RevisionTest)
                               if n.startswith('test_revision_'))
    suite.addTests(loader.loadTestsFromTestCase(CleanupGuardTest))
    return suite

class CleanupGuardTest(unittest.TestCase):
    def test_temporary_launcher_rejects_broad_cleanup_target(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            r = subprocess.run(['/bin/bash', str(cli.ROOT / 'remote/profile/bin/enter'),
                                '/nonexistent-release', str(root / 'state'), 'C.UTF-8',
                                'temporary', str(root)], capture_output=True)
            self.assertEqual(r.returncode, 24)
            self.assertTrue(root.exists())
