# Provenance

Adapted from the `council` skill in `t3dotgg/tstack` at commit `11e37a7`
(https://github.com/t3dotgg/tstack/blob/main/skills/council/SKILL.md), with the round budget and
ledger ideas of `sol-loop` in the same repository. MIT License, Copyright (c) 2026 Theo Browne.

Kept from upstream: fix known issues before review; resolve members and launch in parallel through
the harness; never substitute a missing member; reviewers do not edit; act on results as they
arrive; scores and rounds in the pull request description; fight scope growth.

Changed: three domain gates with their own charters and evidence instead of three members on one
question; members are chosen per gate and need not be three providers; verdicts decide acceptance
and scores only describe; three rounds at most instead of looping until all are satisfied; every
blocker with its resolution in round 1; blockers fixed in the loop and everything else ticketed;
the implementer runs the loop and the coordinator sees only the final report; `UNVERIFIED` and
`UNAVAILABLE` kept apart from `PASS`; a pinned candidate; counted results in the report.

Informed by published adaptations and reports, reviewed 2026-11-17: `s0up4200/skills` (cut to one
round after a five-round session), `cosmicdreams/tstack` (evidence before remediation),
`babs/skills` (candidate digest, stop on fix reversal), `tshrjn/openFIFA` (area rubric),
`daydemir/dstack` (the user's words in the brief), and `t3dotgg/tstack` issue 5 (reviewer ran at
default effort because none was sent).

The upstream license text:

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions: The above copyright notice and this
permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
