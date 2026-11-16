"""No SSH server: fake ssh executes only inside a disposable HOME/root."""
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'remote'))
import pack


class TransportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.home = self.base / 'account home'
        self.home.mkdir(mode=0o700)
        self.store = self.home / 'portable root'
        self.shims = self.base / 'shims'
        self.shims.mkdir()
        self.log = self.base / 'calls'
        infocmp = self.shims / 'infocmp'
        infocmp.write_text('#!/bin/sh\nif [ -n "${FAKE_TERMINFO-}" ]; then [ "$1" = "$FAKE_TERMINFO" ]; else exec /usr/bin/infocmp "$@"; fi\n')
        infocmp.chmod(0o755)
        self.policy = self.base / 'hosts.json'
        self.policy.write_text(json.dumps({'schema': 1, 'hosts': {'fixture': {
            'target': 'fixture.invalid', 'class': 'personal', 'transport': 'ssh',
            'root': str(self.store), 'locale': 'en_US.UTF-8', 'storage': 'persistent',
            'persist': False, 'approved': True, 'user': None, 'port': 22}}}))
        self.policy.chmod(0o600)
        for name in ['.bashrc', '.bash_profile', '.profile', '.gitconfig', '.env']:
            (self.home / name).write_text('DO NOT SOURCE OR CHANGE\n')
        self.before = {p.name: p.read_bytes() for p in self.home.iterdir()}
        ssh = self.shims / 'ssh'
        ssh.write_text('''#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['FAKE_LOG'], 'a') as log: log.write(json.dumps(args)+'\\n')
assert args[0:2] == ['-F', '/dev/null']
assert 'ClearAllForwardings=yes' in args and 'StrictHostKeyChecking=yes' in args
assert args[-2] == 'fixture.invalid'
if os.environ.get('FAKE_SSH_ERROR'):
    print(os.environ['FAKE_SSH_ERROR'], file=sys.stderr)
    sys.exit(255)
if os.environ.get('FAKE_NOISE'):
    print('unexpected startup output', flush=True)
body = sys.stdin.buffer.read() if '-T' in args else b''
if os.environ.get('FAKE_UPLOAD') == 'corrupt' and body: body = body[:-1]+bytes([body[-1]^1])
if os.environ.get('FAKE_UPLOAD') == 'interrupt' and body: body = body[:100]
with open(os.environ['FAKE_LOG'] + '.bytes', 'a') as log: log.write(str(len(body))+'\\n')
if '-tt' in args:
    body = b"printf 'SESSION_OK\\\\n'; printf '%s\\\\n' \\\"$HOME\\\"; test -z \\\"${BASH_ENV-}${LD_PRELOAD-}${HCMUX_SESSION-}\\\" || exit 91; exit 7\\n"
if '-tt' in args:
    if os.environ.get('FAKE_CORRUPT_BEFORE_LAUNCH'):
        for p in Path(os.environ['FAKE_HOME']).glob('portable root/releases/*/bin/enter'): p.write_text('corrupt')
    if os.environ.get('FAKE_REMOTE_PATH'):
        body = b'command -v remote-only-tool || exit 94; ' + body
    body = b'printf "TERM=%s\\\\n" "$TERM"; ' + body
    if os.environ.get('FAKE_CHECK_PATH'):
        body = b'command -v fixture-tool || exit 92; case "$PATH" in *' + os.environ['FAKE_CHECK_PATH'].encode() + b'*) ;; *) exit 93;; esac; ' + body
env = dict(os.environ, HOME=os.environ['FAKE_HOME'])
if os.environ.get('FAKE_REMOTE_PATH'): env['PATH'] = os.environ['FAKE_REMOTE_PATH'] + ':' + env['PATH']
shell = os.environ.get('FAKE_LOGIN_SHELL', '/bin/bash')
flags = {'bash': ['--noprofile', '--norc'], 'fish': ['--no-config'], 'zsh': ['-f'], 'csh': ['-f'], 'tcsh': ['-f']}.get(Path(shell).name, [])
result = subprocess.run([shell, *flags, '-c', args[-1]], input=body, env=env)
sys.exit(result.returncode)
''')
        ssh.chmod(0o755)
        mosh = self.shims / 'mosh'
        mosh.write_text('#!/bin/sh\necho forbidden-mosh >> "$FAKE_LOG"\nexit 99\n')
        mosh.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.shims) + ':' + os.environ['PATH'],
                        FAKE_LOG=str(self.log), FAKE_HOME=str(self.home), HCMUX_SESSION='poison')

    def cli(self, *args, **env):
        return subprocess.run([sys.executable, str(ROOT / 'remote/bin/envi-remote'), *args,
                               '--policy', str(self.policy)], env=dict(self.env, **env),
                              capture_output=True, timeout=60)

    def stage(self, artifact=None, operation='stage'):
        artifact = artifact or pack.build(ROOT, allow_dirty=True)
        return subprocess.run(['/bin/bash', str(ROOT / 'remote/bootstrap.sh'), operation,
                               str(self.store), artifact.digest, artifact.archive_hash,
                               artifact.manifest.decode(), 'en_US.UTF-8', 'persistent'],
                              input=artifact.archive, capture_output=True, env=self.env)

    def test_explicit_ssh_home_unchanged_exit_preserved_and_warm_reuse(self):
        result = self.cli('fixture', '--transport', 'ssh', '--allow-dirty')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertIn(b'SESSION_OK', result.stdout)
        self.assertIn(str(self.home).encode(), result.stdout)
        for name, data in self.before.items():
            self.assertEqual((self.home / name).read_bytes(), data)
        self.assertFalse((self.home / '.bash_history').exists())
        releases = list((self.store / 'releases').iterdir())
        self.assertEqual(len(releases), 1)
        mtime = releases[0].stat().st_mtime_ns
        result = self.cli('fixture', '--allow-dirty')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(releases[0].stat().st_mtime_ns, mtime)
        self.assertFalse(list((self.store / 'staging').iterdir()))
        self.assertFalse(list((self.store / 'locks').iterdir()))
        transfers = [int(n) for n in Path(str(self.log) + '.bytes').read_text().splitlines()]
        self.assertEqual(sum(n > 0 for n in transfers), 1, 'warm connect must not retransmit archive')

    def test_unknown_and_malformed_fail_before_ssh(self):
        for alias in ['unknown', 'bad;command', '-option']:
            self.assertNotEqual(self.cli(alias).returncode, 0)
        self.assertFalse(self.log.exists())

    def test_plan_and_hosts_never_connect(self):
        result = self.cli('plan', 'fixture', '--allow-dirty')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['transport'], 'ssh')
        self.assertEqual(self.cli('hosts').stdout, b'fixture\n')
        self.assertFalse(self.log.exists())

    def test_policy_permissions_and_schema_fail(self):
        self.policy.chmod(0o644)
        self.assertNotEqual(self.cli('fixture').returncode, 0)
        self.policy.chmod(0o600)
        self.policy.write_text('{"schema":9,"hosts":{}}')
        self.assertNotEqual(self.cli('fixture').returncode, 0)
        self.assertFalse(self.log.exists())

    def test_mosh_is_not_a_silent_fallback(self):
        result = self.cli('fixture', '--transport', 'mosh')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_corrupt_and_interrupted_upload_never_activate(self):
        for failure in ['corrupt', 'interrupt']:
            result = self.cli('fixture', '--allow-dirty', FAKE_UPLOAD=failure)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(b'SESSION_OK', result.stdout)
            self.assertFalse(list((self.store / 'releases').iterdir()))
            self.assertFalse(list((self.store / 'staging').iterdir()))

    def test_contaminated_stdout_fails_before_upload(self):
        result = self.cli('fixture', '--allow-dirty', FAKE_NOISE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(list(self.store.glob('releases/*')))
        self.assertNotIn(b'unexpected startup output', result.stderr)

    def test_symlink_root_refused(self):
        self.store.symlink_to(self.base, target_is_directory=True)
        result = self.stage()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'symlink', result.stderr)

    def test_shared_writable_root_refused(self):
        self.store.mkdir(mode=0o777)
        self.store.chmod(0o777)
        self.assertNotEqual(self.stage().returncode, 0)

    def test_lock_never_stolen_and_corrupt_cache_never_runs(self):
        a = pack.build(ROOT, allow_dirty=True)
        self.assertEqual(self.stage(a).returncode, 0)
        lock = self.store / 'locks' / a.digest
        lock.mkdir()
        result = self.stage(a)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.exists())
        lock.rmdir()
        (self.store / 'releases' / a.digest / 'bin/enter').write_text('corrupt')
        self.assertNotEqual(self.stage(a).returncode, 0)

    def test_temporary_cleanup_only_own_child(self):
        data = json.loads(self.policy.read_text())
        data['hosts']['fixture']['storage'] = 'temporary'
        data['hosts']['fixture']['class'] = 'company'
        self.policy.write_text(json.dumps(data))
        self.store.mkdir(mode=0o700)
        sentinel = self.store / 'keep'
        sentinel.write_text('unrelated')
        result = self.cli('fixture', '--allow-dirty')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(list(self.store.iterdir()), [sentinel])

    def test_invalid_locale_rejected_before_upload(self):
        data = json.loads(self.policy.read_text())
        data['hosts']['fixture']['locale'] = 'not_a_real_locale'
        self.policy.write_text(json.dumps(data))
        result = self.cli('fixture', '--allow-dirty')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.store.exists())

    def test_cached_hardlink_and_writable_directory_refused(self):
        a = pack.build(ROOT, allow_dirty=True)
        self.assertEqual(self.stage(a).returncode, 0)
        release = self.store / 'releases' / a.digest
        os.link(release / 'bin/enter', self.base / 'outside-link')
        self.assertNotEqual(self.stage(a).returncode, 0)
        (self.base / 'outside-link').unlink()
        (release / 'bin').chmod(0o777)
        self.assertNotEqual(self.stage(a).returncode, 0)

    def test_publish_failure_never_activates_and_releases_lock(self):
        # Fault injection executes the trusted bootstrap locally, never a host.
        mv = self.shims / 'mv'
        mv.write_text('#!/bin/sh\nexit 1\n')
        mv.chmod(0o755)
        result = self.stage()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(list((self.store / 'releases').iterdir()))
        self.assertFalse(list((self.store / 'staging').iterdir()))
        self.assertFalse(list((self.store / 'locks').iterdir()))

    def test_shell_bash32_syntax_and_no_services(self):
        scripts = [ROOT / 'remote/bootstrap.sh', *list((ROOT / 'remote/profile/bin').iterdir()),
                   ROOT / 'remote/profile/shell/bashrc']
        for script in scripts:
            result = subprocess.run(['/bin/bash', '-n', str(script)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        text = (ROOT / 'remote/profile/shell/bashrc').read_text()
        for forbidden in ['curl ', 'wget ', 'npm ', 'brew ', 'systemctl ', 'source ', 'eval ']:
            self.assertNotIn(forbidden, '\n'.join(l for l in text.splitlines() if not l.startswith('#')))


if __name__ == '__main__':
    unittest.main()
