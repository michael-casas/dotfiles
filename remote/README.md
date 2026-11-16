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

## Private policy and explicit SSH

Private path: **`~/.config/envi-remote/hosts.json`**, owned regular file, mode
0600, outside this repo, with no symlink components. Ship only the placeholder
`hosts.example.json`; create a private policy manually after owner approval.
Exact JSON schema 1: `hosts` maps finite-alphabet local IDs to **all** fields
shown in that example. Duplicate keys and extra fields fail. `class` is
`personal`, `company`, or `shared-uid`; `approved` must be true. Company/shared
UID is temporary only in this first lane; `persist` must be false everywhere.
Storage persistence means cached releases, **not** detached jobs/history.

**Deliberate v1 restriction:** SSH uses `-F /dev/null`, never reads local SSH
config or autodiscovers aliases. `target` must be a directly resolvable DNS name
(e.g. an approved tailnet DNS endpoint), `user` is a validated account name or
null to use SSH's default, `port` is an integer. ProxyJump, custom identity-file
selection, SSH config aliases and site-required env exceptions are unsupported;
stop for an explicit policy extension rather than importing ambient config.
Normal known-host verification stays enabled and strict; forwarding, arbitrary
env sending, local commands and multiplex-master reuse stay off. Authentication
stays inside SSH; no credentials are copied into the payload. Account/system
SSH shell hooks can run **before** our clean child environment; this is not a
sandbox against the host, administrator, or same-UID peers.

`root` is a canonical absolute path with at least two components, restricted to
ASCII letters/digits, underscore, dot, hyphen, slash and space. Quotes/control
characters, `..`, duplicate/trailing slashes fail. All existing ancestors must
be root/self-owned and not group/world writable (root-owned sticky system temp
ancestors excepted); root/subroots must be self-owned 0700, never symlinks.
`locale` must match an installed `locale -a` entry and yield UTF-8. No invented
locale, package install, network download, service start or global config edit.

```sh
# Use a checkout command directly, or add remote/bin to your LOCAL PATH manually.
remote/bin/envi-remote hosts                       # approved local IDs only
remote/bin/envi-remote plan example-personal        # local JSON; no SSH
remote/bin/envi-remote example-personal --transport ssh
remote/bin/envi-remote example-personal --use-cached # verify; never upload
remote/bin/envi-remote example-personal --temporary
remote/bin/envi-remote plan example-personal --revision HEAD
remote/bin/envi-remote plan example-personal --allow-dirty
# --policy /absolute/private/hosts.json overrides the policy path for fixtures.
```

No arbitrary remote commands, named sessions, digest rollback selection, Mosh,
tmux persistence, fish or developer prepare yet. `--revision` selects a **local
Git ref/commit**, not a remote digest. For rollback, export that known commit for
new shells; existing shells retain their pinned release. Transport failures and
policy/probe/staging errors return 20; bootstrap errors return 23 inside SSH;
after attachment the wrapper preserves stock SSH's exit code.

## Transfer, activation, recovery

1. Local policy/identifiers fail before any SSH. Build/verify the closed archive.
2. Fixed read-only probe checks Bash, known tar family, hash utility, installed
   locale/charmap, optional command presence; no environment or identity dump.
3. Verify any cached release completely. Warm connect sends **no archive**.
   Otherwise acquire a digest lock, create 0700 unique same-filesystem staging,
   bound upload, verify **archive SHA-256 before tar**, extract, verify exact
   manifest, file count, types/modes/sizes/hashes, then rename atomically.
4. A separate tty SSH invocation verifies again and enters the pinned Bash rc.
   Real HOME and remote cwd remain. Child env is rebuilt, not forwarded; PATH
   is fixed and no shell-wide XDG override is made. No disk shell history.
   `editor` alone sets app-scoped XDG roots; Git overlay adds display/harmless
   aliases while leaving system/global/repository policy visible.

Only reviewed local bootstrap code runs before verification; tar receives bytes
already checked against the trusted local archive hash. No untrusted remote tar
is accepted as an input to the local packer. The digest is not authentication.
Locks fail boundedly rather than wait/steal. Interrupted/corrupt staging cannot
activate; after rename, every reconnect still verifies. Visibility is atomic,
**not fsync/power-loss durability**. Known-good releases are never deleted or
mutated by publication. Concurrent cold publishers may receive a lock error;
retry explicitly. No automatic GC or stale-lock removal. Inspect a stale lock
privately and remove only after separately confirming no owner remains.

Temporary mode uses a unique private child beneath the approved root; supervisor
cleanup removes only that child after the shell exits normally, including a
nonzero exit. An interrupted staging failure, lost launcher before attachment,
SIGKILL, reboot or abrupt server death can leave the child. Inspect private
staging/temporary paths before any explicitly approved cleanup; no promised
secure erase or automatic deletion on disconnect. Persistent shell/editor state
is digest-scoped; this lane creates a fresh state directory per shell and does
not reattach old jobs. Valid `XDG_RUNTIME_DIR` is not required/rewritten because
no persistence socket is created in this lane.

Prompt defaults to an ANSI cyan ASCII prompt, not RGB. Reviewed Starship files
are passive opt-in reference data; no `eval` or Starship startup execution.
`ff` uses fd/fdfind or `find . -name PATTERN`; `search` uses rg or grep, without
pretending flags are interchangeable. Missing Neovim reports explicit recovery
`vi -u NONE` rather than silently sourcing vimrc. No tmux or Mosh is started.

## Tests and remaining gates

```sh
python3 -m unittest discover -s remote/test -v
shellcheck remote/bootstrap.sh remote/profile/bin/* remote/profile/shell/bashrc
```

Tests use disposable roots/HOMEs, committed fixture repos and fake SSH/Mosh on
PATH. They do not connect to localhost or real hosts or modify Remote Login.
They prove packing rejection, deterministic bytes, Bash 3.2 execution on macOS,
BSD extraction/stat/hash and mocked GNU probe shape, clean control stdout,
unknown-host denial, HOME preservation, no default history, explicit SSH exit
status, temporary cleanup, cache verification and failed-upload nonactivation.
Mocked utility families do **not** certify a real Linux/GNU host. No test proves
SSH authentication/account hooks, real TTY/terminfo/color/key behavior, recording
policy, UDP, network filesystems or power-loss durability.

REP owns independent review and manual Herdr E2E. Pilot selection/approval is
still required. Step 3 must implement and test stock Mosh bootstrap/locale/server
version, approved UDP range, seven-day orphan timeout, private tmux socket,
pinned named sessions/panes, concurrency, stale-session recovery and rollback.
Step 6 must prove real target isolation, edit/save/search, nested keys/colors,
local-view restore, reconnect/outage semantics and policy-specific cleanup.
The read-only pilot probe should guard/bound uname OS/arch, command presence,
Bash/Mosh/tmux/Neovim versions, locale/charmap, terminfo, and approved-root owner/
filesystem checks only. No environment, SSH config, credentials or host dumps.
