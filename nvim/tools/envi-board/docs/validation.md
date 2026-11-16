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

Standing gates: **173/173 existing T3 Node tests**; **all 16 existing T3 Lua
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

## Critic round 1 corrective pass

Baseline: REP-rebased P0–P3 implementation; no implementer rebase/amend.
The critic's 3/5 is an independent review result, not superseded by a self-score.

- **M1:** projection splits LF/CR/CRLF in every pushed field while retaining a
  mapping per physical row; Lua escapes LF as defense in depth. New Node
  projection and real-worker/native regressions use multiline author/label;
  the mocked native harness also feeds a malformed unsplit LF row. RED reproduced
  invalid physical rows/native newline errors; all three checks now pass.
- **M2:** source-edit splits beside any non-file (including terminal) or modified
  invoker. The mocked real-window terminal-invoker regression failed before the
  guard and now confirms the original window still shows the terminal buffer.
- **m1:** watcher error immediately publishes a new generation even with
  unchanged bytes. Hash no-op suppression also compares watcher state, allowing
  manual retry to publish recovery. New Node test observes exactly initial,
  failed and recovered snapshots; RED previously observed `watchError:null`.
- **m2:** worker echoes the requested absolute path unchanged, resolving only
  internally. A Node `nosuch/../` identity regression and real native-worker
  open/edit check pass; source-edit normalizes its explicit editor path too.
- **m3:** README uses fail-closed runners. The tool-local `test/run-lua.sh` uses
  `pcall`/`cquit 1`; a temporary throwing probe confirmed exit **1**, then was
  removed. Existing T3 suite count is **16**, not 15.
- **m4:** cache keys omit ignored width/theme; same-revision graphs stay visible
  while replacements are pending; new jobs show `rendering…`. New worker test
  checks first render, resize and live theme update. New cache test makes the
  Ruby path unusable after the first result and still reuses output with changed
  width/theme. Both had meaningful RED before repair. Ink uses the same retention
  policy; revision guards still reject stale output.
- **n1:** pinned CRLF display strips CR only at line boundaries; a new committed
  CRLF blob regression verifies readable lines and unchanged Git blob bytes.
- **n2:** removed unused `.vendor/`/`.cache/` ignores and unreachable duplicate
  Ctrl-C branch.
- **n3:** shared theme reader deliberately remains in place, per REP's direction;
  no optional relocation or extra coupling churn in this corrective pass.

Corrective gate results: **38/38 envi-board Node tests** (six added), **2/2
board Lua harnesses**, **16/16 T3 Lua suites**, **173/173 T3 Node tests**; all
exit 0. Stylua on touched Lua, `node --check` on all tool modules, shell syntax
and `git diff --check` pass. Node/Lua tests remain synthetic, offline and without
hc/T3/browser calls. Manual Herdr E2E and the independent next critic verdict
remain REP's responsibility; no claim of 5/5 acceptance is made here.

## Critic round 2 corrective pass

The independent critic scored round 1's repairs 4/5 with no blocking/major
finding. This pass addresses the remaining efficiency finding and documentation
nit without relocating the shared theme reader.

- **N1:** worker starts one diagram pass per document hash, retaining settled
  success/failure and in-flight work on resize/theme refresh. A bounded digest
  of the last complete payload suppresses identical snapshot frames; a changed
  palette still publishes once. Ink's render effect now depends only on the
  document hash, so viewport/palette changes do not restart rendering or dismiss
  its source pane. Renderer errors (including timeouts) use the same 64-entry /
  8 MiB input cache as successful output; a genuinely changed document still
  gets a revision-guarded pass.
- **N1 RED/GREEN:** updated worker regression originally observed three snapshots
  for a settled resize. A new mixed success/strict-engine-failure fixture
  originally observed ten snapshots for five resizes. It now observes zero new
  snapshots, zero renderer calls and zero Ruby jobs; live theme update sends
  exactly one snapshot without rendering. A test-only preload counts renderer
  calls and actual sandboxed Ruby launches, without changing production APIs.
  A real Ink PTY regression failed against the prior implementation with extra
  render calls on resize/theme and now passes. It also changes the document and
  proves a fresh pass reuses both cached outcomes without new Ruby. Separate
  diagnostics/deadline regressions verify failed-result cache hits and revision
  rebinding; the pre-fix failure was an empty failure cache.
- **N2:** replaced the obsolete baseline commit IDs with descriptive provenance.
  Tracked validation evidence deliberately uses no commit SHAs so REP rebases
  cannot leave dangling references. A scan for hexadecimal commit-ID tokens
  returns no matches in this document.

Manual Herdr visual E2E and the independent next critic verdict remain REP's
responsibility; these corrective tests do not claim a 5/5 acceptance verdict.

Round 2 gates: **41/41 board Node tests** (three added; one existing worker
assertion strengthened), **173/173 T3 Node tests**, **16/16 T3 Lua suites**,
**2/2 board Lua harnesses**, all exit 0. Stylua, module syntax checks and
`git diff --check` pass. Tests remain synthetic/offline; theme reader unchanged.
