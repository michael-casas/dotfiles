# T3 thread popover

An Ink client for the local T3 Code orchestration-v2 websocket. Open with
`:T3Thread`, `:T3Thread <id>` or `:T3Thread new` in envi. Hiding the float does not
stop the thread or its terminal. Requires Node 22+; no additional dependencies
were added for the redesign.

## Layout

The 85% Neovim popover uses **native terminal scrollback**, not a TUI scroll
view. Ink 5 `<Static>` appends each finished item once above a small live region;
there is no alternate screen or mouse reporting. Existing projected history is
printed oldest first at startup. Item IDs prevent duplicate output after socket
reconnects, snapshot resyncs, theme repaints, and hiding/reopening the same client.

The conversation, composer and status share a centered column of at most 92
cells, with three columns of outer padding. The supported small layout is
80 × 24. Committed lines retain their original width/theme on resize or theme
change; only new output and the live region use the new settings.

- Assistant replies retain Markdown, code, lists, blockquotes and wrapping tables.
  Agent/MCP prompts retain right-aligned chips; human prompts retain bubbles.
- Finished turns print `Worked for Ns · <summary>` and their final answer.
  Errors/system notices are also append-only. Streaming answers stay live until
  completion, then the full answer is printed once (not the truncated preview).
- The live region contains the timer, latest reasoning, active tool, streaming
  answer, pending request cards, completion/model menus, composer and status.
  It is capped at 20 rows and at two fewer than the terminal's height: Ink 5
  clears and reprints static output if its dynamic region reaches screen height.
  On resize the client takes the new size before Ink's own resize repaint, so
  shrinking the popover mid-stream never measures the old, taller frame.
  Long streams/details show a bounded preview; menus take priority over preview.
  Idle threads use only the composer/status rows, with no pinned heading.
- The composer retains its theme surfaces, inverse insertion cursor, model/effort
  label, send/stop control, six-row maximum input and round ANSI fallback.
- Project/thread title, branch/worktree, run status and context usage now live in
  the status line. Action hints or errors replace it temporarily. OSC 7501 still
  reports hc state. There is no `↓ latest` hint or timeline focus.
- **Ctrl-O** prints all available expanded work of the latest finished turn into
  scrollback as a new block (repeat presses intentionally append another block).
  Tool detail is loaded before committing it. Output retains the existing
  bounded-tail limit; a turn without recorded work says so instead of expanding
  an older turn. **Tab** toggles available live work details only.

Use the wheel/trackpad, or Neovim terminal-normal mode (`Ctrl-\ Ctrl-N`) with
`Ctrl-U`, `gg`, `/search`, `n`, visual selection and yank. **`i` returns to the
composer.** The TUI never intercepts these scrolling gestures. Probe evidence:
without mouse reporting Neovim handles the wheel in normal mode; enabling
1000+1006 passes SGR wheel bytes intact through `hc attach` (1002/1003 were not
needed). Those experimental reporting/filter/routing changes were removed.

Hiding and reopening a float reuses the same terminal/buffer, retaining history.
A newly attached viewer still has hcmux's existing **2000-line replay** limit;
`term.lua` defaults remain unchanged. T3-only maps/indicator are in `t3.lua`. Client
restart prints the server's loaded projection anew into its new terminal; it
cannot recover older server pages that were not loaded.

Project names come from the authenticated protocol-2 shell snapshot, cached for
this client process. Failure or a resumable-only response leaves project names
empty without preventing thread display. Branch/worktree values come from the
thread projection and follow metadata events. When a worktree's last folder
matches the workspace basename or project title, its label includes its parent
(e.g. `2/.dotfiles`); otherwise it uses the last folder alone. Read/edit/file
labels use project-prefixed relative paths inside the worktree or workspace,
then `~` for other paths under the home directory. Known Claude model IDs get short
display names such as `Haiku 5.5`; unfamiliar IDs retain their final path segment.

## Thread feed

```sh
node threads.mjs [--project <cwd>] [--once] [--archived]
```

Read-only NDJSON for the envi T3 sidebar. Each `snapshot` contains `at` (ISO),
`projects: [{id, name, cwd}]`, and `threads: [{id, projectId, title, status,
updatedAt, pinned, unread, archived, settled, parentId, listed, relationship,
model, harness, branch, worktreePath}]`. Missing optional metadata is `null`;
flags default to `false`, except `listed` defaults to `true` without lineage.
`listed` uses the desktop's exact lineage filter: false for
`lineage.relationshipToParent === "subagent"` or `lineage.sideChat === true`,
true otherwise. Forks remain listed even with a parent ID. `relationship` copies
`lineage.relationshipToParent` (`"fork"`, `"subagent"`, or `null`). Sources:
`packages/contracts/src/orchestrationV2.ts:167-177` and
`packages/client-runtime/src/state/threadShell.ts:64-69`. Unlisted rows remain
in the feed for nesting; a flat sidebar should filter by `listed`. This flag is
local lineage eligibility, not cross-environment delegated-parent aggregation
or desktop-only project/tag visibility preferences.
`harness` is `modelSelection.instanceId`, falling back to `providerInstanceId`,
then `null`—never inferred from a model name. This identifies the provider instance
(e.g. `claudeAgent`, `pi`, `codex`, `opencode`) for sidebar icons. Wire sources:
`packages/contracts/src/modelSelection.ts:9-12` and
`packages/contracts/src/orchestrationV2.ts:2198-2199`. Desktop-local drafts are
not part of this feed.
`model` is the wire model ID, not a display label. `parentId` comes from
`lineage.parentThreadId` (including forks and children). The redacted fixture at
`test/fixtures/threads-snapshot.json` covers every status, pin/unread and a child.

The feed uses **one `orchestration.subscribeShell` websocket subscription**, not
list polling or per-thread subscriptions. Full initial shell rows and subsequent
`project.updated/removed` and `thread.updated/removed` frames are projected into
full snapshots; sequence cursors resume after reconnect. Metadata-only identity
enrichment snapshots never replace thread rows. With `--archived`, the same socket
also calls `orchestration.getArchivedShellSnapshot` initially and after shell
removals/archive transitions (coalesced, no periodic polling). The current server
omits archived rows from `subscribeShell`; `--once --archived` waits for both
responses. No shell omission flags
are sent: older settled rows and idle children remain available to the consumer.
Archived threads are omitted unless `--archived`; deleted threads always are.
`--project` matches the normalized project workspace path exactly (not a worktree
or arbitrary descendant). Unknown paths produce empty project/thread arrays.

Changes are coalesced with a 250 ms trailing throttle (at most four snapshots per
second); unchanged public data does not emit. There are no idle snapshot ticks.
Disconnects, malformed frames, RPC exits and connection/bootstrap timeouts emit
`{"type":"error","message":"…"}` with fixed safe messages, then reconnect
with exponential backoff from 500 ms to 10 seconds. A valid shell response resets
the backoff. A snapshot-required frame reloads the shell on a fresh subscription.
Recovery emits a snapshot even if its data is unchanged. `--once` writes one
snapshot and exits 0, or one error and exits 1 without retry. A ten-second
bootstrap deadline prevents it hanging if auth/socket/snapshot never arrives.
SIGINT/SIGTERM and a closed stdout pipe release only this feed's connection.

Status mapping follows the desktop shell presentation and sidebar markers:

- **attention:** pending approval or input (even nonblocking async input), guest
  request, usage limit, or a finished plan awaiting action. Auth-refresh requests
  are not user attention. App-owned live child approvals/user-only cards and
  side-chat questions roll up through their ancestors; ordinary child questions
  belong to their coordinator, and native/stopped child requests do not roll up.
- **working:** preparing, queued, starting, running or waiting; the shell's
  `activityRunStatus` takes precedence over the latest run. Attention wins.
- **done:** the latest run completed (`idle` is the legacy completed equivalent),
  its completion is newer than `lastVisitedAt`, and it is not explicitly settled.
  As on desktop, no visit watermark means no unread badge; an invalid visit with
  a valid completion is unread. `unread` is that timestamp comparison independently
  of status and settlement. Older shells omitting completion time use `updatedAt`.
- **idle:** no new completion, seen/settled completion, clean user interruption,
  cancellation/rollback, waiting on another thread, or completion held by awaited
  background work (including child/background tasks). An unawaited command or
  monitor, such as a dev server, does not hold completion.
- **error:** failed latest run or interruption carrying an error/class/code.
  Unlike the desktop's visited-failure marker, this contract intentionally keeps
  failures as error after a visit; clean interrupts are not successful completions.

`settled` means `settledOverride === "settled"`. `pinned` means membership in
the desktop's pinned section, **not raw `pinnedAt`**: it requires `pinnedAt`, a
listed lineage (not a subagent or side chat), no archive, no settled override,
and no effective snooze. Forks remain independently pinnable; being Done or
having a parent ID alone does not exclude a row. Approvals/new input, child/guest
requests and fresh failures can wake snoozes early, as on desktop. Project pins
are unrelated; `--project` scopes the output without changing pin membership.
Child rows remain in the feed, but their inherited pin metadata does not put them
on the pinned shelf. Sources: `packages/contracts/src/orchestrationV2.ts:175-177`,
`apps/web/src/components/Sidebar.logic.ts:195-203,613-632`,
`apps/web/src/components/Sidebar.tsx:627,665-669`, and
`packages/client-runtime/src/state/threadSettled.ts:94-132,156-165`.
Cross-environment `delegatedUnderParent` needs the desktop's enabled environment
catalog and linked parent roster (`state/threadShell.ts:678-700`); this local-only
feed cannot reproduce that filter. It does not blanket-exclude `delegatedFrom`
tasks: desktop keeps them listed when their parent is unavailable/archived.

This five-state contract collapses the desktop's richer Waiting/Limited/Plan Ready
markers. Cross-environment delegated-request aggregation and desktop-only local
visit fallbacks are not available in the local shell feed.

Wire references in `/tmp/t3code-src/repo`: `packages/contracts/src/orchestrationV2.ts`
(`OrchestrationV2ThreadShell`, `OrchestrationV2ShellStreamItem`,
`OrchestrationV2SubscribeShellInput`, `getArchivedShellSnapshot`),
`apps/server/src/orchestration-v2/ShellStream.ts` (active-only snapshots,
archive removals and enrichment markers), `packages/client-runtime/src/state/shell.ts`
(`subscribeShell`), `state/models.ts` (`shellRuntime`, `presentThreadShell`),
`state/threadShell.ts` (request roll-up), and
`apps/web/src/components/Sidebar.logic.ts` (`hasUnseenCompletion`,
`resolveSidebarRowStatus`). Auth uses the additive `openShellSocket()` transport
factory in `t3.mjs`; the existing thread TUI and its status helpers are unchanged.
No dependency was added. The feed never sends prompts, visits, or other commands,
logs auth tokens, or forwards raw server error bodies. Pure tests in
`test/threads.test.mjs` cover status/filter/fixture/reducer behavior, throttle,
reconnect/backoff, safe errors, bootstrap timeout, resume and `--once`.

## Theme hub

The TUI and Neovim float read the repository's
[`theme/theme.json`](../../../theme/theme.json). See the
[theme hub guide](../../../theme/README.md) for tokens, schema and consumer limits.
The default is `nord`; `gruvbox-dark` is also provided.

- `ENVI_THEME_FILE`: override the hub file path.
- `ENVI_THEME`: override the theme ID instead of using the hub's `active` value.

Set overrides before starting envi so its float and child TUI inherit the same
values. The TUI watches the hub directory and repaints only its live region on file changes; reopen
the float to refresh Neovim's highlight groups. Missing/invalid hub data falls
back to ANSI colors in the TUI and leaves the float's normal highlights alone.
This does not switch the editor colorscheme or configure other applications.

## Keys

- **Enter:** send; defaults to steering an active run.
- **Ctrl-Q:** queue the composer after the active run instead.
- **Esc:** dismiss an open completion/model/compact view; **never interrupt** a run.
  In the Neovim T3 popover it also enters **COMMAND** (normal mode). A second
  Esc stays in COMMAND and does not hide the float. Esc also cancels an
  interrupt confirmation; it never sends a stop. The popover never forwards a
  raw Esc: it sends the private `dismiss` control (`ESC[>777;6u`, see
  `control.mjs`) instead, so no TUI version can read it as an interrupt.
- **Ctrl-]** (Neovim popover only): toggle INSERT ⇄ COMMAND; from INSERT it
  dismisses like Esc.
- **Tab:** toggle live work details (when not accepting a completion).
- **Ctrl-O:** append expanded work of the latest finished turn to scrollback.
- **Native scrolling:** wheel/trackpad or Neovim normal-mode motions/search/yank.
  The old TUI PgUp/PgDn/Ctrl-U/Ctrl-D/Ctrl-E navigation is removed.
- With an approval pending and an empty composer: **y** approve, **a** approve for
  this session, **n** decline. Non-resumable requests explain why they cannot act.
- With input requested: enter an option number (comma-separated numbers for
  multi-select), or custom text if allowed, then **Enter**. Each question is
  answered in order; the answers are sent together. Options use their wire value
  when present, otherwise their label.
- **`/` at the start of a message, or `$` anywhere:** a completion list of the
  thread provider's commands or skills opens above the composer, ranked like the
  desktop. **↑/↓** or **Ctrl-P/Ctrl-N** move, **Tab** or **Enter** insert
  (`/name ` or `$name `), **Esc** closes the list for that word. Enter on a fully
  typed command (e.g. `/compact`) sends it. The T3 server does the rest:
  `/compact` compacts the thread (offered only as the whole message while idle),
  provider commands and `$skills` are expanded for the provider. The provider's
  own `/clear` is hidden, as on the desktop. T3's built-in **`/model`** opens
  the picker below instead of inserting or sending provider text. `/clear`,
  `/side` and `/btw` remain unimplemented.
- **`/model` picker:** a single view above the composer with **Harness › Model ›
  Effort** columns, initially on the thread's current selection. **h/l** or
  **←/→** change column; **j/k**, **↓/↑**, or **Ctrl-N/Ctrl-P** move within it;
  **gg/G** jump to the top/bottom; **Enter** applies; **Esc/q** cancels. The
  columns to the right update live. Disabled instances are hidden; unavailable
  or locked harnesses are dimmed and skipped, with a reason below the columns.
  Started threads may switch harnesses only when the desktop's session/history
  handoff rules allow it. Model and option labels come from `server.getConfig`;
  prompt-injected effort levels are omitted, as in the desktop. Models without
  effort show `No effort levels`; boolean thinking offers On/Off. Other options
  are preserved only for the same harness/model, never carried across models.
  Applying dispatches `thread.model-selection.set`; only the resulting server
  event changes the composer label or thread status. On failure the picker stays
  open with an error; uncertain RPC outcomes are never retried automatically.
- **Ctrl-C:** the **only interrupt shortcut**, always with confirmation. Ink's
  Ctrl-C exit is disabled. Active turns/requests show `Interrupt the agent? y/n`;
  only lowercase **y** sends `thread.stop` (when advertised) or `run.interrupt`.
  Any other key, including Esc, cancels. If idle or the run ended before y, show
  `Nothing to interrupt. Press any key to dismiss.` and send nothing. Draft text
  and cursor are preserved. Disconnected/busy clients show a reason, never retry
  an uncertain stop. Ctrl-C never quits the client.
- **Neovim COMMAND | INSERT** (T3 buffer only): the top-right float title shows
  `T3 COMMAND` in normal mode, `T3 INSERT` in terminal mode. Wheel/native
  terminal-normal navigation also updates the indicator.
  - **i/a/I/A:** enter INSERT, where prompts, `$skills`, `/commands`, and model
    picker keys go to the TUI.
  - **j/k:** scroll down/up one line, count-aware (`5k` = five lines). Native
    `gg/G`, Ctrl-U/D, search, visual selection and yank remain available.
  - **m:** open the model picker and enter INSERT **without changing the draft**.
  - **c:** reveal `Compact this thread? y/n` in the live region, read the answer
    in Neovim while staying COMMAND. **y** sends the same `/compact` path as
    typed text; any other key cancels. Active turns/requests, pending actions,
    disconnected/new threads or providers without `/compact` show a reason
    and never send. Draft text/cursor are preserved.
  - **Ctrl-C:** show the same interrupt/idle dialog while staying COMMAND,
    reading the answer in Neovim with the same live-region reveal as **c**.
  - **q:** the only popover hide/detach shortcut, in COMMAND only. INSERT **q**
    is draft text. Normal-mode Esc is a no-op. Leaving the float (Ctrl-W w or a
    click outside) keeps it open, unfocused. **`<leader>hi`**, **`<leader>h?`**
    (`t3.toggle(id)`) and **`:T3Thread [id]`** open or focus it and never hide
    it. Given a different thread than the one shown, they switch the **same
    window** to that thread's client (the other client keeps running, hidden),
    e.g. REP ⇄ keybinder. Deliberate Neovim
    `:q`, `:close`, and Ctrl-W c still close the float; those are not overridden.
- **`:T3Restart`** (command only, no keymap): reload the shown T3 client, or the
  last one when hidden, on the same thread. It checks the `t3.thread` label and
  exact Node/client/thread argv before killing only that client terminal. It
  refuses unverified/picker/new-thread clients rather than guessing a thread.
  Restart prints the loaded thread history afresh and **discards unsent drafts**;
  copy a draft before restarting. It does not stop the agent or restart servers.
- Standalone `node main.mjs <id>` still accepts prompt text, `/model`, `/compact`
  and menus normally; the Neovim mode maps/indicator do not apply. Ctrl-C asks
  for interrupt confirmation here too. To quit standalone, close its terminal
  (which may detach a persistent hc client) or explicitly `hc kill <client>`.
  No quit key is assigned; do not use Ctrl-C to load updates.
- In the thread picker, **↑/↓** or **j/k** move, **Enter** opens, and **n** starts
  a new composer.

Standalone creation can select a provider/model:

```sh
node main.mjs new --provider claudeAgent --model claude-haiku-5-5 --title 'My thread'
```

## Implementation and checks

- `t3.mjs` owns auth, T3 wire shapes, event projection, sequence resume, project
  metadata, display labels, capability negotiation and RPCs. Commands are not
  automatically resent after socket loss, because their outcome may be unknown.
- `view.mjs` owns pure folding, summaries and editor/answer transformations.
- `commands.mjs` owns `/` and `$` completion: trigger detection, the provider's
  command/skill catalog (`server.getConfig`, then `server.refreshProviders` for
  the thread's folder), desktop ranking, and text insertion. Pure.
- `model-picker.mjs` owns the pure three-column draft, catalog interpretation,
  handoff locking, keyboard motions, cascade and option selection.
- `control.mjs` parses private CSI reports and owns compact confirmation/Esc
  policy; `control-input.mjs` removes reports before public Ink stdin, preserving
  ordinary keys and split UTF-8. The private wire is `ESC [ > 777 ; N u`, with
  N=1 model, 2 compact dialog, 3 yes, 4 cancel, 5 interrupt dialog. `t3.lua` sends it with chansend
  through `hc attach`; it is not a printable INSERT shortcut. Unknown/malformed
  private reports are swallowed, including split/bounded partial reports.
- `scrollback.mjs` owns commit/live partitioning, the immutable ID ledger and
  explicit expanded-work blocks.
- `layout.mjs` owns the capped live frame, frozen history lines, wrapping, Markdown
  and shell styling.
- `theme.mjs` loads and watches semantic theme tokens.
- `main.mjs` owns Ink rendering, selection, request actions and expanded output
  lifecycle.

From this directory:

```sh
for file in *.mjs; do node --check "$file" || exit; done
node --test test/*.test.mjs
# The envi Lua suites (mocked; never call hc or kill real terminals). Exits nonzero on a failure:
test/run-lua.sh               # all of them
test/run-lua.sh restart prs   # named ones
```

The tests cover protocol/projection behavior (`test/thread.test.mjs`), `/`/`$` completion (`test/commands.test.mjs`), frame and
formatting (`test/layout.test.mjs`), model-picker catalog/motions/placement and
exact RPC shape (`test/model-picker.test.mjs`), theme loading/watching
(`test/theme.test.mjs`), commit/live/resync/startup/cap/expansion and real Ink
append-only/resize behavior (`test/scrollback*.test.mjs`), private trigger/UTF-8/compact/Esc
behavior (`test/control.test.mjs`, `test/interrupt.test.mjs`), and metadata/model/status helpers plus local HTTP stub
requests (`test/data.test.mjs`). HTTP tests use `T3_URL` and a call-time
`T3_SESSION_TOKEN` override so they never read or replace the real token file.
They include success/cache behavior, rejection, resumable snapshots, invalid JSON
and the five-second request timeout. Do not print or commit real credentials.
`test/scrollback-resize.test.mjs` runs the real `main.mjs` on a real PTY
(`test/support/pty-run.py`, resized with TIOCSWINSZ) against a local synthetic
T3 server (`test/support/fake-t3.mjs`) and checks raw bytes for clears, history
replays and redraw counts. Scenarios live in `test/t3-scrollback-strikes.feature`.

`test/replay.test.mjs` folds all 29 frames of the secret-checked
`test/fixtures/turn.jsonl` capture. It checks the folded prompt/timer/final answer,
exact `Ran 2 commands and read 1 file` group summary, and five ordered expanded
items: reasoning, git, read, grep, reasoning. Assertions use row kinds/text,
not glyphs or chevrons.

## Remaining limits

The client uses full-body snapshots and respects bounded snapshot history when
provided, but does not fetch older pages yet. Output loads on expansion; live
output subscriptions require server support. Expanded output displays a bounded
tail (at most 120 lines, with live buffers capped at 200,000 characters) and
removes terminal control sequences rather than emulating a terminal.

Markdown and shell highlighting are deliberately small renderers, not complete
parsers. Wide tables wrap and split into column bands rather than reproducing
the desktop's table layout. Unusual Unicode/grapheme widths may still differ
between terminal fonts. Composer display is capped at six input
rows. The desktop's proportional fonts, rounded filled surfaces, exact icons,
hover actions, fades/shimmer, microphone and attachment controls are not
reproduced. Agent chips show a truncated prompt rather than a full expanded
prompt view. The live preview can omit earlier streaming text; the committed final is complete.
Native history cannot be restyled, collapsed, or reflowed after printing.
Final pixel-level acceptance belongs to a real-popover check;
replay and pure frame tests do not prove visual fidelity on their own.

The separate unfinished `nvim/lua/hcmux/agent.lua` AGENT-mode work is not wired
or modified here. Its older Esc-interrupt, Ctrl-C/client lifecycle assumptions, timeline/scroll and leader actions
need reconciliation by keybinder; COMMAND mode adds no global/leader bindings.
