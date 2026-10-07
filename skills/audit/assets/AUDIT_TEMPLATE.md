# Audit: <claim or PR> — <N>/5 at `<head sha>`

**Template version:** 2.1.0
**Critic:** <seat alias and model>
**Order:** <ULID>
**UTC:** <YYYY-MM-DDTHH:MM:SSZ>
**PR:** <url> (base `<base>`, draft yes/no)
**Reviewed head:** `<full sha>` (pinned; moved to `<sha>` during review: yes/no)
**Snapshot:** `<path>` from `git archive <head>`
**Independence:** did not implement, repair or coordinate this candidate; write surface = this report, one GitHub review, temporary tests in the snapshot.

## Verdict

**<N>/5** — APPROVED | BLOCKED | ESCALATED (GitHub event `REQUEST_CHANGES` | `APPROVE` | `COMMENT`). One sentence on what separates the head from 5/5.

## Score

| # | Dimension | Point | Decisive evidence |
|---:|---|---:|---|
| 1 | <dimension> | 0/1 | <file:line, command, artifact> |
| 2 | <dimension> | 0/1 | |
| 3 | <dimension> | 0/1 | |
| 4 | <dimension> | 0/1 | |
| 5 | <dimension> | 0/1 | |

`<D1> + <D2> + <D3> + <D4> + <D5> = <N>/5`

## Path to 5/5 (upfront, complete)

| Dimension | Point now | Requirements that earn it | Evidence the owner checks |
|---|---:|---|---|
| <#> <dimension> | 0 | <IDs> | <validator output, anchor re-read> |

A dimension at 1 states what must remain green and its evidence. Meeting every row with every earned point still green yields 5/5. Advisories are not in this table. A requirement that depends on a Founder decision states both outcomes.

## Findings

| ID | Severity | Dim | Anchor (permalink at head) | Owner | Comment (as posted) | Requirement | Validator | Disposition |
|---|---|---:|---|---|---|---|---|---|
| <PR-Fn> | BLOCKING / MAJOR / MINOR | <1-5> | `<path:line>` | <seat> | <exact text> | <exact, testable> | <command / test> | OPEN |

## Advisories (assigned, no score impact)

| ID | Anchor (permalink) | Owner | Comment (as posted or body-only) | Requirement | Validator | Disposition |
|---|---|---|---|---|---|---|

## Validation on the unmodified snapshot

| Command | cwd | Exit | Counts | Decisive output | Artifact |
|---|---|---:|---|---|---|

## Adversarial probes and temporary tests (snapshot only)

| Probe | What it attacks | Result | Evidence |
|---|---|---|---|

## Scope, invariants and security

<Findings with file:line, or the surfaces and commands proving none.>

## Discrepancies between the PR's claims and the head

<Each mismatch with evidence, or none with the inspection that proves it.>

## GitHub review

- Review id and URL:
- Event:
- Inline comment IDs: <list>; body-only IDs (outside the diff): <list>; together = ledger: yes
- POST result read back (id present once): yes

## Inbox report

- Sent to implementer `<alias>` (ULID):
- Sent to owner `<alias>` (ULID):

## Next action

Implementer applies the path to 5/5 (Correct round); owner verifies it against this list and merges at 5/5. No second critic round.

SINGLE_PASS_COMPLETE

---

## Owner verification (filled by the owner on the Correct head)

**Correct head:** `<sha>`  **Verifier:** <owner alias>  **UTC:**

| ID | Correction commit | Validator run (command, cwd, exit, counts) | Anchor re-read | Disposition |
|---|---|---|---|---|

**Earned points re-checked:** <dimension: preservation evidence on the Correct head>  **Scope unchanged:** yes/no  **Checks green on head:** yes/no  **Founder gates:** none open / <gate>

**Returns so far:** <0|1>; a second failed verification escalates.

**Verified arithmetic:** `<D1> + <D2> + <D3> + <D4> + <D5> = <N>/5` (the critic's original N/5 above is not rewritten)

**Result:** 5/5 and merged at `<sha>` | returned to implementer (IDs not done: <list>) | escalated (<decision>).
