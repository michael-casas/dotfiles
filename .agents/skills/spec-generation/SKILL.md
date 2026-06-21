---
name: spec-generation
description: Master skill for generating GOD-LOCK Kiro specs (requirements.md, design.md, tasks.md) where tasks.md is wave/lane-aware and directly consumable by orchestrator agents without a separate transformer step. Use when generating a new spec under .agent/specs/<SPEC>/ for any package, feature, or annexation target. Produces a DAG-encoded tasks.md with explicit waves, lanes, _Requirements linkage, write-surface declarations, and audit-retry semantics. Enforces TDD, traceability, reusable-code quality (via code-quality-check), and write-surface conflict safety.
---

# spec-generation

## Purpose

Generate a complete Kiro spec set — `requirements.md`, `design.md`, `tasks.md` — where `tasks.md` is **directly consumable by orchestrator agents** without an intermediate transformer step.

`tasks.md` encodes a wave/lane DAG. Orchestrators read waves, summon worker subagents per lane within a wave, and gate progression on per-wave audit. If a wave fails the quality bar, the orchestrator issues `RETRY WAVE N:` with audit material — no replanning required.

This skill replaces the prior two-step pattern (Kiro → tasks.md → SYS_TRANSFORMER → LANES.md). The DAG lives inside `tasks.md`. `LANES.md` is no longer generated.

## Use This Skill When

- The user asks to generate a spec for a new package, feature, or annexation target.
- The user references `.agent/specs/<SPEC>/` as the output destination.
- Any runtime (kiro-cli, claude-code, codex, opencode) is being dispatched to produce or refine a spec.
- A prior spec needs upgrading from sequential Task 1..N format to wave-aware format.

## Hard Rules

1. **Three files. No more, no less.** `requirements.md`, `design.md`, `tasks.md` inside `.agent/specs/<SPEC>/`.
2. **Every task carries `_Requirements:`** linking back to one or more requirement IDs from `requirements.md`. No exceptions. This is the traceability key.
3. **`tasks.md` is wave-organized.** Top-level structure is `Wave N`, not `Task N`. Inside each wave, lanes run in parallel; tasks inside a lane run sequentially.
4. **Every task declares its `Write Surface`** — the exact files it is allowed to mutate. No two tasks in the same wave may share any path in their write surfaces.
5. **TDD is mandatory.** Every implementation task pairs with a test task in an earlier or same lane. Tests fail first (RED), then implementation passes (GREEN).
6. **No internal library APIs.** Reject patterns like `schema._def.typeName` (Zod internals), `Symbol(...)` private slots, or any access to underscore-prefixed members of third-party libraries.
7. **Domain logic lives in `src/lib/`** (deep modules). Entry points (`index.ts`, `bin/`) are thin routers. Apply the deletion test from `LANGUAGE.md`.
8. **Halt if grounding fails.** If you cannot identify concrete target files, requirements, or invariants — stop and report. Do not invent.

## Required Inputs

At minimum:

- Spec slug (e.g., `db-package`, `gqloom-agent-skeleton`, `payload-admin-shell`)
- Target package or feature surface (path under `packages/`, `apps/`, `tools/`, `kernel/`, `core/`, `sys/`, or `battlefields/<client>/`)
- Brief description of what the module does

Optional but raises quality:

- Pre-existing reference spec to align with (e.g., `packages/cli` as baseline)
- Prior art from a seed (`battlefields/atlantis-electrical/apps/Aesgoldseed/`)
- Specific Zod schemas, contracts, or kernel primitives that must be honored
- Cost/performance constraints

### Battlefield-specific grounding

When the target is an AES battlefield Payload/admin stack, bind the spec to the current Nx project identities and paths before drafting tasks or prompts:

- `battlefields/atlantis-electrical/apps/admin` → Nx project `admin`
- `battlefields/atlantis-electrical/packages/payload` → Nx project `payload-lib`

Prefer a minimally coupled admin host. If the battlefield cannot support a fully standalone Payload shape, state that explicitly and keep the seam as thin as possible. Use the seed as annexation evidence only — harvest concepts, not files.

See `references/payload-admin-stack-grounding.md` for the session-grounded checklist.

## File 1: `requirements.md`

EARS-style requirements (Easy Approach to Requirements Syntax). Mirror the Aesgoldseed format.

### Required structure

```markdown
# Requirements: <slug> — <one-line summary>

## Context

<2–5 sentences describing the module's purpose, where it lives in the GOD-LOCK topology
(kernel / core / sys / tooling / integration / battlefield), and what existing primitives
it composes from. Use the canonical vocabulary from LANGUAGE.md.>

## Glossary

- **<Concept_Name>**: <definition>
- ...

## Requirements

### Requirement 1: <short title>

**User Story:** As a <role>, I want <capability>, so that <outcome>.

#### Acceptance Criteria

1. THE <Subject> SHALL <behavior>
2. WHEN <trigger>, THE <Subject> SHALL <behavior>
3. IF <precondition>, THEN THE <Subject> SHALL <behavior>
...

### Requirement 2: <short title>

...
```

### Quality bar

- **>= 5 functional requirements** with at least 3 acceptance criteria each.
- **>= 3 non-functional requirements** covering: TDD, tooling consistency, error handling, performance, or operational concerns.
- **Every requirement has a unique number.** Acceptance criteria are sub-numbered (1.1, 1.2, ...) — these become the keys for `_Requirements:` linkage in `tasks.md`.
- **No requirement may rely on internal library APIs.** State the public-surface contract.

## File 2: `design.md`

Concrete architectural intent. The implementer should be able to start coding with no further interpretation.

### Required structure

```markdown
# Design: <slug> — <one-line summary>

## Architecture Context

<Where does this module sit? What kernel primitives does it consume? What seams does it
expose? Reference LANGUAGE.md vocabulary: module, interface, seam, depth, leverage, locality.>

## Package layout

<Tree of files this module will own. Mark generator-owned vs hand-written.
Apply the "domain logic in src/lib/, thin router in index.ts" rule.>

## Public API surface (`src/index.ts`)

```typescript
// Exact re-export shape. Types and runtime values separated.
export type { ... } from './lib/....js';
export { ... } from './lib/....js';
```

## Module designs

### <module-file>

<Purpose, interface, internal implementation sketch, error modes. Include real TypeScript
where it clarifies the contract. Call out depth: what does this module hide from callers?>

## Seams and adapters

<If the module exposes a seam, document the interface and at least one adapter.
One adapter alone is a hypothetical seam — only call it a seam if a second adapter exists
or is imminent.>

## Test strategy

<Unit tests (no external deps) vs integration tests (env-guarded).
Vitest. Co-located in src/__tests__/ or src/lib/<module>/<module>.test.ts.>

## Edge cases and failure modes

<Required: at least 3 named failure modes. Examples: resource exhaustion, malformed input,
upgrade hazards (library version drift), concurrency conflicts, partial-failure recovery.>

## Module boundary rules

<eslint depConstraints update for the new scope tag, if any.>
```

### Quality bar

- **`src/lib/` deepening** explicitly shown unless the module is genuinely a thin adapter (rare; defend the choice).
- **No internal library APIs.** If schema introspection is needed, use the library's official helpers (`instanceof`, `safeParse`, `_def` is forbidden, use Zod's official extraction utilities or document the version pin).
- **Concrete TypeScript snippets** for the public API. Stub implementations may be conceptual but signatures must be exact.
- **>= 3 edge cases.** Vague "handle errors gracefully" is not an edge case.

## File 3: `tasks.md` — The Wave DAG

This is the new shape. `tasks.md` is **the execution contract**. An orchestrator reads it and dispatches workers without re-planning.

The structure layers two concerns:

- **Execution semantics** — `Wave` (DAG horizontal slice) and `Lane` (parallel channel inside a wave). These drive orchestrator dispatch and write-surface conflict checking.
- **Narrative grouping** — `Directive` (intent grouping for a body of work) and `Op Group` (cohesive cluster of tasks within a Directive). These keep the markdown human-readable and align with the Aesgoldseed prior-art structure.

Directives and Op Groups live **inside** a Lane. They are pure markdown grouping — they do not change the DAG.

### Required structure

```markdown
# Tasks: <slug> — <one-line summary>

> **Execution Mode:** Wave-DAG. Orchestrator dispatches lanes within a wave in parallel,
> waits for wave completion, runs audit (see `code-quality-check`), retries if needed,
> then proceeds to next wave.

## DAG Summary

| Wave | Lanes | Concurrency | Depends On |
|------|-------|-------------|------------|
| 1    | A     | serial      | —          |
| 2    | A, B  | parallel    | Wave 1     |
| 3    | A     | serial      | Wave 2     |
| ...  | ...   | ...         | ...        |

## Write Surface Map

| Task ID  | Files (write surface) |
|----------|------------------------|
| W1.A.1.1 | `packages/<x>/package.json` |
| W2.A.1.1 | `packages/<x>/src/lib/foo/foo.test.ts` |
| W2.A.1.2 | `packages/<x>/src/lib/foo/foo.ts` |
| W2.B.1.1 | `packages/<x>/src/lib/bar/bar.test.ts` |
| W2.B.1.2 | `packages/<x>/src/lib/bar/bar.ts` |
| ...      | ... |

**Invariant:** No two tasks in the same wave share any path in their write surface.

---

## Wave 1: <name — e.g., Scaffold>

**Concurrency:** serial
**Depends on:** none
**Audit Material on Failure:** scaffold output, generator logs, package.json shape

### Lane A: <lane name — e.g., Package Scaffold>

#### Directive 1: <intent — e.g., Establish publishable package shell>

##### Op Group 1.1: <cohesive cluster — e.g., Run generator and align package.json>

- [ ] W1.A.1.1 Run nx-generate for the package
  - Invoke the `nx-generate` skill to discover correct flags
  - Run: `pnpm nx g @nx/js:library <name> --directory=packages/<name> --publishable ...`
  - Confirm `pnpm nx show project <name>` resolves
  - **Write Surface:** `packages/<name>/` (generator-owned)
  - **Validation:** `pnpm nx show project <name>` exits 0
  - **TDD Phase:** N/A
  - **_Requirements: 1.1, 1.2, 4.1_**

- [ ] W1.A.1.2 Align package.json to publishable shape
  - Set `type`, `main`, `module`, `types`, `exports`, `files`, `nx.tags`
  - **Write Surface:** `packages/<name>/package.json`
  - **Reference Files:** `packages/strings/package.json` (prior art)
  - **Validation:** `packages/<name>/package.json` matches publishable shape from design.md
  - **TDD Phase:** N/A
  - **_Requirements: 3.1, 3.2, 4.1_**

---

## Wave 2: <name — e.g., Pure Modules>

**Concurrency:** parallel
**Depends on:** Wave 1
**Audit Material on Failure:** test output, lint output, file diffs

### Lane A: <e.g., Type Mapping>

#### Directive 1: <intent — e.g., Zod-to-Postgres type mapping with deletion-test discipline>

##### Op Group 1.1: <cohesive cluster — e.g., Type mapping behavior>

- [ ] W2.A.1.1 Write failing tests for zodToPostgresType (RED)
  - Cover every mapped type from the design.md table
  - Cover unwrap behavior (optional, nullable)
  - Cover throw behavior for unmapped types
  - **Write Surface:** `packages/<x>/src/lib/zod-mapping/zod-mapping.test.ts`
  - **Validation:** `pnpm nx test <x>` shows N failing tests for zod-mapping
  - **TDD Phase:** RED
  - **_Requirements: 5.1, 5.2, 5.5_**

- [ ] W2.A.1.2 Implement zodToPostgresType and zodSchemaToTableDDL (GREEN)
  - Use Zod public introspection helpers (NOT `schema._def.typeName`)
  - Pure functions, no database access
  - **Write Surface:** `packages/<x>/src/lib/zod-mapping/zod-mapping.ts`
  - **Validation:** `pnpm nx test <x>` — all zod-mapping tests pass; `pnpm nx lint <x>` exits 0
  - **TDD Phase:** GREEN
  - **_Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_**

### Lane B: <e.g., Error Classes>

#### Directive 2: <intent — e.g., Typed error contracts for programmatic handling>

##### Op Group 2.1: <cohesive cluster — e.g., Error class definitions>

- [ ] W2.B.1.1 Write failing tests for error classes (RED)
  - **Write Surface:** `packages/<x>/src/lib/errors/errors.test.ts`
  - **Validation:** `pnpm nx test <x>` shows N failing tests for errors
  - **TDD Phase:** RED
  - **_Requirements: 2.4, 5.5_**

- [ ] W2.B.1.2 Implement error classes (GREEN)
  - **Write Surface:** `packages/<x>/src/lib/errors/errors.ts`
  - **Validation:** all error tests pass
  - **TDD Phase:** GREEN
  - **_Requirements: 2.4, 5.5_**

---

## Wave 3: <name — e.g., Integration & Public API>

**Concurrency:** serial
**Depends on:** Wave 2
**Audit Material on Failure:** build output, type-check output, dist contents

### Lane A: <e.g., Public API Wiring>

#### Directive 3: <intent — e.g., Compose lib modules into the public API surface>

##### Op Group 3.1: <cohesive cluster — e.g., Re-exports and build verification>

- [ ] W3.A.1.1 Wire src/index.ts re-exports
  - **Write Surface:** `packages/<x>/src/index.ts`
  - **Validation:** `pnpm nx build <x>` exits 0; dist/index.d.ts contains all exported names
  - **TDD Phase:** N/A (composition only)
  - **_Requirements: 7.1, 9.1_**

---

## Audit Protocol

Before proceeding from Wave N to Wave N+1, the orchestrator MUST run a wave audit using the
`code-quality-check` skill on every file written during the wave.

**Pass criteria:**
- All task validations succeed.
- `code-quality-check` returns `PASS` or `PASS_WITH_WARNINGS`.
- No write-surface invariant violations (no file mutated by two lanes).

**On failure:**
The orchestrator issues `RETRY WAVE N: <reason>` and dispatches a fix subagent with the
audit findings as input. After fix completion, re-run the wave audit. Max retries per wave: 2.
After 2 failures, halt and escalate to the human reviewer.

---

## Acceptance Criteria

<Final checklist. Every criterion traces to at least one task via _Requirements: linkage.>

- [ ] <criterion>
- [ ] ...
```

### Task ID Convention

`W<wave>.<lane>.<directive>.<task-in-op-group>` — e.g., `W2.A.1.2` = Wave 2, Lane A, Directive 1, second task in its Op Group.

This is the addressing scheme orchestrators use when dispatching, auditing, and retrying.

Directives and Op Groups are markdown narrative — they organize tasks within a lane for human readability and align with the Aesgoldseed prior-art structure. They do not affect execution semantics; only Wave + Lane drive the DAG.

### Wave / Lane Sizing Heuristics

- **Wave 1** is almost always a single-lane serial scaffold (generator runs, package.json shape, module boundary update). Do not try to parallelize scaffolding.
- **Wave 2+** parallelizes pure modules with disjoint write surfaces. Type mapping, error classes, utility functions — these run as separate lanes in the same wave.
- **Integration waves** (wiring, public API exports, end-to-end tests) often collapse back to a single lane because they touch shared surfaces (`src/index.ts`).
- **Publish / acceptance waves** are serial. They depend on everything before them.

If a wave has only one lane, the concurrency mode is `serial`. If a wave has ≥ 2 lanes with disjoint write surfaces, it's `parallel`.

### Quality bar for tasks.md

- **DAG Summary table present** at the top.
- **Write Surface Map table present** with every task ID enumerated.
- **No write-surface conflict within any wave.** Verify by hand before emitting.
- **Every task has `_Requirements:` linkage.**
- **Every task has TDD Phase declared** (`N/A`, `RED`, `GREEN`, or `REFACTOR`).
- **Audit Protocol section present** and references `code-quality-check`.
- **Acceptance Criteria preserved** from requirements.

## Procedure

1. **Discover the territory.** Read `LANGUAGE.md` and `CONTEXT.md` in the repo root. Read any prior `.agent/specs/<adjacent>/` set as reference. Inspect the target file surface to ground claims.

2. **Generate `requirements.md`.** EARS format. Number every requirement and acceptance criterion. Apply the quality bar.

3. **Generate `design.md`.** Map requirements onto module decomposition. Apply the deletion test and `src/lib/` deepening rule. Document seams honestly (one-adapter seams are hypothetical).

4. **Generate `tasks.md` with wave-DAG shape.**
   - Group tasks by dependency.
   - Wave 1: scaffolding (single serial lane).
   - Wave 2..N: pure modules in parallel lanes (disjoint write surfaces, TDD pairs).
   - Final wave: integration / wiring / publish (collapse to serial if shared surfaces).
   - Fill in DAG Summary and Write Surface Map tables.
   - Verify write-surface disjointness within each parallel wave by hand.
   - Add `_Requirements:` to every task.
   - Add Audit Protocol section.

5. **Self-audit before emitting.** Run the checklist below.

6. **Post-generation handoff gate.** After the spec files are written, run `code-quality-check` on the generated spec before handoff. If the audit fails, revise the spec and re-run the audit before declaring completion.

7. **Stop.** Do not implement. Do not run code. Spec generation only.

## After Spec Generation: Audit → Align → Execute Pipeline

Spec generation is step 1 of a 4-stage pipeline. After the three spec files are committed, the canonical flow is:

```
spec-gen → spec audit → spec align → execute
```

| Stage | Runtime | What it produces |
|-------|---------|-----------------|
| **spec-gen** | claude-code (SYS_PLANNER) | 3 Kiro spec files at `.agent/specs/<SPEC>/` |
| **spec audit** | Codex (cheaper, narrower) | Audit report at `.django/<SLUG>.AUDIT_REPORT.md` — check against `improve-codebase-architecture` standard |
| **spec align** | claude-code (SYS_PLANNER) | Fixes blocking issues identified by audit; modifies tasks.md in place |
| **execute** | Orchestrator (SYS_COMMANDER_*) | Reads tasks.md wave-DAG, dispatches workers per lane |

**Audit stage details:** Write a `.django/<SLUG>.audit.md` prompt that incorporates the `improve-codebase-architecture` checklist (available as a Hermes skill or at `.agents/skills/improve-codebase-architecture/` in the Mothership). Fire Codex with this prompt. Codex reads the three spec files and the cloned skill, evaluates against all audit criteria, and writes the audit report. Cost is typically ~$0.10–0.30 on gpt-5.4-mini.

**Align stage details:** Write a `.django/<SLUG>.ALIGN.md` prompt that references the audit report and specifies the exact fixes needed. Fire claude-code (SYS_PLANNER) with **no `--max-turns`** (unlimited). Claude reads the audit report and the spec files, applies the fixes to tasks.md, and outputs a completion message. Cost is typically ~$0.50–2.00 on claude-opus-4-7, depending on fix complexity.

**Do not skip the audit stage.** Codex catches coupling leaks, boundary violations, and task-structure issues that look correct to the gen-stage agent. The cost is negligible compared to discovering issues during execution.

## Runtime Selection and Turn Budget

This skill's output is consumed by one of several runtimes. Quality varies by runtime, and so does the turn budget needed to produce a complete spec:

| Runtime | Recommended `--max-turns` | Notes |
|---------|--------------------------|-------|
| `claude-code` (opus/sonnet) | **unlimited (omit `--max-turns`)** | SYS_PLANNER spec generation requires reading the codebase (4+ locations), consulting seeds, making architectural decisions, and producing 3 output files. The first 5–8 turns are codebase reading alone. **Never limit turns for claude-code SYS_PLANNER runs** — see failure mode below. |
| `codex` | 15–20 | Faster but narrower reasoning. Pre-prime with grounding material. |
| `opencode` | 15–20 | Similar budget to codex; depends on underlying model. |
| `kiro-cli` | N/A | Structured generator, no turn budget issue. |

**Common failure mode:** setting `--max-turns 12` (Claude Code default from `~/dotfiles` or mental default) for a complex multi-file spec that requires codebase grounding across 4+ locations, seed consultation, architectural decisions, and 3 output files. The SYS_PLANNER burns 8+ turns reading and never writes files. When this happens, the process logs show `error_max_turns`, the out.log contains a JSON result with `is_error: true`, and zero spec files exist under `.agent/specs/`. The OS process exits silently while the registry entry shows `running` — a stale-entry trap.

**Fix:** for claude-code SYS_PLANNER spec generation, **omit `--max-turns` entirely**. Claude Code's default unlimited turn budget gives the agent the space it needs. Codex and opencode may still benefit from a bounded budget (15-20 turns) for their narrower reasoning tasks. If the process already hit max_turns and died, check `proc.json` and `.agent-delegates/` for the JSON result line or verify with `kill -0 <pid>` — the OS process is already dead and the registry entry must be manually updated to `failed`.

**Distinction:** the unlimited budget applies to SYS_PLANNER spec generation (reading, research, writing). SYS_COMMANDER implementation runs may still benefit from a turn budget to prevent runaway costs on open-ended implementation tasks.

## Self-Audit Checklist (run before emitting)

- [ ] Three files present: `requirements.md`, `design.md`, `tasks.md`.
- [ ] `requirements.md`: ≥ 5 FRs with ≥ 3 acceptance criteria each, ≥ 3 NFRs, EARS format, numbered.
- [ ] `design.md`: package layout, public API in TypeScript, ≥ 3 edge cases, no internal library APIs (no `_def`, no `Symbol(...)`).
- [ ] `tasks.md`: DAG Summary table, Write Surface Map table, every task uses `W<wave>.<lane>.<directive>.<seq>` ID format, every task has `_Requirements:` and `TDD Phase`, Audit Protocol section present.
- [ ] **Wave / Lane / Directive / Op Group nesting consistent:** Waves contain Lanes; Lanes contain Directives; Directives contain Op Groups; Op Groups contain tasks. Task IDs reflect the path.
- [ ] **Write surface disjointness verified:** no two tasks in the same parallel wave touch the same file.
- [ ] **Traceability complete:** every acceptance criterion in `requirements.md` maps to at least one task via `_Requirements:`.
- [ ] **Domain logic placed in `src/lib/`** unless the module is genuinely an adapter.
- [ ] **TDD pairs present:** every implementation task has a preceding or same-lane RED test task.
- [ ] **Halt conditions checked:** if any required input is missing, halt with explicit reason — do not invent.

## Halt / Refusal Conditions

Stop and report instead of fabricating output when:

- The spec slug is ambiguous or conflicts with an existing spec.
- The target file surface cannot be honestly grounded (no package path, no clear consumer, no prior art).
- Required contracts or kernel primitives the module must honor are unspecified and you cannot infer them safely.
- The user is asking for a feature that requires architectural changes outside the scope of a single spec (e.g., new package strata, new orchestration patterns) — escalate to architecture review first.
- Write-surface conflicts cannot be resolved without collapsing parallel waves to serial, AND the user explicitly asked for parallel execution.

## Output Contract

- Three files written to `.agent/specs/<SPEC>/`.
- A short summary printed to stdout listing: wave count, lane count, total task count, parallel-wave count, requirements count, write-surface conflict status (`CLEAN` or `CONFLICTS: <list>`).
- No application source files modified.

## Anti-Patterns to Reject

- Sequential `Task 1..N` format with no wave grouping. (Old shape.)
- `LANES.md` as a separate file. (The DAG belongs in `tasks.md`.)
- Tasks without `_Requirements:` linkage.
- Tasks without explicit Write Surface.
- Parallel waves where two lanes mutate the same file.
- Validation bullets like "tests pass" without an exact command.
- Use of `schema._def.typeName` or any underscore-prefixed library internal.
- Domain logic dumped at `src/` root with no `lib/` deepening.
- Speculative parallelization (forcing two lanes when there is only one real task).
- Lane assignment without an audit reducer (every wave must have an Audit Material specification).
- **Borrowing transport-layer vocabulary from internal Zod contracts** (e.g., `CLEARED / PARTIAL_CLEARANCE / BLOCKED` from `ClearancePayloadSchema`, `ORD / env.k / packet / envelope` terminology, etc.). When mining prior art like `tojson.contract.ts` from a seed, harvest **structural ideas only** (wave grammar, dependency edges, write-surface conflict invariants) and re-express them in practical reusable markdown vocabulary. Reserved verdict words for code-quality-check are `PASS / PASS_WITH_WARNINGS / FAIL`, not contract-internal verdicts.

## Notes

For the post-generation handoff checklist, see `references/post-generation-handoff.md`.

This skill is the entry point for any GOD-LOCK spec generation. It assumes the executor is one of:

- `kiro-cli` (fast structured generator)
- `claude-code` (deeper reasoning, slower)
- `codex` (bounded execution)
- `opencode` (alternative runtime)

The skill produces output usable by all of them. Quality varies by runtime, not by skill output shape.

After the spec is generated, the **next step is execution** by an orchestrator agent who reads `tasks.md` directly and dispatches workers per wave. No transformer step. No `LANES.md`.

For the audit step inside the orchestrator's loop, see the `code-quality-check` skill.

## Downstream Consumer Contract

The `tasks.md` you emit is parsed directly by `SYS_COMMANDER_*` orchestrator charters (located at `~/.dotfiles/opencode/agent/SYS_COMMANDER_GO.md` and `SYS_COMMANDER_CODEX.md`). Those charters perform regex-style extraction on:

- `## DAG Summary` table (Wave | Lanes | Concurrency | Depends On columns)
- `## Write Surface Map` table (Task ID | Files columns)
- `## Wave N: <name>` headers with `**Concurrency:**`, `**Depends on:**`, `**Audit Material on Failure:**` bullets
- `### Lane <X>: <name>` per-lane sections (extracted verbatim and passed as the Lane Dispatch Packet)
- `#### Directive N:` and `##### Op Group N.M:` narrative groupings (preserved in the extract but not parsed)
- `- [ ] W<wave>.<lane>.<directive>.<seq>` checkbox lines with `**Write Surface:**`, `**Validation:**`, `**TDD Phase:**`, `**_Requirements: ...**` bullets per task

**If you change the markdown shape of any of those structural anchors, you break the parsing contract for every downstream charter.** When the spec needs evolution, patch this skill first so the contract is single-source, then propagate to the charters. Never let charter behavior diverge from this skill.

For the full downstream parsing contract — exact headers, packet shapes, halt codes — see `references/downstream-charter-contract.md`.
