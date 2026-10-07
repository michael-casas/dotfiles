---
name: audit
description: Run the Single Pass to Purity review cycle on a pull request or candidate - as the one dedicated critic (score the head N/5 on the five-point rubric, assign every finding to an owner with a file:line anchor and the exact PR review comment, and deliver the complete path from N/5 to 5/5 upfront in ONE GitHub review), or as the merge owner verifying the Correct round against that list. Use whenever a task mentions a critic round, PR review verdict, N/5 score, path to 5/5, findings ledger, audit report, or Purity.
metadata:
  version: "2.1.0"
---

# Audit — Single Pass to Purity

One critic round per claim. The critic's single report must let the implementer reach 5/5 without a second critic round: every finding assigned, anchored and commented, and the exact requirements that take the score from N/5 to 5/5 stated upfront. Repairs are never the critic's.

## Cycle

The cycle is stated once in PURITY (ratified 2026-10-07): `/Users/mcasa_atlantis/Documents/vaults/Agent Wiki/standards/PURITY.md`, identical to `docs/standards/PURITY.md` in `michael-casas/workspace`. In one line: Implement, one Critic round, Correct, owner verification, merge at 5/5. This skill is the procedure, not the law. Roster law: one dedicated GPT 6.1 Sol critic per project, never the PR's author, no second reviewer.

## Read first

1. The nearest `AGENTS.md`/`CLAUDE.md`, your charter and its Amendments, the claim's Directives and frozen acceptance.
2. `PURITY.md` and `AUDIT.md` in `/Users/mcasa_atlantis/Documents/vaults/Agent Wiki/standards/` through the `agent-wiki` skill (the cycle and findings contract; evidence hierarchy, verdict law, false-pass checklist, PR critic profile).
3. [references/process.md](references/process.md): the critic seat protocol, the findings contract and the owner's verification checklist.
4. [references/gh-review.md](references/gh-review.md): the one-review `gh api` call and its checks.
5. [assets/AUDIT_TEMPLATE.md](assets/AUDIT_TEMPLATE.md): the report, filled completely.

Stop if the head, the base, the write surface or your independence is ambiguous, or if the five dimensions are not declared and frozen in your charter before the review; the default set in process.md §3 is a proposal the owner approves first, never a silent substitute.

## Critic round (one per claim)

1. Pin the exact head (`gh pr view <n> --json headRefOid`) and review only it, from a pinned snapshot; a moved head is reported, not chased.
2. Validate the candidate's existing proof first (AUDIT.md §3 and §6 step 3): fresh gate output bound to this exact head is accepted; missing, stale, cached or mismatched proof is re-run uncached. Always add targeted probes and temporary adversarial tests in the disposable snapshot only. Implementer green is a claim.
3. Score five dimensions, each exactly 0 or 1, with decisive evidence; show the arithmetic `D1+D2+D3+D4+D5 = N/5`.
4. Record every finding, advisories included, with all contract fields: ID, severity (BLOCKING, MAJOR, MINOR, ADVISORY), dimension or no score impact, anchor `path:line` at the head, owner, exact comment text, exact requirement, validator, disposition. Continue after the first finding; the ledger is exhaustive.
5. Write the **Path to 5/5** table upfront: for each dimension below 1, the requirement IDs that earn the point and the evidence the owner will check; for each dimension at 1, what must remain green and its evidence. Advisories never appear in it.
6. State one verdict (APPROVED, BLOCKED or ESCALATED) beside the score and post exactly one GitHub review on that head: `REQUEST_CHANGES` below 5/5, `APPROVE` at 5/5, `COMMENT` only when the account cannot do either (it never means approval); body = score table + path to 5/5 + ledger; one line comment per finding whose anchor is a diff line, anchors validated before the POST; findings outside the diff keep permalink and full text in the body; inline plus body-only IDs equal the ledger. A failed or uncertain POST is read back before any retry; a published defect is recorded and escalated, never corrected by a second review.
7. Save the report and send it by inbox to the implementer and the owner: `inbox-send <critic> <to> report "<N/5 at <head>>" <file>`. Then stop. Answer bounded clarification questions; never open a second round, never repair, push or merge.

## Correct round (implementer)

Apply exactly the path-to-5/5 list, one commit per requirement where practical, citing the requirement ID; run each validator; report the new head with a per-requirement evidence table. Nothing outside the list enters the Correct round.

## Verification (merge owner: General or Lieutenant)

Deterministic checklist, no new judgment: for each requirement ID, re-run its validator on the Correct head and record done with evidence, or not done; re-check each earned point's preservation evidence, scope, required checks on that head and Founder gates. All done, nothing regressed → 5/5 → merge under the grant. A not-done item returns to the implementer with the same list, recorded as a return; a second failed verification, a regressed point, a scope change or an unsatisfiable host approval rule is escalated to the General or the Founder; a defect outside the list is a new claim or a Founder decision. Never a further unnamed implementation round, never a second critic round.

## Provenance

Annexed from `~/.codex/skills/audit` (the Codex Workflows external-audit variant with its tmux auditor and `sync-monitor` stall stays there) and realigned to the Founder mandate of 2026-10-07 (`Single Pass to Purity`, ratified in PURITY), which supersedes the "maximum two critic rounds" mandate. The Codex Workflows five dimensions remain that variant's named profile, not general law.
