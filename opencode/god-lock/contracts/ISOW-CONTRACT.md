# ISOW-CONTRACT.md
## GOD-LOCK Inventory Scope of Work Contract
## Version: v1.0 — CANONICAL
## Status: LOCKED

---

# I. Purpose

This document defines the **mandatory structure and validation rules** for all ISoW artifacts produced by SENTINEL.

An ISoW that does not conform to this schema is:

> INVALID → NON-EXISTENT → MUST NOT BE USED

---

# II. Core Principle

ISoW is a **contract**, not a suggestion.

Like JSON Schema enforces structure at runtime, this schema enforces:
- completeness
- traceability
- bounded scope
- classification integrity  [oai_citation:0‡Orbit2x](https://orbit2x.com/blog/json-schema-validation-complete-tutorial?utm_source=chatgpt.com)

---

# III. ISoW Required Structure

Every ISoW MUST contain ALL of the following sections:

```md
# INVENTORY SCOPE OF WORK — [ISOW-ID]

## Goal
## Target Slice
## Discovery Scope
## Inventory Registry
## Dependency Notes
## Write Candidate Set
## Forbidden Surfaces
## Ambiguities / Confidence Gaps
## Recommended Packet Seams
## Stop Boundary
```

If ANY section is missing:
> INVALID

---

# IV. Field-Level Validation Rules

## 1. Goal
- must be non-empty
- must match original directive intent
- must not contain execution instructions

If it contains verbs like:
- "implement"
- "modify"
- "fix"

→ INVALID

---

## 2. Target Slice
- must define a bounded system surface
- must not be “entire repo” unless explicitly authorized

If unbounded:
> HALT REQUIRED

---

## 3. Discovery Scope
Must explicitly include:
- what was inspected
- what was excluded

If exclusions missing:
> INVALID

---

## 4. Inventory Registry

### REQUIRED FORMAT

| Path | Role | Why Included | Write Candidate |
|------|------|--------------|-----------------|

### VALIDATION RULES

Each row MUST satisfy:

#### Path
- must be concrete (no wildcards unless explicitly allowed)
- must exist or be declared missing explicitly

#### Role
MUST be one of:
- read_critical
- write_candidate
- adjacent_reference
- forbidden_surface
- unknown_role

If any other value:
> INVALID

#### Why Included
- must explain causal inclusion (dependency, entry point, etc.)
- must not be vague ("seems important")

#### Write Candidate
- must be `yes` or `no`
- if `yes`, file MUST appear in Write Candidate Set

---

## 5. Dependency Notes
- must describe actual relationships
- must not invent edges
- must not be empty if registry > 3 entries

---

## 6. Write Candidate Set
- must match ALL registry rows marked `yes`
- must not include extra files

Mismatch:
> INVALID

---

## 7. Forbidden Surfaces
- must include at least one exclusion OR explicitly state none
- must align with constraints

---

## 8. Ambiguities / Confidence Gaps
- MUST exist even if empty

If empty:
- must explicitly say: "None detected"

If omitted:
> INVALID

---

## 9. Recommended Packet Seams
- must define logical execution boundaries
- must not be full directives
- must not include code

Example valid:
- "DTO schema mutation boundary"
- "UI render layer boundary"

---

## 10. Stop Boundary
- must explicitly state:
  - where discovery stopped
  - why it stopped

If missing:
> INVALID

---

# V. Cross-Field Validation Rules

## 1. Write Consistency Rule
Every `write_candidate=yes`:
→ MUST appear in Write Candidate Set

## 2. Scope Integrity Rule
No file outside Target Slice:
→ unless justified in "Why Included"

## 3. Minimality Rule
If inventory contains unrelated domains:
> INVALID

## 4. Evidence Rule
Every file must have:
- role
- reason

No silent entries allowed.

---

# VI. Severity System

Validation produces:

- PASS → ISoW usable
- SOFT FAIL → usable with warning
- HARD FAIL → unusable

### HARD FAIL CONDITIONS

- missing required section
- invalid role classification
- write mismatch
- unbounded scope
- invented dependencies
- missing stop boundary

### SOFT FAIL CONDITIONS

- weak explanations
- low-confidence classification
- excessive inventory size

---

# VII. Sentinel Enforcement Law

SENTINEL must:

- self-validate ISoW before returning
- refuse to emit invalid ISoW
- HALT instead of emitting invalid structure

---

# VIII. Advisor Enforcement Law

ADVISOR must:

- reject invalid ISoW
- refuse directive issuance on invalid ISoW
- require correction or re-run of Sentinel

---

# IX. Onslaught Relationship

ONSLAUGHT must:

- NEVER operate without directive
- NEVER consume ISoW directly

ISoW → ADVISOR → Directive → ONSLAUGHT

---

# X. Future Extension

Schema may evolve with:
- machine-validated JSON form
- AST-level inventory graphs
- automated diff-aware ISoW regeneration

But:

> Human-readable markdown remains canonical surface

---

# XI. ISoW Persistence Law (MANDATORY)

Every ISoW produced by SENTINEL must be persisted to disk.

## Required Path
./.agents/ISoW-[DIRECTIVE-ID]-[UTC-TIMESTAMP].md

## Rules
- Must be written after ISoW validation passes
- Must use exact directive ID (no mutation)
- Timestamp must be UTC and filename-safe
- Markdown format required
- Chat output does NOT replace persistence

## Failure Condition
If ISoW cannot be written:
→ HALT (artifact persistence failure)

