# Worker Instructions in ATDD Specs — Manager→Sub-Agent Delegation Pattern

## When to Use

An ATDD spec needs a "Worker Instructions" section when:
- The implementation spans multiple independent files
- A manager profile (software-manager, etc.) coordinates rather than implements
- Sub-agents (deepseek-v4-flash) handle individual file creation
- Each file has clear scope boundaries and verification checks

## Pattern Structure

```
# ATDD Specification

## [Standard ATDD sections: Context, Architecture, Scenarios...]

...

## Worker Instructions for Sub-Agents

Manager coordinates via `delegate_task`. Each sub-agent receives one file
to create (or a small batch) and returns the file content for review.

**Sub-agent 1:** Create `path/to/file.ext`
  - Requirements from Scenario [N]
  - Specific implementation guidance
  - Verification: `npx some-linter` on the result

**Sub-agent 2:** Create `path/to/other.ext`
  - Requirements from Scenario [M]
  - Cross-references Sub-agent 1's output
  - Verification: run `pnpm typecheck`

...
**Sub-agent N (optional):** ...
  - Only if condition X exists

Manager MUST:
1. Read all existing reference files (DESIGN.md, ARCHITECTURE.md, etc.)
2. Read existing project structure before dispatching
3. Dispatch sub-agents in order (dependencies noted; parallel-safe if none)
4. Review each sub-agent's output before accepting
5. Run the validation command before kanban_complete()
6. If validation fails, iterate with sub-agents, not by editing files directly
```

## Key Discipline Rules

### 1. One file per sub-agent (or small batch)

Each sub-agent gets a tightly scoped deliverable. This lets them work
independently, in parallel, and produces clean git diffs. If a sub-agent
needs to touch more than 2-3 files, the task is too big — decompose it.

### 2. Verification checks per sub-agent

Each sub-agent's section includes what verification to run after creating
their file. Common checks:
- `npx eslint` / `npx stylelint` — linter passing
- `pnpm typecheck` — TypeScript passing
- `pnpm test -- --testPathPattern=<file>` — specific test passing
- Manual inspection: "Verify NO raw hex values exist"

### 3. Manager is reviewer, not implementer

The manager dispatches, reviews, and iterates — it does NOT edit files
directly. If a sub-agent's output is wrong, the manager sends it back
with specific guidance, not edit it themselves.

### 4. Parallel-safe dependencies noted

```
**Sub-agent 1:** foundation.css (no deps)
**Sub-agent 2:** semantic.css (references foundation.css tokens)
**Sub-agent 3:** NativeWind bridge (references both)
```

Mark deps so the manager knows which can run in parallel vs. serial.

### 5. Validation as the final gate

The spec defines `pnpm agent:validate:<task>` which must exit 0 before
`kanban_complete()`. The validation script checks:
- File existence
- Parse validity (CSS parser, TypeScript compiler)
- Content rules (no forbidden patterns like raw hex in semantic tokens)
- Story presence (Storybook stories exist per category)

## Example: Design Tokens ATDD

From the June 8, 2026 Casita design tokens spec (`.agent/specs/tokens-first-layer.atdd.md`):

**5 sub-agents dispatched:**
1. `foundation.css` — color, typography, spacing tokens
2. `semantic.css` — surface, text, intent tokens (all var() references)
3. `variants.ts` — NativeWind-compatible export
4. Storybook stories — Colors, Typography, Spacing, RadiusShadows
5. (Optional) Tailwind v4 `@theme` block update

**Manager workflow:**
Read DESIGN.md → Read packages/ui/src/ structure → Dispatch parallel-safe → Review each → Run validate → kanban_complete()

## Pitfalls

- **Don't mix manager and sub-agent roles.** If the manager edits files directly, it breaks the accountability chain — sub-agents don't learn from their mistakes.
- **Don't skip verification per sub-agent.** The validation script catches the aggregate, but per-sub-agent checks (like "stylelint on this one file") catch issues early and save iteration cycles.
- **Too many sub-agents (6+) creates review burden.** 3-5 is the sweet spot for a session. Beyond that, batch smaller tasks into sub-agents.
- **Scope creep through shared files.** If two sub-agents both modify the same file, they'll conflict. Either mark one as blocking the other, or merge them into one sub-agent.
- **Sub-agents inherit the manager's model.** If the manager is deepseek-v4-flash, sub-agents default to deepseek-v4-flash unless overridden. The founder's policy is deepseek-v4-flash for ALL sub-agent work — no expensive models in the workforce.
