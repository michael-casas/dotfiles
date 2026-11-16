# Implementation evidence

## P0 contract freeze

Authority: ratified envi whiteboard format v0 (2026-11-16). The schema and
complete example are retained verbatim. The executable contract is
`test/contract.test.mjs`; CommonMark 0.31.2 determines top-level blocks, with
original byte spans retained separately. No reader save operation exists.

RED: the first executable reader used `JSON.parse` for the envelope and passed
terminal text through. `node --test test/contract.test.mjs` failed observable
contract assertions (duplicate JSON keys accepted, no stable/attached blocks,
terminal ESC and bidi bytes forwarded). This was a behavior failure, not a
missing import. GREEN: all 12 contract tests pass after duplicate-aware JSON,
explicit `$defs` schema references, CommonMark spans and safe-text projection.

Test layers: pure parser/profile tests are L1. Filesystem/CLI/process/Git/private
stdio tests are L2. Headless Neovim verifies native adapter behavior, not visual
acceptance. REP owns L3 Herdr/manual E2E and independent review. Tests never
connect to a browser, hc, T3 or the network. Dependency acquisition is separate.

## P1 reader/session

RED: CLI `render` forwarded an actual OSC/ESC payload; `open` accepted non-TTY,
`validate --strict` did not fail unresolved pins. GREEN: 17 new tests pass,
including real atomic-save/delete/recreate directory watch and no-op suppression.
T3 theme suite remains 21/21 after its reader becomes a compatibility export of
`envi-board/hub-theme.mjs` (same directory depth, identical default hub path).
This narrow extraction has one implementation, no T3 runtime/network coupling.

## P2 rendering/source

RED: public `render` still showed only source after P1; the new public test
required approximate graph plus exact source and explicit render-check results.
GREEN: 26 tests pass. Six small family fixtures render with pinned merminal;
advanced/unprofiled configurations stay source. Missing/old Ruby, job timeout
and output overflow discard all partial output. Local SHA-1/SHA-256 repositories
prove immutable literal-path blob reads, symlink/submodule/binary rejection,
no replace-object substitution and no textconv execution.

Exact gem checksum is recorded in `vendor/manifest.json` with every vendored
file hash and the MIT notice retained. There are no runtime gems/global installs.
The macOS Seatbelt default-deny policy allows only runtime/vendor content reads
(and filesystem metadata), denies network, writes and unrelated executable paths.
Actual sentinel read/write and child-exec denial are tested **without making a
network attempt**. Ruby's CPU limit is 4s; parent deadline 5s; response 16 MiB;
queue/cache 64; cache total 8 MiB. macOS rejects RLIMIT_AS/DATA/RSS, so the host
samples only the owned pid's RSS every 100ms and kills above 256 MiB. This is a
sampled resident-memory policy, **not** an instantaneous hard allocation cap.
Other OSes deliberately source-fallback until an isolation adapter is proven.
Current checkout freshness is honestly `unknown/not compared`; no worktree
file-open alternative is offered (avoids introducing a TOCTOU unsafe-open path).
Tiny six-family fresh processes completed in under 5s each (normally <100ms);
this is not benchmark, official Mermaid conformance, or visual acceptance.

## P3 native adapter and final checks

RED: the public private-stdio test could not obtain an open snapshot from P2;
reader alone did not satisfy native worker behavior. GREEN: `worker` supports
only fixed read operations and sends bounded versioned complete generations.
The real native-worker smoke additionally caught and fixed Lua's empty table
encoding as `[]` instead of a bindings object; this was not visible in mocks.
Missing-file recovery caught a null last-snapshot access and now has a frozen
regression test. FIFO input is opened nonblocking and rejected as nonregular.

New tool: **32/32 Node tests**. **Two Lua harnesses** pass: mocked real-window
lifecycle/protocol safety and a real Node-worker/native-float integration proving
actual diagram delivery, exact source, live theme repaint, invalid/stale save,
atomic recovery and normal source-buffer opening without losing an unsaved draft.
A real foreground PTY test checks 80x24 boot, resize, q exit and canonical/echo
restoration, with no alternate screen/mouse. No browser/network/hc/T3 calls.

Standing gates: **173/173 existing T3 Node tests**; **all 15 existing T3 Lua
harnesses**, no Lua error output. All new `.mjs` pass `node --check`; stylua
`--config-path nvim/stylua.toml --check` passes for `board.lua` and both harnesses;
`git diff --check` passes. Tool-local Prettier formatting was applied once the
whole seam stabilized; no unrelated repository cleanup.

Remaining evidence limits: no GUI/manual Herdr E2E, no official mmdc reference
render/visual comparison, no browser/rich export, no current checkout freshness
comparison/current-file open, no mutation/import/CAS writer, no cross-platform
renderer sandbox, no hard instantaneous memory-cap guarantee. No network-denial
probe is attempted by tests (policy has no network allowance; runtime has no
network code path). REP owns manual E2E/independent critics; keybinder owns
leader/command/statusline wiring. No push/PR/merge/rebase/global installation.
