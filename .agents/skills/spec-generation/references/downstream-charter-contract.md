# Downstream Charter Contract

The `tasks.md` produced by `spec-generation` is consumed directly by the `SYS_COMMANDER_*` and `SYS_WORKER_*` charters at `~/.dotfiles/opencode/agent/`. This file documents the exact contract so future evolutions of the spec shape stay synchronized with the charters.

## Charter inventory

All four charters run inside the opencode runtime. The `_GO` vs `_CODEX` suffix denotes only the **model envelope** — `_GO` uses open-weights models (Kimi K2.6 for commander, MiniMax M2.7 for worker), `_CODEX` uses OpenAI models (GPT-5.4 for commander, GPT-5.4-mini for worker). The runtime is opencode for all four.

| Charter | Role | Model | Reads |
|---------|------|-------|-------|
| `SYS_COMMANDER_GO.md` | COMMANDER | `opencode-go/kimi-k2.6` | `tasks.md` |
| `SYS_COMMANDER_CODEX.md` | COMMANDER | `openai/gpt-5.4` | `tasks.md` |
| `SYS_WORKER_GO.md` | WORKER | `opencode-go/minimax-m2.7` | Lane Dispatch Packet |
| `SYS_WORKER_CODEX.md` | WORKER | `openai/gpt-5.4-mini` | Lane Dispatch Packet |

## Markdown structural anchors the commanders parse

The commander extracts these exact anchors from `tasks.md`. Any change to header levels or label wording breaks the parsing contract.

1. `## DAG Summary` — table with columns: `Wave | Lanes | Concurrency | Depends On`. Concurrency values are exactly `serial` or `parallel`.
2. `## Write Surface Map` — table with columns: `Task ID | Files (write surface)`. Task IDs match `W<wave>.<lane>.<directive>.<seq>`.
3. `## Wave N: <name>` — wave header. Body must contain three bolded labels: `**Concurrency:**`, `**Depends on:**`, `**Audit Material on Failure:**`.
4. `### Lane <X>: <name>` — lane header. Lane letter is single uppercase. The lane body (from this header until the next `### Lane`, `## Wave`, or `## Audit Protocol`) is extracted verbatim and passed as the Lane Extract section of the Lane Dispatch Packet.
5. `#### Directive N: <intent>` and `##### Op Group N.M: <cluster>` — narrative grouping. Preserved in the lane extract but not interpreted by the commander.
6. Task checkbox lines: `- [ ] W<wave>.<lane>.<directive>.<seq> <title>` with bulleted sub-fields:
   - `**Write Surface:** <file paths>`
   - `**Validation:** <commands or assertions>`
   - `**TDD Phase:** <RED | GREEN | REFACTOR | N/A>`
   - `**_Requirements: <ids>_**`
7. `## Audit Protocol` — section that references the `code-quality-check` skill. Marks the end of wave/lane content.

## Lane Dispatch Packet shape (commander → worker)

The commander wraps each lane's extracted markdown into this packet before dispatching via `/task`:

```
=== LANE DISPATCH PACKET ===
spec_slug: <slug from tasks.md filename>
wave_id: W<N>
lane_id: <X>
worktree_root: <absolute path>
audit_material_on_failure: <list from this wave's header>

=== LANE EXTRACT (verbatim from tasks.md) ===
### Lane <X>: <name>

#### Directive N: <intent>

##### Op Group N.M: <cluster name>

- [ ] W<wave>.<lane>.<directive>.<seq> <title>
  - <subtasks>
  - **Write Surface:** ...
  - **Validation:** ...
  - **TDD Phase:** ...
  - **_Requirements: ...**

(... all tasks in this lane ...)

=== END LANE DISPATCH PACKET ===
```

Workers parse the markdown body of the Lane Extract directly. They do not see the full `tasks.md`.

## Retry Packet shape (commander → worker on FAIL)

Prepended to the Lane Dispatch Packet when `code-quality-check` returned FAIL:

```
=== RETRY PACKET ===
wave_id: W<N>
lane_id: <X>
retry_count: <1 | 2>
audit_findings:
  - file: <path>:<line>
    severity: FAIL
    finding: <description>
    suggested_fix: <bounded correction>
audit_material: <wave's audit material verbatim>
previous_diff: |
  <git diff output for this lane's Write Surface>
=== END RETRY PACKET ===
```

Max 2 retries per wave. After the second FAIL, the commander halts with `max_retries_exceeded`.

## Worker completion report shape (worker → commander)

```
status: COMPLETE
spec_slug: <slug>
wave_id: W<N>
lane_id: <X>
tasks_completed:
  - id: W<wave>.<lane>.<directive>.<seq>
    write_surface: [<files>]
    validation_results: [<command: exit_code>, ...]
    tdd_phase: <RED|GREEN|REFACTOR|N/A>
diff_summary:
  files_touched: [<files>]
  insertions: <count>
  deletions: <count>
retry_findings_addressed: <list or []>
```

On HALT, replace with the worker HALT shape (`halt_code`, `halt_message`, `last_task_attempted`, `partial_diff`, `recommended_action`).

## Wave audit invocation

After all workers in a wave return, the commander invokes the `code-quality-check` skill against the union of all files in the wave's Write Surface. The verdict drives:

- `PASS` → advance to next wave.
- `PASS_WITH_WARNINGS` → log warnings, advance.
- `FAIL` → build Retry Packet, refire workers. Max 2 retries.

Pure scaffold waves (every task has `TDD Phase: N/A` and no `src/` mutation) may skip audit if and only if `git diff` shows no `src/` content touched. The commander logs the skip in the final report.

## Known synchronization risks

Whenever any of these change, both this skill AND the four charters must be updated together:

1. **Task ID format.** Currently `W<wave>.<lane>.<directive>.<seq>`. Changing the format breaks Write Surface Map parsing and worker task addressing.
2. **TDD Phase enum.** Currently `RED | GREEN | REFACTOR | N/A`. Adding values requires worker TDD enforcement logic to be extended.
3. **Wave header bullets.** Renaming any of `Concurrency`, `Depends on`, `Audit Material on Failure` breaks commander wave parsing.
4. **Required per-task bullets.** Currently `Write Surface`, `Validation`, `TDD Phase`, `_Requirements`. Adding or removing requires worker `task_field_missing` halt logic to be updated.
5. **Verdict vocabulary.** Currently `PASS | PASS_WITH_WARNINGS | FAIL`. Changing the verdict labels in `code-quality-check` requires the commander's PHASE 4 audit decision tree to be updated.

If you change one, patch the skill first (single source of truth for the contract), then propagate to the four charter bodies in the same commit if possible.

## Bash allowlist known gap

The charter frontmatter `bash` allowlist currently denies `pnpm *`, `node *`, `npm *`. Validation commands like `pnpm nx test <x>` will trigger `validation_command_not_permitted` HALT in workers. This is a frontmatter-level decision reserved for the Founder; the charters surface the gap loudly rather than silently skipping validation.

When the Founder unblocks this, the minimal additions to the two Worker charters' frontmatter are:

```yaml
bash:
  "pnpm *": allow
  "node *": allow
  "npm *": allow
  "mkdir *": allow
  "chmod +x *": allow
```

Commanders do not need these additions (they dispatch and audit; workers run validation).
