# WORK-EVENT-EMISSION-CONTRACT.md
## GOD-LOCK Event Emission Law
## Class: Canonical Execution Record
## Status: ACTIVE — v1.0

---

# I. Purpose

This document defines the **canonical rules for WorkEvent emission**.

WorkEvents are:

> the single source of truth for execution history

All execution performed by ONSLAUGHT must be:

- recorded
- ordered
- attributable
- replayable

WorkEvents replace AGENT-LOG entirely.

---

# II. Core Principle

> If it was not emitted as a WorkEvent, it did not happen.

---

# III. Event Model

Each WorkEvent is:

- atomic
- append-only
- immutable
- directive-bound
- optionally packet-bound

---

# IV. Required Fields

Every WorkEvent must include:

```text
directive_id
event_type
status
actor
worktree_id
branch
summary
created_at
```

Optional but recommended:

```text
packet_id
model
details_json
```

---

# V. Canonical Event Types

The following event types are the only allowed values:

```text
directive_received
compliance_ack

packet_initialized
packet_started
packet_completed

file_read
file_modified

verification_passed
verification_failed

halt_triggered

directive_completed
```

No custom event types may be introduced without system approval.

---

# VI. Event Lifecycle Law

## Directive Lifecycle

```text
directive_received
→ compliance_ack
→ [packet lifecycle(s)]
→ directive_completed
```

---

## Packet Lifecycle

Each packet must follow:

```text
packet_initialized
→ packet_started
→ [execution events]
→ verification_passed | verification_failed
→ packet_completed
```

If failure occurs:

```text
packet_initialized
→ packet_started
→ ...
→ halt_triggered
```

---

# VII. Packet Closure Law

Every packet must terminate in exactly one of:

- `packet_completed`
- `halt_triggered`

No packet may remain open.

---

# VIII. Execution Event Law

## file_read

Must be emitted when:

- reading target file content for decision-making
- inspecting file before mutation

Must include:

```json
{
  "file_path": "...",
  "access": "read"
}
```

---

## file_modified

Must be emitted when:

- any mutation occurs
- any file content changes

Must include:

```json
{
  "file_path": "...",
  "operation": "append | replace | remove | insert",
  "scope": "line | block",
  "description": "short description of mutation"
}
```

---

# IX. Verification Event Law

## verification_passed

Must be emitted when:

- all required checks pass

## verification_failed

Must be emitted when:

- any required check fails

Must include:

```json
{
  "check": "...",
  "reason": "..."
}
```

---

# X. Halt Event Law

## halt_triggered

Must be emitted immediately when:

- ambiguity is encountered
- verification fails
- scope cannot be safely executed
- event emission fails
- packet is invalid or incomplete

Must include:

```json
{
  "halt_code": "...",
  "reason": "...",
  "location": "step or phase"
}
```

After halt:

> no further execution is permitted

---

# XI. Event Ordering Law

Events must be emitted in **strict chronological order**.

Rules:

- no backfilling
- no reordering
- no delayed emission
- no retroactive correction

Event ID order must reflect execution order.

---

# XII. Atomicity Law

Each event must represent:

> one discrete, meaningful action

Do not:

- bundle multiple actions into one event
- summarize multiple mutations in one row
- collapse steps into a single record

---

# XIII. Truthfulness Law

Events must reflect:

> what actually occurred

Not:
- what was intended
- what should have happened
- what partially succeeded

Failure must be recorded truthfully.

---

# XIV. Event Emission Failure Law

If any WorkEvent fails to write:

> HALT immediately

No further execution is allowed.

No mutation may proceed without event recording.

---

# XV. details_json Contract

`details_json` must:

- be valid JSON string
- contain structured data
- avoid natural language paragraphs
- be consistent per event type

Examples:

### file_modified
```json
{
  "file_path": "src/...",
  "operation": "append",
  "line": 148
}
```

### halt_triggered
```json
{
  "halt_code": "HALT-SCOPE-001",
  "reason": "write target missing",
  "location": "execution step 2"
}
```

---

# XVI. Directive Completion Law

`directive_completed` may be emitted only when:

- all packets are closed
- no halts remain unresolved
- all required verification passed

---

# XVII. Minimal Emission Guarantee

For every packet, at minimum:

```text
packet_initialized
packet_started
[file_read / file_modified]
verification_passed | verification_failed
packet_completed
```

---

# XVIII. Prohibited Event Behavior

ONSLAUGHT must not:

- skip required events
- emit events after halt
- emit fake success
- emit completion without verification
- emit out-of-order events
- emit events for actions not performed

---

# XIX. Replay Principle

A complete WorkEvent sequence must be sufficient to:

- reconstruct execution
- audit behavior
- validate correctness
- replay directive intent

If replay is not possible:

> emission is insufficient

---

# XX. Final Law

WorkEvents are:

- the ledger
- the audit trail
- the replay system
- the truth

If execution is lawful:

> WorkEvents will prove it

If execution is unlawful:

> WorkEvents will expose it

---

# XXI. Closing Statement

Execution without logging is invisible.  
Logging without structure is noise.  

WorkEvents are:

> structured truth under law

---

**END OF WORK-EVENT EMISSION CONTRACT**
**Canonical Record: SQLite WorkEvent Ledger**
**Consumer: ONSLAUGHT / Future Orchestrators / Tribunal**