#!/usr/bin/env python3
"""Closed, deterministic minimal payload. No third-party modules; no HOME reads."""
import argparse
from dataclasses import dataclass
import gzip
import hashlib
import io
from pathlib import Path
import re
import stat
import subprocess
import tarfile

ALLOWLIST = {**{f'bin/{n}': 0o755 for n in ('enter', 'shell', 'editor', 'git')},
             **{n: 0o644 for n in ('shell/bashrc', 'shell/inputrc', 'git/ui.gitconfig',
                                   'tmux/tmux.conf', 'starship/nordic.toml', 'starship/ascii.toml',
                                   'config/envi-remote/init.lua')}}
MAX_ARCHIVE = 262144
MAX_FILE = 65536
SECRET = re.compile(rb'PRIVATE KEY-----|(?:AWS_SECRET_ACCESS_KEY|[A-Z_]*(?:TOKEN|PASSWORD|SECRET))\s*=\s*[^\s]+|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16}', re.I)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def source(path):
    return 'remote/profile/' + path.replace('config/envi-remote/', 'nvim/')


def manifest_text():
    return '# envi-remote minimal schema 1\n' + ''.join(
        f'{source(p)} {p} {m:04o}\n' for p, m in sorted(ALLOWLIST.items()))


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.DEVNULL)


def check_bytes(path, data):
    if len(data) > MAX_FILE or b'\0' in data or SECRET.search(data):
        raise ValueError('oversize, binary or secret-like payload: ' + path)


@dataclass
class Artifact:
    archive: bytes
    digest: str
    manifest: bytes
    provenance: dict

    @property
    def archive_hash(self):
        return sha(self.archive)


def build(root, revision=None, allow_dirty=False):
    root = Path(root)
    dirty = bool(git(root, 'status', '--porcelain', '--untracked-files=all', '--', 'remote/profile',
                     'remote/profiles/minimal.manifest'))
    if dirty and revision is None and not allow_dirty:
        raise ValueError('payload sources are dirty; commit, select --revision, or explicitly --allow-dirty')
    worktree = revision is None and allow_dirty
    commit = git(root, 'rev-parse', '--verify', (revision or 'HEAD') + '^{commit}').decode().strip()

    def read(path, mode=None):
        if worktree:
            p = root / path
            for component in [p, *p.parents]:
                if component == root:
                    break
                if component.is_symlink():
                    raise ValueError('symlink source refused')
            st = p.stat()
            if not stat.S_ISREG(st.st_mode) or stat.S_IMODE(st.st_mode) not in (0o644, 0o755):
                raise ValueError('unsafe source mode')
            if mode and bool(st.st_mode & 0o111) != bool(mode & 0o111):
                raise ValueError('wrong executable source mode')
            return p.read_bytes()
        entry = git(root, 'ls-tree', commit, '--', path).decode().split()
        if len(entry) != 4 or entry[0] not in ('100644', '100755'):
            raise ValueError('missing or nonregular committed source: ' + path)
        if mode and (entry[0] == '100755') != bool(mode & 0o111):
            raise ValueError('wrong committed executable mode')
        return git(root, 'show', commit + ':' + path)

    if read('remote/profiles/minimal.manifest').decode() != manifest_text():
        raise ValueError('manifest differs from reviewed exact allowlist')
    files = {p: read(source(p), m) for p, m in ALLOWLIST.items()}
    for p, data in files.items():
        check_bytes(p, data)
    manifest = b'schema 1\nprotocol 1\n' + ''.join(
        f'{m:04o} {len(files[p])} {sha(files[p])} {p}\n' for p, m in sorted(ALLOWLIST.items())).encode()
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for path, data in sorted({'MANIFEST': manifest, **files}.items()):
            member = tarfile.TarInfo(path)
            member.mode = ALLOWLIST.get(path, 0o644)
            member.size = len(data)
            archive.addfile(member, io.BytesIO(data))
    archive = gzip.compress(raw.getvalue(), mtime=0)
    if len(archive) > MAX_ARCHIVE:
        raise ValueError('compressed payload exceeds 256 KiB review gate')
    return Artifact(archive, sha(manifest), manifest, {'commit': commit, 'dirty': bool(worktree and dirty)})


def verify(data, digest):
    if len(data) > MAX_ARCHIVE:
        raise ValueError('archive too large')
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
            members = archive.getmembers()
            expected = {'MANIFEST', *ALLOWLIST}
            if len(members) != len(expected) or {m.name for m in members} != expected:
                raise ValueError('archive is not the exact allowlist')
            files = {}
            for m in members:
                if not m.isreg() or m.mode != ALLOWLIST.get(m.name, 0o644) or m.size > MAX_FILE or m.pax_headers:
                    raise ValueError('unsafe member')
                files[m.name] = archive.extractfile(m).read()
            manifest = b'schema 1\nprotocol 1\n' + ''.join(
                f'{m:04o} {len(files[p])} {sha(files[p])} {p}\n' for p, m in sorted(ALLOWLIST.items())).encode()
            if manifest != files['MANIFEST'] or sha(manifest) != digest:
                raise ValueError('invalid manifest/digest')
            for p in ALLOWLIST:
                check_bytes(p, files[p])
    except (tarfile.TarError, EOFError, OSError) as e:
        raise ValueError('invalid archive') from e


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revision')
    parser.add_argument('--allow-dirty', action='store_true')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        artifact = build(Path(__file__).resolve().parent.parent, args.revision, args.allow_dirty)
        Path(args.output).write_bytes(artifact.archive)
        print(artifact.digest)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'pack: {error}\n')
