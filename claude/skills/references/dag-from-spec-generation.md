# Migrating from spec-generation to atdd-dag-generation

This document is for spec authors and orchestrators that have been
generating specs with `spec-generation` and want to upgrade to the
ATDD form. The migration is **additive** — no spec-generation output
is invalidated; we're adding structure to task bodies.

## What's the same

- **Three files at `.kiro/specs/<slug>/`** — `requirements.md`,
  `design.md`, `tasks.md`. Identical to spec-generation.
- **DAG Summary table** at the top of `tasks.md`. Identical schema.
- **Write Surface Map table**. Identical schema, but the third column
  is now `Validation Script` instead of (or in addition to) any
  prior column.
- **Lane Classification Map**. Identical schema.
- **Audit Protocol section**. Identical schema, with one new pass
  criterion: "No validator orphan."
- **Wave / Lane / Directive / Op Group nesting**. Identical.
- **Task ID format** `W<wave>.<lane>.<directive>.<seq>`. Identical.

## What changes

### Task body shape

Before (spec-generation):
```markdown
- [ ] W2.A.1.1 Write failing tests for zodToPostgresType (RED)
  - Cover every mapped type from the design.md table
  - Cover unwrap behavior (optional, nullable)
  - **Write Surface:** `packages/<x>/src/lib/zod-mapping/zod-mapping.test.ts`
  - **Validation:** `pnpm nx test <x>` shows N failing tests for zod-mapping
  - **TDD Phase:** RED
  - **_Requirements: 5.1, 5.2, 5.5_**
```

After (atdd-dag-generation):
```markdown
- [ ] W2.A.1.1 zodToPostgresType maps Zod primitives to Postgres column types (RED)
  - **Write Surface:** `packages/<x>/src/lib/zod-mapping/zod-mapping.test.ts`
  - **TDD Phase:** RED
  - **_Requirements: 5.1, 5.2, 5.5_**
  - **Executable:** `pnpm agent:validate:W2.A.1.1`

  ### Scenario 1: Primitive types map to Postgres columns
  - **Given:** A Zod object schema with ZodString, ZodNumber, ZodBoolean fields
  - **When:** zodToPostgresType(schema) is called
  - **Then:** It returns {string: 'text', number: 'numeric', boolean: 'boolean'}

  ### Scenario 2: Optional and nullable unwrap
  ...

  ### Definition of Done
  - [ ] `.agent/tools/validate-W2.A.1.1.mjs` exists and exits 1 (RED)
  - [ ] All 3 scenarios implemented as failing tests
  - [ ] Test runner reports "3 failed, 0 passed"
```

Three structural changes per task:

1. **Title is action-oriented, not "Write tests for X"** — describes
   the behavior being specified, not the activity.
2. **`**Executable:**` field replaces `**Validation:**`** — a single
   command instead of a description of what should happen.
3. **`### Scenario N: <title>` blocks** with Given/When/Then —
   3-8 per task, each independently assertable.
4. **`### Definition of Done` block** — 3-6 mechanical checks, no
   subjective language.

### Validator script existence

Every task ID `<task-id>` now has a corresponding
`.agent/tools/validate-<task-id>.mjs` script. The orchestrator's
enqueuer MUST run this before `kanban_complete()`. A task without a
validator is a spec bug, not a missing piece.

### Audit Protocol additions

```diff
**Pass criteria:**
  - All task validations succeed.
  - `code-quality-check` returns `PASS` or `PASS_WITH_WARNINGS`.
  - No write-surface invariant violations.
+ - No validator orphan (every declared task ID has a corresponding
+   `.agent/tools/validate-<task-id>.mjs`).
```

## Migration procedure

1. **Pick a spec to migrate.** Start with the most-recent
   spec-generation output. Smaller specs are easier to learn the
   shape on.
2. **For each task, expand the body.** Move the prose "Cover every
   mapped type" bullets into `### Scenario N: <title>` blocks with
   explicit Given/When/Then. The scenarios should be independently
   assertable — if a scenario only makes sense if the previous
   scenario passed, split it or add an explicit precondition.
3. **Replace `**Validation:**` with `**Executable:**`.** The
   executable must be a single shell command, not a description.
4. **Add a `### Definition of Done` block.** 3-6 mechanical checks.
   Replace vague "tests pass" with "test runner reports 'N failed,
   0 passed' for this task ID" (or equivalent assertion).
5. **Run the scaffolder:**
   ```bash
   python3 scripts/generate.py \
     --spec .kiro/specs/<slug>/tasks.md \
     --output .agent/tools/
   ```
6. **Wire package.json scripts:**
   ```bash
   python3 scripts/generate.py \
     --spec .kiro/specs/<slug>/tasks.md \
     --output .agent/tools/ \
     --wire-package-json
   ```
7. **Audit:**
   ```bash
   python3 scripts/generate.py \
     --spec .kiro/specs/<slug>/tasks.md \
     --output .agent/tools/ \
     --audit
   ```
8. **Run the audit on the spec itself** with `code-quality-check` to
   catch any regressions from the migration.
9. **Commit.** New commit message: `refactor(spec): migrate <slug>
   to atdd-dag-generation`.

## When NOT to migrate

- **Sequential single-agent specs.** If the work is going to be done
  by one agent in a single session, the wave-DAG overhead is
  unjustified. Use `atdd-spec` directly, write the scenarios, skip
  the DAG scaffolding.
- **Pure research tasks.** Use `atdd-spec`'s research pattern, not
  the DAG.
- **Trivial bug fixes.** If the change is a one-file fix with one
  acceptance test, write the test and commit. No spec needed.

## Common migration mistakes

- **Scenarios that read like prose.** "When the system processes
  input correctly" is not a scenario. "When the function is called
  with the schema from Scenario 1, it returns the expected mapping"
  is a scenario. Always include a mechanical Then.
- **DoD with subjective checks.** "Looks good" or "is clean" are
  not DoD items. Replace with mechanical checks: lint passes, file
  exists, test count matches.
- **One big scenario instead of 3-8 small ones.** A scenario that
  tries to cover the whole feature in one Given/When/Then will have
  vague Given ("a properly configured system") and subjective Then
  ("everything works"). Break it down.
- **GREEN task with new scenarios.** The GREEN task inherits the
  RED's scenarios. Adding new scenarios to GREEN without a paired
  RED is a contract violation — flag in audit.
- **Validator script that runs the whole test suite.** The
  validator's contract is one task ID. Filter by `--testPathPattern`
  or `--testNamePattern` to scope the assertion to this task's
  tests only.
