# Single Pass to Purity: critic protocol, findings contract, verification

## 1. Roles

- **Implementer** (a Sergeant): delivers the Implement head, stops at READY_FOR_REVIEW; later applies the Correct round.
- **Critic** (the project's one dedicated GPT 6.1 Sol seat): one round, one report, one GitHub review. Read-only on product source; writes only its report, the GitHub review and temporary tests inside a disposable snapshot.
- **Owner** (the project's Lieutenant; the General for the Workspace repository): verifies the Correct round against the critic's list and merges at 5/5 under its grant.

The critic is never the PR's author and there is never a second reviewer. The critic that repairs anything loses its verdict for that repair.

## 2. Critic seat protocol

1. **Intake.** Read the order (ULID), the charter and Amendments, the claim's Directives, the frozen acceptance, prior reports for the claim. Pin the head: `gh pr view <n> --json headRefOid,baseRefName,isDraft,url`. Record UTC, head, base, PR URL.
2. **Snapshot.** `git -C <repo> archive <head> | tar -x -C <scratch>/snapshot`, link or install dependencies. Every command runs there; the live checkout and the PR branch are never modified.
3. **Baseline gates.** Run the project's declared gates on the unmodified snapshot, uncached, and read the output (counts, exit codes): for an Nx project `NX_DAEMON=false <pm> nx run-many -t <targets> -p <project> --skipNxCache --output-style=static`. Record each as a command evidence row (command, cwd, exit, counts, decisive output).
4. **Attack.** Apply AUDIT.md §9 (false-pass checklist) and §6 step 6. Add temporary adversarial tests to the snapshot only, and keep them: a failing added test is evidence, not a change request to the PR.
5. **Score and verdict.** Five dimensions, each 0 or 1 (section 3); show the arithmetic. One verdict word beside it: APPROVED (5/5, no required change), BLOCKED (correctable within existing authority) or ESCALATED (a decision the claim does not own).
6. **Ledger.** Every finding with every field of the contract (section 4). Do not stop at the first blocking finding; do not keep findings for a later round. If a finding depends on a Founder decision, state the decision needed and the requirement under each outcome.
7. **Path to 5/5.** One table, upfront in the report and in the review body (section 5).
8. **Publish.** Fill `assets/AUDIT_TEMPLATE.md` completely; save it at the path the charter names (default: the control plane `general/review-<critic>-pr<n>.md`); post the one GitHub review (gh-review.md); send the inbox report to the implementer and the owner with the file path. End the file with `SINGLE_PASS_COMPLETE`.
9. **After the round.** Answer a bounded clarification from the implementer or the owner in a PR comment or inbox reply (a question about an existing requirement, never a new finding). Do not re-review the Correct head; the owner verifies it.

## 3. Rubric

Five dimensions, each awarded exactly `0` or `1`; `4/5` is not approval. The critic charter declares the five dimensions for the claim; when it does not, use:

| # | Dimension | Point when |
|---:|---|---|
| 1 | Contract and acceptance | Every Directive requirement and frozen scenario is met on the head, proven by executed evidence. |
| 2 | Test integrity and false-green resistance | RED preceded GREEN, selected counts are nonzero, mocks match the live authority, adversarial probes pass. |
| 3 | Scope, invariants and security | Changes stay inside the write surface and the claim; no invariant, security boundary or forbidden behavior crossed. |
| 4 | Code quality and maintainability | No BLOCKING or MAJOR quality finding against the declared rubric (Clean Code by default). |
| 5 | Evidence, hygiene and documentation | PR body, docs and reports match reality; zero resource delta; commands reproducible. |

A finding zeroes the dimension it names. Severity tells the owner how to read it:

- **BLOCKING**: wrong behavior, broken contract, security or data risk. Always costs its point.
- **MAJOR**: a gap in proof, scope or quality that the rubric counts. Costs its point.
- **MINOR**: a bounded defect the rubric counts only when the charter's dimension says so; its score impact is stated explicitly.
- **ADVISORY**: improvement that does not cost a point. Assigned and listed separately, never in the path to 5/5.

## 4. Findings contract

Every finding carries all of these fields; a finding missing one is incomplete and the report is not publishable.

| Field | Content |
|---|---|
| ID | `<claim or PR>-F<n>`, stable for the claim (`PR31-F1`). |
| Severity | BLOCKING, MAJOR, MINOR or ADVISORY, with its score impact stated. |
| Dimension | The rubric dimension it zeroes (none for ADVISORY). |
| Anchor | `path:line` at the reviewed head, as a permalink `https://github.com/<owner>/<repo>/blob/<head>/<path>#L<line>`; a range when needed. |
| Owner | The seat alias that must act (the implementer, or the owner for a Founder decision). |
| Comment | The exact text posted as the GitHub line comment at the anchor. |
| Requirement | The exact, testable change that closes it: what must be true, not how to code it; includes the test or proof to add. |
| Validator | The command, test name or probe whose output proves closure on the Correct head. |
| Disposition | `OPEN` at the critic round; `CLOSED`, `REGRESSED`, `NOT-APPLICABLE` or `PREFLIGHT-INVALID` after verification, each with evidence. |

Executed counterexamples (a failing added test, a decoded artifact, a measured output) are the preferred evidence; a source-reading argument says so.

## 5. Path to 5/5

Delivered upfront, in the report and the review body, before the ledger. One row per dimension:

| Dimension | Point now | Requirements that earn it | Evidence the owner checks |
|---|---:|---|---|
| 3 Commands and safe rendering | 0 | PR31-F1 | `register.test.ts` long-URL case passes; band mounts with the gate on both surfaces |

Rules: the list is complete (meeting every row yields 5/5 by construction); each row names IDs from the ledger only; a dimension already at 1 has an empty requirement cell; advisories are excluded; a requirement contingent on a Founder decision states both outcomes.

## 6. Correct round (implementer)

- Apply the path-to-5/5 requirements and nothing else; a wider change waits for a new claim.
- One commit per requirement where practical, the ID in the commit body (`Closes PR31-F1`), the validator run and quoted in the PR.
- Report the new head to the owner by inbox with a table: ID, commit, validator command, decisive output.

## 7. Owner verification

Deterministic, no new judgment. For each requirement ID in the path to 5/5, on the Correct head:

| ID | Validator run (command, cwd, exit, counts) | Anchor re-read | Done |
|---|---|---|---|

- All rows done, required checks green on that head, no Founder gate open → the claim is `5/5` and the owner merges under its grant (Lieutenant: its project; General: Workspace only). Record the verification as a closure record appended beside the critic's verdict (`verdicts.md`); the original N/5 stays, the verified arithmetic is shown separately.
- A row not done → back to the implementer with the same list; the Correct round continues; no new findings are added by the owner.
- A defect outside the list that the owner cannot ignore → a new claim, or a Founder decision; never a second critic round.
- Where the project uses Jira lifecycle markers, the implementer's `#review` marker and the Jira read-back precede the merge (AUDIT.md, solo review profile).

## 8. Relation to the campaign audit law

This is the PR critic profile of AUDIT.md. The campaign Wave Judge law (Preflight, retry DAG, Attempt 2, T5 Purity Recovery with a fresh successor Judge) is a different, larger procedure for waves and goals; Purity Recovery is a closed-world remediation after a blocked Attempt 2, not this cycle. The shared laws are: implementer green is a claim, one verdict per round, every finding cited at file:line, exhaustive findings in Attempt 1, history append-only.

## 9. Supersession

Founder mandate 2026-10-07, `Single Pass to Purity`, supersedes the "maximum two critic rounds" mandate of the same day: two implementation rounds (Implement, Correct) and one critic round between them.
