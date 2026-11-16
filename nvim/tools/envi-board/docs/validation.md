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
