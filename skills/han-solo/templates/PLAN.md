# <EPIC-KEY> execution plan

Epic/source snapshot: <Feature Charter path and identity>
Epic introspection: <findings reference/date> | Delivery scope: <approved version/slice>
Authority: <approved assignment> | Delivery grant: <commit/push/readiness>
Claim: <EPIC keys (1–3)> | Seat: <seat>
Worktree: <absolute path, Herdr worktree root> | Branch/base: <any name; SHA> | PR: <one URL per repository>
Directive source: <canonical BATDD template version/digest>

## Task checklist

- [ ] <Jira task key> — <deliverable> — Directive <path/version/digest>
  - [ ] <local step ID> Authority, dependency evidence and scope hydrated.
  - [ ] <local step ID> Applicable proof designed; meaningful RED or justified characterization/N/A recorded.
  - [ ] <local step ID> Acceptance frozen; implementation and required layers GREEN.
  - [ ] <local step ID> Scoped self-review, affected gates and cleanup complete.
  - [ ] <local step ID> Every Subtask committed with its `Refs:` key; Task complete (no separate Task commit).

Repeat per actual Task Directive after Epic introspection. Local steps organize execution; they never masquerade as Jira issues. Each Jira Subtask represents one evidence-based fulfilment requirement of the Directive, recorded below. Keep one active task and record blocked reasons explicitly.

## Directive fulfilment requirements

| Parent Task / Directive version | Subtask key (or explicit local obligation ID) | One obligation / requirement ID | Required closing evidence | Actual evidence / state |
| --- | --- | --- | --- | --- |
| <Task / version> | <real key or local ID> | <one obligation> | <check/artifact and passing outcome> | <reference or pending> |

Check an obligation only on its named evidence. A local check is not a Jira transition or independent acceptance.

## Subtask receipts

| Epic | Task / Directive identity | Subtask | Acceptance IDs | Evidence/results | Subtask commit | State/blocker |
| ---- | ------------------------- | ------- | -------------- | ---------------- | -------------- | ------------- |

Each Epic commit records its Subtask SHAs here; a commit never embeds its own SHA. Checked means implementation delivered, not independently accepted. Nothing is final until review approves and the PR merges.

## Epic handoff

- [ ] Per claimed Epic: child inventory and acceptance coverage reconciled and recorded in its Epic commit.
- [ ] Cross-task/repository integration and final required gates pass.
- [ ] Blocking punch-list items closed; exceptions attributable.
- [ ] Final candidate includes required deliverables and plan receipts.
- [ ] Owning PR head(s), base(s) and required checks verified.
- [ ] Authorized PR readiness action succeeded and state verified.
- [ ] EPIC_IMPLEMENTATION_COMPLETE claim and READY_FOR_REVIEW handoff recorded.
- Independent review: <awaiting/findings/accepted by named authority; agent cannot self-accept>.

For an owner-designated long-lived Epic, hand off the completed delivery slice;
do not claim closure of the Epic or acceptance of future features.

## Resume

- Current task/phase and directive identity: <one active item>.
- Source freshness/amendments: <verified time or explicit snapshot limitation>.
- HEAD and dirty custody: <SHA, owned paths, preserved unrelated paths>.
- Locked proof and open failures: <IDs and evidence>.
- Last successful Subtask or Epic commit: <SHA>.
- Outstanding cleanup: <resources or none>.
- Exact next action and stop boundary: <action>.
