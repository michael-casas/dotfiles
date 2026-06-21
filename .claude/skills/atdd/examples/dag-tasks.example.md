# Tasks: zod-postgres-mapper — Wave-DAG with ATDD bodies

> **Execution Mode:** Wave-DAG with ATDD task bodies. Each task body contains
> Given/When/Then scenarios and binds to `pnpm agent:validate:<task-id>`.
> Workers receive the task body verbatim from the enqueuer.

## DAG Summary

| Wave | Lanes | Concurrency | Depends On |
|------|-------|-------------|------------|
| 1    | A     | serial      | —          |
| 2    | A, B  | parallel    | Wave 1     |
| 3    | A     | serial      | Wave 2     |

## Write Surface Map

| Task ID  | Files (write surface) | Validation Script |
|----------|------------------------|-------------------|
| W1.A.1.1 | `packages/zod-pg-mapper/package.json` | `.agent/tools/validate-W1.A.1.1.mjs` |
| W1.A.1.2 | `packages/zod-pg-mapper/project.json` | `.agent/tools/validate-W1.A.1.2.mjs` |
| W2.A.1.1 | `packages/zod-pg-mapper/src/lib/zod-mapping/zod-mapping.test.ts` | `.agent/tools/validate-W2.A.1.1.mjs` |
| W2.A.1.2 | `packages/zod-pg-mapper/src/lib/zod-mapping/zod-mapping.ts` | `.agent/tools/validate-W2.A.1.1.mjs` |
| W2.B.1.1 | `packages/zod-pg-mapper/src/lib/errors/errors.test.ts` | `.agent/tools/validate-W2.B.1.1.mjs` |
| W2.B.1.2 | `packages/zod-pg-mapper/src/lib/errors/errors.ts` | `.agent/tools/validate-W2.B.1.2.mjs` |
| W3.A.1.1 | `packages/zod-pg-mapper/src/index.ts` | `.agent/tools/validate-W3.A.1.1.mjs` |

**Invariant:** No two tasks in the same wave share any path in their write surface.
**Invariant:** Each task ID appears in `.agent/tools/validate-<task-id>.mjs`.

## Lane Classification Map (Agent / Model scoped per lane)

| Lane | Agent Classification | Model Tier | Rationale |
|------|----------------------|-----------|-----------|
| W1.A | SCAFFOLD-AGENT | `gpt-5.4-mini` | Mechanical generator + config alignment |
| W2.A | PRIMITIVE-AGENT | `gpt-5.4` | Type mapping logic needs reasoning |
| W2.B | PRIMITIVE-AGENT | `gpt-5.4-mini` | Error class definitions are mechanical |
| W3.A | INTEGRATION-AGENT | `gpt-5.4-mini` | Re-export composition only |

## Validation Contract

Every task ID `<task-id>` declared in this file has a corresponding validator at
`.agent/tools/validate-<task-id>.mjs`. The validator's contract:

- Exit 0 → task is GREEN
- Exit 1 → task is RED, error printed to stdout
- Exit 2 → task is BLOCKED (preconditions not met, surface out of scope, etc.)

A task cannot be marked complete until its validator exits 0. The Kanban
dispatcher MUST call `pnpm agent:validate:<task-id>` before `kanban_complete()`.

---

## Wave 1: Scaffold

**Concurrency:** serial
**Depends on:** none
**Audit Material on Failure:** generator logs, package.json shape, Nx project resolution

### Lane A: Package Scaffold

#### Directive 1: Establish publishable package shell

##### Op Group 1.1: Run Nx generator and align config

- [ ] W1.A.1.1 Run nx-generate for the zod-pg-mapper package
  - **Write Surface:** `packages/zod-pg-mapper/package.json`
  - **TDD Phase:** N/A
  - **_Requirements: 1.1, 1.2, 4.1_**
  - **Executable:** `pnpm agent:validate:W1.A.1.1`

  ### Scenario 1: Package directory exists
  - **Given:** A clean Nx workspace at the project root
  - **When:** `pnpm nx g @nx/js:library zod-pg-mapper --directory=packages/zod-pg-mapper --publishable` runs to completion
  - **Then:** `packages/zod-pg-mapper/` exists with `package.json`, `tsconfig.json`, and `src/index.ts`

  ### Scenario 2: Nx recognizes the project
  - **Given:** The package was generated in Scenario 1
  - **When:** `pnpm nx show project zod-pg-mapper` runs
  - **Then:** Exit code is 0 and the project metadata includes `type: "lib"`, `sourceRoot`, and `tags: ["type:lib", "scope:shared"]`

  ### Scenario 3: Package builds without errors
  - **Given:** The package was generated in Scenarios 1 and 2
  - **When:** `pnpm nx build zod-pg-mapper` runs
  - **Then:** Exit code is 0 and `dist/packages/zod-pg-mapper/index.js` exists

  ### Definition of Done
  - [ ] `packages/zod-pg-mapper/` directory exists
  - [ ] `pnpm nx show project zod-pg-mapper` exits 0
  - [ ] `pnpm nx build zod-pg-mapper` exits 0
  - [ ] `.agent/tools/validate-W1.A.1.1.mjs` exists and exits 0
  - [ ] No manual file edits beyond generator output

- [ ] W1.A.1.2 Align project.json tags and dep constraints
  - **Write Surface:** `packages/zod-pg-mapper/project.json`
  - **TDD Phase:** N/A
  - **_Requirements: 3.1, 3.2, 4.1_**
  - **Executable:** `pnpm agent:validate:W1.A.1.2`

  ### Scenario 1: Tags include scope and type
  - **Given:** The zod-pg-mapper project exists
  - **When:** The `tags` array in `project.json` is read
  - **Then:** It contains both `"type:lib"` and `"scope:shared"`

  ### Scenario 2: ESLint dep constraint is present
  - **Given:** The zod-pg-mapper project exists in the Casita monorepo
  - **When:** The `targets.lint.options` for ESLint is read
  - **Then:** It includes the dep constraints from `eslint.config.base.mjs` enforcing `scope:shared` boundaries

  ### Definition of Done
  - [ ] `tags` includes `"type:lib"` and `"scope:shared"`
  - [ ] ESLint dep constraint is wired
  - [ ] `pnpm nx lint zod-pg-mapper` exits 0 (no lint errors on empty src)
  - [ ] `.agent/tools/validate-W1.A.1.2.mjs` exists and exits 0

---

## Wave 2: Pure Modules

**Concurrency:** parallel
**Depends on:** Wave 1
**Audit Material on Failure:** test output, lint output, file diffs

### Lane A: Zod-to-Postgres Type Mapping

#### Directive 1: Map Zod primitives to Postgres column types with TDD discipline

##### Op Group 1.1: Type mapping behavior

- [ ] W2.A.1.1 zodToPostgresType maps Zod primitives to Postgres column types (RED)
  - **Write Surface:** `packages/zod-pg-mapper/src/lib/zod-mapping/zod-mapping.test.ts`
  - **TDD Phase:** RED
  - **_Requirements: 5.1, 5.2, 5.5_**
  - **Executable:** `pnpm agent:validate:W2.A.1.1`

  ### Scenario 1: Primitive types map to Postgres columns
  - **Given:** A Zod object schema with `ZodString`, `ZodNumber`, `ZodBoolean` fields
  - **When:** `zodToPostgresType(schema)` is called
  - **Then:** It returns `{string: 'text', number: 'numeric', boolean: 'boolean'}` and exits 0

  ### Scenario 2: Optional and nullable unwrap
  - **Given:** A Zod schema with `.optional()` and `.nullable()` modifiers
  - **When:** `zodToPostgresType(schema)` is called
  - **Then:** Modifiers are unwrapped before mapping; the inner type determines the Postgres column

  ### Scenario 3: Unmapped type throws
  - **Given:** A Zod schema with `ZodIntersection` (not in the mapping table)
  - **When:** `zodToPostgresType(schema)` is called
  - **Then:** It throws `UnsupportedZodTypeError` with a message naming the offending type

  ### Definition of Done
  - [ ] `.agent/tools/validate-W2.A.1.1.mjs` exists and exits 1 (RED)
  - [ ] All 3 scenarios are implemented as failing tests in the Write Surface file
  - [ ] Test runner reports "3 failed, 0 passed" for this task ID
  - [ ] No implementation file has been written yet

- [ ] W2.A.1.2 Implement zodToPostgresType to make W2.A.1.1 pass (GREEN)
  - **Write Surface:** `packages/zod-pg-mapper/src/lib/zod-mapping/zod-mapping.ts`
  - **TDD Phase:** GREEN
  - **_Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_**
  - **Executable:** `pnpm agent:validate:W2.A.1.1` (re-runs the same validator, now exits 0)

  ### Scenario 1: [inherited from W2.A.1.1]
  ### Scenario 2: [inherited from W2.A.1.1]
  ### Scenario 3: [inherited from W2.A.1.1]

  ### Definition of Done
  - [ ] `pnpm agent:validate:W2.A.1.1` exits 0
  - [ ] All 3 scenarios from W2.A.1.1 now pass
  - [ ] Implementation uses Zod public introspection helpers only (no `schema._def.typeName`)
  - [ ] `pnpm nx lint zod-pg-mapper` exits 0
  - [ ] No new test files added in this task (only implementation)

### Lane B: Error Classes

#### Directive 2: Typed error contracts for programmatic handling

##### Op Group 2.1: Error class definitions

- [ ] W2.B.1.1 Define UnsupportedZodTypeError class surface (RED)
  - **Write Surface:** `packages/zod-pg-mapper/src/lib/errors/errors.test.ts`
  - **TDD Phase:** RED
  - **_Requirements: 2.4, 5.5_**
  - **Executable:** `pnpm agent:validate:W2.B.1.1`

  ### Scenario 1: Error class is constructable
  - **Given:** A test imports `UnsupportedZodTypeError` from the package
  - **When:** `new UnsupportedZodTypeError('ZodIntersection', ['ZodString'])` is called
  - **Then:** The instance has `.name === 'UnsupportedZodTypeError'`, `.message` contains `'ZodIntersection'`, and `.supported` is `['ZodString']`

  ### Scenario 2: Error is throwable and catchable
  - **Given:** A test wraps a function that throws `UnsupportedZodTypeError`
  - **When:** The function executes
  - **Then:** A `try/catch` block catches the error and `err instanceof UnsupportedZodTypeError` is `true`

  ### Definition of Done
  - [ ] `.agent/tools/validate-W2.B.1.1.mjs` exists and exits 1 (RED)
  - [ ] All 2 scenarios are implemented as failing tests
  - [ ] Test runner reports "2 failed, 0 passed" for this task ID
  - [ ] No error class file has been written yet

- [ ] W2.B.1.2 Implement UnsupportedZodTypeError class (GREEN)
  - **Write Surface:** `packages/zod-pg-mapper/src/lib/errors/errors.ts`
  - **TDD Phase:** GREEN
  - **_Requirements: 2.4, 5.5_**
  - **Executable:** `pnpm agent:validate:W2.B.1.1` (re-runs the same validator, now exits 0)

  ### Scenario 1: [inherited from W2.B.1.1]
  ### Scenario 2: [inherited from W2.B.1.1]

  ### Definition of Done
  - [ ] `pnpm agent:validate:W2.B.1.1` exits 0
  - [ ] All 2 scenarios from W2.B.1.1 now pass
  - [ ] `pnpm nx lint zod-pg-mapper` exits 0
  - [ ] Error class extends `Error` (not Object)

---

## Wave 3: Integration & Public API

**Concurrency:** serial
**Depends on:** Wave 2
**Audit Material on Failure:** build output, type-check output, dist contents

### Lane A: Public API Wiring

#### Directive 3: Compose lib modules into the public API surface

##### Op Group 3.1: Re-exports and build verification

- [ ] W3.A.1.1 Wire src/index.ts re-exports
  - **Write Surface:** `packages/zod-pg-mapper/src/index.ts`
  - **TDD Phase:** N/A (composition only)
  - **_Requirements: 7.1, 9.1_**
  - **Executable:** `pnpm agent:validate:W3.A.1.1`

  ### Scenario 1: zodToPostgresType is exported
  - **Given:** The package has been built
  - **When:** A consumer imports `import { zodToPostgresType } from '@casita-media/zod-pg-mapper'`
  - **Then:** TypeScript resolves the import and the runtime export exists in `dist/index.js`

  ### Scenario 2: UnsupportedZodTypeError is exported
  - **Given:** The package has been built
  - **When:** A consumer imports `import { UnsupportedZodTypeError } from '@casita-media/zod-pg-mapper'`
  - **Then:** TypeScript resolves the import and the runtime export exists in `dist/index.js`

  ### Scenario 3: No internal helpers leak
  - **Given:** The package has been built
  - **When:** `dist/index.d.ts` is read
  - **Then:** It contains only `zodToPostgresType`, `UnsupportedZodTypeError`, and their types — no `_def`, no `ZodMapping` private types

  ### Definition of Done
  - [ ] `pnpm nx build zod-pg-mapper` exits 0
  - [ ] `pnpm agent:validate:W2.A.1.1` exits 0 (regression: implementation still works)
  - [ ] `pnpm agent:validate:W2.B.1.1` exits 0 (regression: error class still works)
  - [ ] `dist/index.d.ts` contains exactly 2 exports (function + class)
  - [ ] No new files added beyond `src/index.ts`

---

## Audit Protocol

Before proceeding from Wave N to Wave N+1, the orchestrator MUST run a wave audit using the
`code-quality-check` skill on every file written during the wave.

**Pass criteria:**
- All task validations succeed (every `pnpm agent:validate:<task-id>` exits 0).
- `code-quality-check` returns `PASS` or `PASS_WITH_WARNINGS`.
- No write-surface invariant violations (no file mutated by two lanes).
- No validator orphan (every declared task ID has a corresponding `.agent/tools/validate-<task-id>.mjs`).

**On failure:**
The orchestrator issues `RETRY WAVE N: <reason>` and dispatches a fix subagent with the
audit findings as input. After fix completion, re-run the wave audit. Max retries per wave: 2.
After 2 failures, halt and escalate to the human reviewer.

## Acceptance Criteria

- [ ] All 7 task validators exit 0
- [ ] `pnpm nx test zod-pg-mapper` exits 0
- [ ] `pnpm nx build zod-pg-mapper` exits 0
- [ ] `pnpm nx lint zod-pg-mapper` exits 0
- [ ] `dist/index.d.ts` exposes only public API
- [ ] Every requirement from `requirements.md` is traceable to a task via `_Requirements:`
