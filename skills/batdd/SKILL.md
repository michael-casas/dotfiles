---
name: batdd
description: Apply Behavior Acceptance Test-Driven Development when creating, changing, compiling, lowering, running, or reviewing acceptance; implementing behavior or repairs under RED/GREEN; selecting L1, L2, or L3; configuring Nx targets; generating native Playwright or Maestro artifacts from physical Gherkin; reconciling Web, Android, and iOS evidence; or working from a BATDD assignment envelope. Use whenever a repository or task mentions BATDD, acceptance, Gherkin, Cucumber, Playwright, Maestro, test layers, meaningful RED, frozen scenarios, affected tests, preflight, verification, or judgment.
metadata:
  version: "2.2.2"
---

# BATDD

Compile a repository profile and immutable assignment into a consistent vertical-slice execution plan. Preserve behavioral authority without making Gherkin, a runner, or an implementer exceed its role.

## Canonical directive

Use [templates/DIRECTIVE.md](templates/DIRECTIVE.md) when authoring agent handoffs. It is the owner-approved canonical prompt: objective, problem statement, inline behavioral contract, bounded implementation freedom, Definition of Done, and closeout. Class and optional scope follow Conventional Commit syntax; they do not grant commit authority.

The directive fixes the behavioral destination and protected boundaries while the worker chooses the implementation route. Ordinary debugging, test failures, and authorized reversible environment repair are execution, not reasons to HOLD. Escalate only unresolved authority/product decisions, protected-boundary crossings, unavailable required capabilities, contract amendments, or explicit budget/stop conditions. Preserve explicit repository restrictions and continue useful independent work when possible.

Inline Gherkin is the immutable issuance record. Before execution, select or materialize one canonical physical `.feature` file and record its identity; it becomes the sole executable scenario authority. Do not maintain two editable scenario copies. Amendments explicitly supersede the issued contract and follow the declared authority.

For this directive, `READY_FOR_REVIEW` is the worker gate; independent review owns `MERGE_READY`. Existing compiled assignments may retain their explicit `READY-FOR-AUDIT` marker without implying self-certification. The template's review clause defines one complete findings pass and bounded repair verification; optional polish is nonblocking.

These owner-approved directive rules govern this template where older generic guidance differs. Existing repository profiles and Wiki notes are not silently migrated; explicit repository authority and compatibility requirements remain in force.

### Jira Epic execution

The Agent Wiki's Agent Directives and Jira Epic and Task Contracts standards
recognize this template. Han Solo binds each Jira task to an issued version,
maintains the complete Epic checklist, commits validated tasks under the recorded
grant, and verifies the final PR readiness handoff. Its bundled Directive copies
must match this canonical source. Native skills live under ~/.codex/skills/han-solo
and ~/.claude/skills/han-solo; repositories may vendor a local copy. The solo
profile does not require campaign-only orchestration; independent review remains.

### Generate a directive from JSON

Use [scripts/directive.gen.mjs](scripts/directive.gen.mjs) to render the canonical template. It uses Node.js built-ins only and resolves the template relative to the script, independent of the working directory.

```bash
node /Users/mcasa_atlantis/.agents/skills/batdd/scripts/directive.gen.mjs input.json directive.md
# Or supply JSON on stdin and receive Markdown on stdout:
node /Users/mcasa_atlantis/.agents/skills/batdd/scripts/directive.gen.mjs - < input.json
```

The optional output path must not already exist; parent directories must exist. Prefer the output argument to shell redirection when preserving an existing directive. Errors exit nonzero without emitting a directive.

Input is one flat JSON object. All values are nonempty strings. `scope` defaults to `none` and `breakingChange` to `no`; all other fields below are required. Metadata fields `id`, `title`, `scope`, and `breakingChange` are single-line; narrative fields may contain newlines. Unknown keys, including `gherkin`, are rejected. The completion gate, common obligations, review threshold, and worker closeout form remain canonical template text, not input overrides. Closeout result fields are completed by the worker after execution.

```json
{
  "id": "DIR-001",
  "title": "Prevent duplicate submissions",
  "class": "fix",
  "scope": "orders",
  "breakingChange": "no",
  "objective": "A retried submission produces exactly one order.",
  "currentBehavior": "Retrying can create duplicate orders.",
  "requiredBehavior": "The same submission returns the existing order.",
  "impact": "Duplicate orders create duplicate fulfillment work.",
  "context": "Trace the submission entrypoint and its persistence consumers.",
  "repository": "/absolute/path/to/repository",
  "requiredContext": "AGENTS.md, TESTING.md, and the order feature authority.",
  "authorizedScope": "Order submission, persistence, supporting tests and documentation.",
  "protectedBoundaries": "Existing authorization and unrelated checkout behavior.",
  "baselineExceptions": "none",
  "deliveryAuthority": "Implementation only; no commit, push, PR, or merge."
}
```

**Mandatory authoring step before worker delivery:** patch the generated `GHERKIN_REQUIRED` fenced block with concrete inline Gherkin, including stable unique scenario IDs, load-bearing preconditions, observable outcomes, and applicable forbidden effects. Do not send the unpatched generator output to a worker. For nonbehavioral work, replace the block with an explicit profile-backed N/A reason and the appropriate proof obligations. Inspect the final directive for remaining issuance placeholders and the sentinel, check consistency with the objective and authority, and only then deliver it. The generator intentionally does not author Gherkin or certify delivery readiness.

Run the shim's focused check with:

```bash
node --test /Users/mcasa_atlantis/.agents/skills/batdd/scripts/directive.gen.test.mjs
```

## Load the worker hot path

1. Read the nearest `README.md` and `AGENTS.md` at every project root entered.
2. Read [references/TESTING.md](references/TESTING.md).
3. For any executable L3 or cross-platform UI work, read [references/NATIVE-LOWERING.md](references/NATIVE-LOWERING.md).
4. Prefer the repository's compiled `.agents/batdd/profile.json`, `.agents/batdd/WORKER-CONTRACT.md`, and named assignment envelope.
5. Read repository `TESTING.md` when the compiled profile is missing, invalid, stale, or insufficient for the selected boundary.
6. Load full Wiki standards only when the role authors or amends a contract, performs verification or judgment, detects a version/conflict condition, or cannot resolve authority from the compiled hot path.
7. In Nx workspaces, inspect resolved project targets before selecting commands. Use the repository package manager and Nx.

A compiled profile or assignment may narrow scope and choose tools but must not weaken canonical law. Stop on schema failure, version mismatch, authority conflict, missing write surface, or absent stop boundary.

## Activate native planning

For implementation or repair, read [references/EXECUTION-PLAN.md](references/EXECUTION-PLAN.md) and initialize the runtime's native task plan before the first product write. Use `update_plan` when available. Do not ask permission to create the plan.

Keep plan items compact. Store the detailed Green Contract in its declared artifact and reference its stable ID or hash from plan state.

Every implementation plan must represent:

- authority/profile hydration;
- basic and adversarial Green Contract design;
- meaningful RED for every required new or changed L1/L2/L3 row;
- contract freeze;
- fidelity-ordered GREEN;
- affected standing, cleanup, and resource-delta gates;
- evidence handoff and the declared stop boundary.

Exactly one item remains `in_progress`. Advance items only on evidence, not file existence or self-report.

## Compile the Green Contract

Read [references/GREEN-CONTRACT.md](references/GREEN-CONTRACT.md) and [references/ADVERSARIAL-DESIGN.md](references/ADVERSARIAL-DESIGN.md).

Classify every contract row at the lowest faithful layer:

- **L1 unit:** deterministic logic with controlled collaborators.
- **L1 in-process integration:** multiple components without a real external boundary.
- **L2 real-boundary integration:** persistence, process, protocol, delivery, filesystem, browser, device, or infrastructure.
- **L2 end-to-end:** a complete workflow through its public entry and observable result.
- **L3 behavior:** a representative canonical Gherkin scenario dogfooded through the appropriate real surface.

Integration is not L1.5. All end-to-end tests are L2, but not all L2 tests are end-to-end.

For new behavior, every initially required new or changed contract row must demonstrate meaningful RED before the first product implementation write. After freeze, an additive test may expose a newly discovered counterexample to an existing requirement: preserve frozen assertions and meaning, demonstrate the defect before its repair, and retain the new proof. New behavior or changed acceptance still requires an authorized amendment. Do not break existing greens or manufacture RED. Regression fixes reproduce the defect. Pure refactors preserve characterization GREEN unless repository law declares another boundary.

## Compile native L3 artifacts

Use one physical `<feature>.feature` as the only executable scenario source. `FEATURE.md` owns intent, rules, boundaries, scenario links, and the Green Contract; it must not duplicate Gherkin.

Parse the physical file with the official Gherkin parser, normalize Pickles once, and preserve stable scenario IDs through every selected lane. Lower Web scenarios through Playwright bindings into native Playwright tests. Lower mobile scenarios through typed bindings into deterministic Maestro YAML, then execute the same portable flow separately on Android and iOS when observable semantics and selectors agree.

Keep source, selected, generated, and executed counts distinct. Full cross-platform evidence requires separately attributable Web, Android, and iOS native reports. A single generated mobile flow executed on two operating systems is one generated artifact and two native executions.

Do not make CucumberJS the new acceptance runtime. A repository may retain a deprecated compatibility executor only for already-migrating consumers.

## Preserve layer independence

- Share only framework-neutral fixtures, builders, drivers, and assertions.
- Do not import or execute another layer's test entrypoint.
- Do not let Cucumber steps invoke L1 or L2 targets.
- Do not let Playwright steps or typed mobile bindings invoke Nx subtargets.
- Keep `*.steps.ts` thin and scenario-scoped.
- Await or return every asynchronous action and assertion.
- Require every `Then` to assert an observable outcome.
- Reject scenario-order state, no-op assertions, empty collectors, and proxies incapable of observing the claim.

## Enforce vertical-slice completion

`vertical-slice` is the default completion scope. Every layer declared `required` must be GREEN before the Worker may report `READY_FOR_REVIEW` (or the explicit legacy assignment marker `READY-FOR-AUDIT`). An N/A layer requires an explicit profile-backed reason.

A `layer` assignment may complete only its named layer and must set `mayReportFeatureComplete: false`. It cannot claim feature completion.

Missing runners, targets, mappings, or evidence are blockers, not implicit N/A.

## Execute and repair

1. Run exact targeted Nx gates and capture source, selected, generated, and executed counts; runtime and device; working directory; revision; exit code; duration; and decisive output.
2. Reject syntax errors, broken harnesses, wrong targets, zero selection, or unrelated dependency failures as defective RED.
3. Freeze scenario identity, semantics, test titles, assertions, values, negative guarantees, target vocabulary, and cleanup obligations before GREEN product writes.
4. Implement only within the authorized write surface.
5. Run affected L1 unit, L1 integration, L2 integration, L2 E2E, then L3 Web, Android, and iOS in fidelity order, selecting only required/applicable layers.
6. Preserve locked greens and repair only failed or transitively affected seams.
7. Treat fixtures, imports, clocks, lifecycle setup, and cleanup as plumbing only when contract meaning and assertions remain unchanged.
8. If the contract is wrong, stop for its authority. An assertion change is never plumbing.

## Evidence and stop

A pass is insufficient without intended project, target, layer, runtime/device, nonzero source/selection/generation/execution or explicit N/A, immutable revisions, native reports, artifact hashes, and resource delta.

Runtime completion, terminal quiet, messages, and Markdown are claims. An implementer cannot self-certify. A verifier that repairs loses independence for that repair.

Stop at the assignment's retry, halt, stand-down, `READY_FOR_REVIEW`, legacy `READY-FOR-AUDIT`, or closeout boundary. Report lane-local results separately from unrelated workspace-wide failures.

## Skill maintenance

Every mutation to this skill's procedure or bundled references must increment `metadata.version`. Reconcile every compiled repository profile's `skill.minimumVersion` when the change becomes required for conformance. Never change behavior under an unchanged skill version.
