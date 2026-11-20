# Visionaries final report: <surface> (<parent ticket key>)

Result: accepted | not accepted (<n> blockers open) | partial (<gate> did not judge)
Candidate: `<sha>` · Rounds: <1-3> · Launches: <n, helpers included> · Run folder: `<path>`

| Gate | Member (requested / ran) | Round 1 | Round 2 | Round 3 |
| --- | --- | --- | --- | --- |
| Taste | Claude Opus 5.5, high | CHANGES 4/10 | CHANGES 8/10 | PASS 10/10 |
| Structure | GPT 6.1 Sol, high | CHANGES 6/10 | PASS 9/10 | not run |
| Behavior | Claude Sonnet 5.5, high, 2 helpers | CHANGES 7/10 | PASS 10/10 | not run |

Three models from two providers; each gate was judged by one member. Review files:
`round-<n>/<gate>-review.md` for every cell above.

Reuse: <n> element kinds in scope, adopted <n>, promoted <n>, one-off <n> (ticketed <n>).
Scenarios: in scope <n>, bound end-to-end <n>, run <n>, passed <n>, proven <n>.

## Blockers (all of them, every round)
| Id | Gate | Round | Class | Late | Resolution applied | Proof | Outcome |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | taste | 1 | generic | no | <what was changed> | <render or command, result> | fixed / open / disputed / unverified |

Late blockers by gate (raised after round 1 on unchanged material): taste <n>, structure <n>, behavior <n>.

## Open after the last round (the REP schedules these; they are not in the deferred ticket)
<id — what is still wrong — why it was not fixed — what it needs>, or none

## Disputed (the REP rules)
<id — the gate's claim and evidence in two lines — the implementer's evidence in two lines>, or none

## Deferred items for one ticket (copied from the gates, unedited)
| Id | Gate | Kind | Anchor | Finding | Resolution | Proof it is done |
| --- | --- | --- | --- | --- | --- | --- |
| S7 | structure | refactor | `path:line` | <claim> | <design: name, level, contract, callers> | <check> |
| T9 | taste | nit | `render file` region | <claim> | <change> | <render> |
