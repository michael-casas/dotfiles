# <EPIC-KEY>: <feature charter title>

Version: <version> | Authority: <owner decision/link/date> | Status: <proposed/approved>
Source: <Jira URL, updated timestamp, retrieved timestamp, digest>
Delivery scope: <bounded acceptance version/slice; state if this is an owner-designated long-lived Epic>

## Problem and outcome

<Technical PRD: current problem, users/actors, required outcome and business impact.>

## Ownership and boundaries

- Accountable owner: <person>.
- Primary repository: <repository>.
- Consumers/other repositories: <owner and contract for each>.
- In scope: <behavior>.
- Out of scope/protected: <behavior, data and interfaces>.

## Functional requirements

| ID | User/actor and required behavior | Acceptance IDs |
| --- | --- | --- |
| <EPIC>-FR1 | <observable requirement> | <IDs> |

## Non-functional requirements

| ID | Constraint and measurable threshold | Verification |
| --- | --- | --- |
| <EPIC>-NFR1 | <reliability, security, performance or other relevant constraint> | <evidence> |

Use only grounded requirements; record unchosen thresholds as open decisions, not invented numbers.

## Acceptance

| ID         | Observable required outcome | Forbidden outcome  | Required integration proof |
| ---------- | --------------------------- | ------------------ | -------------------------- |
| <EPIC>-AC1 | <outcome>                   | <forbidden effect> | <proof>                    |

## Child task inventory

Breakdown: <pending Epic introspection | reviewed findings reference/date>.
Publish the Epic batch first. Write Tasks only after deep inspection of this
Epic's requirements, existing implementation, dependencies and open decisions.
Each Task is a canonical Directive; each Subtask names one fulfilment obligation
of that Directive and the evidence that closes it.

| Jira key     | Deliverable | Acceptance IDs | Depends on      | Owning repository | Directive/version |
| ------------ | ----------- | -------------- | --------------- | ----------------- | ----------------- |
| <actual key> | <outcome>   | <IDs>          | <keys/evidence> | <repository>      | <path/version>    |

After introspection, every approved child in the delivery scope is included or explicitly excluded with owner authority. Before then, leave the inventory explicitly pending. Proposed tasks have local proposal IDs until Jira assigns real keys.

## Delivery and aggregate completion

- Claim, worktree, branch and PR: <implementing Sergeant's seat; one Herdr worktree and one PR per repository for the whole claim of 1–3 Epics; branch name carries no meaning>.
- Commit, push and PR-readiness authority: <exact grant>.
- Jira read/write authority: <default read only; exact granted writes if any>.
- Aggregate gates: <resolved checks, integration, public surface, cleanup>.
- Baseline exceptions: <accepted exceptions and authority, or none>.
- Implementation finish: all required task receipts and aggregate proof, final PR heads verified, PRs ready for review.
- Commits: one per Subtask (`Refs: <SUBTASK-KEY>`), then one Epic commit with the reconciliation and Subtask SHAs.
- Acceptance: independent PR review; Jira Done only after review approval and merge, by the authority holding those grants.

For a long-lived Epic, these completion gates apply to the approved delivery slice;
finishing a slice does not close the Epic or accept future features.

## Decisions and amendments

| Version/date | Decision or open question | Owner/source | Affected tasks/contracts |
| ------------ | ------------------------- | ------------ | ------------------------ |

## Evidence and references

<Approved decisions, source snapshot, plan, relevant standards.>
