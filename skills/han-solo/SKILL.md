---
name: han-solo
description: Execute a claim of at most three approved Jira Epics (or a bounded ticket set within that cap) with one primary agent in one worktree and one PR — one commit per Subtask, one Epic commit per Epic — handed off for independent review and finalized only after merge. Also use to plan or resume this workflow without implying execution authority.
metadata:
  version: "1.1.0"
---

# Han Solo — Claude Code

Turn approved Jira intent into a reviewable plan and execute its task Directives faithfully. Stop at READY_FOR_REVIEW; implementation completion is a claim, not acceptance.

## Native adapter

Use the task/todo tools actually exposed by Claude Code to mirror the durable plan. Read CLAUDE.md as well as AGENTS.md. Do not require Codex app tools, update_plan, or Pi extensions. Use the installed Herdr skill only when the assignment requests Herdr and its binding is verified.

Honor the user's chosen model, reasoning, budget and concurrency. Do not hardcode a provider/model or launch agents merely because this skill was invoked. One primary implementer owns the run. Research fan-out requires assignment authority and the supported local transport; no silent alternate harness fallback.

## Ticket authoring

Use the sibling [ticketing skill](../ticketing/SKILL.md) to prepare the Epic batch as technical Feature Charters, then deeply inspect each Epic before writing Task Directives. Each Subtask names one evidence-based fulfilment requirement of its Directive. Bugs retain the canonical Directive. Han Solo consumes approved tickets; it does not silently author new scope while implementing.

## Read and execute

1. Read [the execution contract](references/execution.md), applicable project instructions and the repository BATDD router/profile (or installed BATDD skill when no router exists) before planning or implementation.
2. Hydrate the complete Jira input and its provenance; clarify material ambiguity. Jira defaults to read-only input.
3. Use [the Epic template](templates/EPIC.md) and [the plan template](templates/PLAN.md). Bind each task to [the bundled canonical BATDD Directive](templates/DIRECTIVE.md). This is a synchronized distribution of `~/.claude/skills/batdd/templates/DIRECTIVE.md`, not a competing contract.
4. Issue complete versioned Directives; no placeholder may reach a worker. Execute task-by-task with proof, frozen acceptance, self-review and task-local resource hygiene; claim teardown belongs to the Lieutenant (the General for `~/Workspace`) after settlement.
5. Claim the approved tickets assigned to your implementing Sergeant's seat (**at most three Epics**, a fixed interim cap pending the owner's ticket-based model/effort matrix) and deliver them in one treehouse worktree, one branch and one PR — a slot leased from the repository's own pool (`<repo>/.treehouse/`, `treehouse get --lease --lease-holder <seat>`, opened in Herdr with `herdr worktree open`; Founder mandate 2026-10-06), never a worktree per Task or Subtask. Add scope only before review starts and within the cap; later assignments wait for the next claim. Each new claim starts a fresh agent in a freshly leased slot; retain the stable seat and historical session IDs. Branch names carry no meaning and are never validated (recommended `<type>/<slug>`); Jira keys go in commits.
6. Within the delivery grant, commit each completed Subtask with its key in the repository's ticket-key convention; a Task needs no separate commit. The default is a `Refs: <SUBTASK-KEY>` footer; a repository convention governs where one exists. Where the repository defines Jira lifecycle markers, apply them per Task as it specifies: file review or critique findings as Bugs through the Jira write seat before fixing them, push the start marker when work on the Task begins, go RED then GREEN, and after the gates pass push the review marker alone in an empty commit, in the repository's marker syntax. Marker commits are lifecycle checkpoints; they never close a Subtask. Close each Epic with one Epic commit holding its reconciliation and Subtask SHAs.
7. Verify the PR head and checks, perform the authorized readiness transition, and await independent review. Where the repository defines lifecycle markers, the Jira write seat reads Jira back, and READY_FOR_REVIEW is claimed only when that read-back shows the repository's review status (In Review in Ops). Nothing is final — no Jira Done — until review approves and the PR merges; that settles the claim. The Lieutenant owns cleanup under the git-branch skill, including verified artifact preservation, outgoing-thread archival before transport loss, targeted teardown and safe merged local/remote branch deletion. Report `SETTLED <seat> <claim>` only after verified cleanup. Herdr teardown remains a verification prerequisite; the git-branch settlement policy owns harness-specific archival; the implementer still stops at READY_FOR_REVIEW.

Planning-only requests stop at the requested plan. A skill is not a grant to write Jira, push, merge, deploy, or delete worktrees. Record explicit authority once and act within it without repeated permission requests.

## Canonical alignment

Agent Wiki: `Jira Epic and Task Contracts`, `Agent Directives`, `Han Solo`, `BATDD`, `TESTING`, `GHERKIN`, and `AUDIT`. Use the Agent Wiki skill to retrieve relevant doctrine when authoring/amending contracts or resolving conflicts; do not reload the whole Wiki for every task.

`~/.claude/skills` is canonical. `~/.codex/skills`, `~/.agents/skills`, `~/.pi/agent/skills` and `~/.dotfiles/skills` mirror it, except intentional harness-specific lines (for example Claude Code versus Codex tool names), which stay. Portable execution references and templates match; native entrypoints intentionally differ.
