# Runbook for the WRK: running the loop

Your charter from the REP names the surface, the candidate, the law, the run folder, the members
and what you may do. This runbook is how. You call the REP exactly once, at the end.

## 0. Before round 1

1. Fix what you already know is wrong and run the covering checks. Do not send work you know is
   broken; list checks that are missing or were already failing.
2. Pin the candidate: base commit, head commit, `git status --short`, changed paths, any
   uncommitted or untracked files in scope. One diff command serves the whole loop.
3. Build the evidence pack in the run folder (outside the tracked tree):
   - **renders** for Taste: every changed screen or component state, at each size the
     repository's design law names, in each theme, on each platform it requires. A render that
     shows an error, a blank area or unstyled content is a render error: fix it before round 1.
   - **file map** for Structure: changed files, the repository's list of shared components, the
     output of any boundary or dependency check it has.
   - **behavior map** for Behavior: `.feature` files in scope, the commands for the end-to-end
     and component tests, how to start what they need.
   **If you cannot view images** (some models cannot), say so in the Taste brief and the final
   report, and never call a render inspected. Check each render mechanically and record it in a
   manifest the capture script writes: the expected state was reached, no console or page error,
   no error overlay, no failed script, style or font request, no sideways scroll, styles applied,
   image not near-uniform; prove once that the check can fail. During the rounds, apply a Taste
   blocker's resolution as written, re-render, and ledger it `fixed, gate to confirm`; only the
   gate's next round makes it `fixed`, and what is left unconfirmed when the loop stops is
   `unverified`. Dispute a Taste blocker only with a measurement or the text of the law.
4. Write one brief per gate from `assets/BRIEF.md`. Give requirements and evidence. Do not give
   your defense of the work, the score you hope for, or another gate's conclusions.

## 1. A round

1. Start the gates in parallel, each with `Read and execute <absolute path to its brief>`.
   In T3 Code: `orchestrator_capabilities` to resolve each member, then one `delegate_task` per
   gate (`role: "review"`, `mode: "async"`, a new `clientRequestId`), the reasoning level passed
   explicitly. Elsewhere: the harness's own subagent tools. A new round is a new launch, never a
   message to an old reviewer. If you cannot start a gate, send the REP
   `VISIONARIES BLOCKED <gate> <reason>` and stop.
2. While gates review, do not edit the checkout they read. Do not poll. A gate that fails or
   never returns is `UNAVAILABLE` for the round; cancel it and record it.
3. When a review arrives, check each finding against the code, the render or the run.
   - **Blocker, confirmed:** fix it now, the resolution the gate gave or a smaller one that
     passes the same proof. Run the proof. Ledger: `fixed`.
   - **Blocker, you believe it is wrong:** you may not drop or downgrade it. Ledger: `disputed`,
     with your evidence. Send it back to the gate once in the next round; if the gate holds, it
     stays `disputed` for the REP. If you could not check it because something was unavailable,
     it is `unverified`.
   - **Deferred (`nit`, `refactor`):** do not fix, do not argue. Ledger: `deferred`, copied as the
     gate wrote it, with its resolution and proof.
   - **Referral** (a gate saw something in another gate's domain): pass it to the owning gate in
     its next brief.
4. Fixing a blocker must not grow the change. If the only fix needs files outside your write
   surface, a new requirement or a product decision, ledger `open: needs REP` and continue.
5. Re-render and re-run whatever your fixes touched, and pin the new candidate.

Ledger columns: id (`T1`, `S1`, `B1`...), gate, round raised, class, `late` or not, anchor,
resolution, closure proof, outcome, evidence. One root cause is one entry even when two gates see
it. Never guess an entry.

## 2. Next round, or stop

- **Stop, accepted:** all three gates returned `PASS` on the current candidate. A gate's earlier
  `PASS` stands after later edits only if you record why those edits cannot touch what it
  reviewed; a change to a shared component reopens all three.
- **Next round** (2, then 3): only when every blocker from the last round is `fixed`, `disputed`
  or `open: needs REP`. Send it only to gates with a blocker that was raised or with evidence
  that changed, with the closure section of the brief: the open ids, the change since their last
  round, referrals.
- **Stop after round 3**, whatever is open. Never start a round 4, a second reviewer on a gate,
  or a re-review of a gate that passed and was not reopened.

## 3. Final report and the one callback

Write `<run folder>/VISIONARIES-FINAL.md` from `assets/FINAL-REPORT.md`. Every review file stays
in the run folder beside it. Then send the REP, by the route your charter names:
`VISIONARIES FINAL <absolute path>`. Do not file tickets, merge, or start new work on the
deferred items; they are the REP's to hand on.
