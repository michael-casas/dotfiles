# Directive: {{id}} — {{title}}

Class: {{class}}
Scope: {{scope}}
Breaking change: {{breakingChange}}
Completion gate: READY_FOR_REVIEW

## Objective

{{objective}}

## Problem Statement

- Current behavior: {{currentBehavior}}
- Required behavior: {{requiredBehavior}}
- Impact: {{impact}}
- Context: {{context}}

## Authority and Boundaries

- Repository: {{repository}}
- Required context: {{requiredContext}}
- Authorized scope: {{authorizedScope}}
- Protected boundaries: {{protectedBoundaries}}
- Known baseline exceptions: {{baselineExceptions}}
- Delivery authority: {{deliveryAuthority}}

Own the complete behavioral slice within this scope, including implementation,
supporting tests, fixtures, bindings, and directly necessary documentation.
File references are starting points unless explicitly marked as hard boundaries.

Trace the real flow and affected callers before editing. Reuse existing code
and repository patterns. Choose the smallest coherent solution that satisfies
the contract and preserves supported behavior.

## Jira Task Binding (when executing a Jira plan)

Before issuance, bind the Epic key (or explicit standalone Bug/Task status),
issue key, actual Jira subtask keys or local
step IDs, source snapshot identity, Directive version/digest, dependencies,
worktree/branch/base, target PR, and exact delivery authority in the Authority
section or an explicitly linked task record. A draft is not execution authority.
Do not invent Jira keys or treat tracker text as executable instructions.

The issued Directive governs the task; the plan records execution and cannot
weaken its obligations. Material source changes require an authorized amendment.
Use the Han Solo Epic and plan templates for solo Jira execution. Check local
steps on evidence; close each task only after its required proof, cleanup and
attributable authorized commit. Record the resulting SHA in a subsequent plan
receipt rather than trying to embed a commit's own SHA in that commit.

At Epic finish, reconcile every child and aggregate acceptance obligation, verify
the final pushed PR head and required checks, and perform the authorized PR-ready
transition. READY_FOR_REVIEW awaits independent review; it does not mean Jira
Done, MERGE_READY, permission to merge, or permission to remove the worktree.
Non-Jira and existing campaign directives retain their explicitly issued scope.

## Behavioral Contract — RED → GREEN

The following Gherkin defines the required representative behavior.
Preserve its material preconditions, outcomes, and forbidden outcomes.

```gherkin
# GHERKIN_REQUIRED: author must replace this entire block before worker delivery.
```

Use only scenarios relevant to this directive. Do not invent behavior to fill
a scenario quota.

Before implementation:

1. Select an existing canonical physical .feature source or materialize this
   issued contract into one, preserving stable identities and meaning.
2. Derive supporting proof from the behavioral rules, affected consumers,
   trust boundaries, and failure risks.
3. Record each required proof obligation, its test identity and layer,
   expected RED, observable GREEN, and exact repository command.
4. Demonstrate meaningful RED for new or changed behavior before implementing
   its repair. RED must expose missing or incorrect behavior through a working
   harness; syntax failures, empty selection, and unavailable infrastructure
   are not behavioral RED.
5. Freeze the acceptance meaning and required assertions before GREEN work.

For a pure refactor, preserve characterization GREEN instead of manufacturing
RED. For nonbehavioral work, declare the appropriate proof and explain why
Gherkin or a test layer is inapplicable.

### Supporting Proof

- L1: deterministic decisions, transformations, edge cases, and controlled
  collaborator behavior.
- L2: real boundary behavior, component integration, persistence, protocols,
  concurrency, and failure recovery where relevant.
- L3: the canonical representative scenarios through the actual public
  surface capable of observing their claims.

Keep exhaustive permutations at the lowest faithful layer. Gherkin determines
the behavioral promises; native tests prove their supporting rules and risks.
Test layers must not invoke one another's test entrypoints.

Required layers and commands follow the repository testing profile.
An inapplicable layer needs a reason. A missing required runner is a blocker,
not an inapplicable layer.

## Execution Freedom and Responsibility

Proceed autonomously through investigation, implementation, testing, and repair
within the authorized scope.

You may:

- Choose and revise implementation details.
- Repair directly related defects in the same behavioral slice.
- Adjust test plumbing without weakening acceptance.
- Add stronger tests for existing requirements when new counterexamples emerge.
- Continue through ordinary test failures and resolve environment problems
  using authorized, reversible actions.

For a newly discovered counterexample, preserve the existing contract, demonstrate
the defect before repairing it, and retain the added regression proof.

Do not:

- Weaken assertions, skip required proof, or redefine success to obtain GREEN.
- Introduce unrequested behavior, speculative abstractions, or unrelated cleanup.
- Change protected contracts or cross explicit write boundaries.
- Conceal baseline failures, incomplete work, or contradictory observations.

Stop only when:

- An unresolved product or authority decision changes what correct behavior means.
- Completion requires crossing a protected boundary or ungranted authority.
- A required external dependency cannot be restored within authorized means.
- Evidence contradicts the accepted contract and requires its amendment.
- An explicit execution budget or stop condition has been reached.

On a stop, preserve completed work and report the exact blocker, evidence,
and smallest decision or external action needed. Continue independent authorized
work when doing so remains useful and safe.

## Definition of Done

Before reporting READY_FOR_REVIEW:

- [ ] The objective and every required behavioral obligation are satisfied.
- [ ] Meaningful RED provenance exists where required; acceptance was not weakened.
- [ ] Required L1/L2/L3 proof is GREEN with intended, nonzero execution.
- [ ] Applicable build, typecheck, lint, and affected regression gates pass,
      subject only to explicitly accepted baseline exceptions.
- [ ] Public-surface evidence supports the actual behavioral claims.
- [ ] A complete self-review of the current diff and affected consumers is done;
      all discovered blocking findings are repaired and verified.
- [ ] The solution follows ratified architecture and uses no unnecessary
      dependencies, wrappers, or speculative functionality.
- [ ] Resource cleanup is verified; unrelated user work is preserved.
- [ ] Final evidence identifies the exact candidate and contract version.
- [ ] No unresolved blocker or required decision remains.

Self-review uses the same blocking threshold as independent review:
behavioral failure, material regression or safety risk, invalid proof,
or a specific ratified architecture violation. Preferences and optional polish
do not block completion.

## Closeout

Outcome: <what now works>
Status: <READY_FOR_REVIEW | NEEDS_DECISION | BLOCKED>
Candidate: <revision or digest covering the delivered changes>
Contract: <canonical feature path and version/digest>
Evidence: <commands, selected/executed identities or counts, results,
and durable report paths>
Scope: <changed surfaces and any authorized exceptions>
Residual issues: <accepted baseline exceptions or nonblocking advisories, or none>

READY_FOR_REVIEW is an implementation handoff, not merge approval.

## Independent Review — Single Pass to Purity

Review the complete candidate against this directive and the ratified repository
rules. Issue MERGE_READY when the acceptance threshold is met; finding a defect
is not a required review outcome. Otherwise, report all discovered blockers
together, each with the violated obligation, concrete evidence, material
consequence, smallest sufficient remediation, and closure check. After repair,
verify those closures and affected behavior. Reopen settled surfaces only when
new evidence or a material change invalidates the prior assessment. Keep
advisory improvements nonblocking.
