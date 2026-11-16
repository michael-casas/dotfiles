# envi-remote — portable minimal profile

Host-free implementation of design steps 1, 2, 4, 5. No real host has been
probed or accepted. Mosh, remote tmux and developer provisioning are **not
implemented**; requests must not silently fall back. Never run `setup.sh` remotely.

Local requirements: Python 3.9+, Git, OpenSSH. Target candidate: Linux/macOS,
`/bin/bash` 3.2+, GNU tar or bsdtar (ustar/gzip), `sha256sum` or `shasum`,
GNU/BSD stat, ordinary POSIX utilities and an installed UTF-8 locale. Local
filesystems only; network mounts are not certified. Optional tools never install.

## Trust and export

`pack.py` uses an exact allowlist duplicated in `profiles/minimal.manifest`.
Each regular file has a fixed destination and mode; no recursive exports,
symlink targets, credentials, startup files, identity, caches or repo history.
Unlisted manifest entries fail; unrelated files never enter the archive.
By default payload input must be committed and clean. `--revision <git-ref>`
explicitly exports Git objects, even when worktree inputs differ.
`--allow-dirty` explicitly exports reviewed working files and reports dirty
provenance. Provenance is separate from the content digest; identical approved
bytes have the same digest regardless of source commit.

The manifest schema/protocol, sizes, hashes, modes and contents determine the
release SHA-256. Ustar metadata and gzip timestamps are normalized; the archive
has its own SHA-256 and a 256 KiB gate. This verifies approved bytes, not identity
or a signature. Secret-pattern scanning is defense in depth, not a secret detector.

Private host policy and the connection/activation contract are documented below
as the vertical slice is validated. No production defaults or host discovery.
