---
name: the-visionaries
description: Trigger this if the user says "the visionaries" or "visionaries", or when a worker asks its REP for a visionaries review. Three reviewers gate a user-interface change, each on its own model and its own domain - taste (how it looks and reads), structure (where the code lives, what is reused, what things are called) and behavior (does it do what the Gherkin says, proven at runtime). At most three rounds; blockers are fixed in the loop, everything else is ticketed. Use for UI review, design review, component or design-system audits, and before calling UI work done.
metadata:
  version: "0.3.2"
---

# The Visionaries

Three gates for user-interface work. The members do not answer the same question: each owns one
domain, gets the evidence that domain needs, and is the only voice on it.

| Gate | Asks | Member (default) | Charter |
| --- | --- | --- | --- |
| Taste | Does it look right, follow the design law, have a point of view, and treat the user well? | Claude Opus 5.5, high reasoning | [references/taste.md](references/taste.md) |
| Structure | Is every file where it belongs, is everything reused that can be, is each thing named for what it does? | GPT 6.1 Sol on Codex, high reasoning | [references/structure.md](references/structure.md) |
| Behavior | Does it behave as the `.feature` files say, proven by tests that run the real thing? | Claude Sonnet 5.5, high reasoning, with at most three Sonnet 5.5 helpers | [references/behavior.md](references/behavior.md) |

Members named in the user's instructions, `CLAUDE.md` or `AGENTS.md` replace these defaults.

## Who does what

| Seat | Does | Never |
| --- | --- | --- |
| **WRK** (the implementer) | Asks its REP for the review. Runs the loop from [references/runbook.md](references/runbook.md): prepares evidence, launches the gates, fixes blockers, writes the final report, calls the REP back once. | Reviews or approves its own work; drops or downgrades a blocker; calls the REP between rounds. |
| **Gates** (the three members) | Review, and state every blocker with its resolution in round 1. | Edit, commit, or start a fourth opinion. |
| **REP** (the coordinator) | Writes the loop charter from [assets/LOOP-CHARTER.md](assets/LOOP-CHARTER.md) and gives it to the WRK. Afterwards reads only the final report, rules on disputes, and hands the deferred items to the Ticketmaster. | Follows the rounds, relays reviews, or fixes. |
| **Ticketmaster** (Claude Haiku 5.5 subagent, started by the REP) | Files the deferred items from [assets/TICKETMASTER.md](assets/TICKETMASTER.md). | Invents, merges, rewords or drops an item; files anything the REP did not hand over. |

## The rules that do not bend

1. **Three rounds at most.** Round 1 is full. Rounds 2 and 3 go only to gates with an open
   blocker or changed evidence, and cover only open ids and what changed. There is no round 4:
   whatever is still open after round 3 goes into the final report for the REP. A new loop needs
   a new charter.
2. **Blockers and their resolutions up front.** In round 1 each gate lists every blocker it can
   find, each with the exact resolution and the proof that will close it, so that doing the whole
   list earns its `PASS`. In a later round a gate may raise a new blocker only on something that
   changed since it last looked. A blocker it missed on unchanged material is still fixed, marked
   `late`, and counted against that gate in the final report.
3. **Two outcomes for a finding.** A `blocker` is fixed before the next round is requested. Every
   other finding is `deferred` (`nit` or `refactor`): it is not fixed in the loop and not argued
   about; it goes into the final report and from there into one ticket, at the end of the queue.
4. **What is a blocker.** A bug, a render error, a broken design or accessibility rule, a seam
   break, a scenario that is unproven or not enforced, and for Taste a result that reads as
   machine-made, bland or underwhelming. Each gate's charter gives its own list. A render error
   is never deferred, however old it is: outside the WRK's write surface it is `open: needs REP`.
5. **What is a refactor.** A fix that needs files the change did not touch, a new shared
   component, or a rename that reaches other callers. It is ticketed with its design (name, level,
   contract), unless it is the only way to remove a blocker.
6. **No substitution.** A member or reasoning level that cannot be reached makes that gate
   `UNAVAILABLE`. Never swap a model, drop a gate quietly, or put one model on two gates. Pass the
   reasoning level explicitly and record what was requested and what ran.
7. **Evidence or no verdict.** Taste without renders and Behavior without a run are `UNVERIFIED`,
   never `PASS`. Every render, run and verdict belongs to one pinned candidate.
8. **Accepted** means Taste `PASS` and Structure `PASS` and Behavior `PASS` on the same candidate.
   Scores describe; they never decide and are never averaged. Three passes are three different
   checks by one member each, not three opinions that agree; report them that way.

## REP: starting a loop

When a WRK asks for the review, or you decide its work is ready for it:

1. Fill [assets/LOOP-CHARTER.md](assets/LOOP-CHARTER.md): the surface, the user's request in
   their words, base and candidate, the law to apply, the run folder, the members, the authority
   you grant (to start the three gates, to let Behavior start its helpers, to fix blockers inside
   the WRK's write surface), the parent ticket, and the one callback you expect.
2. Start or message the WRK with `Read and execute <absolute path to the charter>`.
3. Do nothing more until the callback `VISIONARIES FINAL <path>`. A WRK that cannot start a gate
   sends `VISIONARIES BLOCKED <gate> <reason>` instead; fix the seat or start that gate for it.

## REP: after the callback

1. Read the final report and check it is whole: one review file per gate per round, one
   candidate, counts that add up, every round-1 blocker either `fixed` with its proof or `open`.
2. Rule on each `disputed` item (the WRK's evidence against the gate's), or take it to the user.
3. Taste rows reported `unverified` because the WRK could not view images: open the before and
   after renders and rule each closed or open. State the result: `accepted`, or `not accepted`
   with the open blockers. Open blockers after
   round 3 are yours to schedule; they are never folded into the deferred ticket.
4. Start the Ticketmaster with a charter filled from [assets/TICKETMASTER.md](assets/TICKETMASTER.md):
   the final report, the parent ticket, and your explicit instruction to file. Report the result
   and the real ticket keys to the user.
