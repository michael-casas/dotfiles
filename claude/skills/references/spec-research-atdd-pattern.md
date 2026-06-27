# ATDD for Research Tasks — Mobile Testing Landscape

When the task is investigative rather than implementation-focused (e.g., "research the tooling landscape for X"), the ATDD spec structure shifts from implementation scenarios to discovery scenarios.

This pattern was established June 7, 2026 during the React Native / Expo mobile testing research task, and the **working charter shape** documented below was refined through June 20, 2026 recon campaigns (infrastructure unification, graph-DB-for-agent-memory). The shape has converged — use this template verbatim for research recon unless the recon is explicitly bounded to a single narrow question.

## Structure Differences from Implementation ATDD

| Aspect | Implementation ATDD | Research ATDD |
|---|---|---|
| Scenarios | Given/When/Then for code behavior | Given/When/Then for discovery boundaries |
| Acceptance criteria | Test assertions | Information completeness checks |
| Definition of Done | Tests pass | Artifact exists with all required sections |
| Executable validation | Validation script exits 0 | Manual review (no script) |

## Research ATDD Template

```markdown
# ATDD: [Research Topic]

Investigate the tooling landscape for [subject]. Produce a recommendation.

## Context

[Background, constraints, intended use of findings]

### Scenario 1: [Tool/Platform Category 1]

**Given** [context for this tool category]
**When** researching [specific tool or approach]
**Then** document:
- Installation/setup requirements
- CLI API surface (key commands)
- How to detect readiness
- Known issues or limitations
- Relevant version/commit

### Scenario N: Recommended Architecture

**Given** all research findings
**When** synthesizing into a recommendation
**Then** produce:
- The simplest working path for [intended use case]
- Tool stack recommendation
- Estimated complexity (low/medium/high)
- Concrete next step to implement
```

## Acceptance Criteria Template

- [ ] Tool/Platform 1 documented: setup, CLI, readiness detection, limitations
- [ ] Additional platforms as needed
- [ ] Recommendation with simplest working path
- [ ] All findings saved as actionable reference

## Definition of Done

Task is complete when the research artifact exists and contains enough detail for an implementation agent to build the first working workflow from it.

## When to Use

- **Research ATDD** when: the territory is unknown, the goal is discovery, the output is a document
- **Implementation ATDD** when: the territory is understood, the goal is a working change, the output is code

Research tasks should be assigned to agents with web/browser tools enabled. Implementation tasks should be assigned to agents with terminal/file tools enabled.

---

## The Working Research-Charter Shape (Field-Tested, June 2026)

The pattern above is the **research spec**. The working charter that actually fires a recon agent on a cmux surface or kanban profile has additional structure that emerged through repeated dispatch. Use this shape for any recon that will run on a worker surface (Claude Code, OpenCode Hermes-Infra, subprocess m2.7/gpt-5.4-mini).

### Charter Structure (10 sections)

```markdown
# Charter: <Name>

**To:** <surface or profile, model, context, cwd>
**From:** <dispatcher, usually Django>
**Output:** <absolute path of the report to write>
**Format:** <brief: 4-6KB | detailed: 20-30KB | survey-only: <2KB>
**Wake:** <boomerang config or "fire and return">

---

## 0. Pre-flight
<one paragraph of explicit checks the agent must do BEFORE writing any output>
e.g. "Confirm surface state is clean before starting. If you're not at a fresh idle prompt, stop and report."
e.g. "Confirm DB reachable: `psql $DATABASE_URL -c 'SELECT 1'`. If unreachable, stop and report."

## 1. Mission
<2-4 paragraphs. The actual research question, framed against existing context.>

## 2. Existing baseline (DO NOT re-research — reference these)
<bulleted list of pre-existing artifacts the agent should read FIRST, not re-derive>
e.g. "Current substrate: `~/.hermes/.agent/research/pgmem-current-state.md` — read this first"

## 3. Research questions (must all be answered)
<numbered subsections, each is one concrete question with a concrete deliverable>
e.g. "### 3.1 Workload partitioning — classify each of these as graph-native / relational / hybrid"

## 4. Investigation commands
<the bash/web/file commands the agent should run, with comments explaining WHY each one>

## 5. Output format
<H2 headings the report MUST use. Pre-define the table columns, the subsections, the
deliverable sections. Less surprise = less rework.>

## 6. Constraints
<bullets: read-only | cite everything | concrete over abstract | quantify when possible
| length budget | time budget>

## 7. Stop conditions
<numbered list: when to stop. Always include a wall-clock time cap (90 min default).>

## 8. Final response
<what the agent should put in the dispatcher-facing message — pointer + top-N + blockers.
Keep it small. The report is the deliverable; the response is the pointer.>

**End of charter. Begin execution.**
```

### The Dispatch Pairing: Path-Reference, Not Inline

**The charter is written to disk first**, then dispatched via `cmux send --workspace W --surface S 'read /path/to/charter.md and execute exactly as written, beginning with section 0 pre-flight'`. Reasons:

- Charters are 5-15KB. `cmux send` chokes on long prompts with raw newlines/backticks.
- Same charter can be re-fired to a different surface or model.
- Founder can `cat /path/to/charter.md` and edit before fire.
- The surface prompt is human-verifiable: 1 line, easy to spot a wrong dispatch.

**The "beginning with section 0 pre-flight" suffix** is the load-bearing phrase. It tells the agent that section 0 is the FIRST concrete action, not preamble. Without that suffix, agents tend to skim the table of contents and jump to a middle section.

### Length Budget Tiers

Pick one and put it in the charter's frontmatter. The agent uses it to decide how deep to go.

| Tier | Length | When |
|---|---|---|
| Brief | 4-6KB | Quick decision support, single architecture question, "what's the top pick" |
| Detailed | 20-30KB | Architecture decision with multi-week implications, schema sketches, alternatives matrix, citations |
| Survey | <2KB | "Even briefer, just to know what exists" |

Detailed is the safe default for recon that informs a build. Brief is for recon that informs a smaller decision. Survey is rare — usually the right answer is to do brief.

### Final Response Discipline

The agent's final message to the dispatcher should be **≤300 tokens**. Always include:

1. **Path of the deliverable** (so the dispatcher can read it)
2. **Top-3 one-line summaries** ordered by leverage (the highest-leverage finding first)
3. **Any blockers** (couldn't verify X, DB unreachable, time ran out)

NEVER include the full report in the response. The report IS the deliverable; the response is the pointer. This protects the dispatcher's context window.

### Charter Quality Bar (refines Section B of the umbrella)

These are the recurring failure modes in research charters. Encode them as pitfall checks when writing a new charter:

- **Charter doesn't reference existing recon.** If `~/.hermes/.agent/research/` already has reports on adjacent topics, the charter MUST list them in section 2 ("Existing baseline") so the agent doesn't re-derive.
- **Investigation commands are too narrow.** The agent needs to know how to discover unknowns (`web_search`, `web_extract`, `find`, `rg`), not just how to verify knowns (`ls <path>`).
- **Output format is under-specified.** "Write a report" produces 5KB of unstructured prose. "Sections H2.1, H2.2, ... with these columns in this table" produces a usable artifact.
- **Length budget missing.** Without it, agents default to ~10KB regardless of the question's depth needs.
- **Final response not specified.** Without the ≤300 token template, agents paste the full report into chat and burn dispatcher context.
- **Constraints missing.** "Read-only", "no installs", "no DB writes" — these are not obvious to a general-purpose agent. Spell them out.

### Pitfalls (Re-Con-Specific)

- **Recon exceeds its scope.** The agent decides mid-run to "also check X" because it's adjacent. Without an explicit scope fence, recon balloons. Fix: section 1 "Mission" should be tightly framed, and section 7 "Stop conditions" should include "scope expansion is a separate charter."
- **Agent cites web sources without dates.** Web content rots. Charter should require URL + access date.
- **Agent uses `find` without a path scope and times out.** Constrain `find` to `~/.hermes` or `~/Documents/repos` — never `~`.
- **Agent writes raw `terminal` output into the report.** Wrap with file:line citations, not pasted dumps.
- **Agent makes recommendations without showing alternatives.** "Use Neo4j" without "vs Memgraph, FalkorDB, Kuzu" is opinion. Charter should require the alternatives matrix.
- **Two parallel recon agents land at the same time and overlap.** Either sequence them or partition the territory explicitly in section 1.

### When a Charter Should Be Brief, Not Detailed

- The question is "what's the top pick?" — no need for alternatives matrix
- The output will be a single recommendation paragraph
- The recon will inform a small (<1 day) decision
- Existing recon already covers the territory; you're filling a small gap

### When a Charter Should Be Survey-Only

- The user explicitly asked "even briefer, just to know what exists"
- The recon is just to validate that an idea isn't already covered elsewhere
- The output will be a few bullet points, not a structured document

### Anti-Pattern: "Research Charter" That Is Actually an Implementation Charter

If the deliverable requires code changes, installs, or commits, it's an **implementation ATDD**, not a research charter. The two have different validation contracts. Don't conflate them. If the recon reveals that implementation is needed, write a SEPARATE implementation ATDD after the recon lands.
