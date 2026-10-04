---
name: git-branch
description: >-
  Enforce the owner-ratified Git branch hierarchy, worktree isolation, upstream
  synchronization, merge promotion, hotfix continuity, and employee-managed Git
  flow. Use when starting or resuming change-bearing repository work, creating or
  reconciling branches/worktrees, preparing commits or pull requests, promoting
  releases, handling dirty state, or automating Git for nontechnical employees.
---

# Git Branch

Operate Git for the human while preserving one auditable upward hierarchy. This
skill is GitHub-first and Jira-ID-aware, but Jira ticket creation and lifecycle
belong to a separate Jira skill.

## Begin every Git operation with authority and facts

1. Read the nearest repository instructions and contribution documentation.
2. Inspect `git status`, current branch, `HEAD`, configured upstream, worktrees,
   and live remote refs before a change-bearing Git operation.
3. Run [`scripts/check-upstream.sh`](scripts/check-upstream.sh) for a read-only
   opening snapshot. Its result is evidence, not permission to mutate.
4. Load `.agent/identity.json` when present. Never print secrets or remote URLs
   containing credentials.
5. Determine the route:
   - technical Jira work → [core policy](references/core-policy.md);
   - employee-managed work → [employee extension](references/employees.md);
   - production repair → [hotfix protocol](references/hotfixes.md).
6. Stop when authority, ownership, task ID, base branch, or dirty-state custody
   is ambiguous. Do not invent an issue ID or widen the task.

## Canonical branches

```text
main        production and released state
staging     release candidate and final QA
development shared integration
```

No implementation occurs directly on a canonical branch. Normal promotion
(owner amendment 2026-10-02, see [ADR-001](references/ADR-001-git-branch-governance.md)):

```text
claim branch (one per claim; any name)
  → development
  → staging
  → main
```

A **claim** is the set of approved tickets assigned to one implementing Sergeant's seat: **at most
three Epics**, with their Tasks and Subtasks in one repository, delivered on
one branch through one PR. Three is a fixed interim cap until the owner selects
a ticket-based model/effort matrix, not a usual-size recommendation. Additional
tickets may enter only before review starts and within the cap; assignments
received after review starts wait for the next claim. Review repairs stay within
the existing claim scope. Branch names carry no meaning — Herdr's generated name
is fine. Jira keys live in commits: every Subtask commit carries a
`Refs: <SUBTASK-KEY>` footer and each Epic closes with an Epic commit carrying
`Refs: <EPIC-KEY>`. Do not create Task, Subtask or Epic-integration branches for
agent work.

## Worktree rule

One worktree per claim, never per Task or Subtask. Create it with native Herdr
in the Herdr worktree root, outside every checkout; never nest a worktree
inside a repository (no `./.worktrees/`). A seat holds at most one worktree per
repository, and it lives exactly as long as the claim: once the claim settles
(accepted and merged), the Lieutenant (the General for `~/Workspace`) removes it through verified cleanup. The
stable seat outlives the agent and worktree, retains historical harness session
IDs, and starts each new claim with a fresh agent in a fresh Herdr worktree.
Archive the outgoing thread before transport loss (see cleanup below).
For an interactive nontechnical employee, keep the
conversation in its existing workspace and operate the employee's single
worktree from there; do not fork the employee into a new conversation merely
to obtain isolation.

One repository write lease owns branch switches, stash operations, and local
merges. Do not mutate a checkout from under another active agent.

## Dirty-state cycle

When authorized synchronization encounters tracked or untracked work:

1. Inventory the paths and confirm ignored or sensitive files will not enter
   Git object storage.
2. Under the repository write lease, stash tracked and untracked changes with
   an attributable task/thread message.
3. Record the exact stash object and entry before updating the branch. Never
   rely on an unrecorded `stash@{0}` in a multi-worktree repository.
4. Fetch and update using the route's permitted strategy. Never rewrite a
   canonical, integration, employee, or other shared branch.
5. Pop only the recorded stash entry.
6. **On pop: reconcile.** Inspect conflicts, status, and the full resulting diff;
   preserve both upstream intent and owned local work. Never discard either side
   merely to complete the operation.
7. Rerun affected validation after reconciliation.

If ignored/sensitive content, uncertain ownership, an existing conflict, or a
missing write lease prevents safe stashing, stop and report the blocker.

## Validation and delivery

- Use the repository's pinned package manager and resolved task runner.
- Run applicable tests, lint, typecheck, build, and acceptance targets.
- For an application or server, also prove boot/render success and perform a
  small representative interaction before shutdown when safe and supported.
- Never push a red candidate.
- Validate Conventional Commit messages with the repository's commitlint rules.
- Agents may commit, push the owning claim branch, and open its PR when authorized.
- Only an explicitly authorized technical release authority merges or promotes.
- Use merge commits at every hierarchy boundary; do not require linear history.
- Never force-push or bypass hooks.

Use the human-readable templates under [`assets/`](assets/). PR text stays
short: what changed, why, validation, base/target, and remaining risk. Machine
evidence may be linked rather than pasted.

## Cleanup — settlement

A claim is **settled** when independent review has accepted it and its PR has
merged. The **Lieutenant owns cleanup** on the verified merged event for that
accepted claim (owner answers 2026-10-03). Settlement always triggers cleanup;
`agx clean --seat <SEAT_ID>` is the intended automation, not a verified capability:

1. Preflight the exact seat, claim, PR, target, worktree, harness session and branch
   identities, ownership, clean tree and preservation obligations. Verify acceptance,
   merge and landed proof in the intended target: ancestry where available, or
   validated content-equivalence/`merge-tree` evidence for a squash-merged candidate.
   This does not authorize squash promotion or bypass a refused safe deletion.
   Protect canonical, integration and employee branches and unrelated resources.
   Persist cleanup intent and proof outside the departing worktree before removal.
   Missing authority, proof or preservation refuses cleanup before destructive steps.
2. `.agent/` is never tracked in any repository (global ignore at `~/.config/git/ignore`); it is the agents' artifact store. Lift eligible `.agent/` artifacts into the canonical physical checkout's
   `.agent/artifacts/<flattened-branch>/`, replacing branch `/` separators with `-`:
   `worktree/rapid-stone-82f6` → `.agent/artifacts/worktree-rapid-stone-82f6/`.
   Retain original branch/claim provenance and refuse archive collisions; never
   overwrite an existing archive. Exclude credentials/secrets and live runtime
   state (sockets, locks, databases). Verify the copied inventory and hashes before
   removal; exclusions do not authorize discarding valuable state. Future annexation
   into Agent Wiki is deferred and grants no vault write authority.
3. Retain the historical harness session ID on the stable seat record before transport loss.
   Claude Code has no native archive: record the session ID and transcript path
   (`~/.claude/projects/<flattened-cwd>/<session>.jsonl`) in the settlement intent
   record, then `/exit`; leave the transcript in place and copy nothing.
   Codex uses `codex archive <SESSION>`. For another harness, verify its mechanism;
   archival is not deletion of session history.
4. Remove only the exact claim worktree registration/directory and Herdr linkage
   using the verified native teardown sequence. A targeted `git worktree remove
   <path>` is used only where that sequence requires it; never broad-prune or assume
   Git removal and Herdr unlink are interchangeable, or blindly remove twice.
5. Safely delete only the proven merged local and remote claim branch after landed
   proof. Local deletion uses plain `git branch -d`; a refusal stops, never escalates
   automatically to `-D` or `--force`. Reconcile hosting auto-deletion and refuse
   deletion of a remote ref changed since proof. Preserve every canonical,
   integration and employee branch.
6. Verify all cleanup postconditions and durable progress receipts. Retain the
   stable seat and session history; each new claim starts a fresh agent in a fresh
   Herdr worktree. Only then report `SETTLED <seat> <claim>` to the owner line.

Unmerged/abandoned cleanup requires explicit `--abandon` plus case-specific owner
approval and verified remote-branch preservation; never delete that remote branch.
Missing preservation proof is refusal, not authority to push. Every `--force`
request goes to the owner with the exact blocked operation and consequences for
explicit approve/deny each time; approval is not a blanket bypass of safety gates.

Preflight refusals precede destructive steps. A later external failure is partial
cleanup, not success or atomic rollback across Git, Herdr, the harness and remote.
Resume from reverified durable receipts for the original claim, never its successor;
do not emit `SETTLED` while cleanup is pending or partial. Do not clean resources
owned by another seat or person. A throwaway Herdr teardown probe and verification
of any otherwise unspecified harness archive mechanism remain dispatch prerequisites, not operations
authorized by this policy text.

## Bootstrap and enforcement

Repository adoption starts with read-only discovery and an explicit report.
An authorized technical user approves topology changes. A repository that has
opted into employee automation may normalize a nontechnical employee workspace
automatically through an exact Codex App Server execution envelope.

When canonical branches are absent and creation is authorized, create
`development` and `staging` atomically at the verified live `origin/main` SHA.
Never rewind an existing branch.

Use GitHub rulesets, required checks, CODEOWNERS, and environments when the plan
supports them. When server-side protection is unavailable, install Actions
checks and state clearly that agent instructions are defense in depth, not
equivalent enforcement.

## Resources

- [Accepted governance ADR](references/ADR-001-git-branch-governance.md)
- [Core technical topology](references/core-policy.md)
- [Atlantis employee extension](references/employees.md)
- [Production hotfix protocol](references/hotfixes.md)
- [Read-only upstream preflight](scripts/check-upstream.sh)
- [Identity example](assets/identity.example.json)
- [Execution envelope example](assets/execution-envelope.example.json)
- [Issue template](assets/issue-template.md)
- [PR template](assets/pr-template.md)
- [Preflight report template](assets/preflight-report.md)
- [Hotfix report template](assets/hotfix-report.md)
