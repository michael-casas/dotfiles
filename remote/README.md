# envi-remote — portable minimal profile

Host-free implementation of design steps 1, 2, 4, 5. REP has selected and
probed a NAS-class Linux pilot; full live acceptance is still pending. Mosh,
remote tmux and developer provisioning are **not implemented**; requests must not silently fall back. Never run `setup.sh` remotely.

Local requirements: Python 3.9+, Git, OpenSSH. Target candidate: Linux/macOS,
`/bin/bash` 3.2+, GNU tar or bsdtar (ustar/gzip), `sha256sum` or `shasum`,
GNU/BSD stat, `/usr/bin/base64 -d`, ordinary POSIX utilities, installed terminfo
and an installed UTF-8 locale. `infocmp` and `tput` are not required. Account
login shells tested locally: Bash, sh, zsh, fish, csh and tcsh. The carried interactive shell is still Bash only. Local
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
shown in that example; `path_extra` is optional (defaults to `[]`). Duplicate
keys and unknown fields fail. IDs `plan` and `hosts` are reserved. `class` is
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
ASCII letters/digits, underscore, dot, hyphen, slash and space. `@` is not
allowed (e.g. `/volumeN/@tmp/portable` fails locally with 20). Quotes/control
characters, `..`, duplicate/trailing slashes fail. All existing ancestors must
be root/self-owned and not group/world writable (root-owned sticky system temp
ancestors excepted); root/subroots must be self-owned 0700, never symlinks.
ACL-managed shares whose mode bits are group/world writable and non-sticky
are rejected by design, even if their ACLs restrict access. We do not interpret
ACLs or loosen the guard. If such a share is an ancestor of HOME, no root under
HOME is eligible. For temporary storage, the supported workaround is an approved
private root beneath root-owned sticky system temp (e.g. `/tmp`), with the usual
ownership, mode and symlink checks. The filesystem must also allow execution:
`/tmp` is not portable as a guaranteed executable location. System temp may be
cleared by the OS.
`locale` must match an installed `locale -a` entry and yield UTF-8. Codeset
matching ignores case/hyphens: `C.UTF-8`, `C.utf8` and `C.UTF8` are equivalent;
`en_US.UTF-8` similarly matches an installed `en_US.utf8`;
the probe exports and returns the **host's actual spelling**. Language/territory
are not guessed. The example keeps portable request spelling `C.UTF-8`.

The command crossing the login shell is one line of quoted argv, with no variable
expansion for that shell to parse. A fixed `/bin/sh` trampoline preserves the
remote account's HOME/PATH, then enters `env -i` and configuration-free Bash.
Reviewed script/argument bytes are base64-encoded to avoid multiline/single-quote
dialect differences (encoding is not a trust mechanism). The local PATH is
never sent. The shell PATH is `<release>/bin`, approved `path_extra` entries in
order, then the remote login's own PATH with `/usr/sbin:/sbin` appended. Each
extra must be canonical absolute ASCII (same alphabet as `root`), and every
component must exist, be root/self-owned, non-symlinked and not group/world
writable. The target's existing PATH remains target policy, not a sandbox.
`TERM` is validated locally and remotely; missing terminfo falls back through
`xterm-256color`, `vt100`, then `dumb`. The selector and probe availability flags
share one check: use `infocmp` when present; otherwise look for readable compiled
entry files in `$TERMINFO`, `$HOME/.terminfo`, the colon-separated `TERMINFO_DIRS`
entries, then `/etc/terminfo`, `/lib/terminfo`, `/usr/share/terminfo` and
`/usr/lib/terminfo`. Both first-letter (`x/`) and hexadecimal (`78/`) directory
layouts are supported. Empty `TERMINFO_DIRS` entries use the system defaults.
These variables are consulted when present in the bootstrap environment; the
clean SSH trampoline does not forward local environment overrides. No installed
fallback means stop with 22; a failing installed `infocmp` does not trigger a
file-based override. No invented locale, package install, network download,
service start or global config edit.

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
tmux persistence, a carried fish profile or developer prepare yet. `--revision` selects a **local
Git ref/commit**, not a remote digest. For rollback, export that known commit for
new shells; existing shells retain their pinned release. Local error codes:
**20** policy/input/export; **21** SSH transport/authentication/control timeout;
**22** probe/platform/root/protocol; **24** release lock contention;
**25** cache/stage/verification. Bootstrap uses 23 internally and the wrapper maps
only exact authored diagnostics. For ambiguous exit 255, only complete known
OpenSSH client-message forms (Linux and macOS/BSD wording) are displayed; hostname,
port and explicit account fields must match the policy, authentication methods
and host-key types are fixed known names, and closed/reset peers are either the
exact policy target or bounded IP-shaped fields. All other lines are withheld with a fixed message and
diagnostic hint. This pattern check is not authentication of
the message source—a remote can imitate a client message. After tty
attachment, stock SSH's exit status and interactive diagnostics are preserved.

## Transfer, activation, recovery

1. Local policy/identifiers fail before any SSH. Build/verify the closed archive.
2. Fixed read-only probe reports bounded OS/architecture, Bash/Neovim/Mosh/tmux
   version first lines, known tar family, hash utility, canonical locale/charmap,
   selected TERM and xterm/tmux terminfo availability, plus optional command
   presence. Neovim's version probe disables its HOME log writes. No environment
   or identity dump. Standalone `probe` is the REP-only read-only pilot entry
   point (requires separate target approval); CLI `inspect` combines this with
   approved-root creation/cache verification and can write directories/files.
   Before reporting a cache miss or permitting upload, `inspect` creates a tiny
   script with a unique name, marks it executable, runs it directly, and removes
   it in both the approved root and `releases` directory. Launch repeats these
   checks before activation; verified release trees are never modified. No
   `mount` parsing or interpreter bypass of `noexec`. Execution denial maps to
   22, not a late `bin/enter: Permission denied`. This detects execution denial,
   including `noexec`; it cannot prove that mount policy will not change later.
3. Verify any cached release completely. Warm connect sends **no archive**.
   Otherwise acquire a digest lock, create 0700 unique same-filesystem staging,
   bound upload, verify **archive SHA-256 before tar**, extract, verify exact
   manifest, file count, types/modes/sizes/hashes, then rename atomically.
4. A separate tty SSH invocation verifies again and enters the pinned Bash rc.
   Real HOME and remote cwd remain. Child env is rebuilt, not forwarded; PATH
   preserves the target path as described above; no shell-wide XDG override is
   made. No disk shell history.
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

Cold connections use three separate SSH logins (inspect, stage, tty launch);
warm connections use two (inspect, tty launch), with ControlMaster still off.
PIN/touch-gated keys may therefore prompt more than once. No hidden shared master
or background connection is created. Stage timeout is 120 seconds; other control
calls use 45 seconds. Timeout/failure does not authorize stale-lock stealing.

### Failure recovery

- **Host key (21):** verify the fingerprint with the target owner and seed the
  known_hosts entry out of band under explicit approval. Never disable strict
  checking or delete/replace a changed key automatically.
- **Authentication (21):** check the approved account/port and default keys or
  `SSH_AUTH_SOCK`. `-F /dev/null` ignores `IdentityAgent`/`IdentityFile` config;
  a key named only there will not be selected. With approval, load that key into
  the local agent for a limited time: `ssh-add -t <secs> <key>`, using your chosen
  lifetime and private key path. This is the route REP reported working on the
  pilot; the wrapper does not load keys itself. Other config-only requirements
  still need a reviewed policy extension; there is no identity-file policy field.
- **DNS/reachability/timeout (21):** check the approved DNS target and network.
  The error prints a matching `ssh -F /dev/null -p P [-l U] -- TARGET true`
  diagnostic suggestion; running it is a **real connection**, requiring approval.
- **Locale/TERM/path/probe (22):** use an already installed UTF-8 locale/tool or
  approved existing path; never install or loosen root validation on login.
- **Noexec root (22):** `approved root is on a noexec filesystem` means the
  direct executable preflight failed (a security policy may also deny execution).
  Pick and approve a root on an exec-capable filesystem; changing permission bits
  does not bypass `noexec`. REP reported a temporary root under `/dev/shm` worked
  on the NAS-class Linux pilot: it was root-owned, sticky and exec-capable, unlike
  that pilot's `/tmp`. Verify these properties on each target; neither path is a
  universal guarantee. Do not remount or weaken security policy during login.
- **Release locked (24):** retry after the active publisher finishes. If the lock
  persists, inspect `$root/locks/<digest>` privately; confirm its owner is gone
  and obtain explicit cleanup approval before removal. No age-based stealing.
- **Cache/hash/publish (25):** no attachment occurred. Preserve the suspect
  release/staging for inspection, select known-good committed inputs, and seek
  approval before removing damaged owned artifacts. `--use-cached` never uploads
  a missing release; retry explicitly without it only when upload is intended.

Temporary mode uses a unique private child beneath the approved root; supervisor
cleanup removes only that child after the shell exits normally, including a
nonzero exit. An interrupted staging failure, lost launcher before attachment,
SIGKILL, reboot or abrupt server death can leave the child. Inspect private
staging/temporary paths before any explicitly approved cleanup; no promised
secure erase or automatic deletion on disconnect. Persistent shell/editor state
is digest-scoped at `$root/state/<digest>/session.XXXXXXXX`; this lane creates a
fresh state directory per shell and does not reattach old jobs. Persistent state
is **not automatically collected** and grows per connect; explicit cleanup must
preserve any live sessions. Temporary enter also checks the exact
`temporary-<32 lowercase hex>` root suffix before installing its cleanup trap. Valid `XDG_RUNTIME_DIR` is not
required/rewritten because
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
Mocked utility families do **not** certify a real Linux/GNU host. Login-shell
coverage runs each locally installed shell against the same disposable fixture.
Locale probes cover both macOS-style and glibc-style UTF-8 spelling. No test proves
SSH authentication/account hooks, real TTY/terminfo/color/key behavior, recording
policy, UDP, network filesystems or power-loss durability.

REP owns independent review, all real-host checks, and manual Herdr E2E. REP
reported the selected NAS-class Linux pilot has compiled xterm/vt100 terminfo
but neither `infocmp` nor `tput`, only language-specific `.utf8` locales (the
policy requests `en_US.UTF-8`), and an ACL-managed writable HOME ancestor. The
pilot therefore uses an approved temporary root under sticky system temp.
REP subsequently reported a Herdr E2E passed with a prompt, `xterm-256color`
fallback, `en_US.utf8`, no history file, find/grep helpers, explicit editor
recovery, colors, and clean exit with the temporary child removed. REP also
verified hangup cleanup. The successful root was under exec-capable `/dev/shm`;
the earlier `/tmp` root staged but could not launch because its mount was
`noexec`. These are attributed live observations, not live verification of this
correction's executable preflight. Temporary-child cleanup is unchanged.

The pilot also lacks Neovim, Mosh and tmux. The existing missing-editor path
reports `vi -u NONE` for explicit recovery; it does not auto-run vi. Offline
Neovim acceptance awaits an existing supported Neovim or a separately approved
host package installation. Step 3 would also require Mosh/tmux packages on this
pilot; installation is a user decision, never bootstrap work. Step 3 must
implement and test stock Mosh bootstrap/locale/server
version, approved UDP range, seven-day orphan timeout, private tmux socket,
pinned named sessions/panes, concurrency, stale-session recovery and rollback.
Step 6 must prove real target isolation, edit/save/search, nested keys/colors,
local-view restore, reconnect/outage semantics and policy-specific cleanup.
The read-only pilot probe should guard/bound uname OS/arch, command presence,
Bash/Mosh/tmux/Neovim versions, locale/charmap, terminfo, and approved-root owner/
filesystem checks only. No environment, SSH config, credentials or host dumps.

### Offline minimal editor

`editor` requires an existing Neovim 0.9+ (tested candidate: local 0.11.6),
uses built-in syntax only and disables plugins, project exrc, modelines, swap,
persistent undo/shada, clipboard and external language providers. No parser,
LSP, formatter, Node, hc or T3 dependency. `<Space>w` saves, `<Space>/` clears
search highlights, `<Space>v`/`<Space>s` split; ordinary `/`, `n` and Ctrl-w
remain built-in. The passive ANSI/256 Nordic-inspired palette does not advertise
RGB. `python3 -m unittest discover -s remote/test -p test_editor.py -v` exercises
offline open/edit/save/reopen/search/split in disposable HOME/XDG roots, plus
missing/unsupported editor recovery. Startup assertions are checked by a success
marker as Neovim can otherwise exit 0 after a `:luafile` assertion error.

### Host-free validation receipt

Critic-round regression tests add account-shell dialects, locale spelling,
classified errors/recovery, sticky/setgid modes, terminal fallback, target PATH,
policy realpath/symlink/root guards, reserved IDs, SSH argv and no-upload guards,
launch-time cache revalidation, digest state and login-count checks. See the
current verification counts below; no software or container images were installed.

```sh
python3 -m unittest discover -s remote/test -v
nvim/tools/t3-thread/test/run-lua.sh
(cd nvim/tools/t3-thread && node --test test/*.test.mjs)
shellcheck remote/bootstrap.sh remote/profile/bin/* remote/profile/shell/bashrc
# remote/stylua.toml and nvim/stylua.toml now cover ordinary invocations:
~/.local/share/nvim/mason/bin/stylua --check remote/profile/nvim/init.lua remote/test/editor.lua \
  nvim/lua/hcmux/remote.lua nvim/tools/t3-thread/test/remote.lua
git diff --check
```

Current correction gate: **63 Python tests: 62 passed, 1 skipped**;
**17/17 Lua suites** through `run-lua.sh` (exit 0); **173/173 Node tests** pass. ShellCheck, plain StyLua
checks using the directory configs above, and `git diff --check` pass. The stale
168/173 missing-dependency caveat is closed; REP supplied the existing Node
dependency environment, and this correction installed nothing. Account-shell
subtests exercised all six locally available shells: Bash 3.2, sh, zsh, fish,
csh and tcsh. The setgid-inheritance regression is explicitly skipped outside
Linux: BSD mkdir does not inherit setgid, so a macOS pass would not test that
behavior. Linux checks permit inherited setgid while enforcing 0700 permissions
and rejecting setuid/sticky bits. **Reported independent evidence:** round-2
critic verified inspect/stage/re-inspect/launch in an already-local Debian 12
container, with network disabled, as a non-root account whose HOME was 2755;
GNU inherited-setgid directories were accepted and HOME files remained intact.
This correction did not rerun that container. No real SSH host or container was
contacted for this correction.

Round-2 corrections add an exit-255 withholding regression (including recognized
message prefixes with unrecognized suffixes), retain client-error diagnostics,
and remove the obsolete standalone cache-check operation. The REP-only `probe`
entry point remains covered by probe tests.

Round-3 corrections retain Linux and macOS/BSD SSH diagnostics while pinning
policy fields and withholding spoofed account/method/peer text. New host-free
fixtures cover compiled terminfo without either inspection tool, every search
location and both layouts, fallback order and probe flags, missing-entry exit 22,
and `en_US.UTF-8` normalization against `en_US.utf8`. REP must rerun the corrected
bootstrap on the pilot; this implementation agent made no live connection.

P6/P7 correction fixtures emulate execution denial without mounts: inspect
returns 22 before upload/staging for either root or releases, cached-connect
denial is rejected, launch rechecks, and preflight files are removed on success
and failure. Root-alphabet tests now explicitly reject `@` before transport.
REP owns the live rerun of the new preflight.
