# Core Technical Branch Policy

Read this reference for ordinary technical, Jira-identified, worktree, commit,
PR, merge, and release operations. Owner amendment 2026-10-02 replaced the
per-Task/Subtask branch-and-worktree hierarchy with claim delivery.

## Claims and naming

| Role | Pattern | Example |
|---|---|---|
| Claim branch | Any short name, recommended `<type>/<slug>`; never validated | `feat/acm-18-landing` |
| Hotfix | `HOTFIX/<HOTFIX_HASH>` | `HOTFIX/a81c23f` |

A claim is one implementing Sergeant's seat's approved assigned tickets: **at most three Epics**, with
their Tasks and Subtasks in one repository, delivered in one worktree, on one
branch through one PR. Three is a fixed interim cap until the owner selects a
ticket-based model/effort matrix. Additional tickets may enter only before review
starts and within the cap; later assignments wait for the next claim. Review
repairs stay within the existing claim scope. Branch names carry no meaning. Do not create Task, Subtask or Epic-integration
branches for agent work. Do not invent Jira identifiers. The Jira integration
skill owns ticket creation and lifecycle; this skill consumes ratified IDs.

## Commits carry the keys

- One commit per Subtask, Conventional Commit format, with a
  `Refs: <SUBTASK-KEY>` footer and the parent Task key.
- No separate Task commit; a Task is complete when its Subtasks are committed.
- One Epic commit after the Epic's last Subtask: reconciliation, acceptance
  coverage and Subtask SHAs, with `Refs: <EPIC-KEY>`.
- Review repairs are new commits referencing the same Subtask key.
- The repository's commitlint rules win on format.

## Start

1. Run the read-only preflight.
2. Verify the claimed issues, seat, write surface, and intended PR base
   (`development` where it exists, otherwise the repository's documented
   integration base).
3. Fetch before starting the claim.
4. Lease the claim's worktree from the repository's treehouse pool, from the
   repository root: `path=$(treehouse get --lease --lease-holder <seat>)`, then
   `herdr worktree open --cwd <repo root> --path "$path" --label <slug> --no-focus`
   (Founder mandate 2026-10-06; spec `~/Workspace/docs/standards/treehouse.md`).
   A seat holds at most one slot per repository; never one per Task or Subtask.
   `herdr worktree create`, `git worktree add` and `./.worktrees/` are not used.
5. Start a fresh agent and create the claim branch inside the slot from the
   current base (`git -C "$path" switch -c <branch> origin/<base>`; the slot
   starts detached). Resume an existing slot only for its current claim, never
   for a successor claim; retain the stable seat and historical harness session IDs.

## Synchronize

- Rebase only the privately owned claim branch, and not after review has
  started; afterwards merge the base in.
- Never rebase `main`, `staging`, `development`, a department integration
  branch, or an employee branch.
- Mandate-driven exception (Founder mandate 2026-10-06): when the repository
  owner orders it, an open PR branch is rebased onto its updated base and pushed
  with `--force-with-lease`, one PR at a time, by the owner's named seat, keeping
  its name. The shared branches above are never rebased or force-pushed.
- Before mutation and before declaring ready, compare the base with the live
  remote.
- If upstream already contains the fix, stop implementation and record evidence.
- If upstream changed, preserve dirty state through the accepted stash cycle,
  update, pop and reconcile, then rerun validation.

## Integrate

```text
claim branch → development → staging → main
```

The claim PR into `development` is reviewed and merged with a merge commit by an
explicitly authorized technical release authority. Apply the repository's
feature or version bump in the claim PR when it completes an Epic or an
owner-designated slice. Each later arrow is a separate reviewed promotion.
Production originates only from `main`. Nothing in a claim is final — no Jira
Done — until its review approves and the PR merges.

## Authority and bypass

Conversational identity may select the technical interaction mode but never
grants credential authority. GitHub authentication and explicit task authority
govern merges, settings, deployment, and break glass. Agents do not commit
directly to canonical branches.

## Cleanup

The Lieutenant (the General for `~/Workspace`) owns cleanup once independent review accepts the claim and its
PR merges. Follow [the settlement procedure](../SKILL.md#cleanup--settlement):
preflight ownership, clean tree, preservation and landed proof; persist intent;
lift eligible `.agent/` artifacts into the canonical physical checkout's
`.agent/artifacts/<flattened-branch>/` (branch `/` → `-`), excluding credentials,
secrets and live sockets/locks/databases; verify the copy; archive the outgoing
thread before transport loss; close the Herdr pane and workspace, then
`treehouse return "$path" --if-lease-holder <seat>` (confirm `available` in
`treehouse status --json`; never remove or delete the slot); safely delete only the merged local and remote claim
branch. Ancestry or validated content-equivalence proof can establish landing;
this does not change merge-commit promotion law or bypass safe-deletion refusals.
Preserve canonical, integration and employee branches; never broad-prune or remove
another execution's resource. Retain the stable seat and historical session ID;
each new claim starts a fresh agent and worktree. Report `SETTLED <seat> <claim>`
only after all cleanup postconditions are verified.

Unmerged/abandoned cleanup requires explicit `--abandon`, case-specific owner
approval and verified remote-branch preservation. Missing proof refuses cleanup,
not authorizes a push. Every `--force` request requires owner approve/deny for that
exact operation; never automatically escalate to `--force` or `-D`, or treat
approval as a blanket gate bypass. Preflight refusals precede destructive steps;
later external failures are partial cleanup, recovered from verified durable
receipts for the original claim, never claimed as atomic rollback or success.
`agx clean --seat <SEAT_ID>` is intended automation; Herdr teardown probing and
verification of otherwise unspecified harness archive mechanisms remain
dispatch prerequisites. Wiki artifact annexation is deferred.
