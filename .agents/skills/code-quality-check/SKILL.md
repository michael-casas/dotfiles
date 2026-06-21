---
name: code-quality-check
description: Django's reusable-code quality standard for GOD-LOCK code audits. Use during wave audits in orchestrator/worker execution loops, before merging worker output, after a feature branch reaches a checkpoint, or any time you need a structured "is this code worth keeping" evaluation. Returns a PASS/PASS_WITH_WARNINGS/FAIL verdict with concrete findings tied to specific files and line numbers. Enforces module depth, deletion-test reasoning, seam discipline, TDD evidence, no-internal-API rule, src/lib/ deepening, and the LANGUAGE.md vocabulary.
---

# code-quality-check

## Purpose

A structured code audit against Django's reusable-code quality standard. This is the canonical quality gate for:

- Wave audits inside orchestrator execution loops (gate before proceeding to the next wave).
- Worker output review before merge.
- Annexation candidate evaluation (is this concept worth lifting from a seed into the mothership?).
- Self-audit before opening a PR.

The output is a verdict — `PASS`, `PASS_WITH_WARNINGS`, or `FAIL` — with concrete file:line findings. The verdict drives orchestrator decisions: proceed, retry-with-fixes, or escalate.

## Use This Skill When

- An orchestrator agent has dispatched workers for a wave and the wave has completed; before advancing to the next wave, run this audit on every file in the wave's write surface.
- A worker subagent has finished a task and you need to decide whether to accept its output.
- You are reviewing seed code for annexation into the mothership and need to judge whether it meets the quality bar.
- Any agent — Claude Code, Codex, OpenCode — needs to apply the standard before signaling completion.

## Required Inputs

- **Target files:** explicit list of files to audit (typically the write surface of the wave just completed).
- **Spec context:** path to `.kiro/specs/<slug>/` so the audit can verify traceability against `requirements.md` and `tasks.md`.
- **Wave ID (if applicable):** e.g., `W2` — used in the audit output for orchestrator routing.

### Tooling Context (GOD-LOCK)

The mothership uses **Biome** as the primary linting and formatting tool, not ESLint. A custom Nx plugin `@god-lock/biome` (at `plugins/biome/`) registers per-project targets (`biome`, `biome-check`, `biome-format`, `biome-ci`) for any project with a `biome.json` at its root. The root `biome.json` defines workspace law and drives `lint-staged`.

ESLint remains registered via `@nx/eslint/plugin` but only for module-boundary enforcement (`@nx/enforce-module-boundaries`) and framework-specific rules (Next.js, React). When validating a package during audit:

1. **Run `pnpm nx biome-check <project>` first** (or `pnpm exec biome check <projectRoot>`) — this is the primary lint/format gate.
2. **Run `pnpm nx lint <project>` second** — this validates cross-module dependency constraints only.
3. **Do NOT treat `pnpm nx lint` as the primary lint gate.** Reaching for ESLint by default is a tooling hierarchy mistake in this workspace.

If a package lacks a `biome.json`, it cannot participate in the Biome pipeline. Flag this as a Check 8 (write-surface) finding if the spec calls for the package to be linted. The `biome.json` for a new package should contain `{"root": false}` if the workspace root already has a `$schema`-bearing `biome.json` (Biome 2.x treats `$schema` as a root marker; nested configs must explicitly opt out with `"root": false`).

See `references/god-lock-tooling.md` for the full Biome/ESLint split and nested-config details.

Optional but raises signal:

- Prior audit findings on the same surface (so the auditor can verify they were addressed).
- Specific contracts or kernel primitives the code must honor.

## Quality Bar — The Ten Checks

Run all ten checks. Each produces a finding (PASS, WARN, or FAIL) with a file:line reference where applicable.

### Check 1: Module depth

For every module (file with an interface and an implementation), evaluate:

- Does the interface hide substantial behavior, or does it expose nearly as much complexity as the implementation hides?
- Apply the **deletion test:** if this module were deleted, would complexity (a) disappear, or (b) reappear scattered across many callers?

**FAIL** if the module is shallow without justification. A "thin convenience wrapper" with no extracted concept is a fail. Pass-through adapters that exist only to satisfy taste are fails.

**Acceptable shallow modules:** thin routers (e.g., `bin/glx.ts` dispatch), genuine adapters, public re-export surfaces (`index.ts`).

### Check 2: src/lib/ deepening

Domain logic — pure functions, business rules, computational behavior — must live under `src/lib/<module>/`. Entry points (`src/index.ts`, `src/bin/`) must be thin routers or pure re-exports.

**FAIL** if domain logic is dumped at `src/` root or inlined into entry points.

**Acceptable exceptions:** modules so small (< 50 LOC of real logic) that `src/lib/` extraction would create more concepts than it removes. Defend the choice in a code comment.

### Check 3: No internal library APIs

The code must not reach into private fields of third-party libraries. Reject:

- `schema._def.typeName` (Zod internals — use `instanceof ZodString` etc.)
- `obj[Symbol(...)]` accessing library-private slots
- Any access to underscore-prefixed members of imported modules
- Accessing `node_modules/*/dist/internals/*` paths

**FAIL** on any occurrence. These break on library upgrades and are not part of the public contract.

**Acceptable exception:** none. If the library does not expose a public API for the introspection needed, the design itself is wrong — flag it as a design-level finding and escalate.

### Check 4: TDD evidence

For every implementation task in the wave, verify:

- A test file exists co-located with or alongside the implementation.
- The test was written first (check git history or the spec's TDD Phase declaration).
- The test asserts real behavior — no `expect(true).toBe(true)` empty passes.
- The test names describe behavior, not internals (`returns NUMERIC for z.number()` not `calls switch case correctly`).

**FAIL** if implementation exists without a co-located test, or if tests assert nothing meaningful.

### Check 5: Interface as test surface

Tests must exercise the **public interface** of the module, not internal helpers.

**FAIL** if tests reach into module internals (importing non-exported functions, mutating private state, asserting on implementation detail).

**Exception:** unit tests for pure utility functions that *are* the public surface of their `lib/<module>` directory.

### Check 6: Seam honesty

If the design declares a seam (an interface with multiple potential implementations):

- **One adapter is a hypothetical seam.** Acceptable only if a second adapter is imminent (named in the spec or design doc).
- **Two or more adapters justify the seam.** Verify both adapters honor the interface contract.

**FAIL** on "elegant" seams with no real second implementation and no roadmap for one. These are premature abstractions.

### Check 7: Vocabulary discipline

Code, comments, type names, and documentation must use the canonical vocabulary from `LANGUAGE.md`:

- `module` not `component`, `service`, `layer`, `thing` (unless networked service)
- `seam` not `boundary`
- `adapter` not `glue`, `wrapper`, `integration`
- `compiler` for staged transformations with invariants
- `planner` when ordering / dependencies / mutation authority are involved
- `kernel primitive` not `utility`, `helper`
- `annexation` not `migration`, `port`, `copy`

**WARN** on vocabulary drift. **FAIL** if the wrong word causes a design misconception (e.g., a `service` that is actually a pure module being treated as if it needs networked-service semantics).

### Check 8: Write-surface honesty

Verify the files actually mutated by this wave match the Write Surface declared in `tasks.md`:

- No files outside the declared write surface were mutated.
- Every file in the declared write surface was either mutated or has a documented reason for absence.

**FAIL** on out-of-surface writes — this is a wave-protocol violation and breaks parallelism safety guarantees.

### Check 9: Edge cases addressed

The design.md declared at least 3 edge cases. Verify the implementation handles each:

- Look for explicit error classes, defensive checks, or test cases covering each declared edge case.
- Vague "wrap in try/catch" is not handling. Named error types with specific messages are.

**FAIL** if declared edge cases have no corresponding code or tests.

### Check 10: Traceability

Verify every implemented behavior traces back to a requirement:

- Pick 3 random source-of-truth functions in the implementation.
- For each, find the corresponding task in `tasks.md` via the file's appearance in a Write Surface.
- Walk the task's `_Requirements:` linkage back to `requirements.md`.
- The behavior must be justified by the requirement.

**FAIL** on orphan code — behavior that exists with no requirement justification (scope creep, speculative features).

## Verdict Calculus

After running all ten checks:

- **PASS:** zero FAILs, zero or few WARNs. Proceed to next wave.
- **PASS_WITH_WARNINGS:** WARNs only, no FAILs. Orchestrator may proceed but findings must be addressed in the next wave or recorded as technical debt with explicit ticket.
- **FAIL:** one or more FAILs. Orchestrator must issue `RETRY WAVE N:` with the findings as input to a fix subagent. After 2 retries, escalate to human review.

## Output Contract

Return a structured report:

```markdown
# Code Quality Audit: Wave <N> (<slug>)

**Verdict:** PASS | PASS_WITH_WARNINGS | FAIL
**Files audited:** <count>
**Findings:** <FAIL count> FAIL, <WARN count> WARN, <PASS count> PASS

## Findings

### Check 1: Module depth — <PASS|WARN|FAIL>
<finding text, with file:line refs>

### Check 2: src/lib/ deepening — <PASS|WARN|FAIL>
...

(repeat for all 10 checks)

## Retry Material (FAIL verdicts only)

For an orchestrator dispatching a fix subagent, the following findings must be addressed:

1. <file:line> — <FAIL description> — <suggested fix>
2. ...

## Notes for the Next Wave

<any forward-looking observations: technical debt logged, vocabulary drift to monitor,
seams that are still hypothetical but may become real, etc.>
```

## Procedure

1. **Load context.** Read `LANGUAGE.md`, `CONTEXT.md`, the target spec's `requirements.md` and `tasks.md`. Identify the wave under audit and its Write Surface declaration.

2. **Inventory files.** Build the actual list of files mutated during the wave (via git status, file mtimes, or the orchestrator's manifest). Compare against the declared Write Surface — note any discrepancies as Check 8 evidence.

3. **Run all ten checks.** For each, record PASS / WARN / FAIL with concrete file:line references. Do not summarize without evidence.

4. **Compute verdict.** Apply the calculus above.

5. **Emit the report.** Use the exact structure in the Output Contract.

6. **Stop.** Do not fix. Do not modify code. Audit only.

## Anti-Patterns to Reject

- "Looks good to me" verdicts without per-check evidence.
- WARNs that should be FAILs because they violate hard rules (no internal APIs, no orphan code).
- FAILs that should be WARNs because the rule is genuinely contextual (e.g., a 30-line utility legitimately stays at `src/` root).
- Findings without file:line references — orchestrators cannot act on vague feedback.
- Vocabulary policing that ignores the substance. A correctly named bad design is still a bad design.
- Ignoring the spec — audit must be grounded in `requirements.md` and `tasks.md`, not the auditor's taste alone.

## Notes

This skill is the **wave audit reducer** for the orchestrator/worker execution pattern. Every wave that has parallel lanes MUST run this audit before proceeding to the next wave. Serial waves may skip the audit when the work is mechanical (e.g., generator scaffolding) but must run it when the work involves logic.

The skill is also useful outside orchestrator loops — for self-audit before opening a PR, for annexation candidate evaluation, or for any structured "is this code worth keeping" question.

It does NOT replace human review for high-risk surfaces: contract schemas, public APIs, security-sensitive code paths, or anything that touches `kernel/` primitives. Human review is required for those regardless of audit verdict.

**See also:**
- `references/god-lock-tooling.md` for GOD-LOCK-specific Biome/ESLint tooling hierarchy and nested-config guidance.
- `god-lock-package-implementation` skill for the downstream pipeline (worktree creation, async delegation, post-run review, merge).
