---
name: atdd
description: ATDD (Acceptance Test-Driven Development) is the bridge between problem identification and agent implementation. Instead of vague requirements, write black-box test scenarios that define what "done" means. This umbrella consolidates two complementary skills: (1) atdd-spec — single-seam ATDD specifications for one boundary at a time, and (2) atdd-dag-generation — wave-DAG task sets with executable validation, used when the Kanban dispatcher orchestrates multi-lane implementation. Load this skill BEFORE writing any spec the implementing agent (Sonnet, Codex, OpenCode) will execute against, and BEFORE defining a wave-DAG with executable gates for parallel worker dispatch.
version: 1.0.0
author: Django
license: MIT
metadata:
  hermes:
    tags: [atdd, specification, tdd, gates, wave-dag, executable-validation, evidence, black-box, acceptance]
    category: engineering
    related_skills: [god-lock-mothership, code-quality-check, subagent-driven-development, dispatch-intent-gate, meta-orchestration]
    priority: high
---

# ATDD — Acceptance Test-Driven Development (Class-Level Umbrella)

This is the canonical playbook for writing ATDD specifications that ground agent implementation in concrete, assertable test scenarios. It consolidates two previously-distinct skills:

- **atdd-spec** — single-seam ATDD specifications (one boundary, one fix, one spec)
- **atdd-dag-generation** — wave-DAG task sets where every task body is an ATDD block, with executable validation wired as `pnpm agent:validate:<task-id>`

A maintainer would write this as ONE skill: the spec format and the wave-DAG format share the same scenarios, the same Definition of Done, and the same evidence-capture discipline. The single-seam case is just a DAG with one wave and one lane.

## The Core Thesis

> ATDD specs are the bridge between problem identification and agent implementation. The implementing agent (Sonnet, Codex, OpenCode) reads the spec and implements until all scenarios pass.

The flow: **Problem identified → write ATDD spec → agent reads spec + implements → tests pass → done.**

## Table of Contents

1. **Section A — The ATDD Spec Format** (Problem Statement, Scenarios, DoD)
2. **Section B — When to Reach for ATDD (vs Patch Yourself)** (the sequential-wall signal)
3. **Section C — Evidence Capture** (capture real wire format, error output, API responses)
4. **Section D — Model Tier Matching** (work type → model class)
5. **Section E — Spec Dispatch Patterns** (path-reference, /goal, post-impl verification)
6. **Section F — Convergence ATDD** (capstone spec for system-level validation)
7. **Section G — The Wave-DAG Format** (tasks.md with ATDD task bodies)
8. **Section H — The Validation Script Contract** (`.agent/tools/validate-<task-id>.mjs`)
9. **Section I — ATDD as Kanban Task Bodies** (the binding to Hermes dispatcher)
10. **Section J — Anti-Patterns and Founder-Mandated Patterns** (lockup avoidance, expansion grants, HALT-vs-autonomous)

---

## Section A — The ATDD Spec Format

Every ATDD spec follows this structure. The single-seam and wave-DAG forms are both built on it.

```markdown
# ATDD Specification: [Feature or Bug Fix Name]

## 1. Problem Statement
* **Context:** [2-3 sentences on current system state]
* **The Gap / Bug:** [Exactly what is broken or missing. Include raw error messages.]
* **Impact:** [What happens if this isn't fixed?]

## 2. System Constraints & Environment
* **Runtime:** [e.g., Python 3.11, Go 1.23, Node.js 20]
* **Frameworks:** [e.g., stdlib net/http, pytest, jest]
* **External Dependencies:** [e.g., OpenCode API, PostgreSQL]

## 3. Black-Box Test Cases (The "Green" Gates)

### Scenario 1: [Descriptive Title]
* **Given:** [Initial state, mock data, setup]
* **When:** [Action or function invoked]
* **Then:** [Assertable output, state change, or schema]

### Scenario 2: [Edge Case / Error]
* **Given:** [Faulty, missing, or malicious input]
* **When:** [Agent attempts to process]
* **Then:** [Expected error, fallback, or log]

## 4. Definition of Done (DoD)
- [ ] 100% of the above Scenarios implemented as automated tests.
- [ ] Regression testing passes (existing features remain unbroken).
- [ ] Code coverage meets or exceeds [X]%.
```

### Saving Conventions

ATDD specs live at `.agent/specs/atdd/<seam-name>.atdd.md` relative to the project root.

**Seam name = architectural boundary, not bug symptom:**
- ✅ `kimi-streaming.atdd.md` — the streaming seam
- ❌ `fix-double-completed.atdd.md` — the symptom

See `templates/spec-template.md` for the canonical template. See `examples/spec-example-codex-models-schema.atdd.md` and `examples/spec-example-kimi-streaming.md` for worked examples.

### When to Apply ATDD (vs Patch Yourself)

**CRITICAL DECISION RULE:** When you hit a sequential wall — iterative error messages where fixing one reveals the next, or a protocol incompatibility where the real client behaves differently from curl — STOP patching and write an ATDD spec + delegate.

This is a CTO-level discipline. The pattern to break:

```
❌ Error A → patch A → Error B → patch B → Error C → patch C (whack-a-mole)
✅ Error A → ATDD spec with all known errors + probe strategy → delegate to Sonnet/Codex
```

Signals that trigger ATDD delegation:
- **Wire format iteration:** fixing one missing field reveals another (`missing field 'X'` → add X → `missing field 'Y'`)
- **Client vs curl divergence:** the real client (Codex, etc.) fails on a stream that curl handles correctly
- **Timeout/connection issues:** the client disconnects during protocol handshake gaps
- **Real process lifecycle needed:** assertions must involve starting a real server, running a real client subprocess, and inspecting exit codes + output
- **More than 3 manual patch attempts on the same seam** — stop, spec, delegate

The implementing agent should handle the implementation. Your job is to specify the behavior (ATDD spec), dispatch to the agent, and verify the result — not to iterate patches yourself.

### Scenario Best Practices

- **3-8 scenarios per task** is the sweet spot. Fewer than 3 = task too small. More than 8 = split the task.
- **Include at least:** one happy path, one edge case, one error case per fix.
- **Scenarios must be assertable without human judgment.** A test runner should be able to validate them. No "the response looks reasonable" gates.
- **Each scenario is independently assertable.** No "Scenario 3 only makes sense if Scenario 2 passed."
- **Scenarios must capture real process lifecycle** when debugging protocol/server integration. Start the real server, run the real client as a subprocess, assert on exit code and output content (not just HTTP response status). The Go test pattern uses `httptest.NewServer` + `exec.CommandContext` with timeout + `defer server.Close()`. See `references/spec-worker-instructions-atdd.md`.

### Definition of Done (DoD)

Keep DoD minimal — 3-6 items, all verifiable without human judgment. The 3 pillars:
1. Scenarios implemented as automated tests
2. Regression testing passes
3. Tests green

Don't add coverage percentage gates unless they're enforced in CI.

---

## Section B — Evidence Capture (Before You Delegate)

**"It's ALL about context for the agent."** — Founder, June 2026

Before dispatching an ATDD spec to an implementing agent, capture REAL evidence of the problem. Descriptions are not enough — the agent needs to see the actual wire format, the actual error output, the actual API responses.

### What to Capture

1. **The working reference** — if a different provider/service handles the same thing correctly, capture its exact response, save to a JSON file, and reference it:
   ```bash
   curl -s https://some-api.com/v1/models -H "Authorization: Bearer ***" > references/working-reference.json
   ```

2. **The broken output** — capture what your code actually returns and save side-by-side:
   ```bash
   curl -s http://localhost:4000/v1/models > references/broken-output.json
   ```

3. **Client error logs** — run the real client and capture stderr:
   ```bash
   echo "test" | codex --profile bridge-kimi exec - 2>&1 | tee references/client-errors.log
   ```
   Or via a Python/Go debug harness that starts the server, runs the client as a subprocess, and writes timestamped logs.

4. **Root cause snapshot** — compile findings into a single `EVIDENCE.md` the agent reads directly:
   ```markdown
   # Evidence: [Problem Name]
   
   ## Working Reference
   ```json
   {exact response here}
   
   ## Current Broken Output
   ```json
   {exact response here}
   
   ## Client Error
   ```
   error: missing field 'X' at line N column M
   body: {partial response}
   
   ## Root Cause
   [1-2 sentence analysis]
   
   ## Fix
   [Specific code change needed]
   ```
   ```

### Where It Lives

Evidence files sit alongside the spec:

```
.agent/specs/atdd/
├── codex-models-schema.atdd.md     ← The spec (contract)
├── EVIDENCE.md                      ← The evidence (context)
├── opencode-native-models.json      ← Raw API capture
└── debug-logs/
    └── codex-e2e-20260607_102949.log ← Raw client output
```

The spec is the contract. The evidence is the supporting data. The agent reads both.

See `references/spec-evidence-capture.md`, `references/spec-evidence-driven-specs.md`, and `references/spec-evidence-pattern.md` for the full discipline.

### Why This Matters

Without evidence the agent guesses at wire formats, error messages, and correct fixes. With evidence the agent can:
- Compare working vs broken responses side-by-side
- See exact JSON field names the client requires
- Read exact error message text to search for in code
- Validate its fix before running the test suite

### Advanced Investigation Techniques

**Binary extraction for schema reverse-engineering.** When the target system (Codex, agent CLI) has a strict API schema but no documentation, extract the exact schema from its compiled binary:

```bash
ls -la $(which codex)   # follow symlinks to native binary
grep -a -o -P '.{0,100}ModelInfo.{0,200}' /path/to/binary | head -5
# or Python binary read + find known JSON keys
```

The binary contains the exact Rust serde struct definitions. Proven June 7, 2026 during the Codex models schema investigation.

**Agent session handoff across limits.** When an agent hits a session limit (usage cap, timeout) mid-work: (1) document exact state (files changed, what next, key resume commands), (2) send `/compact` to free context, (3) feed the handoff document back as the next prompt — the agent reads its own state and continues.

---

## Section C — Model Tier Matching (Work Type → Model Class)

**Critical efficiency rule:** match the implementing agent's capability to the nature of the work, NOT the importance of the task.

| Work type | Examples | Right model | Reasoning |
|---|---|---|---|
| **Mechanical edits** | Add/remove struct field, fix JSON tag, change config value | Haiku / GPT-5.4-mini | Zero reasoning needed — error message tells you exact line and fix |
| **Investigative work** | Read compiled binary to extract schema, debug protocol handshake, analyze client/curl divergence | Sonnet / GPT-5.4 | Needs protocol-level reasoning and investigative initiative |
| **Architecture design** | Design new module, plan multi-file refactor, spec complex behavior | Opus / GPT-5.5 | Needs system-level thinking and tradeoff analysis |

Applying Opus to a struct field fix is wasteful. Applying Haiku to a binary reverse-engineering task will stall. Choose deliberately.

### Founder's Workflow Role Framework

Beyond task complexity, the Founder has established a **workflow role** for each model family that governs the spec-to-implementation pipeline:

| Role | Model | What they do |
|---|---|---|
| **Law-maker** | **Sonnet** (Claude Code) | Lays down the laws. Architecture, ATDD specs, infrastructure setup, toolchain configuration. Writes the contracts and constraints that everything else follows. |
| **Tightener** | **Codex** (GPT) | Implementation against specs. Takes the ATDD spec and makes it pass. Works within established boundaries. |
| **Executor** | **Deepseek-v4-flash** | Cheap sub-agent workforce. Fills in boilerplate, runs validation, handles bounded tasks under manager coordination. |

**Key behavioral difference:** Sonnet "chugs" — it stays on a problem until it's truly solved, running multi-step diagnostics and self-correcting rather than racing to a plausible answer. This makes it ideal for infrastructure work where correctness matters more than speed. Codex "finishes fast" — it optimizes for token efficiency, good for implementation against clear specs. Codex requires more babysitting (verify scope drift, check every file changed) but covers ground quickly.

### Routing Rule of Thumb for the Spec Pipeline

- **ATDD spec to author?** → Sonnet (or human). Spec-writing requires staying power and edge-case hunting.
- **Implementation against a finished spec?** → Codex or Sonnet, depending on complexity. Codex for straightforward specs, Sonnet for specs that involve investigative work.
- **Bounded mechanical work against a spec?** → Deepseek sub-agent under a manager profile (cheapest path).
- **Toolchain / infrastructure wiring?** → Sonnet every time. The one-shot approach (install → config → verify → fix → verify) requires a model that iterates until green.

Established and embedded June 8, 2026 after the Casita monorepo harness session: Sonnet set up 20+ ESLint plugins, 6 layered configs, TypeScript strict mode, Husky + lint-staged, Nx module boundaries, and commitlint — all in one session, surviving a multi-hour debugging loop on ESLint flat config plugin resolution.

---

## Section D — Spec Dispatch Patterns

Once the ATDD spec is written, dispatch to an implementing agent with a lightweight prompt:

```
Implement the fixes specified in `.agent/specs/<seam>.atdd.md`.

WORKING DIRECTORY: <absolute-project-path>

TDD APPROACH:
1. Read `.agent/specs/<seam>.atdd.md` — all scenarios define the expected behavior
2. Read `.agent/specs/<seam>.EVIDENCE.md` if it exists — contains real error logs and API responses
3. Read any reference files in `.agent/specs/<seam>/` (e.g., `opencode-native-models.json`)
4. Write test cases first (they will fail initially — RED phase)
5. Implement fixes to make them pass (GREEN phase)
6. Run the project's test suite — must pass
7. Run static analysis (vet, lint) — must be clean

Do NOT touch unrelated code. Keep the implementation minimal.
```

### Path-Reference Dispatch (Default for Long Prompts)

**Observed pattern (2026-06-11+):** when the agent prompt is >2K characters (charters, ATDD specs, complex context), `cmux send "..."` with the full prompt inline is wasteful + breaks on quoting + forces the agent to re-parse on every keystroke. The default is **path-reference dispatch**:

1. **Write the full prompt to disk** — at `~/.hermes/.django/_commands/<id>.md` OR at the worktree's `.agent/commands/<name>.md`. Both work; pick based on whether the prompt is project-scoped or session-scoped.
2. **Send a short path reference** via cmux: `cmux send --surface S 'read /path/to/charter.md and execute exactly as written'`
3. **The agent reads the file on first turn**, not the inline text.

**Why this works:**
- Short prompts are atomic — no quoting issues, no truncation, easy to re-fire the same prompt
- The full prompt can be 50K+ characters without choking the cmux send buffer
- Reusable across sessions — the same charter can be re-dispatched to a different surface or a different model
- Reviewable before fire — the Founder can `read /path/to/charter.md` and edit before the agent runs
- The "ground" in `cmux send --workspace W --surface S '...'` is human-verifiable: 1 line, easy to spot a wrong dispatch

**Proven pattern:** for the AES Fable 5 design-system campaign (June 14, 2026), the 25K-char charter lived at `~/.hermes/campaigns/TOKEN-DISTILL.md`. cmux sent a 200-char prompt that pointed to the file. Sonnet read it on first turn, executed the campaign over 27 minutes, and the charter was re-readable for post-mortem.

### Dispatching with `/goal` (Claude Code) for Self-Verifying Loops

For problems where the fix is uncertain and requires iterative probing (e.g., protocol handshake debugging), use Claude Code's `/goal` command to create a self-verifying loop. Codex 0.139.0 also has `/goal` (under the `goals` feature flag — `codex features list | grep goals` to verify, `codex features enable goals` if disabled). The Codex `/goal` is **a standing goal that persists across turns**, not a single-iteration "do X then exit."

```bash
/goal Make the bridge work with Codex CLI

Evidence to read:
- .agent/specs/atdd/codex-models-schema.atdd.md
- .agent/specs/atdd/EVIDENCE.md
- .agent/specs/atdd/opencode-native-models.json
- .agent/specs/atdd/debug-codex-e2e.py

Rules:
1. Fix code per the evidence
2. Run the debug harness: python3 debug-codex-e2e.py
3. Exit 0 → report summary
4. Exit 1 → read debug log, identify next issue, fix, goto 2
5. Max 5 iterations — if still failing, report all findings and halt
```

Use when: the error is iterative (fixing one reveals the next), the real client is the oracle, or multiple unknown issues exist. Django builds the harness and sets the goal — does not iterate patches.

### Post-Implementation Verification (Required — HARD RULE)

After the implementing agent finishes, Django **must verify** before declaring done:

1. **Check scope** — Run `git diff --stat` (or equivalent) and review every file that changed. Verify each file is directly related to the ATDD spec scenarios. If any file is out of scope, revert those changes with `git checkout HEAD -- <file>`.
2. **Run full test suite** — The agent may have run specific tests but not the full suite. Run the complete project test suite to catch regressions.
3. **Run static analysis** — `go vet ./...`, `ruff check .`, `npm run lint`, etc.
4. **Report** — Summarize what changed, what was reverted, and the test results.

**This is non-negotiable.** Never trust the agent's self-report that "all tests pass" — verify independently. The ATDD spec defines the exact boundary of change. Everything outside that boundary is scope drift.

### Agent Scope Drift Is the #1 Post-Impl Risk

Implementing agents (Sonnet, Codex, OpenCode) frequently fix more than the spec asks for — they rename functions, restructure packages, add feature flags, or rewrite adjacent code "to be clean." After the agent finishes, `git diff --stat` against HEAD and verify ONLY spec-relevant files changed. Revert everything else. The test suite is your gate: if the spec-compliant changes pass tests and the scope drift broke things, the drift was wrong.

**Scope drift example (real, from kimi-streaming session):** Sonnet implemented the two spec-compliant fixes (Completed flag, Instructions field) but also rewrote the entire non-streaming `Respond()` method with a request-coalescing pattern that wasn't in any scenario. This broke 4 existing tests. Restoring the original synchronous `Respond()` via `git checkout HEAD -- internal/service/bridge.go` fixed all regressions while keeping the spec-compliant changes.

---

## Section E — Convergence ATDD (Capstone Spec)

When multiple components have been built separately and need to be proven as a system, write a **convergence ATDD** — a capstone spec that defines the full end-to-end flow as a single win condition.

The convergence spec differs from a regular ATDD in scope:
- **Regular ATDD:** tests ONE seam or component (e.g., "input parser handles TUI message format")
- **Convergence ATDD:** tests the FULL PIPELINE across all component boundaries (e.g., "batch JSON → enqueue → dispatch → surface agent runs → complete → Discord ping")

### When to Write a Convergence ATDD

- Multiple components were built independently and need to be validated together
- No single test exercises the full end-to-end path
- The win condition is "the whole system works" not "this one function works"
- You need a spec that assigns to an agent (Opus) to write the COMPLETE test suite that makes the pipeline undeniable

### Structure

```markdown
# ATDD Specification: <system-name>-convergence

## 1. Problem Statement
[Components built independently, no single test exercises full path]

## 2. Pipeline Flow (The Canonical Path)
[ASCII diagram showing the full data flow through all components]

## 3. Black-Box Test Cases (The "Green" Gates)
### Scenario 1: [Component A works correctly]
### Scenario 2: [Component B works correctly]
### Scenario 3: [Component A+B handoff works]
### ... (components assembled)
### Scenario N: [Full end-to-end — all components together]

## 4. Definition of Done — THE WIN CONDITION
[Explicit list of all checks that must pass in a single run]
- [ ] Scenario 1: ...
- [ ] ...
- [ ] Scenario N: Full pipeline runs without manual intervention
- [ ] The system exits 0 on success, pings Discord on completion
- [ ] All existing tests pass
```

### Convergence Spec as Opus Assignment

A convergence ATDD is the ideal assignment for Opus. Instead of asking Opus to implement anything, give Opus the convergence spec and the existing code, and ask Opus to:

> "Write the COMPLETE test suite — unit, integration, and e2e — that proves this pipeline is undeniable. Every failure mode documented. Every edge case gated. So no agent can mess it up."

Opus writes ALL tests (the reds). Any other agent (Sonnet, Codex) can implement against them. The tests are the single source of truth — the convergence spec is the win condition.

This was proven June 7, 2026: Opus wrote the complete test suite for the batch dispatch pipeline (conftest.py, fixtures, surface dispatch tests, failure mode tests) with one deliberately tracked xfail for the Postgres retry path. Every other failure mode was gated and passing.

### Example: Pipeline Convergence

From the June 7, 2026 session: the batch-pipeline-convergence ATDD defined six scenarios from surface dispatch delivery through full end-to-end including Discord ping via browser-harness. The win condition was explicit: all six scenarios pass in a single run from batch JSON to Discord notification with no manual intervention.

### Founder's Addendum ATDD Pattern (Override Spec)

When a campaign or multi-wave execution is already underway and the Founder changes the rules — gates, model assignments, verification protocol, or Definition of Done — write a **Founder's Addendum** ATDD. This is a binding override document that supersedes the parent spec's execution protocol while preserving its lane-level task definitions and write surfaces.

#### When to Write a Founder's Addendum

- **Model swap mid-campaign** — e.g., "Sonnet replaced with Kimi K2.6 for all sub-agents"
- **Gate lifted** — e.g., "Opus Wave Gate LIFTED, manager commits autonomously"
- **New verification mandate** — e.g., "All verification via browser-harness, no model self-certification"
- **DoD revised** — e.g., "Pre-lane server checks required, retry loop until all green"
- **Original spec was written for a different execution context** and the Founder is re-routing

#### Anatomy

A Founder's Addendum contains: (1) Override Status — explicit statement of which parts of the parent spec are replaced, (2) Pre-Lane Dispatch Checks, (3) Wave Gate (Revised), (4) Retry Loop Logic, (5) Authority Chain, (6) Model Mandate Table, (7) Win Condition (DoD).

Save the addendum alongside the parent spec: `.agent/specs/<campaign>/founders-addendum.atdd.md`.

---

## Section F — The Wave-DAG Format (atdd-dag-generation)

Generate a complete spec set — `requirements.md`, `design.md`, `tasks.md` — where `tasks.md` is a **wave-DAG with ATDD-formatted task bodies**. Every task in a lane is a black-box test specification: Given/When/Then scenarios with executable validation that binds to a `pnpm agent:validate:<task-id>` script.

This is the convergence of two concerns: spec-generation (wave/lane/DAG structure, write-surface disjointness, lane classification map) + atdd-spec (Given/When/Then scenarios, executable validation, evidence-driven grounding). The result: a spec that an orchestrator reads structurally (waves, lanes, parallelism) AND a worker reads behaviorally (test scenarios, executable green gates). No re-translation between the two views.

### Use This Skill When

- The user asks for a spec with executable acceptance criteria per task
- The implementation is multi-lane and multi-wave (3+ waves typical)
- The Kanban dispatcher will be the orchestrator (it reads DAG shape, not free-form prose)
- Each task's "done" is provable by running a single test command
- The work spans multiple files and modules (justifies the wave-DAG overhead)
- You want the lane body to ship as a kanban task description without rewriting

**Don't use this skill for:**
- Single-file changes (just write the ATDD spec, no DAG needed)
- Pure research tasks (use the atdd-spec research pattern — `references/spec-research-atdd-pattern.md`)
- Specs that will be implemented sequentially by a single agent (no parallelism to manage)

### Output Files

```
.kiro/specs/<slug>/
├── requirements.md     # EARS requirements (inherited from spec-generation)
├── design.md           # Architecture + public API (inherited from spec-generation)
└── tasks.md            # Wave-DAG with ATDD task bodies (this skill's contribution)
```

Plus, for every task ID declared in `tasks.md`, a corresponding validation script is scaffolded at:
```
.agent/tools/validate-<task-id>.mjs   # default (Node)
.agent/tools/validate-<task-id>.py    # only for Python lanes
```

### Stack Default (Founder's Lock, June 8 2026)

The validator scaffold runs **Node.js** (`node .agent/tools/validate-<task-id>.mjs`). The TypeScript test command pattern is `pnpm nx test <x> -- --testNamePattern="<pattern>"`. Per Founder's explicit capability ladder:

| Rank | Language | When |
|---|---|---|
| 1 (default) | **TypeScript** | Everything in Casita and God-Lock until proven otherwise |
| 2 (concurrency) | Go | Only when TS hits a proven wall (thousands of concurrent streams, sustained throughput) |
| 3 (final escalation) | C++ + v8 Node-addon | Almost never — hot-path FFI only |
| 4 (data/tooling only) | Python | Hermes plugin, data/analysis — NOT Casita application code |

This skill's `assets/dag-validator.template.mjs` is Node. If a lane legitimately needs Python (e.g., a Hermes plugin task), swap the template for a Python variant and the executable for `python .agent/tools/validate-<task-id>.py`. Do not scaffold Python by default; the policy is TS-only unless the task explicitly belongs to the Hermes or data/analysis layer.

**Casita is TS Nx monorepo only until proven capability limitation.** When dispatching a spec, the Lane Classification Map should name the test runner (`pnpm nx test` for TS, `uv run pytest` for Python, `go test` for Go). Specs that mix languages across lanes must justify the split in the design.md.

### Task Body Shape (replaces spec-generation's prose body)

```markdown
- [ ] W2.A.1.1 zodToPostgresType maps Zod primitives to Postgres column types (RED)
  - **Write Surface:** `packages/<x>/src/lib/zod-mapping/zod-mapping.test.ts`
  - **TDD Phase:** RED
  - **_Requirements: 5.1, 5.2, 5.5**
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
```

The next task (`W2.A.1.2`) would be GREEN with the same scenarios but the DoD inverts:

```markdown
- [ ] W2.A.1.2 Implement zodToPostgresType to make W2.A.1.1 pass (GREEN)
  - **Write Surface:** `packages/<x>/src/lib/zod-mapping/zod-mapping.ts`
  - **TDD Phase:** GREEN
  - **_Requirements: 5.1, 5.2, 5.3, 5.4, 5.5**
  - **Executable:** `pnpm agent:validate:W2.A.1.1` (note: same validation, now exits 0)

  ### Scenario 1: [inherited from W2.A.1.1]
  ### Scenario 2: [inherited from W2.A.1.1]
  ### Scenario 3: [inherited from W2.A.1.1]

  ### Definition of Done
  - [ ] `pnpm agent:validate:W2.A.1.1` exits 0
  - [ ] All 3 scenarios from W2.A.1.1 now pass
  - [ ] Implementation uses Zod public introspection helpers only (no `schema._def.typeName`)
  - [ ] `pnpm nx lint <x>` exits 0
  - [ ] No new test files added in this task (only implementation)
```

### Why the Worker Sees the Scenarios, Not Just the Executable

The validation script is the oracle. But a worker who only sees `pnpm agent:validate:W2.A.1.1` and exits doesn't know *what* the validator is checking. The scenarios in the task body are the human-readable contract — what the validator mechanically verifies. Both must be present.

### Why GREEN Task Bodies Inherit RED Scenarios

Two reasons:
1. **No drift:** if the RED scenarios change, the GREEN immediately breaks, surfacing the drift
2. **Reading as a unit:** the implementer sees the contract (RED) and the task (GREEN) on the same page

If a GREEN task's scenarios diverge from its RED pair, that's a contract violation — flag it in audit.

### Required Structure of `tasks.md`

Inherits all spec-generation requirements (DAG Summary, Write Surface Map, Lane Classification Map, Audit Protocol), plus the task body shape above. **Invariant:** No two tasks in the same wave share any path in their write surface. **Invariant:** Each task ID appears in `.agent/tools/validate-<task-id>.mjs`.

### Procedure

1. **Discover territory.** Same as spec-generation. Read LANGUAGE.md, CONTEXT.md, prior specs. Inspect target file surface.
2. **Generate `requirements.md` and `design.md`.** Inherit spec-generation's templates verbatim. ATDD additions go in `tasks.md`.
3. **Decompose into waves/lanes.** Same as spec-generation. Write Surface disjointness per wave is mandatory.
4. **For each task, write the ATDD body.** Use the shape above. Every task gets: Title, Write Surface, TDD Phase, `_Requirements:`, **Executable:**, 3-8 Given/When/Then scenarios, Definition of Done checklist.
5. **Pair RED and GREEN tasks.** Every GREEN task cites a prior or same-lane RED task. The GREEN task's body references the RED's scenarios.
6. **Scaffold validation scripts.** Run `scripts/dag-generate.py --spec .kiro/specs/<slug>/tasks.md --output .agent/tools/` to emit one `.agent/tools/validate-<task-id>.mjs` per task ID.
7. **Wire the validators into package.json.** Add `pnpm agent:validate:<task-id>` scripts. Use a glob pattern or explicit per-task entries.
8. **Self-audit.** Inherit spec-generation's checklist. Add: every task has Given/When/Then scenarios, every task has Definition of Done, every task has `**Executable:**` field, every task ID has a corresponding validator file, every RED task is paired with a GREEN task (or explicitly N/A), no two tasks share validation script unless they're a RED/GREEN pair.
9. **Commit.** `git add .kiro/specs/<slug>/ .agent/tools/validate-* .agent/tools/package.json-scripts` and commit. Do NOT commit generated artifacts (compiled output, build cache, vendor bundles).
10. **Stop.** Do not implement. Do not run code. Spec generation only.

### `scripts/dag-generate.py` Usage

```bash
# Parse tasks.md and emit all validators
python3 scripts/dag-generate.py \
  --spec .kiro/specs/my-feature/tasks.md \
  --output .agent/tools/ \
  --wire-package-json

# Verify all declared task IDs have validators
python3 scripts/dag-generate.py \
  --spec .kiro/specs/my-feature/tasks.md \
  --output .agent/tools/ \
  --audit

# Single-task mode (for incremental adds)
python3 scripts/dag-generate.py \
  --spec .kiro/specs/my-feature/tasks.md \
  --output .agent/tools/ \
  --task-id W2.A.1.1
```

`--audit` mode reads the Write Surface Map and confirms every task ID has a validator file. Exits 1 if any are missing.

### Quality Bar

Inherits spec-generation's quality bar. ATDD-specific additions:
- **3-8 scenarios per task.** Fewer than 3 means the task is too small to warrant a DAG entry. More than 8 means split the task.
- **Each scenario is independently assertable.** No "Scenario 3 only makes sense if Scenario 2 passed."
- **Each Definition of Done is verifiable without human judgment.** A script can check it. No "looks good" gates.
- **Validators are mechanical.** They run shell commands, check file existence, parse output. No LLM-in-the-loop.
- **RED validators distinguish "fail" from "broken".** A test that fails as expected = GREEN for RED task. A test that errors out (compile fail, import error) = RED for RED task.

### Anti-Patterns to Reject

- **Prose-only task bodies** ("Implement feature X with these qualities...") — these are spec-generation's old shape. Reject.
- **Validation commands without a script** ("run tests") — the validator must be a file, not a phrase.
- **Scenarios without a Given** ("When X happens, Y" with no setup) — the worker can't reproduce the state.
- **Scenarios with subjective Then** ("the output looks reasonable") — must be mechanical assertion.
- **Validators that call LLMs** — they're not validators, they're agents. Use a real test runner.
- **One validator covering many tasks** — the validator's contract is one task ID, one set of scenarios, one DoD.
- **DoD with "manual review"** — code review is a separate lane (the review lane in the spec), not part of any single task's DoD.
- **Spec-generation's borrowed vocabulary from internal contracts** (CLEARED / PARTIAL_CLEARANCE / BLOCKED from `ClearancePayloadSchema`) — reserved verdict words for code-quality-check are `PASS / PASS_WITH_WARNINGS / FAIL`, not contract-internal verdicts.
- **Python runtime in a Casita lane** — Casita is TS-only. Python validators exist for Hermes and data/analysis lanes only.
- **Tracking compiled artifacts in git** — generated Pydantic models, `dist/`, `node_modules/`, `__pycache__/` are gitignored. Migrations are tracked.

### Pitfalls

- **Validators go stale.** When a task's scenarios change, the validator's assertions must change too. Run `--audit` after every spec edit.
- **Validation scripts in the wrong directory.** All validators live at `.agent/tools/validate-<task-id>.mjs`, not at the package root. The enqueuer finds them by convention.
- **Validation script execution context.** Validators run from the project root, not from the validator's own directory. Use `resolve(process.cwd(), <relative_path>)`.
- **RED→GREEN confusion.** A RED task with a passing test = bug. A GREEN task with a failing test = bug. The validator is phase-aware; the implementer must update it between phases.
- **Scenario count creep.** Adding "one more scenario" for edge cases is fine. Adding 12 scenarios means the task is too big; split it.

### Downstream Consumer Contract

The Kanban dispatcher's enqueuer:
1. Reads `tasks.md` frontmatter (DAG + classifications + write surface map) — preferred path
2. Walks the body with mistune AST to extract task bodies per task ID
3. For each lane, dispatches a worker with the lane body as the task description
4. Worker runs the task body's `**Executable:**` command
5. Exit 0 → worker reports done → enqueuer marks lane complete
6. Exit non-zero → enqueuer halts, awaits founder intervention

The task body the worker sees is the ATDD block. The validator is the oracle. The scenarios are the contract the worker is implementing against.

**If you change the task body shape, you break the contract for every Kanban dispatch.** When the spec needs evolution, patch this skill first, then propagate to the dispatcher's enqueuer and to the lane classification map.

---

## Section G — The Validation Script Contract

The validator is a Node.js script. `scripts/dag-generate.py` emits a skeleton with TODO markers; the implementer fills in the assertions. See `assets/dag-validator.template.mjs` for the canonical template and `examples/dag-validate-W2.A.1.1.mjs` for a worked exemplar.

### Validator Lifecycle

- **RED task:** validator exists, runs the test command, expects failures. Exits 0 if failures are "expected" (test ran but failed). Exits 1 if test command itself errored (e.g., test file doesn't compile).
- **GREEN task:** same validator runs the same test command, expects passes. Exits 0 if all pass. Exits 1 if any fail.
- The validator is **phase-aware** via the task's TDD Phase in `tasks.md`. The implementer edits the validator's behavior between RED and GREEN, not its overall structure.

### Validator Exit Codes

- Exit 0 → task is GREEN
- Exit 1 → task is RED, error printed to stdout
- Exit 2 → task is BLOCKED (preconditions not met, surface out of scope, etc.)

A task cannot be marked complete until its validator exits 0. The Kanban dispatcher MUST call `pnpm agent:validate:<task-id>` before `kanban_complete()`.

---

## Section H — ATDD as Kanban Task Bodies

When dispatching work via the Hermes kanban board, the task body IS the ATDD spec. Every kanban task must include:

1. **Context** — files, workspace, constraints, AGENTS.md rules
2. **Scenarios** — Given/When/Then for each expected output or behavior
3. **Acceptance criteria** — measurable, verifiable conditions
4. **Artifacts** — exact file paths to produce (always under `.agent/` at project root)
5. **Executable validation** — the exact command (`pnpm agent:validate:<task-name>`) for automated green check that must exit 0 before marking done
6. **Definition of Done** — checklist proving completion

Established June 7, 2026: Founder rejected loose prompts for kanban tasks, requiring ATDD-level rigor with executable validation scripts wired as pnpm commands.

### Executable Validation Pattern

Every ATDD spec that produces a structured artifact gets a corresponding validation script under `.agent/tools/`. The script checks all acceptance criteria programmatically and exits 0 only when all pass. It's wired as a pnpm script so subagents have a single command to run:

```bash
pnpm agent:validate:<task-name>
```

**Validation script contract (`.agent/tools/validate-<task-name>.mjs`):**
- Exit 0 → all acceptance criteria met, artifact is complete
- Exit 1 → one or more failures, specific errors printed to stdout
- Checks: artifact existence, required sections, forbidden patterns, structure quality
- Run by the worker before `kanban_complete()` — the task is not done until validation exits 0

**Example structure (from June 7, 2026 AES keyword research task):**
```
.agent/tools/validate-keyword-research.mjs    ← checks 12 keywords, 4 avatars, Reddit mining, funnel stages, no residential language
.agent/aes/specs/keyword-research.atdd.md     ← the spec with executable validation section
package.json → agent:validate:keyword-research ← the command
```

The AGENTS.md at the project root must document this pattern so every worker knows: **Read spec → do work → save to `.agent/` → run `pnpm agent:validate:<task>` → if exit 0 → `kanban_complete()`.**

Not every task needs a validation script — only tasks where the artifact has structured acceptance criteria that can be checked programmatically.

See `references/spec-workforce-dispatch-pattern.md` for the full manager/subagent model economics and profile setup guide. For research-type tasks (investigative, exploratory, landscape surveys), use `references/spec-research-atdd-pattern.md` instead of the implementation ATDD template — it uses discovery scenarios with information-completeness checks rather than test assertions.

### Agent Production Template

Every agent the workforce deploys (classifiers, extractors, generators) should follow the agent production template documented in `references/spec-agent-production-template.md`. This template — derived from the AES lead qualifier — enforces identity law, a strict output contract, a scoring model with thresholds, a failure policy with safe defaults, tool lockdown, and a Docker/Hono runtime pattern. ATDD specs for production agents should reference this template.

### Clarifying Questions Before Fire (Pre-Dispatch Gate)

**Founder-mandated discipline (2026-06-15):** *you have my green light once you have everything in order and PLEASE ask clarifying questions* — for any visual/UI campaign (page layouts, design tokens, hero treatments, breadcrumb, anything with a canonical look-and-feel), the orchestrator must ask 2-4 multiple-choice `clarify` questions BEFORE writing the charter body. The questions have a specific shape: each one offers 3-4 options (plus the implicit "Other" escape), each option has a 1-line description, and the questions are about LOAD-BEARING decisions, not nice-to-knows.

**Examples from real campaigns:**
- "What should the canonical site-wide max-width be?" → 72rem / 80rem / viewport-percentage / per-section-type
- "Should the section-level governor replace or stack with the hero-level one?" → replace / stack / defer
- "Should the breadcrumb be a continuation of the nav (one unified bar) or stay separate with no divider?" → unify / separate / drop background
- "Use Tailwind v4 (CSS-first) or stay on v3 (config-first)?" → v4 / v3 / hybrid

**Why this matters:** without clarifying questions, the agent picks a default the user didn't intend, ships the work, and forces a revert. The 30 seconds of `clarify` calls save a 60-minute campaign that gets thrown out. The hard rule: for any visual campaign, the charter's first 100 lines should be the clarifying-questions block with the user's answers already filled in. If the user says "no clarifying questions needed, just fire," that's a valid signal too — but the default is to ask.

**The exception:** for non-visual, well-specified work (e.g., a pure code refactor with a clear spec), clarifying questions are usually unnecessary. The orchestrator reads the situation. Visual = ask. Mechanical = don't ask.

---

## Section I — Browser-Harness Verification Mandate

When the Founder mandates browser-harness over model self-certification for visual verification, the following sequence is REQUIRED (no exceptions):

```
browser_navigate(url) → browser_console(clear=True) → browser_refresh()
→ browser_console(clear=True) → browser_refresh()
→ browser_console() → must be empty
→ browser_vision("Describe page layout")
```

### When to Apply
- **Pre-lane dispatch checks** — verify servers boot with zero console errors before any lane runs
- **Wave gate verification** — verify rendered output matches expected appearance
- **Campaign convergence** — verify all waves produce correct output end-to-end

### Deferred Bug Handling
If a known transient error exists (e.g., `useContext` error on first dev server page load):
- Document it as "deferred until Founder specifies"
- 1-2 refreshes required before declaring the error real
- If the error persists beyond 2 refreshes, it is REAL (not deferred) and MUST block the gate

---

## Section J — Anti-Patterns and Founder-Mandated Patterns

### Expansion Grants Pattern (Anti-Lockup Framing)

**Observed pitfall (2026-06-11, Fable 5 visual-migration charter):** when an ATDD/charter doc frames all rules as negative prohibitions ("don't add new section types", "no bypassing the compiler", "no scoped CSS"), the implementing agent (Fable 5, Sonnet with xhigh) tends toward **principled non-action** — it halts because every action seems to require authorization it doesn't have. Three real charter rejections in one session showed this pattern.

**Fix:** frame rules as **expansion grants with caps**, not prohibitions. The agent gets an explicit list of *kinds* of expansion it IS authorized to perform, with hard caps per category. Prohibitions are listed second, as guardrails, not the primary framing.

```
EXPANSION GRANTS (agent is authorized to perform these, with caps):
- DTO EXPRESSION: extend <node contract>. Cap: <=2 new node types per route.
- SECTION VARIATION CONTRACT EXPANSION: extend <section contract> variants.
  Cap: <=2 new variants per section type across the campaign.
- DESIGN TOKEN EXPANSION: add tokens, but ONLY under the 2-layer token law.
  Reuse existing --color-*, --space-*, --radius-* primitives.
- COMPONENT RENDERER EXPANSION: extend existing renderers. Cap: <=2 new
  primitives per route. Only when contract + token expansion cannot express
  the reference.

PROHIBITED:
- No bypassing <the path>
- No hand-rolled <thing>
- No <forbidden action>
```

**Why this works:** the grants say "you may do X with cap Y" — Fable doesn't have to negotiate "is this allowed" before every expansion. The prohibitions are explicit only when Fable is about to cross a line. The grants positive-frame the work; the prohibitions are a safety net.

### Visual Integration Anti-Decomposition Rule

**Founder-flagged anti-pattern (2026-06-11, /about preview):** the hand-rolled `/about` second section is a single visual section (story text on the left, stats sidebar on the right with sticky positioning). The compiler-driven preview decomposed it into a `Text` body section + a `List` stats section — two stacked sections that lost the visual integration. The user (Founder) flagged this as exactly the lockup pattern to avoid.

**Working examples that DO preserve visual integration:**
- Text-left + media-right + floating stat overlay → `type: 'Split', variant: 'media'` with a `media` node inline in `content.nodes`. Reference: `src/content/pages/divisions/divisions.hub.map.ts` (`INTEGRATED DELIVERY` section).
- Sticky sidebar header + scrolling list → `type: 'FAQ', variant: 'accordion-aside'`.

**Litmus test:** if a reference screenshot shows a SINGLE visual section with two sub-regions (sidebar + main, text + image, hero + overlay, etc.), it's ONE section, not two. Add a new VARIANT on an existing section type (allowed under SECTION VARIATION CONTRACT EXPANSION grant) to express it. Do NOT silently decompose into multiple stacked compiler sections.

**Why this matters:** the agent's natural instinct when a section "doesn't fit" an existing variant is to split it into 2-3 sections it can express. This loses the visual rhythm of the reference and produces a different page. The fix is always: a new variant on an existing section type, never a new section type, never a decomposition into multiple sections.

### `/goal` Standing Objective Pattern

**Observed pattern (2026-06-11, Fable 5 /goal launch):** when the `/goal` text is 200+ lines of preamble + 10 prep stages + a rules list, the agent reads it, decides it has no clear objective, and halts. The "standing goal across turns" pattern works best with a *concise* objective plus a separate file that has the recipe.

**Pattern:**
```bash
# In the agent TUI, paste this SHORT block:
/goal <one-paragraph objective, ~5-10 lines, naming the work and the
acceptance criterion>. Per-route memory: <path>. Use <known tools> for
<work>. Expansion grants + caps in the charter's HARD RULES block. <one-line
of "no" rules>. Work continues across turns until the campaign is complete
or blocked.
```

The full recipe (prep stages, per-stage acceptance, expansion grants, prohibitions) lives in a **file the agent reads on first turn via the dispatch prompt**:
```
cmux send ... 'read /path/to/charter.md and execute exactly as instructed,
beginning with /goal'
```

**Why this works:** the `/goal` text is the *north star* the agent checks each turn; the file is the *first-turn recipe*. Without this split, `/goal` becomes a wall of text the agent treats as a one-shot todo list and exits on.

**Proven pattern (June 11, 2026, Fable 5 /goal):** charter file 104 lines, /goal block 11 lines, dispatch flow:
1. Pre-flight (8 explicit checks the agent does before /goal)
2. Read charter file → write /goal
3. Subsequent turns: work on the goal, check convergence doc each turn
4. Wake shim: orchestrator arms a kanban-task watcher (`hermes-kanban-wake.py` + `boomerang-kanban.mjs`) to wake when the agent reaches a terminal state

### CRITICAL: No HALT Language in `/goal` Charters

**Founder-flagged anti-pattern (2026-06-14, Fable 5 design-system token distillation):** the original /goal charter used "HALT" conditions ("if X fails, HALT and wait for user input"). In /goal mode, HALT triggers a stop-hook that waits for human input — this is the OPPOSITE of what a campaign should do. The agent freezes waiting for Founder, even when a low-risk autonomous fix is available. The campaign stalls.

**The right pattern:** replace HALT conditions with autonomous-decision rules.

| Wrong (HALT) | Right (autonomous) |
|---|---|
| "If MDX compilation fails, HALT" | "If MDX compilation fails, take the lowest-risk fix (add a stories glob entry, add a webpack rule for `@mdx-js/loader`) and continue. Document the fix in the final result." |
| "If storybook fails to boot, HALT" | "If storybook fails to boot, check the dev server, check for missing dependencies, take the lowest-risk fix and continue. If truly unrecoverable, surface the exact failure to the user with file:line evidence and stop." |
| "If a gate fails RED, HALT" | "If a gate fails RED and you can't determine the cause within 2 tool calls, note the failure in the result block and continue with the next gate." |

**HALT language is for IRREVERSIBLE STATE CHANGES** (committing wrong files, deleting data, deploying to prod). It's not for tooling config edits, not for "should I take Option A or Option B" decisions. The agent owns those.

**The rule of thumb when authoring a /goal charter:** if a rule could be "if X, do Y autonomously" instead of "if X, stop", write it as "do Y autonomously."

### Founder-Mandated Context Burst Pattern (Governance Prompts)

**Observed pattern (2026-06-16, AES Trust Framework campaign):** when prompting a high-judgment agent (Opus, GPT-5.5 xhigh, etc.) to produce a governance artifact (charter, framework, registry, doctrine document), the prompt needs grounding context BEFORE the agent is asked to generate. Without grounding, the agent produces a generic framework that doesn't fit the actual system.

**The 8-block context burst** (injected between the "AES is / AES is not" framing and the 12 required sections of a governance prompt):

1. **The Real Funnel** — the actual conversion path (referral → trust → conversation → bid, NOT search → quote). The framework should reinforce the real path.
2. **The Client Avatars** — 3-5 named buyer personas with 1-line descriptions. Every rule must serve at least one avatar.
3. **The Real Proof Assets** — actual project names (Airport, EOC, Schools, etc.) not generic claims. Name the assets the framework should surface.
4. **The Copy Law** — 2-3 NON-NEGOTIABLE rules (e.g., "Buyer Success > Service Delivery", "No ungrounded superlatives"). One-sentence each.
5. **The Design System Default** — 2-3 rules about visual treatment (e.g., "Elevated is default", "Use semantic tokens only"). Anchors the framework to the actual design vocabulary.
6. **The Patch List** — explicit list of additive changes the framework implies for existing brand files. Concrete file paths + section names.
7. **The Companion Documents** — 4-8 specific files the agent MUST read before producing output. Grounds the framework to the actual codebase.
8. **The Refusal Patterns** — 6-10 specific slop patterns the framework must catch (centered titles, service catalogs on homepage, stock photography when a proof asset exists, etc.). Each is a real failure mode observed in past runs.

**Why this works:** the 8 blocks are the constitutional grounding. The 12 required sections are the output shape. The agent reads the constitution, then produces the output with the constitution active. Result: framework that's grounded in the actual system, not generic.

**Placement rule:** context burst goes IMMEDIATELY AFTER the "AES is / AES is not" framing, BEFORE the "Your task" + "Required sections" structure. The agent reads the constitution, then reads the task with the constitution active.

### Tool-Call Sprawl

**Each tool call has a fixed overhead** (skill frontmatter loaded, USER.md/MEMORY.md re-injected, system prompt re-evaluated). Dispatching 8 tool calls in one turn burns ~30-50K tokens of context overhead alone. The fix: **script recurring work into one call, use path-reference dispatch (write to disk, send path), batch verifications into a single script.** A 5-call verification loop that could be 1 call is a 5x overhead on the harness.

```
❌ read-screen → check → read-screen → check → read-screen → ... (8 tool calls)
✅ write verification script → run script → read result (1 tool call)
```

Proven June 14, 2026: dispatching 4 sonnet recon lanes + 3 follow-up verification calls in one campaign consumed ~30% of the model's context in tool-call overhead alone. Scripting the work into 1-2 calls dropped the same work to ~8% overhead.

### Wave-DAG Retry Loop Pattern

When execution follows a wave-based DAG with automated gates:

```
for each wave:
    assert pre_lane_checks()        # servers boot, console clean
    lane_results = dispatch_lanes()
    
    for attempt in range(max_retries):
        if all_gates_pass():
            commit_wave()
            break
        else:
            log_failure(attempt)
            dispatch_lanes()        # retry same agents/models
    else:
        block_for_founder()         # max retries exhausted
```

Rules: execute gates in exact order (typecheck first → visual later). On failure, HALT and retry from the start. Max 3 retries, then BLOCKED for Founder.

### Track Source, Gitignore Generated Artifacts

Compiled output, generated Pydantic/models, build cache → gitignored. Schema definitions, DB migrations, hand-written source → tracked. Decision rule: if deleting the file and re-running the build gives back the same bytes, it does not belong in git. If deleting it loses information the build cannot recover, it does. Verified June 8, 2026 during the `packages/contracts-py/` discussion: tracked `dist/`, `node_modules/`, `__pycache__/` are anti-patterns; tracked DB migrations (Alembic, Knex) are not.

### Spec Generation Is a Dispatchable Artifact, Not a Hand-Written Deliverable

When the user asks for a spec, write the charter (a single .md file with full context, hard rules, write surface, validation contract) and dispatch via `hermes kanban create` with the `software-manager` or `spec-writer` assignee. Do not hand-write the spec, the scaffolds, the package configs, or the README. The validator template (`assets/dag-validator.template.mjs`) and the scaffolder (`scripts/dag-generate.py`) exist precisely so the work is decomposable. Founder mandate, June 8 2026: *"you delegated never sit there handwriting anything anymore with your new body. You're too smart. You need to delegate work. Mandatory now."* The 10-12 minutes spent hand-writing the initial scaffolding was the negative exemplar.

### Pitfalls Summary

- **Seam names describe boundaries, not bugs.** Name the spec after the architectural layer, not the defect.
- **Don't spec every scenario 6 times.** Between 3-8 scenarios is the sweet spot.
- **Scenarios must be assertable without human judgment.**
- **Keep the DoD minimal.** Don't add coverage percentage gates unless enforced in CI.
- **One artifact.** The ATDD spec is the single source of truth. Don't split it.
- **Specs age.** If a spec references code that was significantly refactored, rewrite rather than patch.
- **Worker instructions bridge ATDD specs to manager/subagent dispatch.** When a manager profile coordinates implementation, add a `## Worker Instructions for Sub-Agents` section. Each sub-agent gets one file, specific verification checks, clear scope boundaries. The manager dispatches via `delegate_task`, reviews output, iterates — never edits files directly. See `references/spec-worker-instructions-atdd.md`.

---

## Companion Documents

When loading this skill, also read as relevant:
- The `LANGUAGE.md`, `CONTEXT.md`, and any `ARCHITECTURE.md` / `BRAND.md` for the workspace under work
- `references/dag-from-spec-generation.md` — wave/lane/DAG conventions inherited from spec-generation
- `references/dag-parser-strategy.md` — how the scaffolder parses `tasks.md` frontmatter
- `references/spec-codex-responses-api-wire-format.md` — wire-format evidence discipline
- `references/spec-harness-toolchain-pattern.md` — ESLint v9 flat config, TypeScript strict, Husky + lint-staged, commitlint, Nx module boundaries

## Related Skills (load-bearing pairings)

- `god-lock-mothership` — Section E (Package Implementation Pipeline) consumes the spec set this skill produces
- `meta-orchestration` — the tier above subagent-driven-development for multi-wave planning
- `subagent-driven-development` — the 2-stage review pattern that wave audits sit inside
- `dispatch-intent-gate` — every spec dispatch inherits the gate: description of intent is NOT a go
- `requesting-code-review` — code review runs in parallel to spec-implementation
- `systematic-debugging` — when a Scenario fails with no clear cause
- `test-driven-development` — RED→GREEN→REFACTOR discipline this skill operationalizes
