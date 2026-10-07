---
name: audit
description: Run the Single Pass to Purity review cycle on a pull request or candidate - as the one dedicated critic (score the head N/5 on the five-point rubric, assign every finding to an owner with a file:line anchor and the exact PR review comment, and deliver the complete path from N/5 to 5/5 upfront in ONE GitHub review), or as the merge owner verifying the Correct round against that list. Use whenever a task mentions a critic round, PR review verdict, N/5 score, path to 5/5, findings ledger, audit report, or Purity.
metadata:
  version: "2.0.0"
---

# Audit — Single Pass to Purity

One critic round per claim. The critic's single report must let the implementer reach 5/5 without a second critic round: every finding assigned, anchored and commented, and the exact requirements that take the score from N/5 to 5/5 stated upfront. Repairs are never the critic's.

## Cycle

Implement → **one Critic round** → Correct → owner verification → merge at 5/5. The cycle is stated once in `docs/standards/PURITY.md` of the Workspace repository (draft until ratified); this skill is the procedure, not the law. Roster law: one dedicated GPT 6.1 Sol critic per project, never the PR's author, no second reviewer.

## Read first

1. The nearest `AGENTS.md`/`CLAUDE.md`, your charter and its Amendments, the claim's Directives and frozen acceptance.
2. `/Users/mcasa_atlantis/Documents/vaults/Agent Wiki/standards/AUDIT.md` through the `agent-wiki` skill (evidence hierarchy, verdict law, false-pass checklist, PR critic profile).
3. [references/process.md](references/process.md): the critic seat protocol, the findings contract and the owner's verification checklist.
4. [references/gh-review.md](references/gh-review.md): the one-review `gh api` call and its checks.
5. [assets/AUDIT_TEMPLATE.md](assets/AUDIT_TEMPLATE.md): the report, filled completely.

Stop if the head, the base, the rubric, the write surface or your independence is ambiguous.

## Critic round (one per claim)

1. Pin the exact head (`gh pr view <n> --json headRefOid`) and review only it, from a pinned snapshot; a moved head is reported, not chased.
2. Run the declared gates uncached and inspect their output; add targeted probes and temporary adversarial tests in the disposable snapshot only. Implementer green is a claim.
3. Score five dimensions, each exactly 0 or 1, with decisive evidence; show the arithmetic `D1+D2+D3+D4+D5 = N/5`.
4. Record every finding with all contract fields: ID, severity (BLOCKING, MAJOR, MINOR, ADVISORY), dimension, anchor `path:line` at the head, owner, exact comment text, exact requirement, validator, disposition. Continue after the first finding; the ledger is exhaustive.
5. Write the **Path to 5/5** table upfront: for each dimension below 1, the requirement IDs that earn the point and the evidence the owner will check. Advisories never appear in it.
6. State one verdict (APPROVED, BLOCKED or ESCALATED) beside the score and post exactly one GitHub review on that head: `REQUEST_CHANGES` below 5/5, `APPROVE` at 5/5, `COMMENT` only when the account cannot do either (it never means approval); body = score table + path to 5/5 + ledger; one line comment per finding at its anchor.
7. Save the report and send it by inbox to the implementer and the owner: `inbox-send <critic> <to> report "<N/5 at <head>>" <file>`. Then stop. Answer bounded clarification questions; never open a second round, never repair, push or merge.

## Correct round (implementer)

Apply exactly the path-to-5/5 list, one commit per requirement where practical, citing the requirement ID; run each validator; report the new head with a per-requirement evidence table. Nothing outside the list enters the Correct round.

## Verification (merge owner: General or Lieutenant)

Deterministic checklist, no new judgment: for each requirement ID, re-run its validator on the Correct head and record done with evidence, or not done. All done and checks green → 5/5 → merge under the grant. A not-done item returns to the implementer with the same list; a defect outside the list is a new claim or a Founder decision, never a second critic round.

## Provenance

Annexed from `~/.codex/skills/audit` (the Codex Workflows external-audit variant with its tmux auditor and `sync-monitor` stall stays there) and realigned to the Founder mandate of 2026-10-07 (`Single Pass to Purity`), which supersedes the "maximum two critic rounds" mandate.
