# Visionaries loop charter: <surface> (<parent ticket key>)

From: <REP alias>. To: <WRK alias>, the implementer of this change. You run the review loop on
your own work and call me back once, when it is finished.

## Read first
1. `<absolute path>/the-visionaries/SKILL.md`, "The rules that do not bend"
2. `<absolute path>/the-visionaries/references/runbook.md` (your procedure, step by step)
3. `<absolute path>/the-visionaries/assets/BRIEF.md` and `assets/FINAL-REPORT.md`

## The review
- Surface: <screens, components and files in scope>
- The user asked (their words): "<verbatim>"
- Repository and worktree: `<absolute path>`   Base: `<sha>`   Candidate: `<sha or "your current head">`
- Law to apply: design <paths>; structure <paths>; testing <paths>; `.feature` files <paths>
- Run folder: `<absolute path outside the tracked tree>`
- Members: Taste `<provider / model / reasoning>`; Structure `<provider / model / reasoning>`;
  Behavior `<provider / model / reasoning>` with at most three helpers of the same model

## You may
- start the three gates, one launch per gate per round, at most three rounds;
- let the Behavior gate start its helpers;
- fix blockers inside your existing write surface: <paths>, committing as your charter already allows.

## You may not
- drop, downgrade or argue away a blocker (dispute it once with evidence; I rule at the end);
- fix deferred items, file tickets, widen the change, merge, or start a round 4;
- substitute a member, or contact me between rounds.

## Callback (the only one)
When the loop stops (all three `PASS`, or round 3 is in), write
`<run folder>/VISIONARIES-FINAL.md` and send me, by <route: inbox command or thread>:
`VISIONARIES FINAL <absolute path>`.
If you cannot start a gate at all: `VISIONARIES BLOCKED <gate> <reason>`, and stop.
