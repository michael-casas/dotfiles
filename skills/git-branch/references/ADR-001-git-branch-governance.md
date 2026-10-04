# ADR-001: Hierarchical Git Branch Governance

**Status:** Accepted

**Decision date:** 2026-09-04
**Authority:** Repository owner rulings captured through the Git-branch policy discussion

## Context

Multiple humans and coding agents work concurrently, including nontechnical
employees who must not be responsible for Git mechanics. Work needs durable
issue identity, isolated worktrees, reviewable promotion, clean production
history, and automatic recovery without allowing an agent to bypass the branch
hierarchy.

Git reference names also impose a structural constraint. With supported Git
ref behavior, a branch such as `AES-13` cannot coexist with
`AES-13/AES-45`. Long-lived Epic and department branches therefore use the
leaf name `integration`.

## Decision

### Canonical branches

```text
main        production and released state
staging     release candidate and final QA
development shared integration
```

No implementation occurs directly on these branches. Promotion uses reviewed
merge commits in this order:

```text
development → staging → main
```

### Technical Jira hierarchy

```text
<EPIC-ID>/<TASK-ID>_<subtask-id>
  → <EPIC-ID>/<TASK-ID>
  → <EPIC-ID>/integration
  → development
  → staging
  → main
```

Epic and Task identifiers are uppercase. A subtask suffix is lowercase. Every
task has a corresponding issue. Subtask-to-task integration may be performed
as a validated local merge. Task-to-Epic and every higher promotion use a
reviewed pull request. The Epic promotes only after an explicit
`EPIC_COMPLETE` verdict; the repository's feature or version bump belongs to
that Epic-complete merge boundary.

### Employee hierarchy

```text
local task worktree or temporary bridge
  → <department>/<employee>
  → <department>/integration
  → development
  → staging
  → main
```

The agent owns Git mechanics for a nontechnical employee. A temporary bridge
may exist only on the employee branch, must stay green, and must be replaced by
a J5-owned repair before promotion into department integration.

### Worktrees

Every change-bearing task uses an isolated worktree. A detached worktree is
attached to its owning branch before mutation. Nontechnical employees remain in
their existing conversation; their agent creates and operates a local
`./.worktrees/` checkout rather than moving the employee into a new Codex
conversation.

### Dirty-state recovery

The standard recovery is an attributable automatic stash cycle under a
repository write lease:

1. Inventory tracked, untracked, ignored, and sensitive paths.
2. Stash tracked and untracked work and record the exact stash object.
3. Update the permitted base without rewriting a shared branch.
4. Pop only the recorded stash entry.
5. On pop, reconcile the complete resulting diff and every conflict.
6. Rerun affected validation.

Ignored or sensitive files never enter the stash merely to make synchronization
convenient. Unsafe custody stops the update.

### History

Merge commits are used at every hierarchy boundary. Linear-history enforcement
is disabled. Force-push and shared-history rewriting remain prohibited.

### Hotfixes

Emergency work begins at `HOTFIX/<HOTFIX_HASH>` from `main` and reaches `main`
through review. The exact patch is then forward-ported through reviewed branches
based on `development` and, when required by an active release, `staging`.
Shared canonical branches are never rebased onto `main`. Active tasks rebase
onto the updated `development` and run affected validation.

### Authority

Agents may create isolated worktrees, implement, validate, commit, push their
owning task branch, and open pull requests when the assignment authorizes those
actions. An explicitly authorized technical release authority performs merges
and promotion. Direct canonical commits are blocked; break-glass work is
explicit, narrow, and auditable.

## Consequences

- Every production change has a visible upward path.
- Epic and department work can receive many task PRs without Git ref conflicts.
- Merge commits preserve corporate integration boundaries.
- Worktree and branch cleanup become agent responsibilities after merge and
  evidence retention.
- Nontechnical employees can continue working without learning Git operations.
- Temporary bridges create controlled technical debt and therefore require an
  immediate issue, owner, marker, replacement, and promotion block.
- Hotfixes require explicit forward-port work so a later release cannot erase a
  production repair.
- GitHub Actions can detect violations, but server-side rulesets remain the
  stronger enforcement layer when the repository plan supports them.

## Alternatives considered

### Branch named only `<EPIC-ID>`

Rejected because it cannot coexist portably with `<EPIC-ID>/<TASK-ID>`.

### Direct task PRs into `development`

Rejected for multi-task Epics because it removes the Epic-complete integration
gate.

### Linear history and squash-only promotion

Rejected because the owner chose merge commits as durable hierarchy boundaries.

### Generic stash–pull–pop without identity

Rejected. The accepted stash cycle records the exact stash object, runs under a
write lease, excludes unsafe content, and requires reconciliation after pop.

### No hotfix propagation

Rejected because later development promotion could remove or regress a repair
present only on `main`.

### Unbounded employee bridges

Rejected because a bridge must never reach department integration without
purification.

## Amendment 1 — claim delivery (2026-10-02)

**Authority:** repository owner ruling, 2026-10-02, after removing about 25 GB of
nested per-task worktrees.

Supersedes the *Technical Jira hierarchy* and *Worktrees* decisions above for
agent work. Employee, hotfix, dirty-state, history and canonical-branch
decisions are unchanged.

- An agent claims the tickets assigned to its seat — one to three Epics — and
  delivers them in one worktree, on one branch, through one PR into
  `development`.
- One commit per Subtask with its Jira key; one Epic commit per Epic. Keys live
  in commits; branch names carry no meaning (Herdr-generated names are fine).
- One worktree per seat per repository, created by native Herdr outside every
  checkout and reused across claims. Never one per Task or Subtask; never
  nested inside a repository.
- Nothing is final until review approves and the PR merges.

Consequence: the `<EPIC>/<TASK>_<subtask>` and `<EPIC>/integration` ladders are
retired for agent work; review happens once per claim PR.

## Amendment 2 — settlement cleanup (owner ruling 2026-10-03)

Supersedes "reused across claims" in Amendment 1.

- Workers take as many assigned items as they can in one worktree, one branch
  and one PR, with a commit per item, like a human engineer.
- A claim is **settled** when it is accepted and merged. Settlement always
  triggers cleanup: lift all `.agent/` artifacts into the canonical checkout's
  `.agent/artifacts/<WORKTREE_BRANCH_NAME>/`, remove the worktree registration
  and directory (targeted, never a broad prune), unlink the Herdr worktree, and
  delete the merged claim branch.
- The worktree lives exactly as long as its claim; the seat's next claim starts
  in a fresh worktree. `agx clean --seat <SEAT_ID>` is the intended automation.

## Amendment 3 — answered settlement questions (owner answers 2026-10-03)

**Authority:** the owner's nine answers in Workspace `settlement-questions.md`,
recorded in `decisions.md` rulings 19–27. Supersedes advisory interpretations of
"one to three Epics" in Amendment 1 and the unbounded "as many assigned items"
wording and unflattened artifact path in Amendment 2. Earlier decisions and
amendments remain historical provenance; the live procedure is
[Cleanup — settlement](../SKILL.md#cleanup--settlement).

- A claim contains **at most three Epics**, a fixed interim constant until the
  owner selects a ticket-based model/effort matrix. Many assigned Tasks/Subtasks
  remain in one worktree, branch and PR. Scope may grow only before review starts
  and within the cap; later assignments wait for the next claim. Review repairs
  stay within issued scope. Subtask commits, parent Task attribution, no separate
  Task commit and Epic reconciliation/receipt commits remain unchanged.
- Settled means independently accepted and merged. The **Coordinator owns
  cleanup** on the verified merged event and reports `SETTLED <seat> <claim>` only
  after verified cleanup; settlement and cleanup completion are distinct facts.
- Preserve eligible `.agent/` artifacts in the canonical physical checkout's
  `.agent/artifacts/<flattened-branch>/`, replacing `/` with `-` (for example,
  `worktree/rapid-stone-82f6` → `worktree-rapid-stone-82f6`). Retain original
  branch/claim provenance, refuse collisions and verify inventory/hashes before
  removal. Exclude credentials/secrets and live sockets, locks and databases;
  exclusions do not grant disposal authority. Wiki annexation is deferred.
- The stable seat outlives its agent and worktree. Every new claim gets a fresh
  agent in a fresh worktree; preserve the historical harness session ID on the
  seat record. Archive the outgoing thread before transport loss through a
  verified harness-specific mechanism. Requested `/archive` behavior and native
  Herdr teardown semantics remain unverified dispatch prerequisites, not universal
  capabilities. Archival does not erase history.
- Normal cleanup safely deletes only the merged local and remote claim branch
  after landed proof, reconciling hosting auto-deletion and refusing changed
  remote refs. Preserve canonical, integration and employee branches and unrelated
  resources; never broad-prune. Use `git branch -d` locally; a refusal is not
  permission to escalate automatically to `-D` or `--force`.
- Preflight requires clean state, exact ownership/correlation, acceptance, merge,
  landed proof and preservation. Ancestry or validated content-equivalence/
  `merge-tree` proof can establish landing after a squash merge; this neither
  authorizes squash promotion nor bypasses a safe-deletion refusal.
- Unmerged/abandoned cleanup requires explicit `--abandon` plus case-specific
  owner approval and verified preservation of the remote branch. Missing
  preservation proof refuses cleanup and never implies authority to push.
- Bring every `--force` request, exact blocked operation and consequences to the
  owner for explicit approve/deny each time; approval is not a blanket gate bypass.
- Persist cleanup intent and progress outside the departing worktree. Preflight
  refusals precede destructive steps; a later external failure is partial cleanup,
  not atomic rollback across Git/Herdr/harness/remote. Resume from reverified
  durable receipts for the original claim, never a successor, and withhold
  `SETTLED` until all postconditions pass.

This amendment aligns documentation only; it does not implement `agx clean`, run
probes, archive a thread, or grant cleanup of any current resource.

## Amendment 4 — harness archival and artifact custody (2026-10-03)

Owner rulings 35 and 36 supersede Amendment 3’s unresolved Claude/Codex archival wording. [The current settlement procedure](../SKILL.md#cleanup--settlement) owns the harness-specific commands, transcript custody and global artifact-store tracking rule. Its explicit Claude/Codex procedure governs; only otherwise unspecified harness mechanisms and native Herdr teardown still require verification. No cleanup operation is authorized by this documentation amendment.

### Amendment 4: rank terminology — supplement (2026-10-04)

Workspace owner ruling 64 and Architect consensus 65 adopt General → Lieutenant → Sergeant. This supplements the existing Amendment 4 on archival without renumbering or rewriting accepted history. The General is the owner's interface; the Lieutenant owns project delivery and settlement under relayed grants, with the General acting as Lieutenant for `~/Workspace`. The implementing Sergeant's seat owns its claim; seat identity and `SETTLED <seat> <claim>` remain unchanged. Earlier Coordinator references map to that project Lieutenant duty. Rank grants no additional authority; the current skill procedure governs.
