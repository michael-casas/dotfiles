# Output Templates

Use these templates when producing annexation outputs.

## Annexation report

```markdown
# Code Annexation Report: <Source> → GOD-LOCK

## Executive Judgment

<One direct paragraph with the overall annexation verdict. Say what should be salvaged and what should not.>

## Source Concepts

### <Concept Name>

- **Source files:** `<path>`, `<path>`
- **Current module shape:** <module/interface/implementation summary>
- **Decision:** Annex | Deepen | Adapt | Rewrite | Reject | Quarantine | Extract Vocabulary
- **Judgment:** <hard rationale>
- **Depth assessment:** Deep | Shallow | Mixed
- **Deletion test:** <what happens if removed>
- **Leverage:** <what GOD-LOCK callers gain>
- **Locality:** <what maintainers gain>
- **Dependency category:** In-process | Local-substitutable | Remote but owned | True external
- **GOD-LOCK target:** `<candidate package/domain/module>`
- **Recommended interface:** <plain English or TypeScript sketch>
- **Testing strategy:** <preserve/delete/rewrite/add>
- **Recommendation strength:** Strong | Worth exploring | Speculative

## Rejects

<Call out code that should not be annexed and why.>

## Vocabulary to Extract

<Terms, business distinctions, invariants, examples worth keeping.>

## Top Recommendation

<What to do first and why.>
```

## AES Directive/Op plan

Use this exact shape when asked for an implementation plan.

```markdown
# Implementation Plan: <Annexation Title>

## Overview

<Concise overview naming phase count and major work areas.>

---

# Directive 1: <Directive Name>

<Directive description.>

## Op Group 1.1: <Op Group Name>

- [ ] 1.1.1 <Atomic task>

* [ ] 1.1.2 <Expanded task with file target in `backticks`>

  * <Implementation detail>
  * <Validation detail>
  * _Requirements: 1.1.1_

---

## Notes

* <Cross-cutting notes>
```

Requirements line rules:

- put `_Requirements:` as the final nested bullet under the owning task
- use numbered refs only when known
- do not put requirements in prose paragraphs
- do not attach requirements to op groups

## Worker lanes

```markdown
# Parallel Annexation Lanes: <Title>

## Lane A: <Lane Name>

**Purpose:** <what this lane accomplishes>
**Runtime:** opencode | Claude | Codex | Kiro | Hermes
**Conflict scope:** `<paths or modules>`
**Depends on:** <task ids or lanes>
**Reducer:** <who reviews/merges>

### Tasks

* [ ] 2.1.1 <original task title>

  * <preserved details>
  * _Requirements: 1.2.1_

### Validation

- `<command>`

---

## Lane B: <Lane Name>

...
```

Lane rules:

- preserve original task IDs
- preserve original dependency lines
- do not create lanes for tasks with unresolved dependency or file conflicts
- include reducer notes for overlapping interfaces
